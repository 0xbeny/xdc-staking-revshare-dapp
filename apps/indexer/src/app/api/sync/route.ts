import { assertCronAuth } from "@/lib/auth";
import { runSync } from "@/lib/sync";

export const maxDuration = 60;
export const dynamic = "force-dynamic";

async function handle(request: Request) {
  const denied = assertCronAuth(request);
  if (denied) return denied;

  try {
    const result = await runSync();
    return Response.json(result);
  } catch (err) {
    return Response.json(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      { status: 500 },
    );
  }
}

/** Vercel Cron issues GET; local/ops may POST. */
export async function GET(request: Request) {
  return handle(request);
}

export async function POST(request: Request) {
  return handle(request);
}
