// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {Base} from "../Base.t.sol";

/// @dev Adversarial checks at Foundry broadcast boundaries that unit wiring cannot insert.
contract DeployBoundaryTest is Base {
    function test_attackerCannotCaptureDepositorBetweenEscrowAndZap() public {
        VotingEscrow fresh =
            new VotingEscrow(address(wxdc), address(distributor), treasury, timelock, guardian, 5000, 2000);
        assertEq(fresh.bootstrapAdmin(), address(this));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        fresh.setDepositor(attacker);

        ZapDepositor localZap = new ZapDepositor(address(wxdc), address(fresh));
        fresh.setDepositor(address(localZap));
        assertEq(fresh.depositor(), address(localZap));
        assertEq(fresh.bootstrapAdmin(), address(0));

        vm.expectRevert(VotingEscrow.DepositorAlreadySet.selector);
        fresh.setDepositor(attacker);
    }
}
