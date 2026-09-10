export type ContributionVenueRow = {
  epoch: string | null;
  token: string;
  adapter: string;
  dapp: string | null;
  amount: string;
};

export type EpochSettledRow = {
  epoch: string;
  token: string;
  settled: boolean;
};

export type FeesByVenueResult = {
  token: string | null;
  /** True when venue totals came from contribution rows that lacked epoch (pre-migration / ContributionRecorded). */
  legacyFallback: boolean;
  venues: { adapter: string; dapp: string; label: string }[];
  epochs: {
    epoch: number;
    settled: boolean;
    total: string;
    venues: { adapter: string; dapp: string; label: string; amount: string }[];
  }[];
};

function shortVenue(dapp: string, adapter: string): string {
  const src = dapp?.startsWith("0x") ? dapp : adapter;
  if (src.length < 10) return src;
  return `${src.slice(0, 6)}…${src.slice(-4)}`;
}

function pickToken(
  tokens: string[],
  preferred: string | null,
  usdc: string | null | undefined,
  wxdc: string | null | undefined,
): string | null {
  if (preferred && tokens.includes(preferred)) return preferred;
  if (usdc && tokens.includes(usdc)) return usdc;
  if (wxdc && tokens.includes(wxdc)) return wxdc;
  return tokens[0] ?? null;
}

type VenueAgg = { adapter: string; dapp: string; amount: bigint };

function addVenueAmount(
  byEpoch: Map<string, { total: bigint; venues: Map<string, VenueAgg> }>,
  epochKey: string,
  adapterRaw: string,
  dappRaw: string | null,
  amount: bigint,
): void {
  if (amount === 0n) return;
  const entry = byEpoch.get(epochKey) ?? { total: 0n, venues: new Map() };
  const adapter = adapterRaw.toLowerCase();
  const dapp = (dappRaw ?? adapter).toLowerCase();
  const prev = entry.venues.get(adapter);
  entry.venues.set(adapter, {
    adapter,
    dapp,
    amount: (prev?.amount ?? 0n) + amount,
  });
  entry.total += amount;
  byEpoch.set(epochKey, entry);
}

/**
 * Aggregate notified fees per epoch × venue.
 * Prefers contribution rows with `epoch` (from FeeDistributor.RevenueNotified).
 * If none exist, falls back to summing epoch-less rows (ContributionRecorded /
 * pre-migration) into the latest known epoch for that token when available.
 */
export function aggregateFeesByVenue(input: {
  rows: ContributionVenueRow[];
  settled: EpochSettledRow[];
  tokenParam?: string | null;
  usdc?: string | null;
  wxdc?: string | null;
}): FeesByVenueResult {
  const empty: FeesByVenueResult = {
    token: null,
    legacyFallback: false,
    venues: [],
    epochs: [],
  };

  const tokens = [...new Set(input.rows.map((r) => r.token.toLowerCase()))];
  const token = pickToken(
    tokens,
    input.tokenParam?.toLowerCase() ?? null,
    input.usdc?.toLowerCase() ?? null,
    input.wxdc?.toLowerCase() ?? null,
  );
  if (!token) return empty;

  const settledByEpoch = new Map<string, boolean>();
  let latestEpochForToken: string | null = null;
  for (const row of input.settled) {
    if (row.token.toLowerCase() !== token) continue;
    settledByEpoch.set(row.epoch, row.settled);
    if (latestEpochForToken === null || Number(row.epoch) > Number(latestEpochForToken)) {
      latestEpochForToken = row.epoch;
    }
  }

  const tagged = input.rows.filter(
    (r) => r.epoch != null && r.token.toLowerCase() === token,
  );
  const legacy = input.rows.filter(
    (r) => r.epoch == null && r.token.toLowerCase() === token,
  );

  const byEpoch = new Map<string, { total: bigint; venues: Map<string, VenueAgg> }>();
  let legacyFallback = false;

  if (tagged.length > 0) {
    for (const row of tagged) {
      addVenueAmount(
        byEpoch,
        row.epoch as string,
        row.adapter,
        row.dapp,
        BigInt(row.amount),
      );
    }
  } else if (legacy.length > 0) {
    legacyFallback = true;
    const epochKey = latestEpochForToken ?? "0";
    for (const row of legacy) {
      addVenueAmount(byEpoch, epochKey, row.adapter, row.dapp, BigInt(row.amount));
    }
  }

  const venueMeta = new Map<string, { adapter: string; dapp: string; label: string }>();
  const epochsOut = [...byEpoch.entries()]
    .sort(([a], [b]) => Number(a) - Number(b))
    .map(([epoch, entry]) => {
      const venues = [...entry.venues.values()].map((v) => {
        const label = shortVenue(v.dapp, v.adapter);
        venueMeta.set(v.adapter, { adapter: v.adapter, dapp: v.dapp, label });
        return {
          adapter: v.adapter,
          dapp: v.dapp,
          label,
          amount: v.amount.toString(10),
        };
      });
      return {
        epoch: Number(epoch),
        settled: settledByEpoch.get(epoch) ?? false,
        total: entry.total.toString(10),
        venues,
      };
    });

  return {
    token,
    legacyFallback,
    venues: [...venueMeta.values()],
    epochs: epochsOut,
  };
}
