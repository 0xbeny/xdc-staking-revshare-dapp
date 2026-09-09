import { NextResponse } from "next/server";
import { getCorsOrigin } from "./env";

const ALLOWED_METHODS = "GET, OPTIONS";
const ALLOWED_HEADERS = "Content-Type, Authorization, x-cron-secret";

export function corsHeaders(origin?: string | null): HeadersInit {
  const allowed = getCorsOrigin();
  const value =
    allowed === "*"
      ? "*"
      : origin && allowed.split(",").map((o) => o.trim()).includes(origin)
        ? origin
        : allowed.split(",")[0]?.trim() ?? "*";

  return {
    "Access-Control-Allow-Origin": value,
    "Access-Control-Allow-Methods": ALLOWED_METHODS,
    "Access-Control-Allow-Headers": ALLOWED_HEADERS,
    Vary: "Origin",
  };
}

export function jsonWithCors<T>(
  data: T,
  init?: { status?: number; request?: Request },
): NextResponse {
  const origin = init?.request?.headers.get("origin");
  return NextResponse.json(data, {
    status: init?.status ?? 200,
    headers: corsHeaders(origin),
  });
}

export function optionsCors(request: Request): NextResponse {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(request.headers.get("origin")),
  });
}
