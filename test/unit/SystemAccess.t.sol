// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemAccess} from "../../src/SystemAccess.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SystemAccessTest is Base {
    function test_rolesAreKeyedByTarget() public view {
        assertTrue(access.hasRole(address(distributor), Roles.KEEPER, keeper));
        assertFalse(access.hasRole(address(registry), Roles.KEEPER, keeper), "keeper is distributor-scoped");
        assertTrue(access.hasRole(address(registry), Roles.REGISTRY_ADMIN, timelock));
        assertFalse(access.hasRole(address(distributor), Roles.REGISTRY_ADMIN, timelock));
    }

    function test_enumerationListsMembers() public view {
        assertEq(access.getRoleMemberCount(address(distributor), Roles.PAUSER), 1);
        assertEq(access.getRoleMember(address(distributor), Roles.PAUSER, 0), guardian);
    }

    function test_onlyHubAdminCanGrant() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, access.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        access.grantRole(address(distributor), Roles.KEEPER, alice);
    }

    function test_consumersRejectMissingRole() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, Roles.PAUSER)
        );
        distributor.pause();
    }

    function test_renounceClearsMembership() public {
        vm.prank(keeper);
        access.renounceRole(address(distributor), Roles.KEEPER, keeper);
        assertFalse(access.hasRole(address(distributor), Roles.KEEPER, keeper));
        assertEq(access.getRoleMemberCount(address(distributor), Roles.KEEPER), 0);
    }
}
