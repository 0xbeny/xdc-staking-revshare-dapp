import { describe, expect, it } from "vitest";
import { aggregateFeesByVenue } from "./fees-by-venue";

const USDC = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const WXDC = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const ADAPTER_A = "0x1111111111111111111111111111111111111111";
const ADAPTER_B = "0x2222222222222222222222222222222222222222";
const DAPP_A = "0x3333333333333333333333333333333333333333";

describe("aggregateFeesByVenue", () => {
  it("returns empty when there are no contributions", () => {
    expect(
      aggregateFeesByVenue({
        rows: [],
        settled: [],
        usdc: USDC,
        wxdc: WXDC,
      }),
    ).toEqual({
      token: null,
      legacyFallback: false,
      venues: [],
      epochs: [],
    });
  });

  it("stacks tagged contributions by epoch and venue", () => {
    const out = aggregateFeesByVenue({
      rows: [
        {
          epoch: "10",
          token: USDC,
          adapter: ADAPTER_A,
          dapp: DAPP_A,
          amount: "100",
        },
        {
          epoch: "10",
          token: USDC,
          adapter: ADAPTER_B,
          dapp: null,
          amount: "50",
        },
        {
          epoch: "11",
          token: USDC,
          adapter: ADAPTER_A,
          dapp: DAPP_A,
          amount: "25",
        },
      ],
      settled: [
        { epoch: "10", token: USDC, settled: true },
        { epoch: "11", token: USDC, settled: false },
      ],
      usdc: USDC,
      wxdc: WXDC,
    });

    expect(out.legacyFallback).toBe(false);
    expect(out.token).toBe(USDC);
    expect(out.epochs).toHaveLength(2);
    expect(out.epochs[0]).toMatchObject({
      epoch: 10,
      settled: true,
      total: "150",
    });
    expect(out.epochs[0]?.venues).toHaveLength(2);
    expect(out.epochs[1]).toMatchObject({
      epoch: 11,
      settled: false,
      total: "25",
    });
    expect(out.venues.map((v) => v.adapter)).toEqual(
      expect.arrayContaining([ADAPTER_A, ADAPTER_B]),
    );
  });

  it("prefers USDC when multiple tokens exist", () => {
    const out = aggregateFeesByVenue({
      rows: [
        { epoch: "1", token: WXDC, adapter: ADAPTER_A, dapp: null, amount: "9" },
        { epoch: "1", token: USDC, adapter: ADAPTER_A, dapp: null, amount: "1" },
      ],
      settled: [],
      usdc: USDC,
      wxdc: WXDC,
    });
    expect(out.token).toBe(USDC);
    expect(out.epochs[0]?.total).toBe("1");
  });

  it("falls back to legacy rows assigned to latest epoch", () => {
    const out = aggregateFeesByVenue({
      rows: [
        {
          epoch: null,
          token: USDC,
          adapter: ADAPTER_A,
          dapp: DAPP_A,
          amount: "300",
        },
        {
          epoch: null,
          token: USDC,
          adapter: ADAPTER_B,
          dapp: null,
          amount: "100",
        },
      ],
      settled: [
        { epoch: "2957", token: USDC, settled: true },
        { epoch: "2958", token: USDC, settled: false },
      ],
      usdc: USDC,
    });

    expect(out.legacyFallback).toBe(true);
    expect(out.epochs).toHaveLength(1);
    expect(out.epochs[0]).toMatchObject({
      epoch: 2958,
      settled: false,
      total: "400",
    });
    expect(out.venues).toHaveLength(2);
  });

  it("ignores legacy rows when tagged epoch rows exist", () => {
    const out = aggregateFeesByVenue({
      rows: [
        {
          epoch: "5",
          token: USDC,
          adapter: ADAPTER_A,
          dapp: null,
          amount: "10",
        },
        {
          epoch: null,
          token: USDC,
          adapter: ADAPTER_A,
          dapp: null,
          amount: "999",
        },
      ],
      settled: [{ epoch: "5", token: USDC, settled: false }],
      usdc: USDC,
    });

    expect(out.legacyFallback).toBe(false);
    expect(out.epochs[0]?.total).toBe("10");
  });
});
