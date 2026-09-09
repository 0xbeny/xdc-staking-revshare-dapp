# Mode B3 — ZodiacFeeModule

Contract: [`src/adapters/ZodiacFeeModule.sol`](../src/adapters/ZodiacFeeModule.sol)  
Registry mode: `ZODIAC_SAFE`

## When to use

Same economics as [Mode B2](B2-pull.md) (dedicated fee Safe, full-balance skim, split by
`COMMITTED_BPS`), but authorization is a **Safe module** instead of an ERC-20 allowance.

Prefer B3 when:

- You do not want infinite `approve` on the Safe
- Module-based automation fits your Safe ops model (Zodiac / Avatar pattern)

**Dedicated fee Safe only** — `skim` empties each supported token in full.

## How it works

```
Fees ──▶ dedicated Fee Safe (module enabled: ZodiacFeeModule)
Anyone calls skim(USDC)
  → Safe.execTransactionFromModule(
        USDC.transfer(adapter, fullBalance)
    )
  → assert Safe emptied and adapter received exact amount (else SweepIncomplete)
  → split by COMMITTED_BPS → notifyRevenue / DAPP_TREASURY
```

Raw `transfer` via the Safe is not SafeERC20-hardened; the module checks balances so a
false-returning token cannot look like a successful empty skim.

## Integration checklist

### 1. Dedicated fee Safe

Same rule as B2: revenue-only Safe.

### 2. Deploy

```bash
export DISTRIBUTOR=0x...
export ADAPTER_MODE=B3
export DAPP=0x...
export DAPP_TREASURY=0x...
export COMMITTED_BPS=2500
export REWARD_TOKENS=0xWXDC,0xUSDC
export FEE_SAFE=0x...
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

### 3. Register (timelock)

`registry.registerAdapter(...)` with mode `ZODIAC_SAFE`.

### 4. Enable the module

From the fee Safe:

```solidity
enableModule(zodiacFeeModule);
```

(The deploy script prints the calldata.) Point the dApp fee receiver at `FEE_SAFE`.

### 5. Operate

```solidity
zodiacFeeModule.skim(USDC);  // permissionless
```

### 6. Verify

- `token.balanceOf(FEE_SAFE) == 0` after skim
- Module still enabled; distributor pot increased

## Method reference

| Method | Caller | Effect |
|--------|--------|--------|
| `skim(token)` | anyone | Module transfer full balance → split → notify / treasury |
| `FEE_SAFE` | — | Immutable Safe this module is bound to |

Errors worth knowing: `SafeExecutionFailed`, `SweepIncomplete`, `NothingToSkim`.

## Lifecycle

Deactivate in registry to stop notifies. Changing bps → new module + new register +
`enableModule` on the Safe (disable the old module).

## Pitfalls

- Enabling on a **treasury** Safe exposes all supported-token balances to skim.
- Forgetting `enableModule` → `SafeExecutionFailed`.
- B2 vs B3: do not run both against the same Safe for the same tokens without a clear ops
  plan — either allowance **or** module is enough.
