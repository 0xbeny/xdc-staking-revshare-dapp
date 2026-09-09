const indexerBase = () =>
  (process.env.NEXT_PUBLIC_INDEXER_URL ?? "http://localhost:3001").replace(/\/$/, "");

export type ProtocolTvlPoint = {
  day: string;
  totalLocked: string;
  positionCount: number;
};

export type ProtocolRevenuePoint = {
  epoch: number;
  token: string;
  revenue: string;
  pot?: string;
};

export type EarningsPoint = {
  blockNumber?: number;
  amount: string;
  token: string;
  txHash?: string;
  at?: string;
};

export type IndexerPosition = {
  tokenId: string;
  owner: string;
  amount: string;
  unlockTime: number;
  penaltyCapBps: number;
  closed: boolean;
};

async function indexerFetch<T>(path: string): Promise<T | null> {
  try {
    const init: RequestInit & { next?: { revalidate: number } } = {
      headers: { Accept: "application/json" },
    };
    if (typeof window === "undefined") {
      init.next = { revalidate: 30 };
    } else {
      init.cache = "no-store";
    }
    const res = await fetch(`${indexerBase()}${path}`, init);
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export async function fetchProtocolTvl(): Promise<ProtocolTvlPoint[]> {
  const data = await indexerFetch<{ points?: ProtocolTvlPoint[] } | ProtocolTvlPoint[]>(
    "/api/protocol/tvl",
  );
  if (!data) return [];
  return Array.isArray(data) ? data : (data.points ?? []);
}

export async function fetchProtocolRevenue(): Promise<ProtocolRevenuePoint[]> {
  const data = await indexerFetch<
    { points?: ProtocolRevenuePoint[] } | ProtocolRevenuePoint[]
  >("/api/protocol/revenue");
  if (!data) return [];
  return Array.isArray(data) ? data : (data.points ?? []);
}

export async function fetchPositionEarnings(tokenId: string): Promise<EarningsPoint[]> {
  const data = await indexerFetch<
    { claims?: EarningsPoint[]; points?: EarningsPoint[] } | EarningsPoint[]
  >(`/api/positions/${tokenId}/earnings`);
  if (!data) return [];
  if (Array.isArray(data)) return data;
  return data.claims ?? data.points ?? [];
}

export async function fetchOwnerPositions(address: string): Promise<IndexerPosition[]> {
  const data = await indexerFetch<{ positions?: IndexerPosition[] } | IndexerPosition[]>(
    `/api/positions/${address}`,
  );
  if (!data) return [];
  return Array.isArray(data) ? data : (data.positions ?? []);
}
