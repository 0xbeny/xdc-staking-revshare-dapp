# Mode C — Attestor

Contract: [`src/adapters/Attestor.sol`](../src/adapters/Attestor.sol)  
Registry mode: `ATTESTATION`

## When to use

Revenue is **measured off-chain** (or on another chain) and brought on-chain as an atomic
“record + transfer.” Typical for:

- Cross-chain fee aggregation
- Off-chain billing / enterprise revenue
- Cases where there is no on-chain fee stream to skim

Each Attestor instance is bound to **one dApp** (`immutable DAPP`). Deploy a separate
instance per dApp. Uniqueness is per `(dapp, token, sourceEpoch)`.

## How it works

```
Reporter (REPORTER role on SystemAccess for this attestor)
  → postRevenue(token, sourceEpoch, gross, adjustment, metadataHash)
       ├─ writes one immutable Record attributed to DAPP
       ├─ net = gross + adjustment (must be ≥ 0)
       └─ if net > 0: pull net from reporter → notifyRevenue(distributor)
```

Important rules:

| Concept | Meaning |
|---------|---------|
| `DAPP` | Immutable at construction; every record uses this identity. |
| `sourceEpoch` | Metadata for “which period this report is about.” Must already be **closed**. |
| `distributionEpoch` | Set to **current** epoch at receipt. The reporter **cannot** choose it. |
| Duplicate key | Second post for the same `(dapp, token, sourceEpoch)` reverts. |
| Adjustments | Fix mistakes on a **later** source period; never claw back from the distributor. |

Unlike A/B/B2/B3, Attestor does **not** inherit `RevenueAdapterBase`’s split: the reporter
transfers the **net** commitment; registry `committedBps` may be `0` or informational.

Roles live in **`SystemAccess`**:
`access.grantRole(attestor, REPORTER_ROLE, reporter)`.

## Integration checklist

### 1. Deploy

```bash
export DISTRIBUTOR=0x...
export ADAPTER_MODE=C
export SYSTEM_ACCESS=0x...        # deployments/<chainId>.json → systemAccess
export REPORTER=0x...             # will receive REPORTER_ROLE
export REWARD_TOKENS=0xWXDC,0xUSDC
export DAPP=0x...                 # immutable dApp identity for this attestor
export COMMITTED_BPS=0            # Mode C may use 0 in the registry
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

The script prints:

1. `registry.registerAdapter` calldata  
2. `SystemAccess.grantRole(attestor, REPORTER_ROLE, reporter)` calldata  

### 2. Timelock actions

1. Register the attestor (mode `ATTESTATION`) against the same `DAPP`.
2. Grant `REPORTER_ROLE` on `SystemAccess` for **this attestor address**.

### 3. Wire the reporter

```solidity
IERC20(token).approve(attestor, type(uint256).max);
```

### 4. Post each closed period

```solidity
// sourceEpoch must be < currentEpoch
attestor.postRevenue(
  USDC,
  sourceEpoch,
  50_000e6,   // gross
  0,          // adjustment
  keccak256("report-2026-W12")
);
```

### 5. Correcting a mistake

Records are immutable. On a **later** closed `sourceEpoch`:

| Mistake | Call |
|---------|------|
| Under-reported by 1_000 | `postRevenue(..., gross, +1_000e6, hash)` → transfers `gross + 1000` |
| Over-reported by 1_000 | `postRevenue(..., gross, -1_000e6, hash)` → transfers `gross - 1000` |

Nothing is ever pulled back from `FeeDistributor`.

### 6. Verify

- `attestor.posted(key(DAPP, token, sourceEpoch)) == true`
- `records(...).distributionEpoch == epoch at post time`
- Distributor pot for that receipt epoch increased by `net`

## Method reference

| Method | Caller | Effect |
|--------|--------|--------|
| `postRevenue(...)` | `REPORTER` (via SystemAccess) | Atomic record + optional transfer + notify |
| `records` / `recordAt` / `recordCount` | anyone | Read immutable history |
| `hasRole(role, account)` | anyone | Convenience view into SystemAccess for this target |

## Lifecycle

- **Rotate reporter:** timelock
  `access.revokeRole(attestor, REPORTER, old)` /
  `grantRole(attestor, REPORTER, new)`.
- **Stop posts:** deactivate in registry and/or revoke reporter.
- **New terms / new dApp:** new attestor instance + re-grant + re-register.
