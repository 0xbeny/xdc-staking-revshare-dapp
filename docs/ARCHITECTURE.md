# How the system works

This document explains the v1 implementation contract by contract, with the formulas and the
places where the code deliberately differs from the Curve/Velodrome reference it forks. Read
[`SPEC.md`](SPEC.md) first for the *why*; this is the *how*.

```
                       ┌──────────────────────────────────────────────────────┐
                       │                    Governance                         │
                       │   Timelock (admin, params)   Guardian (pause only)    │
                       └───────────┬───────────────────────────┬──────────────┘
                                   │                           │
   native XDC ─▶ ZapDepositor ─▶ ┌─▼──────────────┐      ┌─────▼──────────────┐
   WXDC ─────────────────────▶  │  VotingEscrow  │      │   FeeDistributor   │
                                │  (immutable)   │◀────▶│   (UUPS proxy)     │
                                │  veNFT + weight│ reads │  epochs · claims   │
                                │  penalty rules │       │  bucket · carry    │
                                └───────┬────────┘       └─────▲──────────────┘
                                        │ penalty (80%)        │ notifyRevenue
                                        └──────────────────────┤
                                                               │
        dApp fees ─▶ FeeSplitter / PullAdapter / ZodiacFeeModule / PushAdapter / Attestor
                                        (immutable adapters)   │
                                                      RevenueRegistry (UUPS, metadata only)
```

## Contract inventory

| Contract | Mutability | Holds funds | Role |
|---|---|---|---|
| `VotingEscrow` | immutable | **all principal** | soulbound veNFT, weight, penalty rules and parameters |
| `ZapDepositor` | immutable | never | native XDC → WXDC → lock, in one tx |
| `FeeDistributor` | UUPS | revenue awaiting claim | weekly epoch accounting and claims |
| `RevenueRegistry` | UUPS | never | which adapters may notify, and their terms |
| `PushAdapter` (A) | immutable | never between calls | dApp pushes committed revenue |
| `FeeSplitter` (B) | immutable | never between calls | dApp's fee receiver; anyone skims |
| `PullAdapter` (B2) | immutable | never between calls | sweeps a dedicated fee Safe by allowance |
| `ZodiacFeeModule` (B3) | immutable | never between calls | sweeps a dedicated fee Safe as a Safe module |
| `Attestor` (C) | immutable | never between calls | atomic epoch attestations by a reporter |
| `VeVotesAdapter` | immutable | never | read-only `IVotes` view over ve weight |

The rule of thumb: **anything that can be upgraded never holds principal, and anything that
holds principal can never be upgraded.**

## Time

Everything runs on week-aligned epochs. Unix time 0 was a Thursday, so `timestamp / 1 weeks`
is a Thursday-00:00-UTC epoch index without any offset. `EpochTime` is the only place this
arithmetic lives.

- `epochOf(t) = t / WEEK`
- `startOfEpoch(e) = e * WEEK`
- `ceilWeek(t)` — used for unlock rounding (always **up**).

## VotingEscrow

### Locking

`createLockFor(beneficiary, amount, duration)`:

1. `duration` must be a whole number of weeks in `[1, 104]`.
2. `unlock = ceilWeek(now + duration)` — rounds **up**, so the effective lock is never shorter
   than asked. It can be up to `WEEK - 1` seconds *longer*.
3. The beneficiary must be an EOA, or a contract with a `CUSTODIAN`/`WRAPPER` tier.
4. The position records `penaltyCapBps = maxPenaltyBps` at that instant (grandfathering).
5. It also records `firstEligibleEpoch = epochOf(ceilWeek(now))` — the first epoch whose
   start-of-epoch snapshot can contain it.
6. Principal is credited from the **balance delta** of the escrow token transfer: if
   `received != amount` the call reverts (`IncompleteTransfer`). This keeps
   `totalLocked == token.balanceOf(escrow)`.

`increaseAmount(tokenId, amount)` is **permissionless** (Curve-style): anyone may add
principal and thereby re-weight the position's grandfathered penalty cap. `ZapDepositor.zapIncreaseAmount`
is owner-only because the zap is a consent UX for native XDC; compounding and third-party
funding use the escrow path directly.

### Weight

The canonical weight formula is the **truncated slope** (not `amount × eff / MAX_LOCK`):

```
slope  = amount / MAX_LOCK              (integer division, done once)
weight = slope × min(unlock − t, MAX_LOCK)
```

