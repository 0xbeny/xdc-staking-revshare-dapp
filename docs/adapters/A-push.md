# Mode A — PushAdapter

Contract: [`src/adapters/PushAdapter.sol`](../src/adapters/PushAdapter.sol)  
Registry mode: `PUSH`

## When to use

The dApp (or its treasury ops) **already knows** how much to commit this period and wants to
push that exact amount on-chain. Typical for:

- Off-chain / multi-chain revenue that is reconciled weekly
- A treasury that batches “lockers’ share” as a single transfer
- Teams that do not want a fee receiver / Safe sweep in the product path

## How it works

```
dApp wallet ──transferFrom──▶ PushAdapter ──notifyRevenue (100%)──▶ FeeDistributor
```

1. `SOURCE` (the dApp address baked into the adapter) calls `commitRevenue(token, amount)`.
2. The adapter pulls `amount` from the caller.
3. The **entire** balance held after the pull is forwarded to `FeeDistributor.notifyRevenue`.
   There is no on-adapter split: the pushed amount *is* the commitment.
4. `COMMITTED_BPS` is still recorded in the registry as **metadata** (what the dApp promised
   in human terms). It does not change the push math.

Only `SOURCE` may call `commitRevenue` — so a third party cannot inflate the dApp’s lifetime
contribution stats.

Attribution follows the distributor rule: funds belong to the **epoch of receipt**.

## Integration checklist

### 1. Deploy

```bash
export DISTRIBUTOR=0x...          # deployments/<chainId>.json → feeDistributor
export ADAPTER_MODE=A
export DAPP=0x...                 # must be the address that will call commitRevenue
export DAPP_TREASURY=0x...        # required by the base constructor (unused on push path)
export COMMITTED_BPS=3000         # registry metadata (e.g. “we commit 30%”)
export REWARD_TOKENS=0xWXDC,0xUSDC
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

### 2. Register (timelock)

Execute the printed `registry.registerAdapter(...)` calldata. Until this lands,
`notifyRevenue` reverts with `NotAnActiveAdapter`.

### 3. Wire the dApp

For each reward token, from `DAPP`:

```solidity
IERC20(token).approve(pushAdapter, type(uint256).max); // or exact amounts per push
```

Ops cadence (example):

```solidity
// After weekly reconciliation: “lockers are owed 12_000 USDC”
pushAdapter.commitRevenue(USDC, 12_000e6);
```

### 4. Verify

- `registry.isActiveAdapter(adapter) == true`
- After a push: `FeeDistributor.epochRevenue(token, currentEpoch)` increased
- Adapter ERC-20 balance is ~0 after the call

## Method reference

| Method | Caller | Effect |
|--------|--------|--------|
| `commitRevenue(token, amount)` | `SOURCE` only | Pull → `notifyRevenue` for the full receipt |
| `supportedTokens()` / `isSupported` | anyone | View the hardcoded token list |

## Lifecycle

- **Pause revenue:** deactivate the adapter in the registry (already-notified stays claimable).
- **Change commitment %:** deploy a **new** PushAdapter + register; deactivate the old one.
  `COMMITTED_BPS` on-chain for Mode A is documentation for dashboards, not the transfer size —
  ops still choose `amount` each call.

## Pitfalls

- Pushing from a wrong EOA → `NotSource`.
- Pushing an unsupported token → `UnsupportedToken`.
- Pushing `0` → `NothingToSkim`.
- Pushing after the epoch boundary attributes to the **new** week — time the call if you care
  which pot is filled.
