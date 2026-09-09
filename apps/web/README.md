# @vexdc/web

Next.js 15 frontend for veXDC staking and revenue share. Design system: [`design.md`](./design.md).

## Setup

```bash
# from monorepo root
pnpm install
pnpm --filter @vexdc/contracts build
cp apps/web/.env.example apps/web/.env.local
# set NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID
pnpm --filter @vexdc/web dev
```

Open [http://localhost:3000](http://localhost:3000).

## Env

| Variable | Description |
|----------|-------------|
| `NEXT_PUBLIC_CHAIN_ID` | `51` Apothem (default) or `50` mainnet |
| `NEXT_PUBLIC_RPC_URL` | XDC JSON-RPC |
| `NEXT_PUBLIC_INDEXER_URL` | Indexer origin (charts) |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | WalletConnect Cloud project id |

Addresses come from `@vexdc/contracts`. If deployment is not live, a banner shows and writes stay disabled.

## Scripts

- `pnpm dev` — Next dev server (port 3000)
- `pnpm build` / `pnpm start`
- `pnpm typecheck`

## Docs

See [`docs/FRONTEND.md`](../../docs/FRONTEND.md).
