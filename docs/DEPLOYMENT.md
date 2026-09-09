# Deployment runbook — XDC mainnet

Chain id **50** (mainnet), **51** (Apothem testnet). Explorer: xdcscan.

## 0. What you need before touching mainnet

| Item | Requirement |
|---|---|
| `TIMELOCK` | A deployed **contract** (OpenZeppelin `TimelockController` ≥ 48h, owned by the multisig). The script refuses an EOA on chain 50. |
| `GUARDIAN` | A deployed **contract** (a Safe). Holds `PAUSER_ROLE` on the distributor target in `SystemAccess` only. The script refuses an EOA on chain 50. |
| `TREASURY` | Where the treasury share of penalties goes. Immutable in the escrow — get it right. |
| `KEEPER` | The Hermes signer. Holds `KEEPER_ROLE` on the distributor target in `SystemAccess` only. |
| `WXDC` | The canonical wrapped-XDC contract. **Verify it against the official XDC Network documentation** — the script checks it is a contract with 18 decimals, nothing more. |
| `REWARD_TOKENS` | Comma-separated. Launch: WXDC and USDC. |
| `MAX_PENALTY_BPS` | Launch value ≤ 5000 (hard clamp). Spec suggests 5000. |
| `PENALTY_SPLIT_BPS` | Treasury share of a penalty, ≤ 5000. Spec suggests 2000 (80/20). |
| Signer | Hardware wallet (`--ledger`/`--trezor`) or an encrypted keystore (`cast wallet import`). **Never** a raw private key in `.env` for mainnet. |
| Gas | Enough XDC on the deployer for ~15M gas of deployments. |

Everything above is read from the environment; `.env.example` lists the variables. Keep `.env`
out of git — it is already ignored.

## 1. Rehearse on anvil

```bash
make anvil                 # terminal 1
make deploy-local          # terminal 2 — deploys mocks, then the real Deploy script
```

`Deploy.s.sol` runs its own post-deployment `verify()` and reverts the run if any wiring or
role is wrong. The same library runs under the test-suite, so `forge test` is a rehearsal too.

## 2. Rehearse on Apothem (chain 51)

```bash
cast wallet import deployer --interactive    # once
export DEPLOYER_ACCOUNT=deployer
make deploy-apothem
```

Then run through [OPERATIONS.md](OPERATIONS.md) for at least two epoch boundaries: sweep,
`keepAtMaxLock` in the window, `batchCompound` after it, a claim, an early exit, and a
`syncForfeiture`. Confirm the numbers reconcile with `docs/ARCHITECTURE.md`.

## 3. Mainnet

```bash
export DEPLOYER_ADDRESS=0x...        # the ledger address
make deploy-mainnet
```

What the script does, in one broadcast:

1. Validates config; refuses EOA governance on chain 50.
2. Deploys `RevenueRegistry` impl + proxy (temporary admin = deployer).
3. Deploys `FeeDistributor` impl + proxy (temporary admin = deployer).
4. Deploys `VotingEscrow` with the distributor proxy and treasury as immutables and the
   timelock as its only governance address.
5. Wires `registry.setDistributor`, `distributor.setEscrow` (one-shot), `addRewardToken` ×N.
6. Deploys `ZapDepositor` and `VeVotesAdapter`.
7. Grants every role to the timelock / guardian / keeper and **renounces all of the
   deployer's roles**.
8. Runs `verify()` — reverts if anything is off — and writes `deployments/50.json`.

The deployer ends the run with **no privilege anywhere in the system**.

## 4. Post-deployment checklist

- [ ] Verify sources on xdcscan (`--verify` in the make target; re-run `forge verify-contract`
      for any that failed).
- [ ] `deployments/50.json` committed.
- [ ] `escrow.timelock()`, `escrow.treasury()`, `escrow.distributor()` match the config.
- [ ] `systemAccess.hasRole(DEFAULT_ADMIN_ROLE, deployer) == false`
- [ ] `systemAccess.hasRole(distributor, DEFAULT_ADMIN_ROLE, deployer) == false` (and every other target role).
- [ ] Timelock proposal queued to register the launch adapters (see [INTEGRATION.md](INTEGRATION.md)).
- [ ] Hermes configured with the keeper key and the addresses from `deployments/50.json`.
- [ ] Guardian Safe signers rehearsed `distributor.pause()` on Apothem.
- [ ] Launch TVL caps and monitoring live (outside these contracts — see SPEC §7).

## 5. Upgrading the periphery

Only `FeeDistributor` and `RevenueRegistry` are UUPS. An upgrade is a timelock action:

```solidity
distributor.upgradeToAndCall(newImplementation, "");
```

Before proposing: run the full test-suite against the new implementation, keep the storage
layout append-only (`__gap` is reserved), and re-run the invariant suite with
`fail_on_revert`. The escrow, zap and adapters cannot be upgraded — a change there is a new
deployment and a migration at natural expiry.

## 6. Adapters for new dApps

See [INTEGRATION.md](INTEGRATION.md). In short: `make deploy-adapter` prints the exact
`registerAdapter` calldata for the timelock. Deploying an adapter grants it nothing;
registration is what lets it notify revenue.
