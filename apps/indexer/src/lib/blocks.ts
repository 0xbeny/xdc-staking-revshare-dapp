/** Split an inclusive [from, to] block range into chunks of at most `chunkSize` blocks. */
export function chunkBlockRange(
  from: bigint,
  to: bigint,
  chunkSize: bigint = 2000n,
): Array<{ from: bigint; to: bigint }> {
  if (chunkSize <= 0n) {
    throw new Error("chunkSize must be positive");
  }
  if (to < from) {
    return [];
  }

  const ranges: Array<{ from: bigint; to: bigint }> = [];
  let start = from;
  while (start <= to) {
    const end = start + chunkSize - 1n > to ? to : start + chunkSize - 1n;
    ranges.push({ from: start, to: end });
    start = end + 1n;
  }
  return ranges;
}

export function toBlockString(n: bigint): string {
  return n.toString(10);
}

export function parseBlock(value: string | number | bigint): bigint {
  return BigInt(value);
}

/** UTC calendar day as YYYY-MM-DD. */
export function utcDay(tsSec: number = Math.floor(Date.now() / 1000)): string {
  return new Date(tsSec * 1000).toISOString().slice(0, 10);
}
