import { NextResponse } from "next/server";
import { loadEnv } from "./env";

export function assertCronAuth(request: Request): NextResponse | null {
  const { CRON_SECRET } = loadEnv();
  if (!CRON_SECRET) {
    return NextResponse.json({ error: "CRON_SECRET not configured" }, { status: 500 });
  }

  const bearer = request.headers.get("authorization");
  const headerSecret = request.headers.get("x-cron-secret");
  const token =
    headerSecret ??
    (bearer?.toLowerCase().startsWith("bearer ") ? bearer.slice(7).trim() : null);

  if (!token || token !== CRON_SECRET) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  return null;
}
