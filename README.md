# veXDC Staking — v1

Real-yield `ve` staking for the [XDC Network](https://xdc.org). Users lock XDC/WXDC for
whole-week periods (1–104 weeks) and receive a **soulbound veNFT**. Whitelisted dApps commit
revenue through **immutable adapters**; each weekly epoch distributes that revenue pro-rata to
snapshotted `ve` weight. Early exit forfeits part of the principal to the remaining lockers.

No emissions token. No split/merge. No transfer path. No `wrapInto`. No PenaltyManager.

Implements [`veXDC Staking — v1 Architecture Specification`, draft v0.5](docs/SPEC.md).

## Layout

```
src/                          Solidity core + adapters (Foundry)
script/                       Deploy · ContinueApothem · adapters · mocks
apps/web                      Next.js dApp (Vercel) — design: apps/web/design.md
apps/indexer                  Neon + viem indexer API + keeper cron (Vercel)
packages/contracts            Shared ABIs + TypeScript deployments
deployments/51.json           Live Apothem addresses
test/                         unit · e2e · fuzz · invariant
docs/                         SPEC · ARCHITECTURE · DEPLOYMENT · INDEXER · FRONTEND · …
```

## Quick start

```bash
git clone --recursive <repo>
cp .env.example .env         # fill in RPC + addresses; never commit it
forge build
forge test                   # 197 tests: unit · e2e · fuzz · invariant
make ci                      # the full local gate
make slither-install         # one-time: puts slither in ./.venv so `make ci` includes it
```

Apps (indexer + frontend):

```bash
pnpm install
pnpm prepare:contracts
pnpm --filter @vexdc/contracts build
pnpm --filter @vexdc/indexer dev   # http://localhost:3001
pnpm --filter @vexdc/web dev       # http://localhost:3000
```

See [docs/INDEXER.md](docs/INDEXER.md) and [docs/FRONTEND.md](docs/FRONTEND.md).

Rehearse the real deployment locally:

```bash
make anvil                   # terminal 1
make deploy-local            # terminal 2
```

## How it works, in one screen

- **Weight** `= (amount / MAX_LOCK) × min(unlock − now, MAX_LOCK)`. Unlock rounds *up* to a
  Thursday; the clamp means a 104-week lock never earns more than 1.0×. Globally this is a
  Curve-style linear decay with a *deferred slope activation* for the clamped week, so
  `totalSupply == Σ positions` to the wei.
- **Epochs** are weeks. Revenue received in epoch `n` is split by the weights snapshotted at
  the *start* of `n` and becomes claimable when `n` closes. Attribution is the receipt time —
  nothing can name a past epoch.
- **Early exit** costs `cap × min(remaining, MAX_LOCK) / MAX_LOCK` of principal, continuous
  to zero at expiry. `cap` is snapshotted per position and can only ever go down; adding
  principal re-weights it, extending never changes it. 80% of the penalty streams to the
  remaining lockers from the next epoch, 20% to the treasury (tunable ≤ 50%, destinations
  immutable).
- **Claims** are cursor-bounded (52 epochs per call). Zero-supply epochs carry forward.
  Exited positions keep every finalized epoch and forfeit the in-progress one.
- **Governance** can tune two parameters inside immutable clamps, whitelist custodians,
  register adapters and upgrade the two peripheral contracts. It cannot touch principal.

Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Deploying to XDC Apothem / mainnet

Apothem (chain 51) is live — see [`deployments/51.json`](deployments/51.json).

```bash
# 1) mock USDC (canonical WXDC already on Apothem)
make deploy-apothem-mocks   # or forge script … --private-key $DEPLOYER_PRIVATE_KEY

# 2) core system (use --gas-estimate-multiplier 200 on Apothem)
make deploy-apothem-pk

# If a CREATE proxy OOGs mid-script, set SYSTEM_ACCESS / REVENUE_REGISTRY* and:
make deploy-apothem-continue
```

Use a **separate** EOA for `TIMELOCK` / `GUARDIAN` / `KEEPER` from the deployer — handover
renounces the deployer, and `verify()` rejects leftover deployer roles.

After deploy: register adapters via the timelock, then run [OPERATIONS.md](docs/OPERATIONS.md)
for ≥2 epoch boundaries (skim, keepAtMaxLock, batchCompound, claim, early exit, syncForfeiture).

### Vercel

| App | Production URL |
|---|---|
| Web | https://ve.xdcai.tech |
| Indexer | https://api.ve.xdcai.tech |

```bash
# From repo root (projects already linked under 0xbenys-projects)
vercel link --yes --scope 0xbenys-projects --project vexdc-web && vercel deploy --prod --yes --scope 0xbenys-projects
vercel link --yes --scope 0xbenys-projects --project vexdc-indexer && vercel deploy --prod --yes --scope 0xbenys-projects
```

Indexer needs `DATABASE_URL` (Neon) + optional `KEEPER_PRIVATE_KEY` in the Vercel project env. Hobby plan: crons are daily only.

Mainnet: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). The script refuses EOA governance on chain 50,
verifies its own wiring, and ends with the deployer holding no role anywhere.

## Security

[docs/SECURITY.md](docs/SECURITY.md) — trust boundaries, the named invariants and where each is
enforced, the three bug classes the suite caught before launch, and the accepted risks.

## License

MIT
