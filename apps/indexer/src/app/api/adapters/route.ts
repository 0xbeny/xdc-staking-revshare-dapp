import { asc, eq } from "drizzle-orm";
import { getDb, adapters } from "@/db";
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
    .from(adapters)
    .where(eq(adapters.chainId, chainId))
    .orderBy(asc(adapters.adapter));

  return jsonWithCors(
    {
      adapters: rows.map((a) => ({
        adapter: a.adapter,
        dapp: a.dapp,
        mode: a.mode,
        committedBps: a.committedBps,
        version: a.version,
        termsHash: a.termsHash,
        active: a.active,
      })),
    },
    { request },
  );
}
