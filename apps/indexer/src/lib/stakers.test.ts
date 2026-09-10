import { describe, expect, it } from "vitest";
import { aggregateStakers } from "./stakers";

describe("aggregateStakers", () => {
  it("returns empty when there are no open locks", () => {
    expect(aggregateStakers([])).toEqual({
      stakers: [],
      totalAmount: "0",
      positionCount: 0,
    });
    expect(
      aggregateStakers([{ owner: "0xAA", amount: "1", unlockTime: 10, closed: true }]),
    ).toEqual({ stakers: [], totalAmount: "0", positionCount: 0 });
  });

  it("combines locks per holder with an amount-weighted unlock", () => {
    const out = aggregateStakers([
      { owner: "0xAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAa", amount: "100", unlockTime: 100 },
      { owner: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", amount: "300", unlockTime: 200 },
      { owner: "0xBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBbBb", amount: "100", unlockTime: 50 },
    ]);

    expect(out.totalAmount).toBe("500");
    expect(out.positionCount).toBe(3);
    expect(out.stakers).toHaveLength(2);

    const [first, second] = out.stakers;
    expect(first.owner).toBe("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    expect(first.amount).toBe("400");
    expect(first.positionCount).toBe(2);
    expect(first.unlockTime).toBe(175);
    expect(first.shareBps).toBe(8000);

    expect(second.owner).toBe("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    expect(second.amount).toBe("100");
    expect(second.shareBps).toBe(2000);
  });

  it("skips zero-amount dust", () => {
    const out = aggregateStakers([
      { owner: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", amount: "0", unlockTime: 1 },
      { owner: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", amount: "10", unlockTime: 9 },
    ]);
    expect(out.stakers).toHaveLength(1);
    expect(out.stakers[0]?.owner).toBe("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    expect(out.totalAmount).toBe("10");
  });
});
