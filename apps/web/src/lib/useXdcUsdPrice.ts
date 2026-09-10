"use client";

import { useEffect, useState } from "react";

const CACHE_MS = 60_000;

let cached: { price: number; at: number } | null = null;
let inflight: Promise<number | null> | null = null;

function parsePositive(n: unknown): number | null {
  const v = typeof n === "string" ? Number(n) : typeof n === "number" ? n : NaN;
  return Number.isFinite(v) && v > 0 ? v : null;
}

async function fetchFromGate(): Promise<number | null> {
  const res = await fetch("https://api.gateio.ws/api/v4/spot/tickers?currency_pair=XDC_USDT", {
    headers: { accept: "application/json" },
  });
  if (!res.ok) return null;
  const data = (await res.json()) as Array<{ last?: string }>;
  return parsePositive(data[0]?.last);
}

async function fetchFromCoinGecko(): Promise<number | null> {
  const res = await fetch(
    "https://api.coingecko.com/api/v3/simple/price?ids=xdc-network&vs_currencies=usd",
    { headers: { accept: "application/json" } },
  );
  if (!res.ok) return null;
  const data = (await res.json()) as { "xdc-network"?: { usd?: number } };
  return parsePositive(data["xdc-network"]?.usd);
}

async function fetchXdcUsd(): Promise<number | null> {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.price;
  if (inflight) return inflight;

  inflight = (async () => {
    try {
      const price = (await fetchFromGate()) ?? (await fetchFromCoinGecko());
      if (price == null) return cached?.price ?? null;
      cached = { price, at: Date.now() };
      return price;
    } catch {
      return cached?.price ?? null;
    } finally {
      inflight = null;
    }
  })();

  return inflight;
}

/** Spot XDC/USD (Gate.io first, CoinGecko fallback; module-cached ~1 min). */
export function useXdcUsdPrice(): number | null {
  const [price, setPrice] = useState<number | null>(() => cached?.price ?? null);

  useEffect(() => {
    let cancelled = false;
    const load = () => {
      void fetchXdcUsd().then((p) => {
        if (!cancelled && p != null) setPrice(p);
      });
    };
    load();
    const id = window.setInterval(load, CACHE_MS);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, []);

  return price;
}
