# Frontend — `@vexdc/web`

Next.js 15 App Router dApp for veXDC lockers. Visual system: [`apps/web/design.md`](../apps/web/design.md).

## Stack

- Next.js 15, React 19, TypeScript
- wagmi v2 + viem + TanStack Query
- Recharts (earnings / protocol charts)
- `@vexdc/contracts` for ABIs + Apothem addresses

## Env

```bash
cp apps/web/.env.example apps/web/.env.local
```

| Variable | Example |
|---|---|
| `NEXT_PUBLIC_CHAIN_ID` | `51` |
| `NEXT_PUBLIC_RPC_URL` | `https://rpc.apothem.network` |
| `NEXT_PUBLIC_INDEXER_URL` | `https://your-indexer.vercel.app` |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | WalletConnect cloud id |

## Scripts

```bash
pnpm --filter @vexdc/web dev
pnpm --filter @vexdc/web build
pnpm --filter @vexdc/web start
```

## Vercel (production)

| App | URL |
|---|---|
| Web | https://ve.xdcai.tech |
| Indexer | https://api.ve.xdcai.tech |

Projects (team `0xbenys-projects`): `vexdc-web`, `vexdc-indexer`. Root directories `apps/web` / `apps/indexer`.

Hobby plan limits crons to **once per day** — indexer uses daily sync/keeper schedules. Upgrade to Pro for `*/5` sync.

Set `DATABASE_URL` (Neon) and `KEEPER_PRIVATE_KEY` on `vexdc-indexer` before sync/keeper are useful.

Root directory: `apps/web`. Build: `cd ../.. && pnpm prepare:contracts && pnpm --filter @vexdc/contracts build && pnpm --filter @vexdc/web build` (or rely on workspace install + `next build` with `transpilePackages`).

Set the `NEXT_PUBLIC_*` env vars in the Vercel project (`NEXT_PUBLIC_INDEXER_URL=https://api.ve.xdcai.tech`).

## Routes

| Path | Purpose |
|---|---|
| `/` | Brand hero + Zap deposit |
| `/dashboard` | Positions + protocol charts |
| `/position/[tokenId]` | Manage, claim, exit |

Live reads (weight, claimable) use RPC. History/charts use the indexer API.
