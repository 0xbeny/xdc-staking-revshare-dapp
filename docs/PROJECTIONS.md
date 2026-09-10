# Projections — veXDC vs native XDC staking

**Status:** Illustrative workbook · September 2026
**Audience:** lockers comparing idle XDC in veXDC vs XDPoS (masternode / vote)

This is **not a forecast** and not financial advice. veXDC pays a share of *whatever
revenue actually lands* that week. If integrated dApps notify nothing, lockers earn
nothing. Native staking pays block rewards in XDC on terms set by the chain, not by
this protocol. Plug live numbers into the formulas; do not treat the tables as promised
APY.

Weight and claim mechanics: [`ARCHITECTURE.md`](ARCHITECTURE.md) §Weight, [`WHITEPAPER.md`](WHITEPAPER.md) §3–4.
Native staking facts are cited in §4.

Working spot used below: **$0.028 / XDC** (circa 10 Sep 2026). Substitute the live price as `P`.

---

## 1. veXDC formulas

On-chain weight (truncated slope; `MAX_LOCK = 104 weeks` in seconds):

```
slope  = amount / MAX_LOCK
weight = slope × min(unlock − now, MAX_LOCK)
```

For back-of-envelope projections the continuous form is close enough:

```
weight ≈ amount × (weeks remaining / 104)
```

A 104-week lock has weight ≈ `amount`. A 52-week lock starts at ≈ half. A 1-week lock
starts at ≈ `1/104`. The widget chip is **this fraction**, not your cut of the pot.

Share of an epoch (snapshot at Thursday 00:00 UTC, start of the epoch):

```
share  = yourWeight / Σ allWeights
payout = epochRevenue × share
```

Implied USD APY on a position, treating rewards as USD (USDC at face; WXDC × `P`):

```
APY = (52 × weeklyPayoutUsd) / (amount × P)
    = (52 × weeklyRevenueUsd × yourWeight) / (amount × P × Σ weight)
```

If you are max-locked (`yourWeight ≈ amount`) this collapses to:

```
APY_max ≈ (52 × weeklyRevenueUsd) / (P × Σ weight)
```

Short locks earn less than this pool rate; max locks in a mixed-duration pool earn
**more**, because `Σ weight < Σ amount`.

---

## 2. Worked examples

### 2.1 Three lockers, same size, different duration

A, B, C each lock **1,000,000 XDC**. This week **100,000 USDC** is notified.

| | Unlock | `weight ≈ amount × weeks/104` | Chip (`weeks/104`) | Share | Payout |
|---|---|---|---|---|---|
| A | 1 week | 9,615 | ~1% | 0.64% | 637 USDC |
| B | 52 weeks | 500,000 | ~50% | 33.12% | 33,121 USDC |
| C | 104 weeks | 1,000,000 | 100% | 66.24% | 66,242 USDC |

`Σ weight = 1,509,615`. B’s chip is ~50% because `52/104` — B vs *B’s own max*, not
half the 100k. C sits in the denominator, so B’s **share** is ~33%.

### 2.2 Ten thousand lockers, mixed size and duration

A synthetic pool (internally consistent, not a prediction of who will lock):

| # of users | Amount each | Lock | Weight each | Bucket weight |
|---|---|---|---|---|
| 6,000 | 1,000 XDC | 4 weeks | 38 | 230,769 |
| 2,500 | 10,000 XDC | 26 weeks | 2,500 | 6,250,000 |
| 1,200 | 50,000 XDC | 52 weeks | 25,000 | 30,000,000 |
| 280 | 200,000 XDC | 78 weeks | 150,000 | 42,000,000 |
| 20 | 1,000,000 XDC | 104 weeks | 1,000,000 | 20,000,000 |

Pool: **167,000,000 XDC** locked, **`Σ weight ≈ 98,480,769`**. Average
`weight/amount ≈ 0.59`, so a max-locker earns about **1.7×** the pool-average yield.

One person from each bucket, this week **1,000,000 USDC**:

| Who | Chip | Share of the pot | Payout |
|---|---|---|---|
| 1k / 4w | ~4% | 0.000039% | ~0.39 USDC |
| 10k / 26w | 25% | 0.0025% | ~25 USDC |
| 50k / 52w | 50% | 0.025% | ~254 USDC |
| 200k / 78w | 75% | 0.15% | ~1,523 USDC |
| 1M / 104w | **100%** | **~1.02%** | ~10,154 USDC |

The whale’s chip is 100% because *their* lock is maxed. They still only own ~1% of
total weight.

### 2.3 You add 100,000 XDC to that pool

You are locker 10,001. Duration is the only thing you change:

| Unlock | Chip | Your weight | `Σ weight` | Share | Payout @ 1M USDC/wk |
|---|---|---|---|---|---|
| 1 week | ~1% | 962 | 98,481,731 | 0.00098% | ~10 USDC |
| 52 weeks | 50% | 50,000 | 98,530,769 | 0.051% | ~507 USDC |
| 104 weeks | 100% | 100,000 | 98,580,769 | 0.10% | ~1,014 USDC |

