# Security model

## Trust boundaries

| Actor | Can | Cannot |
|---|---|---|
| **User** | lock, increase, extend, withdraw at expiry, exit early at the immutable penalty, claim, set recipient / keeper flags / operators | transfer, split, merge, wrap, avoid the penalty |
| **Operator** (user-approved) | `increaseUnlockTime` on that user's positions | compound / `claimAndLock`, move principal, anything else |
| **Keeper** (`KEEPER_ROLE`) | extend opted-in locks in the window, compound opted-in rewards (`autoCompound`) | move principal, redirect claims, change parameters |
| **Guardian** (`PAUSER_ROLE`) | pause the distributor | unpause, touch the escrow, touch parameters |
| **Timelock** (`DEFAULT_ADMIN`, `UPGRADER`, `REGISTRY_ADMIN`, escrow `timelock`) | **lower** `maxPenaltyBps` / tune `penaltySplitBps` within immutable clamps, set eligibility tiers, register/deactivate adapters, add reward tokens, unpause, upgrade the two UUPS contracts, rotate the Mode C reporter | move principal, change penalty destinations, **raise** `maxPenaltyBps`, raise an existing position's cap, bypass the clamps, upgrade the escrow |
| **Reporter** (Mode C) | post one immutable record + transfer per period | choose a distribution epoch, edit a record, pull from the distributor |
| **Adapter** (registered) | notify revenue for the tokens it supports | anything once deactivated |

Every role id lives in [`src/libraries/Roles.sol`](../src/libraries/Roles.sol). Membership is
stored once in immutable [`SystemAccess`](../src/SystemAccess.sol), keyed by **target contract**
(`hasRole(target, role, account)`). Timelock holds the hub's `DEFAULT_ADMIN_ROLE` and is the only
address that can grant/revoke. Consumers (`FeeDistributor`, `RevenueRegistry`, `Attestor`) keep
convenience `hasRole(role, account)` views that read their own target slice. The immutable escrow
deliberately does not use SystemAccess: it has exactly one privileged actor (`timelock`, two-step
transferable) whose powers are clamped by constants.

## Principal safety

- All principal is in `VotingEscrow`, which has no upgrade path, no owner and no `selfdestruct`.
- The only functions that move principal out are `withdraw` (owner, after expiry) and
  `emergencyExit` (owner, before expiry, at the immutable formula). Both are gated by a
  governance-tunable `withdrawalCooldown` (default 24h, max 7d); early-exit penalty and
  `readyAt` are snapshotted at request. Both read only escrow storage and make no external call except the
  token transfers themselves on finalize.
- Penalty destinations are `immutable`. Penalty parameters are clamped by `constant`s.
- A paused or maliciously upgraded distributor cannot reach principal
  (`test_upgradedDistributorStillCannotMovePrincipal`, `test_guardianPauseNeverTouchesPrincipal`).
- The deployer holds no role after deployment (`VeXDCDeployer.verify` asserts this and the
  script reverts otherwise).

## Named invariants (SPEC §7) and where they are enforced

| Invariant | Enforced by |
|---|---|
| Principal: `WXDC.balanceOf(escrow) == totalLocked`, deposits == withdrawals + penalties + locked | `invariant_escrowHoldsExactlyItsOutstandingPrincipal`, `invariant_principalIsConserved` |
| `weight ≤ principal`, `effectiveTime ≤ MAX_LOCK` | `invariant_weightNeverExceedsPrincipal`, `testFuzz_weightNeverExceedsPrincipal`, `testFuzz_effectiveTimeIsAlwaysClamped` |
| `totalSupply == Σ position weight` (incl. clamped region) | `invariant_totalSupplyEqualsSumOfPositions`, `testFuzz_totalSupplyEqualsSumOfPositions` |
| `penaltyBps ≤ min(positionCap, maxPenaltyBps) ≤ HARD_MAX` | `invariant_penaltyStaysWithinTheClamps`, `testFuzz_penaltyIsAlwaysWithinTheClamps` |
| Grandfathering: governance never raises an existing cap; `increase_amount` re-weights exactly; extensions never change it | `testFuzz_governanceCannotWorsenAnExistingPosition`, `testFuzz_increaseAmountReweightsCapWithinBounds`, `testFuzz_extensionsNeverChangeTheCap` |
| Conservation per token: `accounted == notified − claimed`, `balance ≥ accounted`, `claimed ≤ notified` | `invariant_distributorConservesValue`, `testFuzz_claimsNeverExceedNotifications` |
| Denominators immutable post-snapshot; exited position never receives own forfeiture | `test_denominatorIsUnchangedByAnExit`, `test_exitingPositionNeverReceivesItsOwnForfeiture` |
| `exitedWeightByEpoch[e] ≤ supply(e)` | `invariant_exitedWeightNeverExceedsEpochSupply` |
| Effective lock ≥ MIN_LOCK, week-aligned | `testFuzz_effectiveLockIsAtLeastMinLock` |
| Soulbound: no transfer path; no `wrapInto`, split or merge | `VotingEscrow.soulbound.t.sol` |
| Claims: cursor monotonic, bounded, idempotent, no double-pay across pages | `invariant_claimCursorsAreMonotonic`, `testFuzz_pagedClaimsSumToTheSameTotal`, `testFuzz_repeatedClaimsAreIdempotent` |
| B2/B3: fee Safe balance == 0 after sweep; double-skim moves zero | `Adapters.t.sol` |
| Mode C: unique immutable records, atomic transfer, reporter cannot set distribution epoch, no clawback | `Attestor.t.sol` |
| Keeper: epoch guards, window guard, missed window never corrected, compound at expiry degrades to claim | `FeeDistributor.keeper.t.sol` |
| Zero-supply epochs carry forward, never divide by zero | `test_zeroSupplyEpochCarriesRevenueForward`, `test_settleNeverDividesByZero` |

