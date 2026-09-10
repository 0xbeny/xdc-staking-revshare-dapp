import { and, eq, sql } from "drizzle-orm";
import { getDeployment } from "@vexdc/contracts";
import { getDb, adapters, contributions, epochs } from "@/db";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";
import { aggregateFeesByVenue } from "@/lib/fees-by-venue";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

/**
 * Fees notified per epoch, broken down by venue/adapter for stacked bar charts.
 * Defaults to USDC when that reward token has data; otherwise WXDC / first token.
 * Falls back to epoch-less contribution rows when RevenueNotified epoch tagging
 * is not yet backfilled.
 */
export async function GET(request: Request) {
  const chainId = getChainId();
  const db = getDb();
  const deployment = getDeployment(chainId);
  const url = new URL(request.url);
  const tokenParam = url.searchParams.get("token")?.toLowerCase() ?? null;

  const venueRows = await db
    .select({
      epoch: contributions.epoch,
      token: contributions.token,
      adapter: contributions.adapter,
      dapp: adapters.dapp,
      amount: sql<string>`coalesce(sum(${contributions.amount}::numeric), 0)::text`,
    })
    .from(contributions)
    .leftJoin(
      adapters,
      and(eq(adapters.chainId, contributions.chainId), eq(adapters.adapter, contributions.adapter)),
    )
    .where(eq(contributions.chainId, chainId))
    .groupBy(contributions.epoch, contributions.token, contributions.adapter, adapters.dapp);

  const settledRows = await db
    .select({
      epoch: epochs.epoch,
      token: epochs.token,
      settled: epochs.settled,
    })
    .from(epochs)
    .where(eq(epochs.chainId, chainId));

  const result = aggregateFeesByVenue({
    rows: venueRows,
    settled: settledRows,
    tokenParam,
    usdc: deployment?.usdc,
    wxdc: deployment?.wxdc,
  });

  return jsonWithCors(result, { request });
}
