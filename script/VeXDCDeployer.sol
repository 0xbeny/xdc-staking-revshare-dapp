// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FeeDistributor} from "../src/FeeDistributor.sol";
import {RevenueRegistry} from "../src/RevenueRegistry.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {ZapDepositor} from "../src/ZapDepositor.sol";
import {VeVotesAdapter} from "../src/governance/VeVotesAdapter.sol";

/// @title VeXDCDeployer
/// @notice The single source of truth for how the system is wired together. Both the mainnet
///         deployment script and the test harness call this, so the topology under test is the
///         topology that ships.
///
/// @dev Ordering is forced by the escrow being immutable: it takes the distributor as an
///      immutable penalty destination, so the distributor proxy must exist first. The proxy is
///      therefore initialised with a temporary admin that wires the escrow in and then hands
///      every role to governance and renounces its own.
library VeXDCDeployer {
    struct Config {
        address wxdc;
        address timelock;
        address guardian;
        address treasury;
        address keeper;
        uint256 maxPenaltyBps;
        uint256 penaltySplitBps;
        address[] rewardTokens;
    }

    struct Deployment {
        RevenueRegistry registry;
        address registryImpl;
        FeeDistributor distributor;
        address distributorImpl;
        VotingEscrow escrow;
        ZapDepositor zap;
        VeVotesAdapter votes;
    }

    error InvalidConfig(string what);

    function validate(Config memory c) internal view {
        if (c.wxdc == address(0)) {
            revert InvalidConfig("wxdc");
        }
        if (c.wxdc.code.length == 0) {
            revert InvalidConfig("wxdc is not a contract");
        }
        if (IERC20Metadata(c.wxdc).decimals() != 18) {
            revert InvalidConfig("wxdc decimals != 18");
        }
        if (c.timelock == address(0)) {
            revert InvalidConfig("timelock");
        }
        if (c.guardian == address(0)) {
            revert InvalidConfig("guardian");
        }
        if (c.treasury == address(0)) {
            revert InvalidConfig("treasury");
        }
        if (c.keeper == address(0)) {
            revert InvalidConfig("keeper");
        }
        if (c.maxPenaltyBps > 5000) {
            revert InvalidConfig("maxPenaltyBps > HARD_MAX_PENALTY_BPS");
        }
        if (c.penaltySplitBps > 5000) {
            revert InvalidConfig("penaltySplitBps > 50%");
        }
        if (c.rewardTokens.length == 0) {
            revert InvalidConfig("no reward tokens");
        }
    }

    /// @param admin The temporary wiring admin (the deployer). It holds no role once
    ///              `handOverToGovernance` has run.
    function deploy(Config memory c, address admin) internal returns (Deployment memory d) {
        validate(c);

        d.registryImpl = address(new RevenueRegistry());
        d.registry = RevenueRegistry(
            address(new ERC1967Proxy(d.registryImpl, abi.encodeCall(RevenueRegistry.initialize, (admin))))
        );

        d.distributorImpl = address(new FeeDistributor());
        d.distributor = FeeDistributor(
            address(
                new ERC1967Proxy(
                    d.distributorImpl, abi.encodeCall(FeeDistributor.initialize, (admin, address(d.registry)))
                )
            )
        );

        d.escrow = new VotingEscrow(
            c.wxdc, address(d.distributor), c.treasury, c.timelock, c.maxPenaltyBps, c.penaltySplitBps
        );

        d.registry.setDistributor(address(d.distributor));
        d.distributor.setEscrow(address(d.escrow));
        for (uint256 i; i < c.rewardTokens.length; ++i) {
            d.distributor.addRewardToken(c.rewardTokens[i]);
        }

        d.zap = new ZapDepositor(c.wxdc, address(d.escrow));
        d.votes = new VeVotesAdapter(address(d.escrow));
    }

    /// @notice Grants every role to its governance holder and renounces the deployer's own.
    function handOverToGovernance(Deployment memory d, Config memory c, address admin) internal {
        FeeDistributor dist = d.distributor;
        RevenueRegistry reg = d.registry;

        dist.grantRole(dist.DEFAULT_ADMIN_ROLE(), c.timelock);
        dist.grantRole(dist.UPGRADER_ROLE(), c.timelock);
        dist.grantRole(dist.PAUSER_ROLE(), c.guardian);
        dist.grantRole(dist.KEEPER_ROLE(), c.keeper);

        reg.grantRole(reg.DEFAULT_ADMIN_ROLE(), c.timelock);
        reg.grantRole(reg.UPGRADER_ROLE(), c.timelock);
        reg.grantRole(reg.REGISTRY_ADMIN_ROLE(), c.timelock);

        dist.renounceRole(dist.PAUSER_ROLE(), admin);
        dist.renounceRole(dist.UPGRADER_ROLE(), admin);
        dist.renounceRole(dist.DEFAULT_ADMIN_ROLE(), admin);

        reg.renounceRole(reg.REGISTRY_ADMIN_ROLE(), admin);
        reg.renounceRole(reg.UPGRADER_ROLE(), admin);
        reg.renounceRole(reg.DEFAULT_ADMIN_ROLE(), admin);
    }

    /// @notice Post-deployment assertions. Anything false here means do not go live.
    function verify(Deployment memory d, Config memory c, address admin) internal view returns (string memory) {
        FeeDistributor dist = d.distributor;
        RevenueRegistry reg = d.registry;

        if (d.escrow.distributor() != address(dist)) {
            return "escrow.distributor mismatch";
        }
        if (d.escrow.treasury() != c.treasury) {
            return "escrow.treasury mismatch";
        }
        if (d.escrow.timelock() != c.timelock) {
            return "escrow.timelock mismatch";
        }
        if (d.escrow.token() != c.wxdc) {
            return "escrow.token mismatch";
        }
        if (address(dist.escrow()) != address(d.escrow)) {
            return "distributor.escrow mismatch";
        }
        if (address(dist.registry()) != address(reg)) {
            return "distributor.registry mismatch";
        }
        if (reg.distributor() != address(dist)) {
            return "registry.distributor mismatch";
        }
        if (address(d.zap.ESCROW()) != address(d.escrow)) {
            return "zap.escrow mismatch";
        }
        if (address(d.votes.ESCROW()) != address(d.escrow)) {
            return "votes.escrow mismatch";
        }

        if (!dist.hasRole(dist.DEFAULT_ADMIN_ROLE(), c.timelock)) {
            return "timelock lacks distributor admin";
        }
        if (!dist.hasRole(dist.PAUSER_ROLE(), c.guardian)) {
            return "guardian lacks pauser";
        }
        if (!dist.hasRole(dist.KEEPER_ROLE(), c.keeper)) {
            return "keeper lacks keeper role";
        }
        if (!reg.hasRole(reg.REGISTRY_ADMIN_ROLE(), c.timelock)) {
            return "timelock lacks registry admin";
        }

        if (dist.hasRole(dist.DEFAULT_ADMIN_ROLE(), admin)) {
            return "deployer still holds distributor admin";
        }
        if (dist.hasRole(dist.UPGRADER_ROLE(), admin)) {
            return "deployer still holds upgrader";
        }
        if (dist.hasRole(dist.PAUSER_ROLE(), admin)) {
            return "deployer still holds pauser";
        }
        if (reg.hasRole(reg.DEFAULT_ADMIN_ROLE(), admin)) {
            return "deployer still holds registry admin";
        }
        if (reg.hasRole(reg.UPGRADER_ROLE(), admin)) {
            return "deployer still holds registry upgrader";
        }
        if (reg.hasRole(reg.REGISTRY_ADMIN_ROLE(), admin)) {
            return "deployer still holds registry role";
        }

        for (uint256 i; i < c.rewardTokens.length; ++i) {
            if (!dist.isRewardToken(c.rewardTokens[i])) {
                return "reward token not registered";
            }
        }
        return "";
    }
}
