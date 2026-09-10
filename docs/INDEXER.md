# Indexer

The `@vexdc/indexer` app (`apps/indexer`) is a Vercel-deployable Next.js service that:

1. Incrementally indexes veXDC contract logs into Neon Postgres
2. Serves read APIs consumed by `@vexdc/web`
3. Runs keeper batches on a cron (`batchKeepAtMaxLock`, `batchCompound`, optional FeeSplitter `skim`)

## Architecture

```
RPC (Apothem / Mainnet)
        │  eth_getLogs (~2k block chunks)
        ▼
   sync engine (src/lib/sync.ts)
        │  upsert positions / epochs / claims / adapters / …
        ▼
   Neon Postgres (Drizzle schema)
        │
        ▼
   App Router GET APIs  ──CORS──▶  web app
   POST/GET /api/sync   ◀── Vercel Cron (Bearer CRON_SECRET)
   POST/GET /api/keeper ◀── Vercel Cron
```

Deployments come from `@vexdc/contracts` (`getDeployment` / `requireDeployment`). Chain id defaults to **51** (`DEPLOYMENT_CHAIN_ID`). If the deployment is not live (zero addresses / `deployedAt == 0`), sync and keeper **no-op** and return a message — safe for preview deploys before broadcast.

## Tables

| Table | Key | Purpose |
|-------|-----|---------|
| `sync_cursors` | `(chainId, contractKey)` | Next `fromBlock` per contract |
| `positions` | `(chainId, tokenId)` | Current lock state |
| `position_events` | serial + unique `(chainId, txHash, logIndex)` | Event history for charts |
| `epochs` | `(chainId, token, epoch)` | Revenue / settle / forfeiture |
| `claims` | serial | Claimed amounts per position |
| `adapters` | `(chainId, adapter)` | Registry metadata |
| `contributions` | serial | `ContributionRecorded` |
| `protocol_stats` | `(chainId, day)` | Daily TVL snapshot (`YYYY-MM-DD`) |

## Synced events

| Contract | Events |
|----------|--------|
| VotingEscrow | `Deposit`, `LockExtended`, `Withdraw`, `EmergencyExit`, `ExitRequested`, `ExitRequestCancelled` |
| FeeDistributor | `RevenueNotified`, `EpochSettled`, `ForfeitureSynced`, `Claimed`, `Compounded`, `KeepAtMaxLockSet`, `AutoCompoundSet` |
| RevenueRegistry | `AdapterRegistered`, `AdapterDeactivated`, `AdapterReactivated`, `ContributionRecorded` |
| ZapDepositor | `Zapped`, `ZapIncreased` |

After each sync pass, the indexer refreshes `protocol_stats` from `totalLocked`, open position count, and summed epoch revenue (WXDC / USDC).

## API surface

- `GET /api/health` — `ok` + sync cursors for the configured chain
- `POST|GET /api/sync` — run incremental sync (cron auth)
- `GET /api/positions/[address]` — positions owned by address
- `GET /api/positions/[tokenId]/earnings` — claims + related events
- `GET /api/protocol/tvl` — `protocol_stats` time series
- `GET /api/protocol/revenue` — epochs rows
- `GET /api/adapters` — registered adapters
- `POST|GET /api/keeper` — keeper batches (cron auth + `KEEPER_PRIVATE_KEY`)

GET APIs send CORS headers (`CORS_ORIGIN`, default `*`). Cron routes accept `Authorization: Bearer $CRON_SECRET` or `x-cron-secret`.

Both GET and POST are exported for `/api/sync` and `/api/keeper` because **Vercel Cron issues GET**.

## Local / Vercel env

Copy `apps/indexer/.env.example`. Required for real sync:

- `DATABASE_URL` — Neon connection string
- `CRON_SECRET` — shared with Vercel Cron
- `INDEXER_RPC_URL` — optional; defaults to public Apothem/Mainnet RPC
- `KEEPER_PRIVATE_KEY` — optional; keeper no-ops if unset
- `FEE_SPLITTER` / `REWARD_TOKENS` — optional skim targets

## Commands

```bash
pnpm --filter @vexdc/indexer dev
pnpm --filter @vexdc/indexer db:generate
pnpm --filter @vexdc/indexer db:migrate
pnpm --filter @vexdc/indexer test
pnpm --filter @vexdc/indexer typecheck
```

Crons live in `apps/indexer/vercel.json`:

- sync every 5 minutes (`*/5 * * * *`), tip lagged by `SYNC_CONFIRMATIONS` (default 12)
- keeper Wednesday 22:00 UTC (`0 22 * * 3`) for the pre-boundary keep window
- keeper Thursday 00:05 UTC (`5 0 * * 4`) for post-boundary compound / skim

Keeper batches are chunked (`KEEPER_BATCH_SIZE`, default 50). Failed required actions return HTTP 503.
