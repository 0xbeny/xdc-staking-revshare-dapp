import { asc, eq } from "drizzle-orm";
import { getDb, protocolStats } from "@/db";
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
    .from(protocolStats)
    .where(eq(protocolStats.chainId, chainId))
    .orderBy(asc(protocolStats.day));

  const points = rows.map((r) => ({
    day: r.day,
    totalLocked: r.totalLocked,
    epochRevenueWxdc: r.epochRevenueWxdc,
    epochRevenueUsdc: r.epochRevenueUsdc,
    positionCount: r.positionCount,
  }));

  return jsonWithCors({ points }, { request });
}
