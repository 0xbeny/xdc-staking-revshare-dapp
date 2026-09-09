import { describe, expect, it } from "vitest";
import { chunkBlockRange } from "@/lib/blocks";

describe("chunkBlockRange", () => {
  it("splits an inclusive range into fixed-size chunks", () => {
    expect(chunkBlockRange(100n, 4500n, 2000n)).toEqual([
      { from: 100n, to: 2099n },
      { from: 2100n, to: 4099n },
      { from: 4100n, to: 4500n },
    ]);
  });

  it("returns a single chunk when the range fits", () => {
    expect(chunkBlockRange(10n, 20n, 2000n)).toEqual([{ from: 10n, to: 20n }]);
  });

  it("returns empty when to < from", () => {
    expect(chunkBlockRange(50n, 10n, 2000n)).toEqual([]);
  });

  it("rejects non-positive chunk sizes", () => {
    expect(() => chunkBlockRange(0n, 10n, 0n)).toThrow(/positive/);
  });
});
