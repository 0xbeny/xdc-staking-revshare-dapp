# veXDC — Real-Yield Vote-Escrowed Staking for the XDC Network

**Author:** Beny ([@zeroxbeny](https://x.com/zeroxbeny))
**Version:** 1.0 · September 2026
**Status:** Pre-launch draft — contracts implemented, audit pending

---

## Abstract

veXDC is a vote-escrowed staking protocol for the XDC Network that pays lockers **real
revenue, not token emissions**. Users lock XDC for 1–104 weeks and receive a soulbound NFT
whose weight decays linearly toward unlock. Participating dApps commit a fixed share of their
revenue on-chain through immutable adapter contracts; every week, that revenue is distributed
pro-rata to a snapshot of locker weight. There is no inflationary reward token, no emissions
schedule, and no way for governance to touch locked principal: the vault holding user funds is
immutable, and the only two doors out of it — maturity withdrawal and early exit at a
pre-agreed penalty — are burned into its bytecode.

The design goal is a credible, long-horizon alignment instrument for the XDC ecosystem:
dApps rent loyal stake-weighted users; lockers earn a share of real cash flow; and the
time-decay weighting ensures rewards concentrate on those with the longest remaining
commitment.

---

## 1. Motivation

Most ve-model protocols (Curve, Velodrome, and their forks) pay lockers primarily in a native
emissions token. This bootstraps liquidity quickly but creates a structural problem: yields
are denominated in an asset whose supply inflates to fund them. When emissions outrun organic
demand, the flywheel reverses.

veXDC takes the other branch: **no emissions, revenue only.** Weekly payouts are made in the
tokens dApps actually earn (WXDC and USDC at launch). This makes the yield honest — if
integrated dApps produce no revenue in a week, lockers earn nothing that week — and it makes
the protocol's value proposition legible: locked XDC is a claim on a share of participating
dApps' cash flow, weighted by commitment.

Two secondary motivations shape the architecture:

1. **Principal safety as a structural property, not a policy.** Users lock principal for up
   to two years. The contract holding it must not be upgradeable, pausable into a trap, or
   parameterizable into confiscation. veXDC enforces this with a strict rule: *anything
   upgradeable never holds principal; anything holding principal is never upgradeable.*
2. **Predictable exit economics.** A locker must know, at lock time, the worst case of
   leaving early. Penalty terms are snapshotted per position at creation and can never be
   worsened retroactively.

---

## 2. System overview

```
                     Governance (Timelock · Guardian · Keeper)
                                      │
                                SystemAccess
                          (immutable role registry)
                                      │
 User ── XDC/WXDC ──▶ ZapDepositor ──▶ VotingEscrow ◀──────┐
                      (sole mint path)  (immutable vault,   │ weight snapshots,
                                        soulbound veNFT)    │ penalties
                                                            │
 dApp fees ──▶ Revenue adapters ── notifyRevenue ──▶ FeeDistributor
              (immutable, per-dApp)                 (weekly epochs, claims)
                        ▲
                 RevenueRegistry (adapter whitelist, metadata only)
```

| Contract | Mutability | Holds funds | Purpose |
|---|---|---|---|
| `VotingEscrow` | immutable | all principal | soulbound veNFT, weight math, penalty rules |
| `ZapDepositor` | immutable | never | sole mint path (native XDC or WXDC) |
| `FeeDistributor` | upgradeable (UUPS) | revenue awaiting claim | weekly epochs, claims, forfeiture |
| `RevenueRegistry` | upgradeable (UUPS) | never | adapter whitelist and terms metadata |
| Revenue adapters | immutable | never between calls | move committed dApp revenue |
| `SystemAccess` | immutable | never | central role registry for the periphery |
| `VeVotesAdapter` | immutable | never | read-only governance weight (IVotes) |

The upgradeable pieces (distributor, registry) handle accounting and metadata. The immutable
pieces hold principal and define economics. A compromised or malicious upgrade of the
periphery can, at worst, disrupt *reward* flow — it can never reach locked principal.

---

## 3. Locking mechanism

### 3.1 Positions

A user locks XDC (wrapped to WXDC) for a whole number of weeks between 1 and 104, entering
exclusively through the `ZapDepositor`. They receive a **soulbound ERC-721** — it can never
be transferred, sold, or wrapped in v1. Unlock times round **up** to the next weekly boundary
(Thursday 00:00 UTC), so the effective lock is never shorter than requested.

There is no split or merge. A user wanting multiple maturity profiles creates multiple
positions. This keeps the immutable core small and removes an entire class of
checkpoint-migration attack surface.

### 3.2 Weight

Weight follows the Curve linear-decay model with a truncated slope:

```
slope  = amount / MAX_LOCK                     (MAX_LOCK = 104 weeks, in seconds)
weight = slope × min(unlock − now, MAX_LOCK)
```

A 104-week lock has weight ≈ amount; a 52-week lock starts at ≈ half of that; every position
decays linearly to zero at unlock. The truncated-slope form guarantees the global total equals
the sum of positions **to the wei** — a property the revenue-conservation accounting depends
on — and gives `weight ≤ principal` unconditionally.

### 3.3 Maintaining weight

Decay is a feature — it prices commitment — but passive decay is inconvenient for
long-horizon holders. Three consent-based mechanisms address this:

- **`increaseUnlockTime`** — the owner (or an approved operator) re-extends the lock.
- **`keepAtMaxLock`** — an opt-in flag: a keeper re-extends the position to maximum every
  week, in a fixed window before the weekly snapshot, so opted-in positions are always
  snapshotted at full weight. Operators can *only* extend locks — never withdraw, exit,
  claim, or redirect funds — and the flag is revocable at any time.
- **`autoCompound`** — an opt-in flag: claimed WXDC rewards are folded back into the
  position's principal each week.

Together these make "lock and forget" viable: a user locks once, opts into both flags, and
holds a permanently max-weight, self-compounding position — while remaining the only party
who can ever move principal.

---

## 4. Revenue: from dApp to locker

### 4.1 Immutable adapters

A dApp commits revenue through an **immutable adapter** whose terms — source, committed share
in basis points, distributor, dApp treasury — are fixed at construction. Changing a
commitment means deploying a new adapter and re-whitelisting it, which makes every change in
terms publicly visible on-chain. Five modes cover the practical integration surface:

| Mode | Contract | Pattern |
|---|---|---|
| A | `PushAdapter` | dApp pushes a known committed amount |
| B | `FeeSplitter` | dApp's fee receiver; anyone may skim; splits committed share vs. treasury |
| B2 | `PullAdapter` | sweeps a dedicated fee Safe via ERC-20 allowance |
| B3 | `ZodiacFeeModule` | sweeps a dedicated fee Safe as a Safe module |
| C | `Attestor` | off-chain/cross-chain revenue attested and transferred atomically |

Adapters never hold a balance between calls, and B2/B3 assert the fee Safe is emptied by
every sweep. The registry that whitelists adapters is metadata-only: it holds no funds and no
allowances.

### 4.2 Weekly epochs

Time is divided into weekly epochs at Thursday 00:00 UTC. The distribution rule is frozen:

> Revenue received during epoch *n* is allocated by locker weights snapshotted at the
> **start** of epoch *n*, and becomes claimable when *n* closes.

Attribution is by receipt time only — no caller can assign revenue to a past epoch. Positions
created mid-epoch first earn at the next snapshot. If an epoch's snapshot supply is zero, its
revenue carries forward to the first epoch with non-zero supply; nothing is ever stranded or
swept to a treasury by accident.

Per token, an audited conservation invariant holds:
**claims + forfeiture bucket + carry-forward = total revenue notified.**

### 4.3 Claims

`claim` is permissionless, always pays the position's designated recipient, and processes a
bounded number of epochs per call (52) behind a monotonic cursor — a position left unclaimed
for years settles in a couple of transactions with no unbounded loops. Lockers can direct
rewards to a separate recipient (e.g. a cold wallet holds the NFT, a hot wallet receives
cash flow) or compound them back into principal.

---

## 5. Exits and the penalty

### 5.1 Two doors, both immutable

Principal leaves the vault through exactly two functions:

- **`withdraw`** — after the lock expires: full principal, no penalty.
- **`emergencyExit`** — before expiry, at a penalty known since lock time.

Both are **two-phase** with a governance-tunable cooldown (default 24 hours, hard-capped at
7 days): a first call arms the request; after the cooldown, a second call pays out. The
penalty is snapshotted at request time, and a pending request blocks any modification of the
position. The cooldown gives monitoring a reaction window against key theft without ever
giving governance a veto — no role can block or confiscate a legitimate exit.

### 5.2 Penalty formula

```
eff        = min(unlock − now, MAX_LOCK)
penaltyBps = cap × eff / MAX_LOCK          (linear, reaches 0 at expiry — no floor)
```

The cap is bounded by an immutable constant of **50%** (`HARD_MAX_PENALTY_BPS = 5000`).
Example: exiting a 52-week lock at week 26, with a 50% cap, costs
`50% × 26/104 = 12.5%` of principal.

The penalty is split between remaining lockers (majority share, streamed through the next
epoch's distribution) and the protocol treasury (immutably capped at ≤ 50% of the penalty).
Early exits therefore directly compensate those who stay.

### 5.3 Grandfathered terms

Each position stores the penalty cap in force at its creation. The effective cap is always
`min(position cap, current global cap)` — governance lowering the cap benefits every position
immediately; raising it never reaches an existing position. Adding principal re-weights the
stored cap by size (old principal keeps its exact terms, new principal enters at current
terms), which closes the loophole of parking a small position under cheap terms and pouring
size into it later. Extending a lock never changes the cap: a keeper convenience flag is not
a consent mechanism.

---

## 6. Security model

- **Principal-safety invariant (machine-checked):** no governance action, upgrade, registry
  change, pause, or peripheral failure can move principal except through `withdraw` /
  `emergencyExit` under their immutable rules. `emergencyExit` makes no external calls except
  the token transfers themselves — it cannot be bricked by any other contract.
- **Immutable/upgradeable split:** the vault, zap, adapters, and role registry are immutable;
  only the distributor and registry (which never hold principal) are UUPS-upgradeable behind
  a timelock.
- **Roles, centrally auditable:** all periphery permissions (upgrader, pauser, keeper,
  registry admin, reporter) live in a single immutable `SystemAccess` registry, keyed by
  target contract, granted and revoked only by the timelock. "Who can pause the distributor?"
  is one on-chain read. The guardian can pause reward periphery only — never the escrow, never
  exits.
- **Verification:** a Foundry invariant suite (conservation, weight ≤ principal, soulbound
  unreachability, grandfathering, cursor idempotence, adapter zero-balance), static analysis
  in CI, and an external audit before mainnet. Launch controls include weekly TVL caps and
  rate limits.

The honest limitations are stated rather than hidden: until a liquid-wrapper module ships,
the penalty exit is the *only* early door — users should lock only what they can commit; and
contract-eligibility checks are a protocol-support policy, not a cryptographic guarantee.

---

## 7. Governance

Governance (a multisig maturing into a timelock) operates strictly within immutable clamps:
it can tune the penalty cap (≤ 50%), the penalty split (treasury ≤ 50%), the exit cooldown
(≤ 7 days), whitelist adapters, and upgrade the two peripheral contracts after a timelock
delay. It cannot mint positions, move principal, alter the weight formula, or change penalty
destinations.

Checkpointed ve weight is exposed through a read-only `IVotes` adapter, making veXDC the
governance primitive for future protocol decisions: weight already reflects both size and
remaining commitment, which is exactly the constituency a long-horizon protocol should answer
to.

## 8. Roadmap

- **v1 (this paper):** locking, weekly real-yield distribution, five adapter modes,
  keeper conveniences, governance reads. Launch reward tokens: WXDC and USDC.
- **v1.5 — liquid wrapper (stveXDC):** an optional liquid staking lane bootstrapped from new
  deposits only; existing soulbound positions join at natural expiry. Adds secondary-market
  liquidity without weakening v1's soulbound guarantees.
- **Later:** gauge-style voting to direct incentives, revenue conversion, cross-chain
  revenue ingestion.

---

## 9. Summary

veXDC pays XDC lockers a pro-rata share of real dApp revenue, weekly, weighted by how much
they lock and how long they commit. The contract holding principal is immutable and admits
exactly two exits, both user-initiated, both on terms fixed at lock time. Everything
upgradeable is quarantined away from principal. No emissions, no inflation — if the
ecosystem earns, lockers earn.

---

*Contact: [@zeroxbeny](https://x.com/zeroxbeny) on X.*

*This document describes software under active development, prior to external audit. Nothing
here is financial advice or an offer of securities. Parameters cited (lock bounds, penalty
caps, cooldowns, launch tokens) are v1 defaults and may change before mainnet deployment;
the immutable clamps described in §5–§7 cannot.*
