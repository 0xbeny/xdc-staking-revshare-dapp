# veXDC Staking — v1 Architecture Specification

**Status:** Draft v0.5 · **Chain:** XDC Network (EVM) · **Model:** real-yield ve staking (no emissions token)

**v0.5 changes (second review response):** effective-time clamp `min(timeRemaining, MAX_LOCK)` for weight and penalty (#1) · **split/merge removed from v1** (#2) · bounded claims with `MAX_EPOCHS_PER_CLAIM` cursor (#3) · keeper window moved pre-boundary (#4) · per-position penalty cap grandfathering, with a weighted-average rule closing an `increase_amount` loophole (#5) · Mode C reduced to atomic one-shot submissions with later-period adjustments (#6) · B3 requires a dedicated fee Safe; zero-balance-after-sweep invariant unified across B2/B3 (#7) · revenue attribution frozen to notification time; sourceEpoch vs distributionEpoch separated (#8) · **`wrapInto` removed — Option B** (#9) · SmartWalletChecker reworded, counterfactual-contract threat model stated (#10) · **PenaltyManager removed; parameters live in the escrow behind immutable clamps** (#11) · zero-supply epochs carry revenue forward (#12) · journey example corrected (#13).

**The six frozen decisions** (per reviewer): 1. MAX_LOCK clamping — frozen as §3.1. 2. split/merge — frozen as *absent*. 3. keeper timing — frozen as §5's pre-boundary window. 4. penalty terms for existing positions — frozen as §3.4 grandfathering. 5. Mode C — frozen as §3.2's atomic one-shot. 6. `wrapInto` — frozen as *absent* (Option B).

---

## 1. Concept

Users lock XDC/WXDC for whole-week periods (1 week min, 104 weeks max). They receive a **soulbound veNFT** representing time-weighted stake. Whitelisted dApps commit revenue through standardized immutable adapters; revenue distributes each weekly epoch pro-rata to snapshotted ve weight. Early exit forfeits part of principal to remaining lockers. veXDC checkpointed weight is the future governance primitive. Users wanting multiple maturity profiles create multiple positions — there is no split/merge.

v1 contract inventory is now four immutable contracts (VotingEscrow, ZapDepositor, per-dApp adapters, Attestor) plus two upgradeable ones (FeeDistributor, RevenueRegistry).

---

## 2. System overview

```
        Governance (Multisig → Timelock) — periphery config + escrow params within immutable clamps
                           │
   User ──XDC / WXDC───▶ ZapDepositor ──create_lock_for──▶ ┌──────────────────────┐
                                                          │  VotingEscrow        │
                                                          │  soulbound veXDC NFT │
                                                          │  penalty formula,    │
                                                          │  params, clamps and  │
                                                          │  destinations INSIDE │
                                                          └───────┬──────────────┘
                                                            │ snapshots · penalties
                                                    ┌───────▼──────────┐
    Immutable revenue adapters ──notifyRevenue──▶   │  FeeDistributor  │◀─ forfeiture bucket
    (Splitter · PullAdapter ·                       │  (weekly epochs) │   (epoch-delayed)
     Zodiac module · Attestor)                      └──────────────────┘
              ▲ register/version (metadata only)
        RevenueRegistry
```

**Principal-safety property (named Foundry invariant):** no governance action, module upgrade, registry change, pause, or peripheral contract can move user principal except through the immutable withdrawal and penalty rules enforced inside VotingEscrow. Emergency exit makes **no external calls** for parameters or logic (#11) — it cannot be bricked by any other contract's failure.

---

## 3. Core contracts

### 3.1 VotingEscrow — immutable

**Locking:**
- WXDC or native XDC **only via `ZapDepositor`** → `create_lock_for(beneficiary, ...)`; the escrow rejects every other mint caller. Eligibility is checked against the beneficiary.
- `duration % 1 weeks == 0`, `MIN_LOCK ≤ duration ≤ MAX_LOCK`. Unlock **rounds UP** to the next week boundary; `require(effective ≥ MIN_LOCK)`.
- **Effective-time clamp (#1):** everywhere `timeRemaining` is used, it is first clamped: `effectiveTime = min(unlock − now, MAX_LOCK)`. **Weight uses the truncated slope** `weight = (amount / MAX_LOCK) × effectiveTime` so Σ positions == `totalSupply` to the wei (dust locks with `amount < MAX_LOCK` have zero weight). Penalty uses the same `effectiveTime`. A nominal 104-week lock whose aligned unlock lands at ~104.9 weeks earns exactly 1.0× weight and can never exceed `maxPenaltyBps`. **Invariants: `weight ≤ principal`; `penaltyBps ≤ maxPenaltyBps ≤ HARD_MAX_PENALTY_BPS`.**
- `increase_amount(tokenId, amount)` is **permissionless** (anyone may fund a position; the cap re-weights). `increase_unlock_time(tokenId, newUnlock)` is owner-or-operator only (same round-up + clamp). `ZapDepositor.zapIncreaseAmount` is owner-only as a native-XDC consent UX; auto-compound uses the escrow path.
- `withdraw(tokenId)` after expiry and `emergencyExit(tokenId)` before expiry: both are two-phase
  with a timelock-tunable `withdrawalCooldown` (default 24h, hard max 7d). First call (or
  `requestWithdraw` / `requestEmergencyExit`) arms the exit and **snapshots `readyAt`**; after
  that deadline, a subsequent call pays out. Later cooldown changes do not move pending
  requests. Early-exit penalty is also snapshotted at request. `cancelExitRequest` aborts with
  no funds moved. When cooldown is `0`, a single call still completes.
- **No split, no merge (#2).** Multiple maturities = multiple positions. This deletes checkpoint lineage, reward-debt migration, forced-settlement plumbing, and the mid-epoch entitlement-migration problem from the immutable core entirely.

**Soulbound (#9 — Option B):** `transferFrom`/`safeTransferFrom` revert unconditionally. **There is no `wrapInto` and no transfer carve-out of any kind.** The future stveXDC wrapper accepts only new WXDC deposits; existing veNFT positions are never wrappable. Migration path for existing lockers is natural: every position expires within ≤ 104 weeks, after which the holder can withdraw and re-deposit into the wrapper if they prefer the liquid lane. This keeps v1's escrow free of any underspecified future-module code.

**Contract eligibility (#10):** EOAs (checked as `code.length == 0` at lock time) need no whitelist; contracts require the `CUSTODIAN` (Safes: create + hold own locks) or `WRAPPER` (empty at launch) tier, timelock-added. **Stated honestly:** this is a *protocol-support policy*, not a cryptographic guarantee — a counterfactual CREATE2 address has no code before deployment, so a position could be created for an address that later becomes a contract. Threat model: with soulbound NFTs, no `wrapInto`, and per-tokenId claims, such a contract can hold and claim for its own position (equivalent to an EOA doing the same) and could at most offer off-chain pooled exposure — the same residual risk already accepted for custodians. Monitored (Hermes flags locks to empty-code addresses that later gain code), not claimed impossible.

**Penalty parameters live here (#11):** `maxPenaltyBps` and `penaltySplitBps` are storage variables in the escrow, settable **only by the timelock**, clamped by immutable constants (`HARD_MAX_PENALTY_BPS = 5000`; treasury share ≤ 50%). Penalty destinations (distributor forfeiture bucket, treasury) are immutable addresses. There is no PenaltyManager contract. `emergencyExit` reads only escrow storage — no external call, no liveness dependency, nothing upgradeable on the path.

Checkpointed `balanceOfNFTAt` / `totalSupplyAt` reads; Curve-style linear-decay weight forked from an audited reference, diff-documented; time-based weighting only.

### 3.2 Revenue standard — registry (metadata) + immutable adapters (funds)

Registry: whitelisting, terms/mode/version, lifetime contribution. No allowances, no custody. Adapters hardcode `(source, tokens, committedBps, distributor, dappTreasury)`.

- **Mode A — Push.** `commitRevenue(token, amount)`.
- **Mode B — FeeSplitter (default).** Fee receiver → immutable splitter; permissionless `skim()`.
- **Mode B2 — PullAdapter on a dedicated fee Safe.** Allowance to the immutable adapter only; `skim()` sweeps the full balance (committed → distributor, remainder → dApp treasury).
- **Mode B3 — Zodiac module on a dedicated fee Safe (#7).** Same sweep-both rule. **B3 no longer operates on a general treasury Safe** — commingled treasury capital must never be bps-taxed. The dApp routes fees to a dedicated fee Safe and installs the module there.
- **Unified B2/B3 invariant (#7):** `feeSafe balance == 0` after every successful sweep; everything entering that address is definitionally revenue.
- **Mode C — atomic epoch attestation (#6).** Per-dApp `Attestor` with immutable `DAPP`. `postRevenue(token, sourceEpoch, gross, adjustment, metadataHash)`: exactly one immutable record per `(dapp, token, sourceEpoch)`; record and fund transfer are one atomic transaction; duplicates revert. **No pre-finalization superseding, no mutable state.** `net = gross + adjustment` must be ≥ 0; positive net transfers that amount, zero net records without transferring. Errors are corrected by posting a signed adjustment against a *later* source period — a positive adjustment transfers additional funds; a negative adjustment offsets against that later transfer (never a clawback from the distributor).

**Revenue attribution — frozen rule (#8):**

> Revenue belongs to the distribution epoch in which the FeeDistributor actually receives it. Keeper timing never causes retroactive accounting.

A skim landing 10 seconds into epoch *n+1* is epoch *n+1* revenue, period. Hermes carries a pre-boundary sweep SLA (§5) as an operational target, not an accounting dependency. For Mode C, `sourceEpoch` (what period the revenue relates to — metadata, for dashboards and reconciliation) is strictly separated from `distributionEpoch` (assigned automatically at receipt); **a reporter can never choose a past distribution epoch.**

Lifecycle/versioning and "mechanically enforced on registered revenue flows" terminology unchanged from v0.4. Launch tokens: WXDC + USDC, in-kind.

### 3.3 FeeDistributor — upgradeable (UUPS)

**Frozen epoch rule:** revenue received during epoch *n* is allocated by weights snapshotted at the **start of epoch *n***, claimable after *n* closes. Positions created or increased during *n* first participate in *n+1*.

- Weekly epochs, Thursday 00:00 UTC.
- **Bounded claims (#3):** `claim(tokenId, tokens[])` processes up to `MAX_EPOCHS_PER_CLAIM` (suggest 52) finalized epochs per call and advances the position's cursor; if more remain, the call reports `remaining > 0` and the caller (or Hermes) calls again. No unbounded loops exist anywhere in the system — and with split/merge gone, nothing ever *requires* full settlement in one transaction.
- **Zero-supply epochs (#12):** if `totalSupplyAt(epochStart) == 0`, that epoch's revenue **carries forward to the first epoch with non-zero eligible supply**. Never divide by zero, never sweep to treasury, never strand. Folded into the conservation invariant: per token, claims + forfeiture bucket + carry-forward == total notified.
- **Forfeiture bucket:** unchanged — exit-epoch shares and lockers' penalty share; notifies no earlier than the first epoch whose snapshot excludes the exited tokenId; denominators never modified post-snapshot; exiting positions can never receive their own forfeiture.

**Claim paths:** `claim` (cursor-bounded) · `claimAndLock` (WXDC → `increase_amount`; never extends duration) · keeper flags `autoCompound` and `keepAtMaxLock` (§5 timing) · `setRecipient` (custody/cash-flow split; no transfers exist, so no reset logic).

### 3.4 Penalty system

`emergencyExit(tokenId)`, fully inside the escrow:

- `penalty = effectivePenaltyBps × effectiveTime / MAX_LOCK` with `effectiveTime = min(unlock − now, MAX_LOCK)`. Continuous to zero at expiry; no floor.
- **Grandfathered terms (#5):** each position stores `positionPenaltyCap`, snapshotted from the global `maxPenaltyBps` at creation. Effective cap = `min(positionPenaltyCap, current maxPenaltyBps)`. Governance may only **lower** `maxPenaltyBps` (monotonically non-increasing); raises revert. Reductions benefit everyone immediately. Soulbound + penalty-as-only-door makes this essential: exit economics must be predictable at lock time.
- **`increase_amount` rule:** on `increase_amount`, the cap re-weights — `newCap = (oldPrincipal × oldCap + addedPrincipal × currentGlobal) / newPrincipal`. Old principal keeps its terms exactly; new principal enters at current (≤ prior) terms. With a non-increasing global, a single weighted cap cannot be worsened by later governance. `autoCompound`'s small weekly adds drift the cap only marginally and only toward current terms, which is fair.
- **Extensions never change the cap.** `increase_unlock_time` (including `keepAtMaxLock`'s weekly calls) must not silently re-opt users into harsher terms — a keeper convenience flag cannot be a consent mechanism. A position's cap changes only through the weighted `increase_amount` rule above.
- Already-finalized rewards pay in full at exit; in-progress epoch share → forfeiture bucket. Forfeit split 80/20 (tunable; treasury ≤ 50%; destinations immutable).
- v1 honesty note stands: until the wrapper ships, penalty exit is the only early door. Lock what you can commit; say so loudly in launch materials.

### 3.5 Governance

Unchanged: checkpointed read-only weight; `VeVotesAdapter` (IVotes); future token either is veXDC or distributes against checkpoint history.

---

## 4. Modularity & upgradeability

- **Immutable:** VotingEscrow (formula + params-behind-clamps + destinations), all adapters, ZapDepositor.
- **UUPS:** FeeDistributor, RevenueRegistry.
- **Deleted from the system:** PenaltyManager (#11), split/merge (#2), `wrapInto` (#9).
- **Roles:** UPGRADER (timelock 48h+), REGISTRY_ADMIN, PARAM_ADMIN (escrow-clamped, timelock-executed), PAUSER (guardian, periphery-only), REPORTER (Mode C).

---

## 5. Epoch lifecycle (#4 — reordered)

1. **During epoch *n*:** adapters accumulate; Hermes skims/sweeps continuously; Mode C attestations post (funds atomically; distributionEpoch = receipt epoch).
2. **Pre-boundary keeper window (last ~2h of *n*):** Hermes executes `keepAtMaxLock` for opted-in positions and runs the final sweep pass (SLA target: all adapter balances swept before boundary — a miss shifts revenue to *n+1*, never retroactively).
3. **Epoch boundary:** snapshot for *n+1* taken — *after* re-extensions, so `keepAtMaxLock` positions are snapshotted at full weight. Epoch *n* finalizes against its own start snapshot; exited shares → bucket; prior bucket contents and any carry-forward notify into *n+1*.
4. **Post-boundary:** claims open for *n*; Hermes runs the `autoCompound` batch (compounds first earn in the *next* snapshot, per §3.3). All keeper txs epoch-guarded; **a missed `keepAtMaxLock` window is never retroactively corrected** — that week's decayed weight stands.

---

## 6. Incentive model (illustrative)

Unchanged framing from v0.4 (stylized, assumptions stated, dominance claims scoped to the model). One update: with no split/merge, position-management games (fragmenting or consolidating around epoch events) are structurally absent rather than mitigated.

---

## 7. Security program

Foundry invariants first-class; fork audited escrow references, audit the diff; Slither in `make ci`; branch coverage tracked in [`SECURITY.md`](SECURITY.md) (`FeeDistributor` / adapters / registry at 100%; escrow 57/65 with documented unreachable defensive branches).

**Named invariants (v0.5 set):**
- Principal safety: no path but immutable withdraw/exit; `emergencyExit` makes no external calls; post-maturity `withdraw` succeeds under hostile periphery.
- `weight ≤ principal`; `effectiveTime ≤ MAX_LOCK`; `penaltyBps ≤ min(positionPenaltyCap, maxPenaltyBps) ≤ HARD_MAX_PENALTY_BPS`; penalty destinations exactly the two immutable addresses.
- Grandfathering: no governance action increases any existing position's effective cap; `increase_amount` re-weights the cap exactly per formula; `increase_unlock_time` never changes it.
- Conservation per token: claims + forfeiture bucket + zero-supply carry-forward == total notified; denominators immutable post-snapshot; exited tokenId never receives own forfeiture.
- Effective lock ≥ MIN_LOCK at every boundary; weight always from actual (clamped) unlock time.
- Soulbound: no transfer path exists, none reachable by any call sequence.
- Claims: cursor monotonic, `MAX_EPOCHS_PER_CLAIM` bound respected, repeated claims idempotent, no epoch double-paid across cursor pages.
- B2/B3: fee Safe balance == 0 after successful sweep; double-skim moves zero.
- Mode C: `(dapp, token, sourceEpoch)` unique and immutable; amount == transferred atomically; reporter cannot set distributionEpoch; adjustments never pull from the distributor.
- Keeper: epoch guards revert stale txs; `keepAtMaxLock` outside the pre-boundary window has no retroactive effect; compound at/after expiry degrades to plain claim.

**Audit path & launch controls:** unchanged (primary audit → contest → upgradeable-path review → Immunefi; weekly TVL caps, rate limits, guardian pause, Hermes monitoring).

**Build order:** epoch + attribution semantics (frozen) → escrow storage layout (clamps, caps, params) → distributor cursor/bucket/carry-forward accounting → adapters → invariant suite → implementation.

---

## 8. Future modules (unchanged intent, smaller v1 surface)

Hooks that remain in v1: WRAPPER whitelist tier (empty), `create_lock_for`, checkpointed reads, `VeVotesAdapter`, forfeiture-bucket plumbing. **Removed from the hook list: `wrapInto`** — the v1.5 wrapper bootstraps from new WXDC deposits only; existing positions join at natural expiry. Deferred as before: wrapper (AMM pool, redemption backstop, collateral listings with min(rate, TWAP) oracle, delegate-through/capped voting), gauge voting, RevenueConverter, CCIP ingestion.

---

## 9. User journey (v1, 100k XDC)

Example economics: 5,300 USDC + 18,000 WXDC per weekly epoch, 25M total ve.

1. **Lock:** 100k XDC via Zap, 52 weeks → rounds up to the next Thursday boundary (effective ≥ 52 weeks, clamped at 104 for weight/penalty math) → soulbound veNFT, initial weight ≈ 50,000 ve (0.2%). The position's penalty cap snapshots at the current `maxPenaltyBps` and can never be raised for this position.
2. **First epoch:** mid-epoch locks first earn at the next start-of-epoch snapshot.
3. **Earning (#13, corrected):** **if the position maintains roughly a 0.2% share for ten epochs** — e.g. via `keepAtMaxLock`, with total supply roughly stable — it accrues ~106 USDC + ~360 WXDC over those ten weeks. Without re-extension the share decays linearly each week (≈0.19% by week 10, halved by week 26), so a passive claim lands proportionally lower.
4. **Receiving:** one cursor-bounded `claim()` (a 10-week backlog fits comfortably in one call); or opt into `autoCompound` and, separately, `keepAtMaxLock` (executed in the pre-boundary window so full weight is what gets snapshotted). `setRecipient` for custody/cash-flow separation.
5. **Endgame:** withdraw full principal at expiry, or re-extend and continue (cap unchanged by extension). Early exit at week 26 of 52: `effectiveTime = 26w`, penalty = cap × 26/104 → at a 50% cap, 12.5% → 87,500 XDC back, finalized rewards paid in full, forfeits streaming to remaining lockers from the next epoch. Until the wrapper ships, this is the only early door.

Concrete call sequences for every locker path (Zap, cooldown exits, operator, Safe, multi-NFT): [`USER_FLOWS.md`](USER_FLOWS.md).
