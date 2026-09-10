"use client";

import { useEffect, useState } from "react";

const COINGECKO_URL =
  "https://api.coingecko.com/api/v3/simple/price?ids=xdc-network&vs_currencies=usd";

const CACHE_MS = 60_000;

let cached: { price: number; at: number } | null = null;
let inflight: Promise<number | null> | null = null;

async function fetchXdcUsd(): Promise<number | null> {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.price;
  if (inflight) return inflight;

  inflight = (async () => {
    try {
      const res = await fetch(COINGECKO_URL, { headers: { accept: "application/json" } });
      if (!res.ok) return cached?.price ?? null;
      const data = (await res.json()) as { "xdc-network"?: { usd?: number } };
      const price = data["xdc-network"]?.usd;
      if (typeof price !== "number" || !Number.isFinite(price) || price <= 0) {
        return cached?.price ?? null;
      }
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

/** Spot XDC/USD from CoinGecko (module-cached, refreshed about once a minute). */
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
