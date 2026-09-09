# Mode B — FeeSplitter (default)

Contract: [`src/adapters/FeeSplitter.sol`](../src/adapters/FeeSplitter.sol)  
Registry mode: `SPLITTER`

## When to use

The dApp can point its **protocol fee receiver** at a contract address. That is the common
case for DEXes, lending fee hooks, and any product that already has a single fee sink.

Anyone may `skim` — usually the Hermes keeper or a public keeper bot.

## How it works

```
Users pay fees ──▶ FeeSplitter (fee receiver)
Anyone calls skim(token)
  ├─ committed = balance × COMMITTED_BPS / 10_000  ──notifyRevenue──▶ FeeDistributor
  └─ remainder                                   ──transfer──────▶ DAPP_TREASURY
```

The splitter’s **entire** ERC-20 balance is definitionally revenue. Every successful skim
empties the adapter for that token (no residual custody).

Example: `COMMITTED_BPS = 3000`, skim finds 100_000 USDC → **30_000** to lockers, **70_000**
to the dApp treasury.

Attribution: receipt epoch on `notifyRevenue` (a skim at 23:59 Wednesday vs 00:01 Thursday
hits different pots).

## Integration checklist

### 1. Deploy

```bash
export DISTRIBUTOR=0x...
export ADAPTER_MODE=B
export DAPP=0x...                 # dApp identity in the registry
export DAPP_TREASURY=0x...        # where the uncommitted share goes
export COMMITTED_BPS=3000         # 30% to lockers
export REWARD_TOKENS=0xWXDC,0xUSDC
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

### 2. Register (timelock)

Execute printed `registry.registerAdapter(...)` with mode `SPLITTER` and the same bps.

### 3. Wire the dApp

Set the product’s fee / protocol-fee recipient to the **FeeSplitter address**.

No allowance is required: tokens are already on the splitter when fees accrue.

### 4. Operate

```solidity
feeSplitter.skim(USDC);  // permissionless
```

Run on a schedule (continuous or pre-boundary). A missed skim only shifts revenue into a later
epoch; it never backdates.

### 5. Verify

- Fees visibly accumulate on the splitter address before skim
- After skim: splitter balance ≈ 0; treasury received remainder; distributor pot increased

## Method reference

| Method | Caller | Effect |
|--------|--------|--------|
| `skim(token)` | anyone | Split full balance → distributor + treasury |
| `SOURCE` / `COMMITTED_BPS` / … | — | Immutable constructor params |

## Lifecycle

- **Stop new revenue:** `registry.deactivateAdapter(adapter)` (timelock).
- **Change bps:** new FeeSplitter deploy + register; point the fee receiver at the new
  address; deactivate the old adapter.
- **Terms hash only:** `registry.updateTerms` — dashboard metadata, not on-chain split.

## Pitfalls

- Pointing a **general treasury** at the splitter taxes everything that lands there — only use
  a fee stream address.
- Unsupported token sitting on the splitter cannot be skimmed (`UnsupportedToken`); recover
  via a future governance process / do not send random tokens here.
- `skim` with zero balance → `NothingToSkim`.
