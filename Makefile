# veXDC v1 — developer commands
# Secrets come from .env (gitignored). Never pass a raw private key to a mainnet command.

-include .env
export

# `make ci FORGE=/path/to/forge` runs the gate with a specific forge build. The lint policy in
# foundry.toml is written against forge v1.8.1; older builds know fewer rules and pass trivially.
FORGE ?= forge
SLITHER ?= $(if $(wildcard .venv/bin/slither),.venv/bin/slither,slither)

.PHONY: ci fmt-check lint-ci lint-tests sizes slither slither-install \
        build test test-unit test-e2e test-fuzz test-invariant test-invariant-strict coverage lint fmt \
        anvil deploy-local deploy-apothem-mocks deploy-apothem deploy-apothem-pk deploy-apothem-continue \
        deploy-mainnet deploy-adapter simulate-apothem-revenue clean

## The full local gate — the same steps the GitHub Actions PR/push workflow runs.
ci: fmt-check lint-ci lint-tests sizes test test-invariant-strict coverage slither
	@echo "✔ local CI passed ($(shell $(FORGE) --version | head -1))"

fmt-check:
	$(FORGE) fmt --check

## Zero findings on shipping code. Tests are linted advisory-only (see lint-tests).
## The rule set in foundry.toml targets forge >= 1.8.1; an older forge rejects the newer rule
## ids and must fail here loudly rather than pass with nothing linted.
lint-ci:
	@set -o pipefail; $(FORGE) lint src/ script/ 2>&1 | tee /tmp/vexdc-lint.log || { \
		echo "✘ forge lint failed to run ($$($(FORGE) --version | head -1))."; \
		echo "  The lint policy needs forge >= 1.8.1: 'foundryup -i v1.8.1' or 'make ci FORGE=/path/to/forge'."; exit 1; }
	@if grep -qE '^(warning|note)\[' /tmp/vexdc-lint.log; then echo "✘ lint findings in src/ or script/"; exit 1; fi

lint-tests:
	-$(FORGE) lint test/

sizes:
	$(FORGE) build --sizes

## Slither is required for `make ci`. Install with `make slither-install` if missing.
slither:
	@if command -v $(SLITHER) >/dev/null 2>&1 || [ -x "$(SLITHER)" ]; then \
		$(SLITHER) . --config-file slither.config.json --fail-high; \
	else \
		echo "✘ slither not installed — run 'make slither-install'"; exit 1; \
	fi

slither-install:
	python3 -m venv .venv && .venv/bin/pip install --quiet --upgrade pip slither-analyzer
	@echo "installed: $$(.venv/bin/slither --version)"

build:
	$(FORGE) build

test:
	$(FORGE) test

test-unit:
	forge test --match-path "test/unit/*"

test-e2e:
	forge test --match-path "test/e2e/*"

test-fuzz:
	FOUNDRY_PROFILE=ci forge test --match-path "test/fuzz/*"

test-invariant:
	forge test --match-path "test/invariant/*"

test-invariant-strict:
	rm -rf cache/invariant
	FOUNDRY_INVARIANT_FAIL_ON_REVERT=true FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=64 \
		$(FORGE) test --match-path "test/invariant/*"

coverage:
	$(FORGE) coverage --no-match-path "test/invariant/*" --report summary --no-match-coverage "(script|test|mocks)"

lint:
	forge fmt --check
	forge lint src/ test/ script/

fmt:
	forge fmt

anvil:
	anvil --chain-id 31337

## Local rehearsal: `make anvil` in another terminal, then:
##   make deploy-local        (deploys mocks, prints exports, deploys the system)
deploy-local:
	@forge script script/LocalMocks.s.sol:LocalMocks --rpc-url localhost \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast \
		| grep -E '^\s*export' | sed 's/^\s*//' > /tmp/vexdc-local.env
	@echo "export TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8" >> /tmp/vexdc-local.env
	@echo "export KEEPER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" >> /tmp/vexdc-local.env
	@cat /tmp/vexdc-local.env
	@bash -c 'source /tmp/vexdc-local.env && forge script script/Deploy.s.sol:Deploy --rpc-url localhost \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast'

## Apothem: deploy mock USDC against canonical WXDC. Prints REWARD_TOKENS exports.
deploy-apothem-mocks:
	forge script script/ApothemMocks.s.sol:ApothemMocks --rpc-url xdc_apothem \
		--account $(DEPLOYER_ACCOUNT) --broadcast --slow --gas-estimate-multiplier 200

## Apothem testnet (chain 51). Uses a keystore account: `cast wallet import deployer --interactive`.
## Or: DEPLOYER_PRIVATE_KEY=0x… make deploy-apothem-pk
## Gas multiplier: Apothem under-estimates CREATE+init (proxy deploys); 200 avoided OOG.
deploy-apothem:
	forge script script/Deploy.s.sol:Deploy --rpc-url xdc_apothem --account $(DEPLOYER_ACCOUNT) \
		--broadcast --verify --slow --gas-estimate-multiplier 200

deploy-apothem-pk:
	forge script script/Deploy.s.sol:Deploy --rpc-url xdc_apothem \
		--private-key $(DEPLOYER_PRIVATE_KEY) --broadcast --slow --gas-estimate-multiplier 200

## Resume after a partial Apothem deploy (SYSTEM_ACCESS + REVENUE_REGISTRY* in .env).
deploy-apothem-continue:
	forge script script/ContinueApothemDeploy.s.sol:ContinueApothemDeploy --rpc-url xdc_apothem \
		--private-key $(DEPLOYER_PRIVATE_KEY) --broadcast --slow --gas-estimate-multiplier 200

## XDC mainnet (chain 50). Hardware wallet only.
deploy-mainnet:
	forge script script/Deploy.s.sol:Deploy --rpc-url xdc --ledger --sender $(DEPLOYER_ADDRESS) \
		--broadcast --verify --slow

## One adapter. Set ADAPTER_MODE, DAPP, DAPP_TREASURY, COMMITTED_BPS, REWARD_TOKENS, DISTRIBUTOR (+ FEE_SAFE).
deploy-adapter:
	forge script script/DeployAdapter.s.sol:DeployAdapter --rpc-url $(NETWORK) --account $(DEPLOYER_ACCOUNT) \
		--broadcast --verify

## Apothem: mint mock USDC to a FeeSplitter and skim (USDC + FEE_SPLITTER in env; optional AMOUNT).
simulate-apothem-revenue:
	forge script script/ApothemMockRevenue.s.sol:ApothemMockRevenue --rpc-url xdc_apothem \
		--account $(DEPLOYER_ACCOUNT) --broadcast --slow

clean:
	forge clean
	rm -rf broadcast cache
