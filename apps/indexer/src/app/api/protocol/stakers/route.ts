import { and, eq } from "drizzle-orm";
import { getDb, positions } from "@/db";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";
import { aggregateStakers } from "@/lib/stakers";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

export async function GET(request: Request) {
  const chainId = getChainId();
  const db = getDb();
  const rows = await db
    .select({
      tokenId: positions.tokenId,
      owner: positions.owner,
      amount: positions.amount,
      unlockTime: positions.unlockTime,
      closed: positions.closed,
    })
    .from(positions)
    .where(and(eq(positions.chainId, chainId), eq(positions.closed, false)));

  const { stakers, totalAmount, totalWeight, positionCount } = aggregateStakers(rows);

  return jsonWithCors(
    {
      stakers,
      totalAmount,
      totalWeight,
      positionCount,
      stakerCount: stakers.length,
    },
    { request },
  );
}
