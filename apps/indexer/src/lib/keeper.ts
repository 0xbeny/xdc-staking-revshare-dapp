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

export type KeeperResult = {
  ok: true;
  chainId: number;
  message?: string;
  keepAtMaxLock?: { hash: Hex; count: number };
  compound?: { hash: Hex; count: number };
  skims?: Array<{ token: Address; hash: Hex }>;
  skipped?: string[];
};

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

function currentEpoch(): bigint {
  return BigInt(Math.floor(Date.now() / 1000)) / WEEK;
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

  const privateKey = env.KEEPER_PRIVATE_KEY as Hex;
  const publicClient = makePublicClient(chainId);
  const wallet = makeWalletClient(chainId, privateKey);
  const epoch = currentEpoch();
  const skipped: string[] = [];
  const result: KeeperResult = { ok: true, chainId, skipped };

  const keepIds = await optedInTokenIds(chainId, "KeepAtMaxLockSet");
  if (keepIds.length > 0) {
    try {
      const hash = await wallet.writeContract({
        address: deployment.feeDistributor,
        abi: abis.FeeDistributor,
        functionName: "batchKeepAtMaxLock",
        args: [keepIds, epoch],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      result.keepAtMaxLock = { hash, count: keepIds.length };
    } catch (err) {
      skipped.push(
        `batchKeepAtMaxLock: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  const compoundIds = await optedInTokenIds(chainId, "AutoCompoundSet");
  if (compoundIds.length > 0) {
    try {
      const hash = await wallet.writeContract({
        address: deployment.feeDistributor,
        abi: abis.FeeDistributor,
        functionName: "batchCompound",
        args: [compoundIds, epoch],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      result.compound = { hash, count: compoundIds.length };
    } catch (err) {
      skipped.push(
        `batchCompound: ${err instanceof Error ? err.message : String(err)}`,
      );
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

  if (skipped.length === 0) delete result.skipped;
  return result;
}