The invariant suite runs under `make ci` with `fail_on_revert = true`, 256 runs × 64 depth.

## Coverage

`make coverage` reports 100% branch coverage on `FeeDistributor`, `RevenueRegistry`,
`ZapDepositor` and every adapter. `VotingEscrow` reports 57/65 branches; the eight unhit
branches are deliberately defensive and unreachable through any public path, and are kept
rather than deleted because each one bounds the blast radius of a bug that the invariant suite
says does not exist:

| Branch | Why it is unreachable | Why it stays |
|---|---|---|
| `bias < 0` / `slope < 0` clamps in `_globalCheckpoint`, `_applyLock`, `totalSupplyAt` (6) | contributions are added and removed with the same truncated slope, so the aggregate never undershoots zero (`invariant_totalSupplyEqualsSumOfPositions`) | a negative aggregate would corrupt every snapshot; clamping fails safe |
| `unlock - now < MIN_LOCK` after round-up in `createLockFor` | `duration >= MIN_LOCK` is checked first and `ceilWeek` only lengthens | keeps the `effective lock >= MIN_LOCK` invariant local to the function that must uphold it |
| `from != address(0)` in `_update` | every transfer entry point is overridden to revert before reaching `_update` | a second, independent enforcement of soulbound-ness against a future ERC721 base change |

## Bugs the test-suite found before launch

These are recorded because each one is a class, not an instance:

1. **Snapshot-boundary eligibility.** A position created exactly on a week boundary is inside
   that epoch's snapshot denominator. Starting its claim cursor one epoch later stranded its
   slice. Fixed with `firstEligibleEpoch = epochOf(ceilWeek(createdAt))`.
2. **Mid-block cache freeze.** Memoising a week-boundary supply while `block.timestamp` still
   equals that boundary froze a value that later locks in the same block would change.
   Fixed by memoising only boundaries strictly in the past (both in the escrow and in the
   distributor's cache).
3. **Same-block create-and-exit.** Recording the forfeited weight *before* rewriting the lock
   captured a weight that the snapshot, read later, no longer contained — letting the forfeited
   slice exceed the epoch's whole pot. Fixed by recording after the rewrite.

## Known limitations and accepted risks

- **Counterfactual contracts.** Eligibility is `code.length == 0` at lock time. A CREATE2
  address can gain code later. With soulbound positions and per-tokenId claims, such a contract
  can do no more than an EOA that co-ordinates off-chain. Monitored, not prevented (SPEC §3.1 #10).
- **`_safeMint`.** A whitelisted custodian must implement `onERC721Received`. A Safe with the
  standard compatibility fallback handler does. A contract that does not will revert at lock
  time — before principal is committed — rather than strand it afterwards.
- **Keeper as operator.** `keepAtMaxLock` requires the user to approve the distributor (an
  upgradeable contract) as an operator. The operator right covers *only* extension, which can
  never shorten a lock, touch principal, or change the penalty cap. Users who prefer can
  approve the keeper EOA directly instead, or extend themselves.
- **Late forfeiture sync.** A penalty's locker share is credited to the epoch after the sync
  that notices it, not the epoch after the exit. It is never lost; it may be delayed if no
  claim, settle or sync happens for a while. The keeper syncs on every `EmergencyExit` event.
- **Rounding dust.** Integer division leaves at most one wei per claim in the distributor.
  It is counted in `accounted` and never leaves the contract. This is deliberate: sweeping dust
  would be a path that moves lockers' tokens somewhere other than lockers.
- **Reentrancy.** All state-changing entry points on the escrow and distributor are
  `nonReentrant`; adapter `skim` / `commitRevenue` / `postRevenue` are too. Reward tokens are
  governance-listed; fee-on-transfer tokens are rejected on the escrow (`IncompleteTransfer` when
  `received != amount`) and accounted by balance delta on the distributor; tokens with transfer
  hooks should not be listed.
- **History gaps.** If no lock is touched for more than 255 weeks (≈4.9 years) a single
  checkpoint cannot catch up; `checkpoint()` is permissionless and can be called repeatedly.
  The distributor's own cache and the escrow's week cache make this a theoretical concern.

## Static analysis

The gate is local: `make ci` runs formatting, lint, sizes, tests, strict invariants, coverage
and Slither on the developer's machine (the GitHub workflow mirrors it and runs on demand only).
The lint policy targets **forge v1.8.1** — `make ci FORGE=<path>` — with zero findings on `src/`
and `script/`; tests are linted advisory-only. The rules excluded in `foundry.toml` are listed there
with the reason each does not fit an epoch-based ve design (bounded loops over epochs,
week-aligned timestamp comparisons, events after `nonReentrant`-guarded calls). Every remaining
suppression is inline, next to the code, with its justification.

Slither runs as part of `make ci` (`--fail-high`, config in `slither.config.json`). Two findings are
suppressed inline by design and are worth knowing about:

- `arbitrary-send-erc20` on `PullAdapter.skim` — Mode B2 *is* an allowance-based pull from an
  immutable fee Safe into the immutable adapter, whose split targets are immutable.
- `divide-before-multiply` in `VotingEscrow.weightAt` / `_quoteExit` — the truncated slope and
  the whole-basis-point penalty are the spec's units; the rounding is the intended semantics
  and is what makes `Σ positions == totalSupply` exact.

The reference this forks (Curve `VotingEscrow`, via Velodrome) is audited; the diffs are
enumerated at the top of `VotingEscrow.sol`.

## Reporting

Please report vulnerabilities privately to the maintainers before disclosure. An Immunefi
programme is planned for launch (SPEC §7).
