import { asc, eq } from "drizzle-orm";
import { getDb, epochs } from "@/db";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

export async function GET(request: Request) {
  const chainId = getChainId();
  const db = getDb();
  const rows = await db
    .select()
    .from(epochs)
    .where(eq(epochs.chainId, chainId))
    .orderBy(asc(epochs.epoch), asc(epochs.token));

  const points = rows.map((r) => ({
    epoch: Number(r.epoch),
    token: r.token,
    revenue: r.revenue,
    settled: r.settled,
    supply: r.supply,
    pot: r.pot ?? undefined,
    forfeited: r.forfeited,
  }));

  return jsonWithCors({ points }, { request });
}
