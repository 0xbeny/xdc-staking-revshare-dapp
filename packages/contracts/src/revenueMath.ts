/** BPS denominator used by RevenueAdapterBase._splitAndForward. */
export const BPS = 10_000n;

/**
 * Committed share forwarded to the distributor on a FeeSplitter skim:
 * `amount * committedBps / 10000`.
 */
export function committedFromSkim(amount: bigint, committedBps: number | bigint): bigint {
  if (amount < 0n) throw new RangeError("amount must be non-negative");
  const bps = typeof committedBps === "bigint" ? committedBps : BigInt(committedBps);
  if (bps < 0n || bps > BPS) throw new RangeError("committedBps must be in [0, 10000]");
  return (amount * bps) / BPS;
}
