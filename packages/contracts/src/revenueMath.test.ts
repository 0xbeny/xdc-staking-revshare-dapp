import { describe, expect, it } from "vitest";
import { BPS, committedFromSkim } from "./revenueMath.js";

describe("committedFromSkim", () => {
  it("matches FeeSplitter math for 30% commit", () => {
    expect(committedFromSkim(1_000_000n, 3000)).toBe(300_000n);
  });

  it("floors dust like Solidity integer division", () => {
    expect(committedFromSkim(100n, 3333)).toBe(33n);
  });

  it("returns full amount at 10000 bps", () => {
    expect(committedFromSkim(42n, BPS)).toBe(42n);
  });

  it("rejects out-of-range bps", () => {
    expect(() => committedFromSkim(1n, 10001)).toThrow(/committedBps/);
  });
});
