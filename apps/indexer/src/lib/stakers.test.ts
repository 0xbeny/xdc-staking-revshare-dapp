import { describe, expect, it } from "vitest";
import { aggregateStakers, lockWeight } from "./stakers";

const WEEK = 7 * 24 * 60 * 60;
const NOW = 1_700_000_000;

describe("lockWeight", () => {
  it("is zero when unlocked", () => {
    expect(lockWeight(10n ** 18n, NOW - 1, NOW)).toBe(0n);
  });

  it("scales with remaining time", () => {
    const amount = 104n * 10n ** 18n;
    const max = lockWeight(amount, NOW + 104 * WEEK, NOW);
    const half = lockWeight(amount, NOW + 52 * WEEK, NOW);
    expect(max).toBeGreaterThan(half);
    expect(half * 2n).toBe(max);
  });
});

describe("aggregateStakers", () => {
  it("returns empty when there are no open locks", () => {
    expect(aggregateStakers([])).toEqual({
      stakers: [],
      totalAmount: "0",
      totalWeight: "0",
      positionCount: 0,
    });
  });

  it("sums veXDC, weight, share, and flags majority NFT", () => {
    const out = aggregateStakers(
      [
        {
          owner: "0xAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAa",
          tokenId: "1",
          amount: (10n * 10n ** 18n).toString(),
          unlockTime: NOW + 104 * WEEK,
        },
        {
          owner: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          tokenId: "2",
          amount: (30n * 10n ** 18n).toString(),
          unlockTime: NOW + 104 * WEEK,
        },
        {
          owner: "0xBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBb",
          tokenId: "3",
          amount: (10n * 10n ** 18n).toString(),
          unlockTime: NOW + 52 * WEEK,
        },
      ],
      NOW,
    );

    expect(out.stakers).toHaveLength(2);
    expect(out.stakers[0]?.owner).toBe("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    expect(out.stakers[0]?.amount).toBe((40n * 10n ** 18n).toString());
    expect(out.stakers[0]?.positionCount).toBe(2);
    expect(out.stakers[0]?.positions[0]?.tokenId).toBe("2");
    expect(out.stakers[0]?.positions[0]?.majority).toBe(true);
    expect(out.stakers[0]?.positions[1]?.majority).toBe(false);
    expect(out.totalWeight).not.toBe("0");
  });
});
