import { and, asc, eq, inArray } from "drizzle-orm";
import { getDb, claims, positionEvents } from "@/db";
import { jsonWithCors, optionsCors } from "@/lib/cors";
import { getChainId } from "@/lib/env";

export function OPTIONS(request: Request) {
  return optionsCors(request);
}

type Params = { params: Promise<{ address: string }> };

const EARNINGS_EVENTS = ["Claimed", "Compounded", "Deposit", "Zapped", "ZapIncreased"] as const;

/**
 * Path is `/api/positions/[tokenId]/earnings`.
 * The dynamic segment is named `address` to share the Next.js folder with owner lookup.
 */
export async function GET(request: Request, { params }: Params) {
  const { address: tokenId } = await params;
  if (!/^\d+$/.test(tokenId)) {
    return jsonWithCors({ error: "Invalid tokenId" }, { status: 400, request });
  }

  const chainId = getChainId();
  const db = getDb();

  const [claimRows, eventRows] = await Promise.all([
    db
      .select()
      .from(claims)
      .where(and(eq(claims.chainId, chainId), eq(claims.tokenId, tokenId)))
      .orderBy(asc(claims.blockNumber), asc(claims.id)),
    db
      .select()
      .from(positionEvents)
      .where(
        and(
          eq(positionEvents.chainId, chainId),
          eq(positionEvents.tokenId, tokenId),
          inArray(positionEvents.eventName, [...EARNINGS_EVENTS]),
        ),
      )
      .orderBy(asc(positionEvents.blockNumber), asc(positionEvents.logIndex)),
  ]);

  const claimPoints = claimRows.map((c) => ({
    amount: c.amount,
    token: c.token,
    txHash: c.txHash,
    blockNumber: Number(c.blockNumber),
    claimCursor: c.claimCursor,
    to: c.to,
  }));

  return jsonWithCors(
    {
      tokenId,
      claims: claimPoints,
      points: claimPoints,
      events: eventRows.map((e) => ({
        eventName: e.eventName,
        txHash: e.txHash,
        logIndex: e.logIndex,
        blockNumber: e.blockNumber,
        payload: e.payload,
        createdAt: e.createdAt.toISOString(),
      })),
    },
    { request },
  );
}
