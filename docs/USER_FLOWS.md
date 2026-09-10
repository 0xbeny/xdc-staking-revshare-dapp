# User flows — concrete scenarios

End-to-end examples for every locker path in v1. Actors, contracts, and call sequences use
placeholder addresses; replace with your deployment (`deployments/<chainId>.json`).

**Related docs:** [ARCHITECTURE.md](ARCHITECTURE.md) · [SPEC.md](SPEC.md) §9 ·
[adapters/](adapters/README.md) (dApp revenue) · [OPERATIONS.md](OPERATIONS.md) (keeper) ·
[INTEGRATION.md](INTEGRATION.md)

### Cast used below

| Who | Address | Notes |
|-----|---------|--------|
| Alice | EOA locker | Primary user |
| Bob | Friend / funder | Pays for Alice’s NFT in gift flows |
| Cold | Alice’s cold wallet | Claim recipient only |
| Hermes | Keeper | `KEEPER_ROLE` on distributor via SystemAccess |
| Safe | Alice’s Safe | Needs `CUSTODIAN` tier + ERC721 receiver |
| Timelock / Guardian | Governance | Not required for normal locker flows |

Defaults: `MAX_LOCK = 104 weeks`, `withdrawalCooldown = 24h` (production). Tests often set
cooldown to `0` for one-call exits.

---

## 1. Deposit — first lock

### 1.1 Native XDC → own NFT

Alice wants a 52-week lock of 100_000 XDC.

```text
Alice → ZapDepositor.zapCreateLock{value: 100_000 ether}(52 weeks)
         └─ wrap XDC→WXDC
         └─ VotingEscrow.createLockFor(Alice, 100k, 52w)
              └─ mint soulbound veNFT #7 to Alice
```

**Result:** NFT `#7` owned by Alice; unlock = `ceilWeek(now + 52w)`;
`penaltyCapBps` snapshotted; weight ≈ half of max for that principal until extended.
Mid-epoch locks first earn at the **next** epoch snapshot (`firstEligibleEpoch`).

### 1.2 Already-wrapped WXDC → own NFT

```text
Alice: WXDC.approve(Zap, 100_000e18)
Alice → Zap.lockWXDC(100_000e18, 52 weeks)
```

Same escrow mint path as 1.1.

### 1.3 Gift / custodial — Bob funds, Alice owns

```text
Bob → Zap.zapCreateLockFor{value: 50_000 ether}(Alice, 26 weeks)
  // or lockWXDCFor(Alice, amount, duration) after Bob approves Zap
```

Escrow eligibility is checked against **Alice** (beneficiary), not Bob.
Events record Bob as depositor.

### 1.4 Max lock from day one

```text
Alice → Zap.lockWXDC(1_000_000e18, 104 weeks)
```

Starts near full weight for that principal. Without later extends, weight still decays as
`end − now` shrinks (see §3).

### 1.5 Contract wallet (Safe)

```text
Timelock → escrow.setTier(Safe, CUSTODIAN)   // once
Safe must implement onERC721Received
Safe → Zap.lockWXDC(...)   // or a module/relayer that sets msg.sender = Safe
```

EOAs need no tier. Wrong/missing receiver → mint reverts **before** principal is taken.

---

## 2. Grow an existing position

### 2.1 Top up with native XDC (owner consent via Zap)

```text
Alice → Zap.zapIncreaseAmount{value: 10_000 ether}(7)
```

Owner-only on Zap (re-weights grandfathered `penaltyCapBps`). Escrow
`increaseAmount` itself is permissionless, but Zap enforces owner for the wrap UX.

### 2.2 Top up with WXDC via Zap

```text
Alice: WXDC.approve(Zap, 10_000e18)
Alice → Zap.increaseAmountWXDC(7, 10_000e18)
```

### 2.3 Top up via escrow directly (anyone funds Alice’s NFT)

```text
Carol: WXDC.approve(Escrow, 5_000e18)
Carol → escrow.increaseAmount(7, 5_000e18)
```

Same cap re-weight formula. Useful for auto-compound (`claimAndLock`) and gifts of principal.

### 2.4 Blocked while exit is pending

```text
Alice → escrow.requestEmergencyExit(7)   // or first withdraw/emergencyExit with cooldown > 0
Alice → escrow.increaseAmount(7, 1e18)   // reverts ExitPending
```

Cancel first (§5.4) or finalize the exit.

---

## 3. Manage duration / weight

### 3.1 Manual extend

```text
Alice → escrow.increaseUnlockTime(7, block.timestamp + 104 weeks)
```

Unlock rounds **up** to a week boundary; must be strictly later; cannot exceed `now + MAX_LOCK`.
**Does not** change `penaltyCapBps`.

