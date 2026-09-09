# veXDC Staking — v1

Real-yield `ve` staking for the [XDC Network](https://xdc.org). Users lock XDC/WXDC for
whole-week periods (1–104 weeks) and receive a **soulbound veNFT**. Whitelisted dApps commit
revenue through **immutable adapters**; each weekly epoch distributes that revenue pro-rata to
snapshotted `ve` weight. Early exit forfeits part of the principal to the remaining lockers.

No emissions token. No split/merge. No transfer path. No `wrapInto`. No PenaltyManager.

Implements [`veXDC Staking — v1 Architecture Specification`, draft v0.5](docs/SPEC.md).

## Layout

```
src/
  VotingEscrow.sol            immutable · soulbound veNFT, weight, penalty rules + params
  FeeDistributor.sol          UUPS      · weekly epochs, bounded claims, forfeiture, carry-forward
  RevenueRegistry.sol         UUPS      · adapter whitelist + terms (metadata only, no custody)
  ZapDepositor.sol            immutable · native XDC → lock in one tx
  adapters/                   immutable · PushAdapter (A) · FeeSplitter (B) · PullAdapter (B2)
                                          ZodiacFeeModule (B3) · Attestor (C)
  governance/VeVotesAdapter   immutable · read-only IVotes over ve weight
  libraries/EpochTime.sol               · week-aligned epoch arithmetic
script/
  VeXDCDeployer.sol           the wiring, shared by the deploy script and the test harness
  Deploy.s.sol                full system deploy + governance hand-over + self-verification
  DeployAdapter.s.sol         one adapter per run; prints the timelock's registration calldata
  LocalMocks.s.sol            anvil rehearsal
test/
  unit/  e2e/  fuzz/  invariant/
docs/
  SPEC.md  ARCHITECTURE.md  DEPLOYMENT.md  OPERATIONS.md  INTEGRATION.md  SECURITY.md
```

## Quick start

```bash
git clone --recursive <repo>
cp .env.example .env         # fill in RPC + addresses; never commit it
forge build
forge test                   # 197 tests: unit · e2e · fuzz · invariant
make ci                      # the full local gate: fmt · lint · sizes · tests · strict invariants · coverage · slither
make slither-install         # one-time: puts slither in ./.venv so `make ci` includes it
```

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

## Deploying to XDC mainnet

[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). The script refuses EOA governance on chain 50,
verifies its own wiring, and ends with the deployer holding no role anywhere.

## Security

[docs/SECURITY.md](docs/SECURITY.md) — trust boundaries, the named invariants and where each is
enforced, the three bug classes the suite caught before launch, and the accepted risks.

## License

MIT
