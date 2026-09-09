// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {RevenueRegistry} from "../../src/RevenueRegistry.sol";
import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @dev A trivially upgraded implementation, used to prove the UUPS path works *and* that it
///      cannot reach user principal.
contract FeeDistributorV2 is FeeDistributor {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract UpgradeabilityTest is Base {
    function test_distributorUpgradePreservesState() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        uint256 epoch = _currentEpoch();

        FeeDistributorV2 impl = new FeeDistributorV2();
        vm.prank(timelock);
        distributor.upgradeToAndCall(address(impl), "");

        assertEq(FeeDistributorV2(address(distributor)).version(), "v2");
        assertEq(distributor.epochRevenue(address(usdc), epoch), 1000e6, "epoch accounting survives");
        assertEq(address(distributor.escrow()), address(escrow));

        _nextEpoch();
        assertEq(_claim(alice, a, address(usdc)), 1000e6);
    }

    function test_onlyUpgraderCanUpgrade() public {
        FeeDistributorV2 impl = new FeeDistributorV2();
        bytes32 role = distributor.UPGRADER_ROLE();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        distributor.upgradeToAndCall(address(impl), "");
    }

    /// @dev Principal safety (§2): the escrow has no upgrade path at all, so no distributor
    ///      upgrade can reach user principal.
    function test_escrowHasNoUpgradePath() public {
        string[3] memory sigs = ["upgradeTo(address)", "upgradeToAndCall(address,bytes)", "proxiableUUID()"];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(escrow).call(abi.encodeWithSignature(sigs[i], address(1), ""));
            assertFalse(ok, "the escrow is immutable");
        }
    }

    /// @dev A malicious distributor upgrade must not be able to take principal out of the escrow.
    function test_upgradedDistributorStillCannotMovePrincipal() public {
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);

        FeeDistributorV2 impl = new FeeDistributorV2();
        vm.prank(timelock);
        distributor.upgradeToAndCall(address(impl), "");

        vm.startPrank(address(distributor));
        (bool ok,) = address(escrow).call(abi.encodeWithSignature("withdraw(uint256)", a));
        assertFalse(ok, "only the owner may withdraw");
        (ok,) = address(escrow).call(abi.encodeWithSignature("emergencyExit(uint256)", a));
        assertFalse(ok, "only the owner may exit");
        (ok,) = address(escrow).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, bob, a));
        assertFalse(ok, "soulbound");
        vm.stopPrank();

        assertEq(escrow.totalLocked(), 100_000 ether);
    }

    function test_setEscrowIsOneShot() public {
        vm.prank(timelock);
        vm.expectRevert(FeeDistributor.EscrowAlreadySet.selector);
        distributor.setEscrow(address(0xBEEF));
    }

    function test_setDistributorIsOneShot() public {
        vm.prank(timelock);
        vm.expectRevert(RevenueRegistry.DistributorAlreadySet.selector);
        registry.setDistributor(address(0xBEEF));
    }

    function test_implementationsCannotBeInitializedDirectly() public {
        FeeDistributor impl = new FeeDistributor();
        vm.expectRevert();
        impl.initialize(address(access), address(registry));

        RevenueRegistry regImpl = new RevenueRegistry();
        vm.expectRevert();
        regImpl.initialize(address(access));
    }

    function test_registryUpgradeIsRoleGated() public {
        RevenueRegistry impl = new RevenueRegistry();
        bytes32 role = registry.UPGRADER_ROLE();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        registry.upgradeToAndCall(address(impl), "");

        vm.prank(timelock);
        registry.upgradeToAndCall(address(impl), "");
    }
}
