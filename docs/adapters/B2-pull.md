# Mode B2 — PullAdapter

Contract: [`src/adapters/PullAdapter.sol`](../src/adapters/PullAdapter.sol)  
Registry mode: `PULL_SAFE`

## When to use

Fees already flow to a **Gnosis/Safe-style wallet** that you control, and you prefer an
ERC-20 **allowance** from that Safe to an immutable adapter (no Safe module install).

**The fee Safe must be dedicated.** `skim` pulls the Safe’s **entire** balance of each
supported token. Never point this at a general treasury Safe.

## How it works

```
Fees ──▶ dedicated Fee Safe
Safe approved PullAdapter for USDC (max)
Anyone calls skim(USDC)
  → transferFrom(Safe → adapter) of full Safe balance
  → split by COMMITTED_BPS
       ├─ notifyRevenue → FeeDistributor
       └─ remainder → DAPP_TREASURY
  → Fee Safe balance of USDC is 0
```

Same economic split as Mode B; the custody hop is Safe → adapter instead of “fees land on
adapter.”

## Integration checklist

### 1. Create a dedicated fee Safe

Empty Safe used only as the fee sink for this dApp / this commitment. Fund it only with
revenue tokens you intend to skim.

### 2. Deploy

```bash
export DISTRIBUTOR=0x...
export ADAPTER_MODE=B2
export DAPP=0x...
export DAPP_TREASURY=0x...
export COMMITTED_BPS=2500
export REWARD_TOKENS=0xWXDC,0xUSDC
export FEE_SAFE=0x...             # the dedicated Safe
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

The script also prints the `approve(adapter, type(uint256).max)` calldata.

### 3. Register (timelock)

`registry.registerAdapter(...)` with mode `PULL_SAFE`.

### 4. Wire the Safe

From the fee Safe, for **each** reward token:

```solidity
token.approve(pullAdapter, type(uint256).max);
```

Point the dApp’s fee receiver at `FEE_SAFE` (not at the adapter).

### 5. Operate

```solidity
pullAdapter.skim(USDC);  // permissionless
```

### 6. Verify

- After skim: `token.balanceOf(FEE_SAFE) == 0`
- Adapter empty; distributor + treasury received the split

## Method reference

| Method | Caller | Effect |
|--------|--------|--------|
| `skim(token)` | anyone | Pull full Safe balance → split → notify / treasury |
| `FEE_SAFE` | — | Immutable Safe address |

## Lifecycle

Same as Mode B: deactivate to stop notifies; new adapter to change bps; retarget fee receiver
and re-approve if you rotate Safes.

## Pitfalls

- **Commingled Safe:** skim will tax operating capital. Dedicated only.
- Allowance revoked / never set → transferFrom fails.
- Token not on the constructor list → `UnsupportedToken`.
- Zero Safe balance → `NothingToSkim`.
