import { and, eq } from "drizzle-orm";
import { getDb, positions } from "@/db";
import { isAddress, normalizeAddress } from "@/lib/chain";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

type Params = { params: Promise<{ address: string }> };

export async function GET(request: Request, { params }: Params) {
  const { address } = await params;
  if (!isAddress(address)) {
    return jsonWithCors({ error: "Invalid address" }, { status: 400, request });
  }

  const chainId = getChainId();
  const db = getDb();
  const rows = await db
    .select()
    .from(positions)
    .where(
      and(
        eq(positions.chainId, chainId),
        eq(positions.owner, normalizeAddress(address)),
      ),
    );

  return jsonWithCors(
    {
      positions: rows.map((p) => ({
        tokenId: p.tokenId,
        owner: p.owner,
        amount: p.amount,
        unlockTime: Number(p.unlockTime),
        penaltyCapBps: p.penaltyCapBps,
        closed: p.closed,
        firstEligibleEpoch: p.firstEligibleEpoch,
        exitEpoch: p.exitEpoch,
        createdAtBlock: p.createdAtBlock,
        updatedAtBlock: p.updatedAtBlock,
      })),
    },
    { request },
  );
}