### 3.2 Keeper convenience — one-shot max

```text
Alice → escrow.keepAtMaxLock(7)
  // == increaseUnlockTime(7, now + MAX_LOCK)
```

### 3.3 Set-and-forget max weight (operator + flag)

```text
Alice → escrow.setOperator(FeeDistributor, true)
Alice → distributor.setKeepAtMaxLock(7, true)
// each week, last ~2h before boundary:
Hermes → distributor.batchKeepAtMaxLock([7, …], expectedEpoch)
```

If Hermes misses the window, that week’s snapshot keeps the **decayed** weight — no backfill.

### 3.4 Revoke operator / stop auto-extend

```text
Alice → escrow.setOperator(FeeDistributor, false)
Alice → distributor.setKeepAtMaxLock(7, false)
```

Unlock stops sliding; position will eventually mature.

### 3.5 Passive decay (do nothing)

Alice locks 1M for 104 weeks and never extends:

| Time | Approx weight share vs day-0 max |
|------|----------------------------------|
| Day 0 | ~100% |
| Week 52 | ~50% |
| Week 104 | 0 → withdraw |

Principal stays 1M the whole time; **reward share** decays with weight.

---

## 4. Rewards

### 4.1 Passive claim (permissionless payee = owner)

After epoch `n` closes and is settled (anyone may `settle`):

```text
Anyone → distributor.claim(7, [USDC, WXDC])
  // pays Alice (or recipientOf[7])
  // walks ≤ 52 epochs; returns remaining if backlog
```

Alice can call it herself; a friend/bot can too — funds still go to her recipient.

### 4.2 Claim to a cold wallet

```text
Alice → distributor.setRecipient(7, Cold)
Anyone → distributor.claim(7, [USDC])
  // USDC → Cold; NFT still Alice; principal still in escrow
```

### 4.3 Self-compound WXDC rewards

```text
Alice → distributor.claimAndLock(7)
  // accrue WXDC → escrow.increaseAmount(7, …)
  // if lock already expired/closed → plain payout to recipient instead
```

Allowed: owner, escrow operator, or keeper when `autoCompound[7]`.

### 4.4 Auto-compound via keeper

```text
Alice → distributor.setAutoCompound(7, true)
// after epoch boundary:
Hermes → distributor.batchCompound([7, …], expectedEpoch)
```

Compounded WXDC first affects the **next** snapshot (same as a mid-epoch increase).

### 4.5 View before claiming

```text
(amount, remaining) = distributor.claimable(7, USDC)
```

For exactness after exits, call `settle(USDC, 52)` first.

### 4.6 Missed weeks / backlog

Alice ignores claims for 10 weeks → one `claim` usually clears it (`MAX_EPOCHS_PER_CLAIM = 52`).
If `remaining > 0`, call again.

---

## 5. Exit

Production: `withdrawalCooldown = 1 days` (timelock-tunable, max 7 days). Both mature and
emergency exits are **request → wait → finalize**. The request snapshots an immutable
`readyAt`; later cooldown changes do not move pending requests.

### 5.1 Mature withdraw (full principal)

```text
// lock.end reached
Alice → escrow.withdraw(7)     // arms ExitRequest (Withdraw); no payout if cooldown > 0
… wait ≥ withdrawalCooldown …
Alice → escrow.withdraw(7)     // pays 100% WXDC to Alice; NFT stays, lock zeroed, closed=true
```

With `cooldown == 0`, a single `withdraw` does both steps.

### 5.2 Explicit request then finalize

```text
Alice → escrow.requestWithdraw(7)
… wait …
Alice → escrow.withdraw(7)
```

### 5.3 Emergency exit (early, with penalty)

Example: 100_000 locked, 52w originally, exit at week 26, cap 50% → illustrative penalty
~12.5% (see SPEC §9); returned ~87_500; remainder split lockers/treasury per `penaltySplitBps`.

```text
Alice → escrow.emergencyExit(7)   // snapshots penalty; arms ExitRequest (Emergency)
… wait ≥ cooldown …
Alice → escrow.emergencyExit(7)   // pays snapshot: Alice / distributor / treasury
```

Or `requestEmergencyExit` then `emergencyExit`. Penalty is **fixed at request** — waiting
extra days after request does not change the quote.

Finalized reward epochs remain claimable after exit; in-progress epoch share is forfeited
into the distributor’s next pot via `syncForfeiture`.

### 5.4 Cancel a pending exit

```text
Alice → escrow.cancelExitRequest(7)
  // no funds moved; can increase/extend again; can choose the other exit kind later
```

### 5.5 Wrong path while pending

```text
Alice requested Withdraw, then calls emergencyExit → WrongExitKind
Alice requested Emergency, then calls withdraw → WrongExitKind
Alice calls withdraw before ready → CooldownActive(readyAt)
```

