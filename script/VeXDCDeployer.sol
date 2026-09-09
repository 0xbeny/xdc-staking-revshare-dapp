// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FeeDistributor} from "../src/FeeDistributor.sol";
import {RevenueRegistry} from "../src/RevenueRegistry.sol";
import {SystemAccess} from "../src/SystemAccess.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {ZapDepositor} from "../src/ZapDepositor.sol";
import {VeVotesAdapter} from "../src/governance/VeVotesAdapter.sol";
import {Roles} from "../src/libraries/Roles.sol";

/// @title VeXDCDeployer
/// @notice The single source of truth for how the system is wired together. Both the mainnet
///         deployment script and the test harness call this, so the topology under test is the
///         topology that ships.
///
/// @dev Ordering is forced by the escrow being immutable: it takes the distributor as an
///      immutable penalty destination, so the distributor proxy must exist first. Roles live in
///      `SystemAccess` and are keyed by target (`address(distributor)`, `address(registry)`, …).
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
        SystemAccess access;
        RevenueRegistry registry;
        address registryImpl;
        FeeDistributor distributor;
        address distributorImpl;
        VotingEscrow escrow;
        ZapDepositor zap;
        VeVotesAdapter votes;
    }

    /// @dev Mirrors the escrow's immutable clamps so a bad config fails before any deployment.
    uint256 internal constant HARD_MAX_BPS = 5000;

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
        if (c.maxPenaltyBps > HARD_MAX_BPS) {
            revert InvalidConfig("maxPenaltyBps > HARD_MAX_PENALTY_BPS");
        }
        if (c.penaltySplitBps > HARD_MAX_BPS) {
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

        d.access = new SystemAccess(admin);

        d.registryImpl = address(new RevenueRegistry());
        d.registry = RevenueRegistry(
            address(new ERC1967Proxy(d.registryImpl, abi.encodeCall(RevenueRegistry.initialize, (address(d.access)))))
        );

        d.distributorImpl = address(new FeeDistributor());
        d.distributor = FeeDistributor(
            address(
                new ERC1967Proxy(
                    d.distributorImpl,
                    abi.encodeCall(FeeDistributor.initialize, (address(d.access), address(d.registry)))
                )
            )
        );

        // Bootstrap: deployer can wire one-shot admin surfaces before handover.
        d.access.grantRole(address(d.registry), Roles.DEFAULT_ADMIN, admin);
        d.access.grantRole(address(d.distributor), Roles.DEFAULT_ADMIN, admin);

        d.escrow = new VotingEscrow(
            c.wxdc, address(d.distributor), c.treasury, c.timelock, c.maxPenaltyBps, c.penaltySplitBps
        );

        d.registry.setDistributor(address(d.distributor));
        d.distributor.setEscrow(address(d.escrow));
        for (uint256 i = 0; i < c.rewardTokens.length; ++i) {
            d.distributor.addRewardToken(c.rewardTokens[i]);
        }

        d.zap = new ZapDepositor(c.wxdc, address(d.escrow));
        d.escrow.setDepositor(address(d.zap));
        d.votes = new VeVotesAdapter(address(d.escrow));
    }

    /// @notice Grants every target role to its governance holder and renounces the deployer's own.
    function handOverToGovernance(Deployment memory d, Config memory c, address admin) internal {
        SystemAccess access = d.access;
        address dist = address(d.distributor);
        address reg = address(d.registry);

        access.grantRole(dist, Roles.DEFAULT_ADMIN, c.timelock);
        access.grantRole(dist, Roles.UPGRADER, c.timelock);
        access.grantRole(dist, Roles.PAUSER, c.guardian);
        access.grantRole(dist, Roles.KEEPER, c.keeper);

        access.grantRole(reg, Roles.DEFAULT_ADMIN, c.timelock);
        access.grantRole(reg, Roles.UPGRADER, c.timelock);
        access.grantRole(reg, Roles.REGISTRY_ADMIN, c.timelock);

        access.revokeRole(dist, Roles.DEFAULT_ADMIN, admin);
        access.revokeRole(reg, Roles.DEFAULT_ADMIN, admin);

        access.grantRole(access.DEFAULT_ADMIN_ROLE(), c.timelock);
        access.renounceRole(access.DEFAULT_ADMIN_ROLE(), admin);
    }

    /// @notice Post-deployment assertions. Anything non-empty here means do not go live.
    function verify(Deployment memory d, Config memory c, address admin) internal view returns (string memory) {
        string memory failure = _verifyWiring(d, c);
        if (bytes(failure).length != 0) {
            return failure;
        }
        return _verifyRoles(d, c, admin);
    }

    function _verifyWiring(Deployment memory d, Config memory c) private view returns (string memory) {
        string memory failure = _verifyEscrowWiring(d, c);
        if (bytes(failure).length != 0) {
            return failure;
        }
        return _verifyPeripheryWiring(d, c);
    }

    function _verifyEscrowWiring(Deployment memory d, Config memory c) private view returns (string memory) {
        if (d.escrow.distributor() != address(d.distributor)) {
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
        return "";
    }

    function _verifyPeripheryWiring(Deployment memory d, Config memory c) private view returns (string memory) {
        if (address(d.distributor.authority()) != address(d.access)) {
            return "distributor.authority mismatch";
        }
        if (address(d.registry.authority()) != address(d.access)) {
            return "registry.authority mismatch";
        }
        if (address(d.distributor.escrow()) != address(d.escrow)) {
            return "distributor.escrow mismatch";
        }
        if (address(d.distributor.registry()) != address(d.registry)) {
            return "distributor.registry mismatch";
        }
        if (d.registry.distributor() != address(d.distributor)) {
            return "registry.distributor mismatch";
        }
        if (address(d.zap.ESCROW()) != address(d.escrow)) {
            return "zap.escrow mismatch";
        }
        if (d.escrow.depositor() != address(d.zap)) {
            return "escrow.depositor != zap";
        }
        if (address(d.votes.ESCROW()) != address(d.escrow)) {
            return "votes.escrow mismatch";
        }
        for (uint256 i = 0; i < c.rewardTokens.length; ++i) {
            if (!d.distributor.isRewardToken(c.rewardTokens[i])) {
                return "reward token not registered";
            }
        }
        return "";
    }

    /// @dev Governance holds every role; the deployer holds none on targets or the hub.
    function _verifyRoles(Deployment memory d, Config memory c, address admin) private view returns (string memory) {
        SystemAccess access = d.access;
        address dist = address(d.distributor);
        address reg = address(d.registry);

        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), c.timelock)) {
            return "timelock lacks system access admin";
        }
        if (!access.hasRole(dist, Roles.DEFAULT_ADMIN, c.timelock)) {
            return "timelock lacks distributor admin";
        }
        if (!access.hasRole(dist, Roles.PAUSER, c.guardian)) {
            return "guardian lacks pauser";
        }
        if (!access.hasRole(dist, Roles.KEEPER, c.keeper)) {
            return "keeper lacks keeper role";
        }
        if (!access.hasRole(reg, Roles.REGISTRY_ADMIN, c.timelock)) {
            return "timelock lacks registry admin";
        }

        bool deployerHoldsSomething = access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin)
            || access.hasRole(dist, Roles.DEFAULT_ADMIN, admin) || access.hasRole(dist, Roles.UPGRADER, admin)
            || access.hasRole(dist, Roles.PAUSER, admin) || access.hasRole(dist, Roles.KEEPER, admin)
            || access.hasRole(reg, Roles.DEFAULT_ADMIN, admin) || access.hasRole(reg, Roles.UPGRADER, admin)
            || access.hasRole(reg, Roles.REGISTRY_ADMIN, admin);
        if (deployerHoldsSomething) {
            return "deployer still holds a role";
        }
        return "";
    }
}