Using the truncated slope as the unit of weight — rather than `amount × eff / MAX_LOCK` — is
deliberate. It makes the per-position read and the global aggregate agree **to the wei**, which
the distributor's conservation property depends on, and it gives `weight ≤ amount` for free.
The cost is that a position smaller than ~6.3e7 wei (`MAX_LOCK` in seconds) has zero weight;
that is dust for any 18-decimal token.

### The clamp, globally

Curve's aggregate works because every position's weight is a straight line to zero at
`unlock`, so the global point only needs a bias, a slope, and a schedule of slope changes at
week boundaries. The clamp breaks the straight line: a max lock whose unlock rounded up past
`MAX_LOCK` is *flat* for up to a week, then decays.

The implementation models this as a **deferred slope activation**:

```
activation = unlock − MAX_LOCK          (week-aligned, because MAX_LOCK is whole weeks)

if activation ≤ now:   contribute bias = slope × (unlock − now),  slope = slope
else:                  contribute bias = slope × MAX_LOCK,        slope = 0
                       schedule  slopeChanges[activation] += slope
always:                schedule  slopeChanges[unlock]     −= slope
```

Both `activation` and `unlock` sit on the existing weekly `slopeChanges` schedule, so the
Curve stepping loop handles them without a new mechanism. The invariant
`totalSupply() == Σ balanceOfNFT(id)` is asserted at every step of the invariant suite,
including inside the clamped region.

### History

- **Global:** `pointHistory[epoch] = (bias, slope, ts)`, advanced by `_globalCheckpoint()`
  which steps week by week from the last point to `now`, applying `slopeChanges`. Every week
  boundary it crosses is memoised in `_weekSupply` — but **only boundaries strictly in the
  past**. A boundary equal to `block.timestamp` may still receive locks later in the same block,
  so freezing it would desynchronise the distributor's denominator from its numerator.
- **Per position:** `_userPointHistory[tokenId]` stores `(amount, unlock, ts)` — the lock
  itself, not a `(bias, slope)` pair. `balanceOfNFTAt(id, t)` binary-searches for the last point
  at or before `t` and recomputes the clamped formula. Historic weight can therefore never drift
  from the formula, and it survives the position being zeroed later.

### Penalty (`emergencyExit`)

```
eff        = min(unlock − now, MAX_LOCK)
cap        = min(position.penaltyCapBps, maxPenaltyBps)
penaltyBps = cap × eff / MAX_LOCK               → continuous to 0 at expiry, no floor
penalty    = amount × penaltyBps / 10_000
toTreasury = penalty × penaltySplitBps / 10_000  (≤ 50%, immutable clamp)
toLockers  = penalty − toTreasury                 → transferred to the distributor
```

`maxPenaltyBps` and `penaltySplitBps` are storage variables settable only by the timelock,
clamped by the immutable constants `HARD_MAX_PENALTY_BPS = 5000` and
`HARD_MAX_PENALTY_SPLIT_BPS = 5000`. The two destinations are `immutable`. There is no
PenaltyManager; `emergencyExit` makes no external call except the three WXDC transfers.

**Grandfathering.** `position.penaltyCapBps` is snapshotted at creation. Governance lowering
the global cap helps everyone at once (`min`); raising it never reaches an existing position.
`increaseAmount` re-weights the cap so old principal keeps its exact terms and new principal
enters at current terms:

```
newCap = (oldPrincipal × oldCap + added × maxPenaltyBps) / newPrincipal
```

`increaseUnlockTime` (and `keepAtMaxLock`) never touch the cap.

**Recording the forfeited share.** The exiting position loses its slice of the *current*
epoch. The escrow records `exitedWeightByEpoch[currentEpoch] += balanceOfNFTAt(id, epochStart)`
so the distributor can later move exactly that slice forward. This is read *after* the lock is
rewritten so that the recorded figure is exactly what the distributor's later read will see —
a position created and exited inside the same block as a boundary is absent from both sides of
the fraction and forfeits nothing.

### Positions are never burned

`withdraw` and `emergencyExit` zero the lock and mark the position `closed`, but the NFT stays
with its owner. Already-finalized epochs remain claimable through the distributor after either
exit, and the `exitEpoch` recorded on the position caps what an exited position can claim.

### Operators

`setOperator(operator, approved)` grants **only** the right to call `increaseUnlockTime`
on the owner's positions. It is how a user lets the keeper run `keepAtMaxLock`. Operators can
never withdraw, exit, transfer, or claim to a different address.

## FeeDistributor

### Attribution

`notifyRevenue(token, amount)` credits `epochRevenue[token][currentEpoch]`. There is no
argument that could name a different epoch. A skim that lands ten seconds after a boundary is
next week's revenue.

