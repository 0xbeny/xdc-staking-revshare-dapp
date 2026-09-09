# @vexdc/indexer

Vercel-ready Next.js App Router indexer for veXDC: syncs contract logs into Neon Postgres and exposes read APIs for the web app.

## Stack

- Next.js 15 (App Router) + TypeScript strict
- Drizzle ORM + `@neondatabase/serverless` (HTTP)
- viem for `eth_getLogs` / contract reads
- `@vexdc/contracts` for ABIs and deployments

## Setup

```bash
# from repo root
pnpm install
cp apps/indexer/.env.example apps/indexer/.env
# set DATABASE_URL, CRON_SECRET, optional KEEPER_PRIVATE_KEY

pnpm --filter @vexdc/contracts build
pnpm --filter @vexdc/indexer db:generate
pnpm --filter @vexdc/indexer db:migrate
pnpm --filter @vexdc/indexer dev   # http://localhost:3001
```

## API

| Method | Path | Auth |
|--------|------|------|
| GET | `/api/health` | — |
| POST/GET | `/api/sync` | Bearer `CRON_SECRET` or `x-cron-secret` |
| GET | `/api/positions/[address]` | CORS |
| GET | `/api/positions/[tokenId]/earnings` | CORS |
| GET | `/api/protocol/tvl` | CORS |
| GET | `/api/protocol/revenue` | CORS |
| GET | `/api/adapters` | CORS |
| POST/GET | `/api/keeper` | Bearer `CRON_SECRET` |

Vercel Cron is configured in `vercel.json` (`/api/sync` every 5m, `/api/keeper` every 30m).

## Notes

- If `getDeployment(DEPLOYMENT_CHAIN_ID)` is not live, sync/keeper no-op with a message.
- See [docs/INDEXER.md](../../docs/INDEXER.md) for schema and sync details.