### 5.6 Exit while distributor is paused

```text
Guardian → distributor.pause()
Alice → escrow.withdraw / emergencyExit   // still works (principal path)
Alice → distributor.claim(...)            // blocked while paused
```

### 5.7 After exit — claim leftover rewards

```text
Alice → distributor.claim(7, [USDC])   // cursor capped by exitEpoch; NFT still hers
```

---

## 6. Multiple maturities (no split/merge)

Alice wants 26w and 104w exposure:

```text
Alice → Zap.lockWXDC(40_000e18, 26 weeks)   // NFT #7
Alice → Zap.lockWXDC(60_000e18, 104 weeks)  // NFT #8
```

Manage, claim, and exit **per tokenId**. No merge/split on escrow.

---

## 7. Full “set and forget” stack

Alice wants max share + auto compound + claims to cold storage:

```text
1. Zap.lockWXDC(1_000_000e18, 104 weeks)           → #7
2. escrow.setOperator(FeeDistributor, true)
3. distributor.setKeepAtMaxLock(7, true)
4. distributor.setAutoCompound(7, true)
5. distributor.setRecipient(7, Cold)               // optional; compounds still top up #7
```

Weekly (Hermes): `batchKeepAtMaxLock` pre-boundary, `batchCompound` post-boundary.
Alice only needs to act to **exit** or change settings. Non-WXDC rewards (e.g. USDC) still
need occasional `claim` to Cold (or a claim bot).

---

## 8. Scenario matrix (quick index)

| Goal | Primary calls |
|------|----------------|
| Lock native XDC | `zap.zapCreateLock` |
| Lock WXDC | `zap.lockWXDC` |
| Gift lock | `zap.*For(beneficiary, …)` |
| Add principal (self) | `zap.zapIncreaseAmount` / `increaseAmountWXDC` |
| Add principal (anyone) | `escrow.increaseAmount` |
| Extend | `increaseUnlockTime` / `keepAtMaxLock` |
| Auto max weight | `setOperator` + `setKeepAtMaxLock` |
| Claim rewards | `distributor.claim` |
| Compound WXDC | `claimAndLock` / `setAutoCompound` + batch |
| Pay claims elsewhere | `setRecipient` |
| Unlock at maturity | `withdraw` ×2 (or ×1 if cooldown 0) |
| Leave early | `emergencyExit` ×2 (snapshot at request) |
| Abort exit | `cancelExitRequest` |
| Safe locker | `setTier(CUSTODIAN)` + ERC721 receiver + Zap from Safe |
| Two horizons | Two Zap locks (two NFTs) |

---

## 9. What users cannot do

| Attempt | Outcome |
|---------|---------|
| Transfer / approve veNFT | `Soulbound` |
| Mint without Zap | `NotDepositor` |
| Withdraw before expiry | `LockNotExpired` (use emergency exit) |
| Emergency exit after expiry | use `withdraw` |
| Operator withdraws / exits | `NotAuthorized` |
| Avoid penalty on early exit | Impossible by design |
| Claim past `exitEpoch` after exit | Cursor stops; finalized epochs only |

---

## 10. dApp / keeper flows (concrete)

Full adapter integration: [adapters/](adapters/README.md). Short call sequences:

### 10.1 Mode B — fees hit FeeSplitter

```text
DEX feeRecipient = FeeSplitter
… users trade, USDC accrues on splitter …
Anyone → splitter.skim(USDC)
         └─ 30% notifyRevenue → distributor pot[thisEpoch]
         └─ 70% → dApp treasury
```

### 10.2 Mode A — treasury pushes

```text
DAPP: USDC.approve(PushAdapter, amount)
DAPP → push.commitRevenue(USDC, 12_000e6)
```

### 10.3 Mode B2 / B3 — dedicated fee Safe

```text
feeRecipient = FeeSafe
// once: Safe.approve(PullAdapter)  or  Safe.enableModule(Zodiac)
Anyone → pull.skim(USDC)  // or zodiac.skim(USDC)
         └─ empties Safe → split → notify / treasury
```

### 10.4 Mode C — reporter attest

```text
Timelock → access.grantRole(attestor, REPORTER, reporter)
Reporter: USDC.approve(attestor, …)
Reporter → attestor.postRevenue(USDC, closedSourceEpoch, gross, 0, hash)
```

### 10.5 Hermes week

```text
boundary − 2h:  batchKeepAtMaxLock(ids, epoch) + final adapter skims
boundary:       snapshots
after:          batchCompound(ids, epoch); settle/claim as needed
```

Ops detail: [OPERATIONS.md](OPERATIONS.md).

