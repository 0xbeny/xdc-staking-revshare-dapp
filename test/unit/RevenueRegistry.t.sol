// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RevenueRegistry} from "../../src/RevenueRegistry.sol";
import {IRevenueRegistry} from "../../src/interfaces/IRevenueRegistry.sol";
import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RevenueRegistryTest is Base {
    function test_registryHoldsMetadataOnlyAndNeverCustody() public view {
        assertEq(usdc.balanceOf(address(registry)), 0);
        assertEq(usdc.allowance(address(registry), address(distributor)), 0);

        IRevenueRegistry.AdapterInfo memory info = registry.adapterInfo(address(splitter));
        assertEq(info.dapp, dapp);
        assertEq(uint8(info.mode), uint8(IRevenueRegistry.Mode.SPLITTER));
        assertEq(info.committedBps, 3000);
        assertTrue(info.active);
    }

    function test_deactivateAndReactivate() public {
        vm.prank(timelock);
        registry.deactivateAdapter(address(splitter));
        assertFalse(registry.isActiveAdapter(address(splitter)));

        vm.prank(timelock);
        registry.reactivateAdapter(address(splitter));
        assertTrue(registry.isActiveAdapter(address(splitter)));
    }

    function test_cannotRegisterTwice() public {
        vm.prank(timelock);
        vm.expectRevert(RevenueRegistry.AlreadyRegistered.selector);
        registry.registerAdapter(address(splitter), dapp, IRevenueRegistry.Mode.SPLITTER, 3000, 1, "");
    }

    function test_registerRejectsInvalidInput() public {
        vm.startPrank(timelock);
        vm.expectRevert(RevenueRegistry.InvalidMode.selector);
        registry.registerAdapter(address(0xA1), dapp, IRevenueRegistry.Mode.NONE, 3000, 1, "");
        vm.expectRevert(RevenueRegistry.InvalidBps.selector);
        registry.registerAdapter(address(0xA1), dapp, IRevenueRegistry.Mode.SPLITTER, 10_001, 1, "");
        vm.expectRevert(RevenueRegistry.ZeroAddress.selector);
        registry.registerAdapter(address(0), dapp, IRevenueRegistry.Mode.SPLITTER, 3000, 1, "");
        vm.stopPrank();
    }

    function test_onlyRegistryAdminCanRegister() public {
        bytes32 role = registry.REGISTRY_ADMIN_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        registry.registerAdapter(address(0xA1), dapp, IRevenueRegistry.Mode.SPLITTER, 3000, 1, "");
    }

    function test_onlyDistributorRecordsContributions() public {
        vm.prank(alice);
        vm.expectRevert(RevenueRegistry.NotDistributor.selector);
        registry.recordContribution(address(splitter), address(usdc), 1);
    }

    /// @dev Terms are versioned metadata: updating them cannot change on-chain behaviour.
    function test_updatingTermsDoesNotChangeAdapterBehaviour() public {
        vm.prank(timelock);
        registry.updateTerms(address(splitter), keccak256("v2"), 2);

        assertEq(registry.adapterInfo(address(splitter)).version, 2);
        assertEq(splitter.COMMITTED_BPS(), 3000, "the hardcoded split is untouched");
    }

    function test_enumeration() public view {
        assertEq(registry.allAdapters().length, 5);
        assertEq(registry.adaptersOfDapp(dapp).length, 5);
    }
}
