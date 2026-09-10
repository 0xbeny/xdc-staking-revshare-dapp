import {
  abis,
  getDeployment,
  type Address,
  type DeploymentAddresses,
} from "@vexdc/contracts";
import { and, count, eq, sql } from "drizzle-orm";
import {
  type Abi,
  type AbiEvent,
  type Log,
  type PublicClient,
  decodeEventLog,
} from "viem";
import {
  adapters,
  claims,
  contributions,
  epochs,
  getDb,
  positionEvents,
  positions,
  protocolStats,
  syncCursors,
  type Db,
} from "@/db";
import { chunkBlockRange, toBlockString, utcDay } from "@/lib/blocks";
import { makePublicClient, normalizeAddress } from "@/lib/chain";
import { getChainId, loadEnv } from "@/lib/env";

export type ContractKey =
  | "votingEscrow"
  | "feeDistributor"
  | "revenueRegistry"
  | "zapDepositor";

export type SyncResult = {
  ok: true;
  chainId: number;
  message?: string;
  advanced: Record<string, string>;
  logsProcessed: number;
};

const WEEK = 7n * 24n * 60n * 60n;
const LOG_CHUNK = 2000n;

function contractAbi(key: ContractKey) {
  switch (key) {
    case "votingEscrow":
      return abis.VotingEscrow;
    case "feeDistributor":
      return abis.FeeDistributor;
    case "revenueRegistry":
      return abis.RevenueRegistry;
    case "zapDepositor":
      return abis.ZapDepositor;
  }
}

function deploymentAddress(
  deployment: DeploymentAddresses,
  key: ContractKey,
): Address {
  return deployment[key];
}

function pickEvents(key: ContractKey, names: readonly string[]): AbiEvent[] {
  const abi = contractAbi(key) as Abi;
  const nameSet = new Set(names);
  return abi.filter((item): item is AbiEvent => {
    return item.type === "event" && nameSet.has(item.name);
  });
}

async function getCursor(
  db: Db,
  chainId: number,
  contractKey: ContractKey,
  startBlock: bigint,
): Promise<bigint> {
  const rows = await db
    .select()
    .from(syncCursors)
    .where(
      and(eq(syncCursors.chainId, chainId), eq(syncCursors.contractKey, contractKey)),
    )
    .limit(1);
  const row = rows[0];
  if (!row) return startBlock;
  return BigInt(row.fromBlock);
}

async function setCursor(
  db: Db,
  chainId: number,
  contractKey: ContractKey,
  nextFrom: bigint,
): Promise<void> {
  await db
    .insert(syncCursors)
    .values({
      chainId,
      contractKey,
      fromBlock: toBlockString(nextFrom),
    })
    .onConflictDoUpdate({
      target: [syncCursors.chainId, syncCursors.contractKey],
      set: { fromBlock: toBlockString(nextFrom) },
    });
}

async function insertEvent(
  db: Db,
  args: {
    chainId: number;
    tokenId: string;
    eventName: string;
    txHash: string;
    logIndex: number;
    blockNumber: string;
    payload: Record<string, unknown>;
  },
): Promise<void> {
  await db
    .insert(positionEvents)
    .values(args)
    .onConflictDoNothing({
      target: [positionEvents.chainId, positionEvents.txHash, positionEvents.logIndex],
    });
}

function jsonSafe(value: unknown): Record<string, unknown> {
  return JSON.parse(
    JSON.stringify(value, (_k, v) => (typeof v === "bigint" ? v.toString(10) : v)),
  ) as Record<string, unknown>;
}