Chip jumps 1% → 100%. Share barely moves (still ~0.1% at max) because **10k other
weights** sit in the denominator.

---

## 3. veXDC yield grid

`P = $0.028`. Cells are **implied APY for a max-lock** (`weight ≈ amount`). A 52-week
lock earns about half; a 1-week lock about `1/104`.

```
APY_max ≈ (52 × weekly USDC) / (0.028 × Σ weight)
```

| Weekly USDC in → / `Σ weight` ↓ | $1,000 | $5,000 | $10,000 | $50,000 |
|---|---|---|---|---|
| 10M (small, all max) | 18.6% | 92.9% | 186% | 929% |
| 50M | 3.7% | 18.6% | 37.1% | 186% |
| 98.5M (the 10k-user pool, you max-locked) | 1.9% | 9.4% | **18.8%** | 94% |
| 200M | 0.9% | 4.6% | 9.3% | 46% |
| 500M | 0.4% | 1.9% | 3.7% | 18.6% |

Reading it: at the 10k-user pool, **~$10k USDC/week** puts a max-locker in the same
ballpark as native masternode APR (see §5). **~$1k/week** does not. Dilution from a
bigger `Σ weight` is linear — double the committed weight, halve everyone’s APY, all
else equal.

Same grid as **USD per year** on a **100,000 XDC** max-lock (`$2,800` of principal):

| Weekly USDC in / pool `Σ weight` | 10M | 98.5M | 200M | 500M |
|---|---|---|---|---|
| $1,000 | $520 | $53 | $26 | $10 |
| $5,000 | $2,600 | $264 | $130 | $52 |
| $10,000 | $5,200 | $527 | $260 | $104 |
| $50,000 | $26,000 | $2,637 | $1,300 | $520 |

---

## 4. What native XDC staking actually is

