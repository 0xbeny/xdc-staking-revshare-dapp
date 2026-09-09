# Integrating a dApp — committing revenue

A dApp commits a share of its revenue to veXDC lockers through an **immutable adapter**. The
adapter hardcodes the terms; the registry mirrors them as metadata and controls whether the
adapter may notify. Changing the terms means deploying a new adapter.

## Choose a mode

| Mode | Contract | When to use | Who calls |
|---|---|---|---|
| A — Push | `PushAdapter` | The dApp computes the committed amount itself and pushes it. | The dApp (`SOURCE`) |
| B — Splitter (default) | `FeeSplitter` | The dApp can point its fee receiver at an address. The whole balance is revenue; the splitter keeps `COMMITTED_BPS` for lockers and forwards the rest to the dApp treasury. | Anyone (`skim`) |
| B2 — Pull | `PullAdapter` | Fees already flow to a **dedicated** fee Safe. The Safe approves the adapter. | Anyone (`skim`) |
| B3 — Zodiac | `ZodiacFeeModule` | Same as B2 but via a Safe module instead of an allowance. | Anyone (`skim`) |
| C — Attestation | `Attestor` | Revenue is measured off-chain (or off this chain). A reporter posts one atomic record + transfer per period. | The reporter |

**B2/B3 require a dedicated fee Safe.** The sweep moves the Safe's *entire* balance of each
supported token. Never install either on a general treasury Safe.

## Deploy the adapter

```bash
export DISTRIBUTOR=0x...          # from deployments/<chainId>.json
export ADAPTER_MODE=B             # A | B | B2 | B3 | C
export DAPP=0x...                 # the dApp's identity (its fee source / treasury signer)
export DAPP_TREASURY=0x...        # where the uncommitted remainder goes
export COMMITTED_BPS=3000         # 30% to lockers
export REWARD_TOKENS=0xWXDC,0xUSDC
export FEE_SAFE=0x...             # B2 / B3 only
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

The script prints:

1. the adapter address;
2. the exact `registry.registerAdapter(...)` calldata for the **timelock** to execute;
3. for B2, the `approve` the fee Safe must execute; for B3, the `enableModule` the fee Safe
   must execute.

Until the timelock registers it, the adapter cannot notify revenue — `notifyRevenue` reverts
with `NotAnActiveAdapter`.

## Wire the dApp

- **A:** call `commitRevenue(token, amount)` from `DAPP` after approving the adapter.
- **B:** set the dApp's fee receiver to the adapter address. Done.
- **B2:** from the fee Safe, `token.approve(adapter, type(uint256).max)` for each token.
- **B3:** from the fee Safe, `enableModule(adapter)`.
- **C:** the reporter approves the attestor for each token and calls
  `postRevenue(dapp, token, sourceEpoch, gross, adjustment, metadataHash)` once per closed
  source period.

## What lockers see

Revenue is attributed to the **epoch it lands in**, allocated by the weights snapshotted at
that epoch's start, and claimable once the epoch closes. A sweep at 23:59 on Wednesday is this
week's revenue; one at 00:01 on Thursday is next week's. The keeper targets pre-boundary
sweeps, but nothing depends on it.

## Correcting a Mode C mistake

Records are immutable. Post the correction against a **later** source period:

- under-reported by 1,000: `postRevenue(dapp, token, laterEpoch, gross, +1_000e6, hash)` —
  transfers `gross + 1000`;
- over-reported by 1,000: `postRevenue(dapp, token, laterEpoch, gross, −1_000e6, hash)` —
  transfers `gross − 1000`. Nothing is ever pulled back from the distributor.

## Lifecycle

- **Deactivate:** timelock calls `registry.deactivateAdapter(adapter)`. Notifications stop;
  funds already notified stay claimable.
- **Change terms:** deploy a new adapter with the new bps, register it, deactivate the old one.
- **Terms metadata:** `registry.updateTerms(adapter, termsHash, version)` updates the
  human-readable record only. It cannot change what the adapter does.
