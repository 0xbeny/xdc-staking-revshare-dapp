# Integrating a dApp — committing revenue

A dApp commits a share of its revenue to veXDC lockers through an **immutable adapter**. The
adapter hardcodes the terms; the registry mirrors them as metadata and controls whether the
adapter may notify. Changing the terms means deploying a new adapter.

**Per-mode guides** (how it works + step-by-step integration):

| Mode | Guide |
|------|--------|
| A — Push | [adapters/A-push.md](adapters/A-push.md) |
| B — FeeSplitter (default) | [adapters/B-fee-splitter.md](adapters/B-fee-splitter.md) |
| B2 — Pull (fee Safe + allowance) | [adapters/B2-pull.md](adapters/B2-pull.md) |
| B3 — Zodiac (fee Safe + module) | [adapters/B3-zodiac.md](adapters/B3-zodiac.md) |
| C — Attestation | [adapters/C-attestor.md](adapters/C-attestor.md) |

Index: [adapters/README.md](adapters/README.md).

## Choose a mode (summary)

| Mode | Contract | When to use | Who calls |
|---|---|---|---|
| A — Push | `PushAdapter` | The dApp computes the committed amount itself and pushes it. | The dApp (`SOURCE`) |
| B — Splitter (default) | `FeeSplitter` | The dApp can point its fee receiver at an address. | Anyone (`skim`) |
| B2 — Pull | `PullAdapter` | Fees already flow to a **dedicated** fee Safe (allowance). | Anyone (`skim`) |
| B3 — Zodiac | `ZodiacFeeModule` | Same as B2 but via a Safe module. | Anyone (`skim`) |
| C — Attestation | `Attestor` | Revenue measured off-chain; reporter posts record + transfer. | The reporter |

**B2/B3 require a dedicated fee Safe.** The sweep moves the Safe's *entire* balance of each
supported token. Never install either on a general treasury Safe.

## Deploy (all modes)

```bash
export DISTRIBUTOR=0x...          # from deployments/<chainId>.json
export ADAPTER_MODE=B             # A | B | B2 | B3 | C
export DAPP=0x...
export DAPP_TREASURY=0x...
export COMMITTED_BPS=3000
export REWARD_TOKENS=0xWXDC,0xUSDC
export FEE_SAFE=0x...             # B2 / B3 only
export SYSTEM_ACCESS=0x...        # C only
export REPORTER=0x...             # C only
make deploy-adapter NETWORK=xdc DEPLOYER_ACCOUNT=deployer
```

The script prints registration calldata for the **timelock** (and Mode C reporter grant /
B2 approve / B3 `enableModule` as needed). Until registration,
`notifyRevenue` reverts with `NotAnActiveAdapter`.

## What lockers see

Revenue is attributed to the **epoch it lands in**, allocated by the weights snapshotted at
that epoch's start, and claimable once the epoch closes. A sweep at 23:59 on Wednesday is this
week's revenue; one at 00:01 on Thursday is next week's. The keeper targets pre-boundary
sweeps, but nothing depends on it.

For every locker call sequence (deposit, compound, cooldown exits, Safe, etc.) see
[USER_FLOWS.md](USER_FLOWS.md).

## Lifecycle

- **Deactivate:** timelock calls `registry.deactivateAdapter(adapter)`. Notifications stop;
  funds already notified stay claimable.
- **Change terms:** deploy a new adapter with the new bps, register it, deactivate the old one.
- **Terms metadata:** `registry.updateTerms(adapter, termsHash, version)` updates the
  human-readable record only. It cannot change what the adapter does.
