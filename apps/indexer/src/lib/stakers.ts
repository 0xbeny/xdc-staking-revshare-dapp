export type OpenLock = {
  owner: string;
  amount: string;
  unlockTime: string | number;
  closed?: boolean;
};

export type StakerRow = {
  owner: string;
  amount: string;
  unlockTime: number;
  positionCount: number;
  shareBps: number;
};

export type StakerAggregate = {
  stakers: StakerRow[];
  totalAmount: string;
  positionCount: number;
};

function asAmount(raw: string): bigint {
  try {
    const n = BigInt(raw);
    return n < 0n ? 0n : n;
  } catch {
    return 0n;
  }
}

/** Group open locks by owner: summed XDC, amount-weighted unlock, share of TVL. */
export function aggregateStakers(locks: OpenLock[]): StakerAggregate {
  const open = locks.filter((lock) => !lock.closed);
  const byOwner = new Map<string, { amount: bigint; weighted: bigint; count: number }>();

  for (const lock of open) {
    const amount = asAmount(lock.amount);
    if (amount === 0n) continue;
    const owner = lock.owner.toLowerCase();
    const unlock = asAmount(String(lock.unlockTime));
    const cur = byOwner.get(owner) ?? { amount: 0n, weighted: 0n, count: 0 };
    cur.amount += amount;
    cur.weighted += amount * unlock;
    cur.count += 1;
    byOwner.set(owner, cur);
  }

  let total = 0n;
  for (const row of byOwner.values()) total += row.amount;

  const stakers: StakerRow[] = [...byOwner.entries()]
    .map(([owner, row]) => ({
      owner,
      amount: row.amount.toString(10),
      unlockTime: Number(row.weighted / row.amount),
      positionCount: row.count,
      shareBps: total === 0n ? 0 : Number((row.amount * 10_000n) / total),
    }))
    .sort((a, b) => {
      const diff = asAmount(b.amount) - asAmount(a.amount);
      if (diff > 0n) return 1;
      if (diff < 0n) return -1;
      return a.owner.localeCompare(b.owner);
    });

  return {
    stakers,
    totalAmount: total.toString(10),
    positionCount: open.filter((lock) => asAmount(lock.amount) > 0n).length,
  };
}