Only adapters the registry marks active may call it, and only for tokens the distributor has
been told to accept. The distributor records the contribution back into the registry so the
registry can show lifetime totals without ever touching funds.

### Settlement

`settle(token, maxEpochs)` is permissionless and bounded. It walks closed epochs in order and,
for each one:

- if the snapshot supply was **zero**, moves the whole pot to the next epoch (carry-forward);
- otherwise, if positions **exited** during that epoch, adds
  `pot × exitedWeight / supply` to the next epoch's pot — **without** subtracting from this
  one. Remaining lockers still claim `pot × w / supply` against the unchanged denominator,
  which sums to exactly the part that was not forfeited.

Epochs below `settledEpoch[token]` are final. Claims only read final epochs.

### Claims

`claim(tokenId, tokens[])` is permissionless (it always pays the position's recipient) and
walks at most `MAX_EPOCHS_PER_CLAIM = 52` epochs per token, from the position's cursor up to
`min(settledEpoch, exitEpoch)`. It returns `remaining > 0` when **closed** epochs still sit
ahead of the cursor (the open epoch is excluded). That signal includes closed-but-unsettled
epochs so a bounded `settle` inside `claim` still prompts another call. The cursor starts at
`firstEligibleEpoch`.

`claimAndLock` claims WXDC and folds it straight back via `increaseAmount` — so the
weighted-cap rule applies — and degrades to a plain claim once the lock has expired or closed.

### Forfeiture bucket

The escrow sends the lockers' share of every penalty straight to the distributor as a plain
ERC-20 transfer, with no callback (so `emergencyExit` has no liveness dependency on the
distributor). `syncForfeiture(token)` — permissionless, and run by every `settle` and `claim` —
notices `balanceOf > accounted` and credits the difference to `currentEpoch + 1`: the first
epoch whose snapshot excludes the position that exited. A late sync only delays the credit;
it never backdates it and never loses it.

### Keeper batches

- `batchKeepAtMaxLock(ids, expectedEpoch)` — only inside the last `KEEPER_WINDOW = 2 hours`
  of an epoch, only for positions flagged `keepAtMaxLock`, epoch-guarded, tolerant of
  individual failures. A missed window is never retroactively corrected.
- `batchCompound(ids, expectedEpoch)` — post-boundary, only for `autoCompound` positions.

## RevenueRegistry

Pure metadata: `(dapp, mode, committedBps, version, termsHash, active)` per adapter, plus
lifetime contribution per `(adapter, token)`. It never holds a balance or an allowance. Terms
are versioned metadata; changing them cannot change an adapter's on-chain behaviour — a new
commitment means a new adapter. `setDistributor` is one-shot (mirrors `FeeDistributor.setEscrow`).
Modes A/B/B2/B3 require `committedBps ∈ (0, 10_000]`; Mode C may record `0` as metadata.

## Adapters

All adapters share `RevenueAdapterBase`: `(SOURCE, DISTRIBUTOR, DAPP_TREASURY,
COMMITTED_BPS, tokens)` are fixed at construction with no setter, no owner and no upgrade
path. Sweep / commit / attest entry points are `nonReentrant`. Every sweep splits the full
amount in the same transaction, so an adapter never holds a balance between calls. B2 and B3
additionally leave the dedicated fee Safe at a zero balance — B3 asserts that after Safe
`exec` (raw `transfer` is not SafeERC20-hardened, so a false-returning token reverts
`SweepIncomplete` rather than reporting a successful empty skim).

The Attestor (Mode C) is the one adapter that serves many dApps: one immutable record per
`(dapp, token, sourceEpoch)` via `postRevenue(dapp, token, sourceEpoch, gross, adjustment, metadataHash)`;
funds transferred in the same transaction, `distributionEpoch` assigned at receipt. Corrections
are posted against a later source period; a negative adjustment nets against that transfer and
never pulls from the distributor.

## VeVotesAdapter

A read-only `IVotes` over the escrow: `getVotes` sums an owner's positions,
`getPastVotes` reads checkpointed history, `getPastTotalSupply` reads the global history.
Delegation reverts rather than silently no-op'ing; v1 weight is always self-held.

## Deployment topology

The escrow takes the distributor as an `immutable` penalty destination, so the distributor
proxy must exist first. `script/VeXDCDeployer.sol` encodes the order — registry proxy,
distributor proxy, escrow, wiring, zap, votes — and the hand-over that grants every role to
governance and renounces the deployer's. The test harness uses the same library, so the
topology under test is the topology that ships.
