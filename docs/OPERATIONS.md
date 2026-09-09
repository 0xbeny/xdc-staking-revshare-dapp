# Operations runbook — Hermes keeper

Hermes is the off-chain keeper. It holds `KEEPER_ROLE` on the distributor and nothing else.
Every keeper transaction is epoch-guarded, so a stale transaction reverts instead of doing
something surprising.

## The weekly cycle

Epochs are weeks starting Thursday 00:00 UTC. Let `n` be the current epoch and
`boundary = (n + 1) × 1 weeks`.

| When | Action | Notes |
|---|---|---|
| Continuously | `skim(token)` on every Mode B / B2 / B3 adapter with a balance | Permissionless. Revenue is attributed to the epoch it *lands* in. |
| Continuously | `syncForfeiture(token)` after any `EmergencyExit` event | Also runs inside every claim and settle, so this is an optimisation not a dependency. |
| `boundary − 2h` → `boundary` | `batchKeepAtMaxLock(ids, n)` for every position with `keepAtMaxLock == true` | **Must** land before the boundary. Reverts with `OutsideKeeperWindow` earlier and `StaleEpoch` later. A missed window is never corrected retroactively. |
| `boundary − 2h` → `boundary` | Final sweep pass on all adapters | SLA target only. A miss shifts revenue to `n+1`; it never backdates. |
| after `boundary` | `settle(token, 52)` for each reward token | Permissionless. Finalises `n`, moves exited shares and carry-forward into `n+1`. |
| after `boundary` | `batchCompound(ids, n+1)` for every position with `autoCompound == true` | Compounds first earn in the *next* snapshot. |
| after `boundary` | Optional: `claim` on behalf of users who want it | Permissionless; funds always go to the position's recipient. |

## Finding positions

- `escrow.tokensOfOwner(owner)` enumerates an owner's positions.
- `KeepAtMaxLockSet` / `AutoCompoundSet` events on the distributor are the source of truth for
  the opt-in sets. Rebuild them from logs on start-up.
- A position can be extended by the keeper only if its owner also called
  `escrow.setOperator(distributor, true)`. `batchKeepAtMaxLock` emits
  `KeeperExtended(tokenId, false)` for any it could not extend; surface those to the user.

## Monitoring (SPEC §7)

- `Deposit` to a beneficiary with `code.length == 0` that later gains code → flag.
- `escrow.totalLocked() == WXDC.balanceOf(escrow)` at every block → alert on any drift.
- Per token: `distributor.accounted(token) == totalNotified − totalClaimed` and
  `balanceOf(distributor) ≥ accounted` → alert on any drift.
- `feeSafe` balances for B2/B3 should read zero after every successful sweep.
- Guardian: `distributor.pause()` freezes `notifyRevenue`, `claim`, `claimAndLock` and the
  keeper batches. It **cannot** freeze `withdraw` or `emergencyExit` — that is by design.

## Reconciliation

For any closed epoch `e` and token:

```
pot        = distributor.epochRevenue(token, e)
supply     = escrow.totalSupplyAtWeek(e × 1 weeks)
exited     = escrow.exitedWeightByEpoch(e)
claimable  = pot × (supply − exited) / supply     → paid to remaining lockers
forwarded  = pot × exited / supply                → added to epochRevenue(token, e+1)
```

Rounding dust (at most one wei per claim) stays in the contract and is never lost.

## Incident playbook

| Symptom | Action |
|---|---|
| Adapter compromised / dApp terms breached | Timelock: `registry.deactivateAdapter(adapter)`. It can no longer notify. Funds already notified stay claimable. |
| Distributor bug suspected | Guardian: `distributor.pause()`. Users can still `withdraw` and `emergencyExit`. Timelock proposes an upgrade. |
| Keeper key compromised | Timelock: `revokeRole(KEEPER_ROLE, old)`, `grantRole(KEEPER_ROLE, new)`. The keeper can only extend opted-in locks and compound opted-in rewards; it cannot move principal or redirect claims. |
| Reporter (Mode C) key compromised | Timelock: `attestor.setReporter(new)`. Records are immutable; a bad record is corrected by a later negative adjustment. |
| Missed `keepAtMaxLock` window | Nothing to do on-chain. Communicate; the decayed snapshot stands for that week. |
