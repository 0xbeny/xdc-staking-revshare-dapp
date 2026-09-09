# Revenue adapters

Immutable contracts that move a dApp’s committed revenue into [`FeeDistributor`](../src/FeeDistributor.sol).
Terms are fixed at construction; the [`RevenueRegistry`](../src/RevenueRegistry.sol) only
whitelists and stores metadata. Changing a commitment means deploying a **new** adapter.

Shared rules for Modes A/B/B2/B3 live in
[`RevenueAdapterBase`](../src/adapters/RevenueAdapterBase.sol): `(SOURCE, DISTRIBUTOR,
DAPP_TREASURY, COMMITTED_BPS, tokens)` are immutable; a successful skim leaves no residual
balance on the adapter.

## Choose a mode

| Mode | Doc | Contract | When to use |
|------|-----|----------|-------------|
| **A** | [Push](A-push.md) | `PushAdapter` | dApp pushes a known committed amount |
| **B** | [FeeSplitter](B-fee-splitter.md) | `FeeSplitter` | Fee receiver can be set to a contract (default) |
| **B2** | [Pull](B2-pull.md) | `PullAdapter` | Dedicated fee Safe + ERC-20 allowance |
| **B3** | [Zodiac](B3-zodiac.md) | `ZodiacFeeModule` | Dedicated fee Safe + Safe module |
| **C** | [Attestor](C-attestor.md) | `Attestor` | Off-chain / cross-chain attestation + transfer |

**B2/B3:** never install on a general treasury Safe — skim empties supported token balances.

## Common deploy command

```bash
export DISTRIBUTOR=0x...          # deployments/<chainId>.json
export ADAPTER_MODE=B             # A | B | B2 | B3 | C
export DAPP=0x...
export DAPP_TREASURY=0x...
export COMMITTED_BPS=3000
export REWARD_TOKENS=0xWXDC,0xUSDC
export FEE_SAFE=0x...             # B2 / B3
export SYSTEM_ACCESS=0x...        # C
export REPORTER=0x...             # C
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

Until the timelock **registers** the adapter, `notifyRevenue` reverts (`NotAnActiveAdapter`).
Mode C also needs `SystemAccess.grantRole(attestor, REPORTER_ROLE, reporter)`.

## What lockers see

Revenue is attributed to the **epoch it lands in**, paid by snapshotted ve weight after the
epoch is settled. See [INTEGRATION.md](../INTEGRATION.md) and [ARCHITECTURE.md](../ARCHITECTURE.md).

## Lifecycle (all modes)

- **Deactivate:** `registry.deactivateAdapter(adapter)` — stops new notifies; past revenue stays claimable.
- **Change terms:** deploy new adapter → register → deactivate old; retarget fee receiver / Safe / pushes.
- **Metadata only:** `registry.updateTerms(adapter, termsHash, version)` does not change on-chain behaviour.