async function refreshPosition(
  db: Db,
  client: PublicClient,
  deployment: DeploymentAddresses,
  chainId: number,
  tokenId: bigint,
  blockNumber: bigint,
): Promise<void> {
  const escrow = deployment.votingEscrow;
  const [owner, lock, firstEligible, exitEp, closedFlag] = await Promise.all([
    client.readContract({
      address: escrow,
      abi: abis.VotingEscrow,
      functionName: "ownerOf",
      args: [tokenId],
    }),
    client.readContract({
      address: escrow,
      abi: abis.VotingEscrow,
      functionName: "locked",
      args: [tokenId],
    }),
    client.readContract({
      address: escrow,
      abi: abis.VotingEscrow,
      functionName: "firstEligibleEpoch",
      args: [tokenId],
    }),
    client.readContract({
      address: escrow,
      abi: abis.VotingEscrow,
      functionName: "exitEpoch",
      args: [tokenId],
    }),
    client.readContract({
      address: escrow,
      abi: abis.VotingEscrow,
      functionName: "closed",
      args: [tokenId],
    }),
  ]);

  const amount = lock.amount.toString(10);
  const unlockTime = lock.end.toString(10);
  const penaltyCapBps = Number(lock.penaltyCapBps);
  const tokenIdStr = tokenId.toString(10);
  const blockStr = toBlockString(blockNumber);

  await db
    .insert(positions)
    .values({
      chainId,
      tokenId: tokenIdStr,
      owner: normalizeAddress(owner),
      amount,
      unlockTime,
      penaltyCapBps,
      closed: closedFlag,
      firstEligibleEpoch: firstEligible.toString(10),
      exitEpoch: exitEp === 0n ? null : exitEp.toString(10),
      createdAtBlock: blockStr,
      updatedAtBlock: blockStr,
    })
    .onConflictDoUpdate({
      target: [positions.chainId, positions.tokenId],
      set: {
        owner: normalizeAddress(owner),
        amount,
        unlockTime,
        penaltyCapBps,
        closed: closedFlag,
        firstEligibleEpoch: firstEligible.toString(10),
        exitEpoch: exitEp === 0n ? null : exitEp.toString(10),
        updatedAtBlock: blockStr,
      },
    });
}

async function markClosed(
  db: Db,
  chainId: number,
  tokenId: bigint,
  blockNumber: bigint,
  exitEpoch?: bigint,
): Promise<void> {
  await db
    .update(positions)
    .set({
      closed: true,
      amount: "0",
      updatedAtBlock: toBlockString(blockNumber),
      ...(exitEpoch !== undefined ? { exitEpoch: exitEpoch.toString(10) } : {}),
    })
    .where(
      and(
        eq(positions.chainId, chainId),
        eq(positions.tokenId, tokenId.toString(10)),
      ),
    );
}

async function upsertEpochRevenue(
  db: Db,
  chainId: number,
  token: Address,
  epoch: bigint,
  deltaRevenue: bigint,
  forfeitedDelta: bigint = 0n,
): Promise<void> {
  const tokenNorm = normalizeAddress(token);
  const epochStr = epoch.toString(10);
  const existing = await db
    .select()
    .from(epochs)
    .where(
      and(
        eq(epochs.chainId, chainId),
        eq(epochs.token, tokenNorm),
        eq(epochs.epoch, epochStr),
      ),
    )
    .limit(1);

  if (!existing[0]) {
    await db.insert(epochs).values({
      chainId,
      token: tokenNorm,
      epoch: epochStr,
      revenue: deltaRevenue.toString(10),
      forfeited: forfeitedDelta.toString(10),
      settled: false,
    });
    return;
  }

  const revenue = BigInt(existing[0].revenue) + deltaRevenue;
  const forfeited = BigInt(existing[0].forfeited) + forfeitedDelta;
  await db
    .update(epochs)
    .set({
      revenue: revenue.toString(10),
      forfeited: forfeited.toString(10),
    })
    .where(
      and(
        eq(epochs.chainId, chainId),
        eq(epochs.token, tokenNorm),
        eq(epochs.epoch, epochStr),
      ),
    );
}

