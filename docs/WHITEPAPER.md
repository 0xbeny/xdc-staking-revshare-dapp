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

## 6. Game theory

The mechanism is designed so that the individually rational strategy is also the one that
strengthens the system: lock long, maintain weight, stay through stress. This section makes
the incentive structure explicit. (Payoffs are stylized and directional, not simulations.)

### 6.1 The locker's strategy menu

For a holder deciding what to do with idle XDC, against a backdrop of ongoing dApp revenue:

| Strategy | Weekly revenue share | Exit cost | Net position |
|---|---|---|---|
| **Max-lock + `keepAtMaxLock`** | full weight, every epoch | up to cap (50%) if exiting immediately, linearly less over time | dominant while revenue > 0 and horizon is real |
| Lock, let weight decay | starts equal, halves by mid-lock | shrinks at the same linear rate | strictly dominated by maintaining, for the same capital and horizon |
| Lock short (repeated 1-week locks) | ≈ 1/104 of max weight per token | near zero | earns almost nothing; commitment is what's priced |
| Don't lock | zero | zero | forfeits yield; correct only if you can't commit at all |

Weight is linear in *remaining* time, so the marginal reward of every additional week of
commitment is constant — there is no plateau after which commitment stops paying, and no
cliff that punishes intermediate choices arbitrarily. The 104-week locker earns exactly 104×
the weight of a 1-week locker per token locked. Short-lock cycling is not an exploit; it is
simply priced at what it is.

### 6.2 Stay vs. exit — the anti-bank-run matrix

The classic failure mode of locked systems is the reflexive run: fear of others leaving makes
leaving rational. veXDC inverts this, because **every early exit pays the remaining lockers**
(the majority share of the penalty streams to stayers, and the exiter's share of the current
epoch is forfeited into the next). Consider a stressed market, a locker ("You") against the
aggregate behavior of everyone else:

| | **Others stay** | **Others exit early** |
|---|---|---|
| **You stay** | baseline yield | **best case:** your revenue share rises (smaller denominator) *and* you collect a share of every exiter's penalty |
| **You exit early** | worst case: you pay the penalty, others absorb it | you pay the penalty *and* miss the penalty flow from everyone else |

Staying is the better response to *both* columns: exits by others make staying **more**
attractive, not less. The run dynamic is self-damping rather than self-reinforcing — the
opposite sign of the coordination failure that drains conventional lock systems. An early
exit is never "punished into impossibility" (the door is always open, at a price known since
lock time), but it is never contagious either.

Two design details keep this matrix honest under adversarial conditions:

- The penalty is **snapshotted at exit request** and the formula lives in immutable
  bytecode, so the payoffs cannot be changed mid-game by governance or by the crowd.
- The exiter can never receive any part of their own forfeiture, so there is no self-dealing
  path through the compensation mechanism.

### 6.3 The ve(3,3) matrix

The "(3,3)" meme popularized by OlympusDAO — and carried into the ve world by Solidly-style
ve(3,3) designs — frames staking as a coordination game: everyone is best off if everyone
stakes, but each player is tempted to defect. Writing veXDC in the same notation shows where
this design departs from its ancestors. Two capital holders each choose one of three
strategies; payoffs are ordinal (row player first, higher is better):

| You ▼ / Other ► | **Max-lock & maintain** | **Hold unlocked** | **Lock, then exit early** |
|---|---|---|---|
| **Max-lock & maintain** | **(3, 3)** | (2, 0) | **(4, −2)** |
| **Hold unlocked** | (0, 2) | (0, 0) | (0, −2) |
| **Lock, then exit early** | (−2, 4) | (−2, 0) | (−2, −2) |

Reading the cells:

- **(3, 3) — both max-lock.** Both earn full revenue share; supply is committed; dApps see a
  deep, long-horizon stake base worth committing revenue to. The cooperative optimum, as in
  every (3,3) system.
- **(2, 0) / (0, 2) — one locks, one holds.** The locker earns the yield (slightly more than
  baseline: fewer competing weights); the holder earns nothing but loses nothing. Holding is
  not punished — it is simply unpaid.
