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

## Partner UI flow (Modes A & B)

For approved FeeSplitter (default) or PushAdapter deployments on Apothem / configured chain:

1. **Deploy** — open `/integrate` in the web app, pick Mode B or A, set `committedBps`, treasury
   (and Push `source`), keep WXDC/USDC reward tokens prefilled from the deployment, and deploy
   from the partner wallet. Copy the adapter address from the success checklist.
2. **Whitelist** — send the address out of band to a `REGISTRY_ADMIN`. On `/admin` → Adapters,
   paste the address; the desk checks contract code, `DISTRIBUTOR` match, and `COMMITTED_BPS`
   vs the form, then `registerAdapter`. The adapter appears in the **Listed dApps** table.
3. **Fund / skim (testnet)** — on Apothem, use Admin → **Simulate revenue** (mint mock USDC →
   `skim`) or CLI:

```bash
export USDC=0x...            # from deployments/51.json
export FEE_SPLITTER=0x...    # registered Mode B adapter
export AMOUNT=1000000000     # optional; default 1000e6
make simulate-apothem-revenue DEPLOYER_ACCOUNT=deployer
```

Expected committed = `amount * committedBps / 10000`. After an epoch settles, confirm claims /
indexer revenue.

B2 / B3 / C stay Foundry + docs only in v1 (no partner UI).

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

CLI (any mode, including B2/B3/C):

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

Or Modes A/B from the web: `/integrate` (see above).

The script / UI prints or shows the adapter address. Registration remains a separate
`REGISTRY_ADMIN` / timelock action. Until registration, `notifyRevenue` reverts with
`NotAnActiveAdapter`.

## What lockers see

Revenue is attributed to the **epoch it lands in**, allocated by the weights snapshotted at
that epoch's start, and claimable once the epoch closes. A sweep at 23:59 on Wednesday is this
week's revenue; one at 00:01 on Thursday is next week's. The keeper targets pre-boundary
sweeps, but nothing depends on it.

For every locker call sequence (deposit, compound, cooldown exits, Safe, etc.) see
[USER_FLOWS.md](USER_FLOWS.md).

## Lifecycle

Registry status is **governance-controlled metadata** and takes effect immediately — there is
no on-chain notice period.

- **Deactivate:** timelock calls `registry.deactivateAdapter(adapter)`. Notifications stop;
  funds already notified stay claimable.
- **Change terms:** deploy a new adapter with the new bps, register it, deactivate the old one.
- **Terms metadata:** `registry.updateTerms(adapter, termsHash, version)` updates the
  human-readable record only. It cannot change what the adapter does.
