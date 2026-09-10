// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

import {FeeDistributor} from "../src/FeeDistributor.sol";
import {RevenueRegistry} from "../src/RevenueRegistry.sol";
import {SystemAccess} from "../src/SystemAccess.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {ZapDepositor} from "../src/ZapDepositor.sol";
import {VeVotesAdapter} from "../src/governance/VeVotesAdapter.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {VeXDCDeployer} from "./VeXDCDeployer.sol";

/// @notice Continues an interrupted Apothem deploy after SystemAccess + RevenueRegistry proxy exist.
///
/// Env: WXDC, TIMELOCK, GUARDIAN, TREASURY, KEEPER, REWARD_TOKENS, MAX_PENALTY_BPS, PENALTY_SPLIT_BPS,
///      SYSTEM_ACCESS, REVENUE_REGISTRY, REVENUE_REGISTRY_IMPL
contract ContinueApothemDeploy is Script {
    error DeploymentVerificationFailed(string reason);

    function run() external {
        VeXDCDeployer.Config memory config = _loadConfig();
        VeXDCDeployer.validate(config);

        SystemAccess access = SystemAccess(vm.envAddress("SYSTEM_ACCESS"));
        address registryProxy = vm.envAddress("REVENUE_REGISTRY");
        address registryImpl = vm.envAddress("REVENUE_REGISTRY_IMPL");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        FeeDistributor distributorImpl = new FeeDistributor();
        FeeDistributor distributor = FeeDistributor(
            address(
                new ERC1967Proxy(
                    address(distributorImpl),
                    abi.encodeCall(FeeDistributor.initialize, (address(access), registryProxy))
                )
            )
        );

        access.grantRole(registryProxy, Roles.DEFAULT_ADMIN, deployer);
        access.grantRole(address(distributor), Roles.DEFAULT_ADMIN, deployer);

        VotingEscrow escrow = new VotingEscrow(
            config.wxdc,
            address(distributor),
            config.treasury,
            config.timelock,
            config.guardian,
            config.maxPenaltyBps,
            config.penaltySplitBps
        );

        RevenueRegistry(registryProxy).setDistributor(address(distributor));
        distributor.setEscrow(address(escrow));
        for (uint256 i = 0; i < config.rewardTokens.length; ++i) {
            distributor.addRewardToken(config.rewardTokens[i]);
        }

        ZapDepositor zap = new ZapDepositor(config.wxdc, address(escrow));
        escrow.setDepositor(address(zap));
        VeVotesAdapter votes = new VeVotesAdapter(address(escrow));

        VeXDCDeployer.Deployment memory d;
        d.access = access;
        d.registry = RevenueRegistry(registryProxy);
        d.registryImpl = registryImpl;
        d.distributor = distributor;
        d.distributorImpl = address(distributorImpl);
        d.escrow = escrow;
        d.zap = zap;
        d.votes = votes;

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

    function _report(VeXDCDeployer.Deployment memory d, VeXDCDeployer.Config memory config) internal pure {
        console2.log("=== veXDC v1 continued deploy ===");
        console2.log("SystemAccess          ", address(d.access));
        console2.log("VotingEscrow          ", address(d.escrow));
        console2.log("FeeDistributor (proxy)", address(d.distributor));
        console2.log("FeeDistributor  (impl)", d.distributorImpl);
        console2.log("RevenueRegistry(proxy)", address(d.registry));
        console2.log("RevenueRegistry (impl)", d.registryImpl);
        console2.log("ZapDepositor          ", address(d.zap));
        console2.log("VeVotesAdapter        ", address(d.votes));
        console2.log("timelock              ", config.timelock);
        console2.log("guardian              ", config.guardian);
        console2.log("treasury              ", config.treasury);
        console2.log("keeper                ", config.keeper);
    }

    // forge-lint: disable-start(unused-return)
    function _write(VeXDCDeployer.Deployment memory d, VeXDCDeployer.Config memory config) internal {
        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployedAt", block.timestamp);
        vm.serializeAddress(key, "systemAccess", address(d.access));
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
        vm.createDir("./deployments", true);
        vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
    // forge-lint: disable-end(unused-return)
}
