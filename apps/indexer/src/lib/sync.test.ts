import { describe, expect, it } from "vitest";
import { recordedPot } from "./sync";

describe("recordedPot", () => {
  it("records a zero-supply epoch as empty after it carries forward", () => {
    expect(recordedPot(0n, 1000n)).toBe(0n);
  });

  it("keeps the pot when lockers were in the snapshot", () => {
    expect(recordedPot(10n, 1000n)).toBe(1000n);
  });
});