- **(4, −2) / (−2, 4) — one locks, one exits early.** The departure from Olympus. There,
  a defector *extracts* value from stakers and the matrix decays toward (−3, −3). Here the
  exiter pays a penalty **into the lockers' pool** and forfeits the epoch in progress —
  defection is the locker's *best* cell, not their worst.
- **(−2, −2) — both exit early.** Both pay penalties known since lock time. Even mutual
  defection is bounded: it cannot cascade below the immutable penalty formula, and no third
  party is dragged down.

The structural difference from classic (3,3): in Olympus-style games, cooperation is an
equilibrium only while everyone *believes* others will cooperate — defection pays the
defector, so the matrix is fragile to fear. In veXDC, **max-lock is a strictly dominant
strategy** for any holder with a real time horizon: whatever the other player does, locking
is the best response (3 > 0 > −2; 2 > 0; 4 > 0 > −2). Defection costs only the defector and
compensates the cooperators, so the (3, 3) cell is not a hopeful social contract — it is
where self-interest lands without coordination, communication, or trust. And because there
is no emissions token, the "3" is denominated in transferred cash flow rather than reflexive
supply expansion: the payoff exists whether or not anyone believes in it.

### 6.4 The dApp's commitment game

A dApp choosing whether to commit revenue plays against the locker community's willingness
to lock:

| | **Users lock XDC** | **Users don't lock** |
|---|---|---|
| **dApp commits revenue** | alignment equilibrium: dApp rents a stake-weighted, long-horizon user base; lockers earn real yield | dApp pays briefly into a small pool — cheap experiment, visible on-chain, easily wound down (deploy no successor adapter) |
| **dApp commits nothing** | free-rides on ecosystem stake it did nothing to attract; loses the loyalty channel to committing competitors | dead market |

Because adapter terms are immutable and public, a commitment is a *credible signal* — a dApp
cannot quietly reduce its share without deploying a new adapter, which is an on-chain event
anyone can observe. Credibility is what moves the game from cheap talk to the top-left cell:
lockers can verify, not merely trust, that the yield source is contractual. Symmetrically,
the protocol cannot retroactively tax dApps — the committed share is fixed in the adapter
the dApp itself deployed.

### 6.5 Time-consistency: why the rules can't defect

Every game above assumes the rules hold. In most protocols that assumption is itself a game
against governance. Here, the moves governance could use to defect are removed rather than
discouraged: it cannot raise `maxPenaltyBps` at all (monotonically non-increasing) and therefore
cannot raise any existing position's effective penalty cap, cannot touch the weight formula or
penalty destinations (immutable), cannot block exits beyond a hard-capped cooldown (and pending
`readyAt` is snapshotted), and cannot reach principal through any upgrade (the vault is not
upgradeable). The players' subgame-perfect strategies can therefore be computed at lock time —
which is precisely what "exit economics must be predictable at lock time" means in
game-theoretic terms.

---

## 7. Security model

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

## 8. Governance

Governance (a multisig maturing into a timelock) operates strictly within immutable clamps:
it can tune the penalty cap (≤ 50%), the penalty split (treasury ≤ 50%), the exit cooldown
(≤ 7 days), whitelist adapters, and upgrade the two peripheral contracts after a timelock
delay. It cannot mint positions, move principal, alter the weight formula, or change penalty
destinations.

Checkpointed ve weight is exposed through a read-only `IVotes` adapter, making veXDC the
governance primitive for future protocol decisions: weight already reflects both size and
remaining commitment, which is exactly the constituency a long-horizon protocol should answer
to.

## 9. Roadmap

- **v1 (this paper):** locking, weekly real-yield distribution, five adapter modes,
  keeper conveniences, governance reads. Launch reward tokens: WXDC and USDC.
- **v1.5 — liquid wrapper (stveXDC):** an optional liquid staking lane bootstrapped from new
  deposits only; existing soulbound positions join at natural expiry. Adds secondary-market
  liquidity without weakening v1's soulbound guarantees.
- **Later:** gauge-style voting to direct incentives, revenue conversion, cross-chain
  revenue ingestion.

---

## 10. Summary

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
the immutable clamps described in §5–§8 cannot.*
