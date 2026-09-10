import {
  abis,
  getDeployment,
  type Address,
} from "@vexdc/contracts";
import { and, desc, eq } from "drizzle-orm";
import type { Hex } from "viem";
import { getDb, positionEvents, positions } from "@/db";
import { makePublicClient, makeWalletClient, normalizeAddress } from "@/lib/chain";
import { getChainId, loadEnv } from "@/lib/env";

const WEEK = 7n * 24n * 60n * 60n;
const KEEPER_WINDOW = 2n * 60n * 60n;
const DEFAULT_BATCH_SIZE = 50;

export type KeeperResult = {
  ok: boolean;
  chainId: number;
  message?: string;
  blockTimestamp?: number;
  epoch?: string;
  keepAtMaxLock?: { hashes: Hex[]; count: number };
  compound?: { hashes: Hex[]; count: number };
  skims?: Array<{ token: Address; hash: Hex }>;
  skipped?: string[];
};

function chunkIds(ids: bigint[], size: number): bigint[][] {
  if (ids.length === 0) return [];
  const out: bigint[][] = [];
  for (let i = 0; i < ids.length; i += size) {
    out.push(ids.slice(i, i + size));
  }
  return out;
}

async function optedInTokenIds(
  chainId: number,
  eventName: "KeepAtMaxLockSet" | "AutoCompoundSet",
): Promise<bigint[]> {
  const db = getDb();
  const rows = await db
    .select()
    .from(positionEvents)
    .where(and(eq(positionEvents.chainId, chainId), eq(positionEvents.eventName, eventName)))
    .orderBy(desc(positionEvents.blockNumber), desc(positionEvents.logIndex));

  const latest = new Map<string, boolean>();
  for (const row of rows) {
    if (latest.has(row.tokenId)) continue;
    const enabled = Boolean(row.payload["enabled"]);
    latest.set(row.tokenId, enabled);
  }

  const open = await db
    .select({ tokenId: positions.tokenId })
    .from(positions)
    .where(and(eq(positions.chainId, chainId), eq(positions.closed, false)));
  const openSet = new Set(open.map((r) => r.tokenId));

  return [...latest.entries()]
    .filter(([id, enabled]) => enabled && openSet.has(id))
    .map(([id]) => BigInt(id));
}

function rewardTokens(deployment: NonNullable<ReturnType<typeof getDeployment>>): Address[] {
  const env = loadEnv();
  if (env.REWARD_TOKENS) {
    return env.REWARD_TOKENS.split(",")
      .map((t) => t.trim())
      .filter((t): t is Address => /^0x[0-9a-fA-F]{40}$/.test(t))
      .map(normalizeAddress);
  }
  const tokens: Address[] = [normalizeAddress(deployment.wxdc)];
  if (deployment.usdc) tokens.push(normalizeAddress(deployment.usdc));
  return tokens;
}

export async function runKeeper(): Promise<KeeperResult> {
  const chainId = getChainId();
  const deployment = getDeployment(chainId);
  if (!deployment) {
    return {
      ok: true,
      chainId,
      message: `No live deployment for chain ${chainId}; keeper no-op`,
    };
  }

  const env = loadEnv();
  if (!env.KEEPER_PRIVATE_KEY) {
    return {
      ok: true,
      chainId,
      message: "KEEPER_PRIVATE_KEY not set; keeper no-op",
    };
  }

  const batchSize = Math.max(
    1,
    env.KEEPER_BATCH_SIZE ?? DEFAULT_BATCH_SIZE,
  );

  const privateKey = env.KEEPER_PRIVATE_KEY as Hex;
  const publicClient = makePublicClient(chainId);
  const wallet = makeWalletClient(chainId, privateKey);
  const latest = await publicClient.getBlock({ blockTag: "latest" });
  const now = latest.timestamp;
  const epoch = now / WEEK;
  const epochEnd = (epoch + 1n) * WEEK;
  const inKeepWindow = now + KEEPER_WINDOW >= epochEnd;
  const skipped: string[] = [];
  const result: KeeperResult = {
    ok: true,
    chainId,
    skipped,
    blockTimestamp: Number(now),
    epoch: epoch.toString(),
  };

  // Pre-boundary extensions: Wednesday 22:00–24:00 UTC for Thursday epochs.
  if (inKeepWindow) {
    const keepIds = await optedInTokenIds(chainId, "KeepAtMaxLockSet");
    if (keepIds.length > 0) {
      const hashes: Hex[] = [];
      for (const chunk of chunkIds(keepIds, batchSize)) {
        try {
          const hash = await wallet.writeContract({
            address: deployment.feeDistributor,
            abi: abis.FeeDistributor,
            functionName: "batchKeepAtMaxLock",
            args: [chunk, epoch],
          });
          await publicClient.waitForTransactionReceipt({ hash });
          hashes.push(hash);
        } catch (err) {
          skipped.push(
            `batchKeepAtMaxLock[${chunk.length}]: ${err instanceof Error ? err.message : String(err)}`,
          );
        }
      }
      if (hashes.length > 0) {
        result.keepAtMaxLock = { hashes, count: keepIds.length };
      }
    }
  } else {
    skipped.push(
      `batchKeepAtMaxLock: outside window (now=${now} epochEnd=${epochEnd} window=${KEEPER_WINDOW}s)`,
    );
  }

  // Post-boundary compounds can run any time in the new epoch (not window-gated on-chain).
  const compoundIds = await optedInTokenIds(chainId, "AutoCompoundSet");
  if (compoundIds.length > 0) {
    const hashes: Hex[] = [];
    for (const chunk of chunkIds(compoundIds, batchSize)) {
      try {
        const hash = await wallet.writeContract({
          address: deployment.feeDistributor,
          abi: abis.FeeDistributor,
          functionName: "batchCompound",
          args: [chunk, epoch],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        hashes.push(hash);
      } catch (err) {
        skipped.push(
          `batchCompound[${chunk.length}]: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    if (hashes.length > 0) {
      result.compound = { hashes, count: compoundIds.length };
    }
  }

  const feeSplitter =
    (env.FEE_SPLITTER as Address | undefined) || deployment.feeSplitter;
  if (feeSplitter) {
    const skims: Array<{ token: Address; hash: Hex }> = [];
    for (const token of rewardTokens(deployment)) {
      try {
        const hash = await wallet.writeContract({
          address: feeSplitter,
          abi: abis.FeeSplitter,
          functionName: "skim",
          args: [token],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        skims.push({ token, hash });
      } catch (err) {
        skipped.push(
          `skim(${token}): ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    if (skims.length > 0) result.skims = skims;
  }

  // Outside the keep window, the keep skip is expected — not a failure.
  const unexpected = skipped.filter((s) => !s.startsWith("batchKeepAtMaxLock: outside window"));
  if (unexpected.length > 0) {
    result.ok = false;
  }
  if (skipped.length === 0) delete result.skipped;
  return result;
}