async function processVotingEscrowLog(
  db: Db,
  client: PublicClient,
  deployment: DeploymentAddresses,
  chainId: number,
  log: Log,
): Promise<void> {
  const decoded = decodeEventLog({
    abi: abis.VotingEscrow,
    data: log.data,
    topics: log.topics,
  });
  const blockNumber = log.blockNumber ?? 0n;
  const txHash = log.transactionHash ?? "0x";
  const logIndex = log.logIndex ?? 0;

  switch (decoded.eventName) {
    case "Deposit": {
      const { tokenId } = decoded.args;
      await refreshPosition(db, client, deployment, chainId, tokenId, blockNumber);
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: "Deposit",
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    case "LockExtended": {
      const { tokenId, newUnlock } = decoded.args;
      await db
        .update(positions)
        .set({
          unlockTime: newUnlock.toString(10),
          updatedAtBlock: toBlockString(blockNumber),
        })
        .where(
          and(
            eq(positions.chainId, chainId),
            eq(positions.tokenId, tokenId.toString(10)),
          ),
        );
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: "LockExtended",
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    case "Withdraw": {
      const { tokenId } = decoded.args;
      // Mature withdraw: weight is already zero after expiry; exitEpoch is not recorded on-chain.
      await markClosed(db, chainId, tokenId, blockNumber);
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: "Withdraw",
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    case "EmergencyExit": {
      const { tokenId } = decoded.args;
      const block = await client.getBlock({ blockNumber });
      const exitEpoch = block.timestamp / WEEK;
      await markClosed(db, chainId, tokenId, blockNumber, exitEpoch);
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: "EmergencyExit",
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    case "ExitRequested":
    case "ExitRequestCancelled": {
      const { tokenId } = decoded.args;
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: decoded.eventName,
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    default:
      break;
  }
}

async function processFeeDistributorLog(
  db: Db,
  chainId: number,
  log: Log,
): Promise<void> {
  const decoded = decodeEventLog({
    abi: abis.FeeDistributor,
    data: log.data,
    topics: log.topics,
  });
  const blockNumber = log.blockNumber ?? 0n;
  const txHash = log.transactionHash ?? "0x";
  const logIndex = log.logIndex ?? 0;

  switch (decoded.eventName) {
    case "RevenueNotified": {
      const { token, amount, distributionEpoch } = decoded.args;
      await upsertEpochRevenue(db, chainId, token, distributionEpoch, amount);
      break;
    }
    case "ForfeitureSynced": {
      const { token, amount, creditedEpoch } = decoded.args;
      await upsertEpochRevenue(db, chainId, token, creditedEpoch, amount, amount);
      break;
    }
    case "EpochSettled": {
      const { token, epoch, supply, pot, movedForward } = decoded.args;
      const tokenNorm = normalizeAddress(token);
      const epochStr = epoch.toString(10);
      await db
        .insert(epochs)
        .values({
          chainId,
          token: tokenNorm,
          epoch: epochStr,
          revenue: pot.toString(10),
          settled: true,
          supply: supply.toString(10),
          pot: pot.toString(10),
          forfeited: "0",
        })
        .onConflictDoUpdate({
          target: [epochs.chainId, epochs.token, epochs.epoch],
          set: {
            settled: true,
            supply: supply.toString(10),
            pot: pot.toString(10),
          },
        });
      if (movedForward > 0n) {
        await upsertEpochRevenue(db, chainId, token, epoch + 1n, movedForward);
      }
      break;
    }
    case "Claimed": {
      const { tokenId, token, to, amount, newCursor } = decoded.args;
      await db
        .insert(claims)
        .values({
          chainId,
          tokenId: tokenId.toString(10),
          token: normalizeAddress(token),
          amount: amount.toString(10),
          to: normalizeAddress(to),
          claimCursor: newCursor.toString(10),
          txHash,
          logIndex,
          blockNumber: toBlockString(blockNumber),
        })
        .onConflictDoNothing();
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: "Claimed",
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    case "Compounded":
    case "KeepAtMaxLockSet":
    case "AutoCompoundSet": {
      const { tokenId } = decoded.args;
      await insertEvent(db, {
        chainId,
        tokenId: tokenId.toString(10),
        eventName: decoded.eventName,
        txHash,
        logIndex,
        blockNumber: toBlockString(blockNumber),
        payload: jsonSafe(decoded.args),
      });
      break;
    }
    default:
      break;
  }
}

async function processRevenueRegistryLog(
  db: Db,
  chainId: number,
  log: Log,
): Promise<void> {
  const decoded = decodeEventLog({
    abi: abis.RevenueRegistry,
    data: log.data,
    topics: log.topics,
  });
  const blockNumber = log.blockNumber ?? 0n;
  const txHash = log.transactionHash ?? "0x";

  switch (decoded.eventName) {
    case "AdapterRegistered": {
      const { adapter, dapp, mode, committedBps, version, termsHash } = decoded.args;
      await db
        .insert(adapters)
        .values({
          chainId,
          adapter: normalizeAddress(adapter),
          dapp: normalizeAddress(dapp),
          mode: Number(mode),
          committedBps: Number(committedBps),
          version: Number(version),
          termsHash,
          active: true,
        })
        .onConflictDoUpdate({
          target: [adapters.chainId, adapters.adapter],
          set: {
            dapp: normalizeAddress(dapp),
            mode: Number(mode),
            committedBps: Number(committedBps),
            version: Number(version),
            termsHash,
            active: true,
          },
        });
      break;
    }
    case "AdapterDeactivated": {
      const { adapter } = decoded.args;
      await db
        .update(adapters)
        .set({ active: false })
        .where(
          and(
            eq(adapters.chainId, chainId),
            eq(adapters.adapter, normalizeAddress(adapter)),
          ),
        );
      break;
    }
    case "AdapterReactivated": {
      const { adapter } = decoded.args;
      await db
        .update(adapters)
        .set({ active: true })
        .where(
          and(
            eq(adapters.chainId, chainId),
            eq(adapters.adapter, normalizeAddress(adapter)),
          ),
        );
      break;
    }
    case "ContributionRecorded": {
      const { adapter, token, amount } = decoded.args;
      await db
        .insert(contributions)
        .values({
          chainId,
          adapter: normalizeAddress(adapter),
          token: normalizeAddress(token),
          amount: amount.toString(10),
          blockNumber: toBlockString(blockNumber),
          txHash,
          logIndex,
        })
        .onConflictDoNothing();
      break;
    }
    case "TermsUpdated": {
      const { adapter, termsHash, version } = decoded.args;
      await db
        .update(adapters)
        .set({
          termsHash,
          version: Number(version),
        })
        .where(
          and(
            eq(adapters.chainId, chainId),
            eq(adapters.adapter, normalizeAddress(adapter)),
          ),
        );
      break;
    }
    default:
      break;
  }
}

async function processZapDepositorLog(
  db: Db,
  chainId: number,
  log: Log,
): Promise<void> {
  const decoded = decodeEventLog({
    abi: abis.ZapDepositor,
    data: log.data,
    topics: log.topics,
  });
  const blockNumber = log.blockNumber ?? 0n;
  const txHash = log.transactionHash ?? "0x";
  const logIndex = log.logIndex ?? 0;

  if (decoded.eventName === "Zapped" || decoded.eventName === "ZapIncreased") {
    const { tokenId } = decoded.args;
    await insertEvent(db, {
      chainId,
      tokenId: tokenId.toString(10),
      eventName: decoded.eventName,
      txHash,
      logIndex,
      blockNumber: toBlockString(blockNumber),
      payload: jsonSafe(decoded.args),
    });
  }
}

const VE_EVENTS = [
  "Deposit",
  "LockExtended",
  "Withdraw",
  "EmergencyExit",
  "ExitRequested",
  "ExitRequestCancelled",
] as const;

const FD_EVENTS = [
  "RevenueNotified",
  "EpochSettled",
  "ForfeitureSynced",
  "Claimed",
  "Compounded",
  "KeepAtMaxLockSet",
  "AutoCompoundSet",
] as const;

const RR_EVENTS = [
  "AdapterRegistered",
  "AdapterDeactivated",
  "AdapterReactivated",
  "ContributionRecorded",
  "TermsUpdated",
] as const;

const ZAP_EVENTS = ["Zapped", "ZapIncreased"] as const;

function eventsFor(key: ContractKey): AbiEvent[] {
  switch (key) {
    case "votingEscrow":
      return pickEvents(key, VE_EVENTS);
    case "feeDistributor":
      return pickEvents(key, FD_EVENTS);
    case "revenueRegistry":
      return pickEvents(key, RR_EVENTS);
    case "zapDepositor":
      return pickEvents(key, ZAP_EVENTS);
  }
}

async function syncContract(
  db: Db,
  client: PublicClient,
  deployment: DeploymentAddresses,
  chainId: number,
  key: ContractKey,
  toBlock: bigint,
): Promise<number> {
  const address = deploymentAddress(deployment, key);
  const startBlock = BigInt(deployment.startBlock ?? deployment.deployedAt ?? 0);
  const fromBlock = await getCursor(db, chainId, key, startBlock);
  if (fromBlock > toBlock) {
    return 0;
  }

  const events = eventsFor(key);
  let processed = 0;

  for (const range of chunkBlockRange(fromBlock, toBlock, LOG_CHUNK)) {
    const logs = await client.getLogs({
      address,
      events,
      fromBlock: range.from,
      toBlock: range.to,
    });

    for (const log of logs) {
      if (key === "votingEscrow") {
        await processVotingEscrowLog(db, client, deployment, chainId, log);
      } else if (key === "feeDistributor") {
        await processFeeDistributorLog(db, chainId, log);
      } else if (key === "revenueRegistry") {
        await processRevenueRegistryLog(db, chainId, log);
      } else {
        await processZapDepositorLog(db, chainId, log);
      }
      processed += 1;
    }

    await setCursor(db, chainId, key, range.to + 1n);
  }

  return processed;
}

async function snapshotProtocolStats(
  db: Db,
  client: PublicClient,
  deployment: DeploymentAddresses,
  chainId: number,
): Promise<void> {
  const totalLocked = await client.readContract({
    address: deployment.votingEscrow,
    abi: abis.VotingEscrow,
    functionName: "totalLocked",
  });

  const countRows = await db
    .select({ value: count() })
    .from(positions)
    .where(and(eq(positions.chainId, chainId), eq(positions.closed, false)));
  const positionCount = countRows[0]?.value ?? 0;

  const wxdc = normalizeAddress(deployment.wxdc);
  const usdc = deployment.usdc ? normalizeAddress(deployment.usdc) : null;

  const revenueRows = await db
    .select({
      token: epochs.token,
      total: sql<string>`coalesce(sum(${epochs.revenue}::numeric), 0)::text`,
    })
    .from(epochs)
    .where(eq(epochs.chainId, chainId))
    .groupBy(epochs.token);

  let epochRevenueWxdc = "0";
  let epochRevenueUsdc = "0";
  for (const row of revenueRows) {
    if (row.token === wxdc) epochRevenueWxdc = row.total;
    if (usdc && row.token === usdc) epochRevenueUsdc = row.total;
  }

  const day = utcDay();
  await db
    .insert(protocolStats)
    .values({
      chainId,
      day,
      totalLocked: totalLocked.toString(10),
      epochRevenueWxdc,
      epochRevenueUsdc,
      positionCount,
    })
    .onConflictDoUpdate({
      target: [protocolStats.chainId, protocolStats.day],
      set: {
        totalLocked: totalLocked.toString(10),
        epochRevenueWxdc,
        epochRevenueUsdc,
        positionCount,
      },
    });
}

export async function runSync(): Promise<SyncResult> {
  const chainId = getChainId();
  const deployment = getDeployment(chainId);

  if (!deployment) {
    return {
      ok: true,
      chainId,
      message: `No live deployment for chain ${chainId}; sync no-op`,
      advanced: {},
      logsProcessed: 0,
    };
  }

  const db = getDb();
  const client = makePublicClient(chainId);
  const latest = await client.getBlockNumber();
  const confirmations = Math.max(
    0,
    loadEnv().SYNC_CONFIRMATIONS ?? 12,
  );
  const safeTip = latest > BigInt(confirmations) ? latest - BigInt(confirmations) : 0n;

  const keys: ContractKey[] = [
    "votingEscrow",
    "feeDistributor",
    "revenueRegistry",
    "zapDepositor",
  ];

  let logsProcessed = 0;
  const advanced: Record<string, string> = {};

  for (const key of keys) {
    const n = await syncContract(db, client, deployment, chainId, key, safeTip);
    logsProcessed += n;
    const cursor = await getCursor(db, chainId, key, 0n);
    advanced[key] = cursor.toString(10);
  }

  await snapshotProtocolStats(db, client, deployment, chainId);

  return {
    ok: true,
    chainId,
    advanced,
    logsProcessed,
  };
}
