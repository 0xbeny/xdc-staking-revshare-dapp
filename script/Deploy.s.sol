// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VeXDCDeployer} from "./VeXDCDeployer.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys the full veXDC v1 system and hands every role to governance in one run.
///
/// Usage (Apothem testnet):
///   forge script script/Deploy.s.sol:Deploy --rpc-url xdc_apothem --account <keystore> --broadcast
///
/// Usage (XDC mainnet) — hardware wallet or keystore only, never a raw key:
///   forge script script/Deploy.s.sol:Deploy --rpc-url xdc --ledger --broadcast --verify
///
/// Required environment: WXDC, TIMELOCK, GUARDIAN, TREASURY, KEEPER, MAX_PENALTY_BPS,
/// PENALTY_SPLIT_BPS, REWARD_TOKENS (comma-separated).
contract Deploy is Script {
    error GovernanceMustBeAContract(string role, address who);
    error DeploymentVerificationFailed(string reason);

    function run() external {
        VeXDCDeployer.Config memory config = _loadConfig();
        // Fail fast, before the signer is ever engaged. With --account/--ledger, forge sets
        // `msg.sender` to the signing account, so this is the same address that will broadcast.
        _preflight(config, msg.sender);

        vm.startBroadcast();
        // The wiring admin must be the account that actually signs the transactions.
        (, address deployer,) = vm.readCallers();
        VeXDCDeployer.Deployment memory d = VeXDCDeployer.deploy(config, deployer);
        VeXDCDeployer.handOverToGovernance(d, config, deployer);
        vm.stopBroadcast();

        string memory failure = VeXDCDeployer.verify(d, config, deployer);
        if (bytes(failure).length != 0) {
            revert DeploymentVerificationFailed(failure);
        }

        _report(d, config);
        _write(d, config);
    }

    function _loadConfig() internal view returns (VeXDCDeployer.Config memory config) {
        config.wxdc = vm.envAddress("WXDC");
        config.timelock = vm.envAddress("TIMELOCK");
        config.guardian = vm.envAddress("GUARDIAN");
        config.treasury = vm.envAddress("TREASURY");
        config.keeper = vm.envAddress("KEEPER");
        config.maxPenaltyBps = vm.envOr("MAX_PENALTY_BPS", uint256(5000));
        config.penaltySplitBps = vm.envOr("PENALTY_SPLIT_BPS", uint256(2000));
        config.rewardTokens = vm.envAddress("REWARD_TOKENS", ",");
    }

    /// @dev On a live chain, governance addresses must be contracts (a Timelock and a Safe).
    ///      Deploying with an EOA in either seat would silently defeat the whole governance model.
    function _preflight(VeXDCDeployer.Config memory config, address deployer) internal view {
        VeXDCDeployer.validate(config);
        if (block.chainid == 50) {
            if (config.timelock.code.length == 0) {
                revert GovernanceMustBeAContract("TIMELOCK", config.timelock);
            }
            if (config.guardian.code.length == 0) {
                revert GovernanceMustBeAContract("GUARDIAN", config.guardian);
            }
            if (config.timelock == deployer) {
                revert GovernanceMustBeAContract("TIMELOCK", config.timelock);
            }
        }
    }

    function _report(VeXDCDeployer.Deployment memory d, VeXDCDeployer.Config memory config) internal pure {
        console2.log("=== veXDC v1 deployed ===");
        console2.log("VotingEscrow          ", address(d.escrow));
        console2.log("FeeDistributor (proxy)", address(d.distributor));
        console2.log("FeeDistributor  (impl)", d.distributorImpl);
        console2.log("RevenueRegistry(proxy)", address(d.registry));
        console2.log("RevenueRegistry (impl)", d.registryImpl);
        console2.log("ZapDepositor          ", address(d.zap));
        console2.log("VeVotesAdapter        ", address(d.votes));
        console2.log("--- governance ---");
        console2.log("timelock              ", config.timelock);
        console2.log("guardian (pauser)     ", config.guardian);
        console2.log("treasury              ", config.treasury);
        console2.log("keeper                ", config.keeper);
    }

    function _write(VeXDCDeployer.Deployment memory d, VeXDCDeployer.Config memory config) internal {
        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployedAt", block.timestamp);
        vm.serializeAddress(key, "votingEscrow", address(d.escrow));
        vm.serializeAddress(key, "feeDistributor", address(d.distributor));
        vm.serializeAddress(key, "feeDistributorImpl", d.distributorImpl);
        vm.serializeAddress(key, "revenueRegistry", address(d.registry));
        vm.serializeAddress(key, "revenueRegistryImpl", d.registryImpl);
        vm.serializeAddress(key, "zapDepositor", address(d.zap));
        vm.serializeAddress(key, "veVotesAdapter", address(d.votes));
        vm.serializeAddress(key, "wxdc", config.wxdc);
        vm.serializeAddress(key, "timelock", config.timelock);
        vm.serializeAddress(key, "guardian", config.guardian);
        vm.serializeAddress(key, "treasury", config.treasury);
        string memory json = vm.serializeAddress(key, "keeper", config.keeper);

        vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
}
