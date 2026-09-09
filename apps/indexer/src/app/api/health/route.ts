import { eq } from "drizzle-orm";
import { getDb, syncCursors } from "@/db";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

export async function GET(request: Request) {
  const chainId = getChainId();
  try {
    const db = getDb();
    const cursors = await db
      .select()
      .from(syncCursors)
      .where(eq(syncCursors.chainId, chainId));

    return jsonWithCors(
      {
        ok: true,
        chainId,
        cursors: cursors.map((c) => ({
          contractKey: c.contractKey,
          fromBlock: c.fromBlock,
        })),
      },
      { request },
    );
  } catch (err) {
    return jsonWithCors(
      {
        ok: false,
        chainId,
        error: err instanceof Error ? err.message : String(err),
      },
      { status: 503, request },
    );
  }
}