veXDC does **not** replace XDPoS. Native staking is how the chain is secured.
Sources: [XDC rewards](https://docs.xdc.network/xdcchain/rewards/),
[masternode requirements](https://docs.xdc.network/xdcchain/developers/node_operators/masternode/),
[`XDCValidator.sol`](https://github.com/XinFinOrg/XDPoSChain/blob/master/contracts/validator/contract/XDCValidator.sol).

| | Masternode (validator / standby) | Voter (delegate) |
|---|---|---|
| Job | Produce / back up blocks | Stake on a candidate |
| Minimum | **10,000,000 XDC** + KYC + node | **25,000 XDC** (`minVoterCap`) |
| Advertised APR (protocol docs) | **10%** validator / **8%** standby, paid in **XDC** | Share of that node’s rewards (net of operator take; third-party trackers have printed ~7–10%) |
| Unbond | `candidateWithdrawDelay = 1,296,000` blocks (~35 days at ~2.3s) | `voterWithdrawDelay = 432,000` blocks (~12 days) |
| Early-exit haircut | None. You wait. Rewards typically stop once unvoted. | Same |
| Reward asset | More XDC (issuance / epoch rewards) | More XDC |

Protocol docs also publish an epoch table (5,000 XDC per 900-block epoch, 10%
foundation slice). That issuance schedule and the 10%/8% APR tables are not always
arithmetically identical; treat **10% / 8% as the user-facing native headline** and
check live masternode APRs before allocating.

Same 100,000 XDC, **price-flat**, native voter at 8% vs 10%:

| Native APR | Extra XDC / year | USD / year @ $0.028 | Liquidity |
|---|---|---|---|
| 8% | 8,000 XDC | $224 | ~12 days after `unvote` + `withdraw` |
| 10% | 10,000 XDC | $280 | same (voter); ~35 days if you *are* the masternode |

A 10M masternode at the advertised 10%: **1,000,000 XDC / year ≈ $28,000**, plus
ops/KYC, plus XDC price risk on both principal and rewards.

---

## 5. Side by side

| | Native XDPoS | veXDC |
|---|---|---|
| What you are paid for | Securing the chain | Financing dApp cash-flow share |
| Reward source | Epoch / block rewards (XDC issuance) | Notified dApp revenue (USDC + WXDC at launch) |
| If the ecosystem earns $0 fees this week | You still get native rewards | You get **$0** that week |
| Min size | 25k vote / 10M masternode | **1 XDC** |
| Duration | ~12d voter / ~35d masternode unbond; no term lock | You pick **1–104 weeks**; 24h exit cooldown |
| Time weighting | Amount (and validator vs standby) | `amount × remaining/104` |
| Early liquidity | Wait the delay, **no principal haircut** | Wait until unlock (no haircut) **or** `emergencyExit` at up to **50%** of remaining time |
| KYC / node | Masternode: yes | No |
| Can the same XDC sit in both? | **No** — `XDCValidator` and `VotingEscrow` are different vaults | **No** |
| Dilution | More native stake → lower XDC APR | More ve weight → lower share of the *same* revenue |
| Price path of rewards | More XDC (moves with `P`) | USDC is stable; WXDC moves with `P` |

They are **substitutes for idle XDC** and **complements as products**: native staking
is consensus; veXDC is a revenue-share vault on top of the same token.

---

## 6. Break-even vs native

For a **max-lock** to match native APR `r` in USD (price-flat XDC):

```
52 × weeklyRevenueUsd × (yourWeight / Σ weight)  =  r × amount × P

weeklyRevenueUsd  =  r × P × Σ weight     when yourWeight ≈ amount
```

With `P = $0.028` and you max-locked:

| `Σ weight` | Weekly USDC to match **8%** native | Weekly USDC to match **10%** native |
|---|---|---|
| 10M | $431 | $538 |
| 50M | $2,154 | $2,692 |
| 98.5M (10k-user pool) | **$4,246** | **$5,308** |
| 200M | $8,615 | $10,769 |
| 500M | $21,538 | $26,923 |

On the §2.3 position (100k XDC, 104 weeks, 10k-user pool):

| Weekly USDC into veXDC | Your weekly payout | USD / year | vs native 8% ($224/yr) | vs native 10% ($280/yr) |
|---|---|---|---|---|
| $1,000 | ~$10 | $53 | loses | loses |
| $4,250 | ~$43 | ~$224 | **matches 8%** | slightly under 10% |
| $10,000 | ~$101 | $527 | beats (~2.4×) | beats (~1.9×) |
| $50,000 | ~$507 | $2,637 | beats | beats |

A **52-week** lock in the same pool needs roughly **2×** those weekly inflows to match
the same native APR, because `weight/amount ≈ 0.5`. A 1-week lock is not in the same
comparison — it is priced at ~`1/104` of max weight.

### Native masternode vs veXDC on 10M XDC

Advertised native: **10% = 1,000,000 XDC/year ≈ $28,000**, plus you run a node.

Same 10M max-locked *into the 10k-user pool* (`Σ weight` becomes ~108.5M):

```
share ≈ 10,000,000 / 108,480,769 ≈ 9.2%
```

| Weekly USDC in | veXDC USD / year on 10M | vs $28k native |
|---|---|---|
| $5,000 | ~$24k | slightly under |
| $5,800 | ~$28k | match |
| $10,000 | ~$48k | ahead in USD, still illiquid for 104 weeks |

That comparison ignores masternode operating cost, KYC, standby vs validator, and
the fact that native yield is **more XDC** (optional compound into the same 10% if
you restake) while veXDC yield is mostly **USDC**.

---

## 7. How to think about the allocation

1. **Job.** Need chain rewards and ~12-day liquidity → native vote (if you have ≥25k).
   Want a claim on dApp fees and can accept 1–104 weeks → veXDC.
2. **Denomination.** Native APR is XDC/XDC. veXDC APY in the tables is USD on XDC
   principal. If `P` halves, native rewards’ USD value halves too; USDC payouts do not.
3. **Duration price.** Native does not pay you extra for locking two years. veXDC
   does — that is the whole weight function. Short ve locks will *lose* to native
   almost every revenue scenario; max-lock + `keepAtMaxLock` is the only ve strategy
   that belongs in an APR comparison.
4. **Dilution.** Native APR compresses as more XDC is staked on the chain. veXDC APY
   compresses as `Σ weight` grows, *unless* weekly notified revenue grows with it.
5. **Zero week.** Native has a floor (issuance). veXDC’s floor is zero. Any “beats
   10%” cell in §3 assumes that week’s revenue actually arrives.
6. **Exit.** Native: time. veXDC: time *or* a known haircut
   (`penaltyBps = cap × remaining/104`, cap ≤ 50%). Stayers receive most of that
   haircut next epoch — that flow is extra yield not in the grid above.

**Split book (allowed, different coins):** 25k+ in native vote for the issuance
coupon and 12-day option; the rest max-locked in veXDC if you believe weekly
notified revenue will clear the break-even row in §6.

---

## 8. Recalculating with live inputs

```
P              = spot XDC-USD
r_native       = live voter or masternode APR (decimal)
W              = escrow.totalSupply()          // Σ weight, wei
weeklyUsd      = USDC notified this epoch
               + (WXDC notified this epoch × P)
yourW          = escrow.balanceOfNFT(tokenId)
amount         = locked principal

payoutUsd      = weeklyUsd × yourW / W
APY            = 52 × payoutUsd / (amount × P)
beat_native    = APY > r_native
```

`totalSupply` and `balanceOfNFT` are wei; 1 XDC = `1e18`. Indexer
`GET /api/protocol/revenue` is the practical source for trailing weekly inflows
once adapters are live.

---

*Parameters (lock bounds, penalty cap, cooldown) are v1 defaults. Native APR, unbond
delays, and `P` move independently of this repo. Nothing here is an offer or a
guarantee of yield.*
