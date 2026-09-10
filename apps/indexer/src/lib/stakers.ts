export type OpenLock = {
  owner: string;
  amount: string;
  unlockTime: string | number;
  closed?: boolean;
  tokenId?: string | number;
};

export type StakerPosition = {
  tokenId: string;
  amount: string;
  weight: string;
  unlockTime: number;
  shareBps: number;
  majority: boolean;
};

export type StakerRow = {
  owner: string;
  amount: string;
  weight: string;
  unlockTime: number;
  positionCount: number;
  shareBps: number;
  positions: StakerPosition[];
};

export type StakerAggregate = {
  stakers: StakerRow[];
  totalAmount: string;
  totalWeight: string;
  positionCount: number;
};

const WEEK = 7 * 24 * 60 * 60;
const MAX_LOCK = 104 * WEEK;

function asAmount(raw: string): bigint {
  try {
    const n = BigInt(raw);
    return n < 0n ? 0n : n;
  } catch {
    return 0n;
  }
}

function shareBps(part: bigint, total: bigint): number {
  return total === 0n ? 0 : Number((part * 10_000n) / total);
}

/** Truncated-slope weight — same as VotingEscrow.weightAt / estimateLockWeight. */
export function lockWeight(amount: bigint, unlockTs: number, nowSec: number): bigint {
  if (amount === 0n || unlockTs <= nowSec) return 0n;
  const remaining = BigInt(unlockTs - nowSec);
  const maxLock = BigInt(MAX_LOCK);
  const effective = remaining > maxLock ? maxLock : remaining;
  return (amount / maxLock) * effective;
}

/** Group open locks by owner with weight-based share and per-veNFT majority flag. */
export function aggregateStakers(
  locks: OpenLock[],
  nowSec = Math.floor(Date.now() / 1000),
): StakerAggregate {
  const open = locks.filter((lock) => !lock.closed);
  const byOwner = new Map<
    string,
    {
      amount: bigint;
      weight: bigint;
      weightedUnlock: bigint;
      positions: { tokenId: string; amount: bigint; weight: bigint; unlockTime: number }[];
    }
  >();

  for (const lock of open) {
    const amount = asAmount(lock.amount);
    if (amount === 0n) continue;
    const owner = lock.owner.toLowerCase();
    const unlock = Number(asAmount(String(lock.unlockTime)));
    const weight = lockWeight(amount, unlock, nowSec);
    const tokenId =
      lock.tokenId !== undefined && lock.tokenId !== null
        ? String(lock.tokenId)
        : `${owner}-${byOwner.get(owner)?.positions.length ?? 0}`;
    const cur = byOwner.get(owner) ?? {
      amount: 0n,
      weight: 0n,
      weightedUnlock: 0n,
      positions: [],
    };
    cur.amount += amount;
    cur.weight += weight;
    cur.weightedUnlock += amount * BigInt(unlock);
    cur.positions.push({ tokenId, amount, weight, unlockTime: unlock });
    byOwner.set(owner, cur);
  }

  let totalAmount = 0n;
  let totalWeight = 0n;
  for (const row of byOwner.values()) {
    totalAmount += row.amount;
    totalWeight += row.weight;
  }

  const stakers: StakerRow[] = [...byOwner.entries()]
    .map(([owner, row]) => {
      const sorted = [...row.positions].sort((a, b) => {
        const diff = b.weight - a.weight;
        if (diff > 0n) return 1;
        if (diff < 0n) return -1;
        const amt = b.amount - a.amount;
        if (amt > 0n) return 1;
        if (amt < 0n) return -1;
        return a.tokenId.localeCompare(b.tokenId);
      });
      const majorityId = sorted[0]?.tokenId;
      const positions = sorted.map((p) => ({
        tokenId: p.tokenId,
        amount: p.amount.toString(10),
        weight: p.weight.toString(10),
        unlockTime: p.unlockTime,
        shareBps: shareBps(p.weight, totalWeight),
        majority: sorted.length > 1 && p.tokenId === majorityId,
      }));

      return {
        owner,
        amount: row.amount.toString(10),
        weight: row.weight.toString(10),
        unlockTime: Number(row.weightedUnlock / row.amount),
        positionCount: positions.length,
        shareBps: shareBps(row.weight, totalWeight),
        positions,
      };
    })
    .sort((a, b) => {
      const diff = asAmount(b.weight) - asAmount(a.weight);
      if (diff > 0n) return 1;
      if (diff < 0n) return -1;
      return a.owner.localeCompare(b.owner);
    });

  return {
    stakers,
    totalAmount: totalAmount.toString(10),
    totalWeight: totalWeight.toString(10),
    positionCount: open.filter((lock) => asAmount(lock.amount) > 0n).length,
  };
}
