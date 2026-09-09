# veXDC v1 — developer commands
# Secrets come from .env (gitignored). Never pass a raw private key to a mainnet command.

-include .env
export

.PHONY: build test test-unit test-e2e test-fuzz test-invariant test-invariant-strict coverage lint fmt \
        anvil deploy-local deploy-apothem deploy-mainnet deploy-adapter clean

build:
	forge build

test:
	forge test

test-unit:
	forge test --match-path "test/unit/*"

test-e2e:
	forge test --match-path "test/e2e/*"

test-fuzz:
	FOUNDRY_PROFILE=ci forge test --match-path "test/fuzz/*"

test-invariant:
	forge test --match-path "test/invariant/*"

test-invariant-strict:
	FOUNDRY_INVARIANT_FAIL_ON_REVERT=true FOUNDRY_INVARIANT_RUNS=512 FOUNDRY_INVARIANT_DEPTH=96 \
		forge test --match-path "test/invariant/*"

coverage:
	forge coverage --no-match-path "test/invariant/*" --report summary --no-match-coverage "(script|test|mocks)"

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

## Apothem testnet (chain 51). Uses a keystore account: `cast wallet import deployer --interactive`.
deploy-apothem:
	forge script script/Deploy.s.sol:Deploy --rpc-url xdc_apothem --account $(DEPLOYER_ACCOUNT) \
		--broadcast --verify --slow

## XDC mainnet (chain 50). Hardware wallet only.
deploy-mainnet:
	forge script script/Deploy.s.sol:Deploy --rpc-url xdc --ledger --sender $(DEPLOYER_ADDRESS) \
		--broadcast --verify --slow

## One adapter. Set ADAPTER_MODE, DAPP, DAPP_TREASURY, COMMITTED_BPS, REWARD_TOKENS, DISTRIBUTOR (+ FEE_SAFE).
deploy-adapter:
	forge script script/DeployAdapter.s.sol:DeployAdapter --rpc-url $(NETWORK) --account $(DEPLOYER_ACCOUNT) \
		--broadcast --verify

clean:
	forge clean
	rm -rf broadcast cache
