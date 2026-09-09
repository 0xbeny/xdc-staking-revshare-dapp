// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract VotingEscrowGovernanceTest is Base {
    function test_timelockHandoverIsTwoStep() public {
        address newTimelock = makeAddr("newTimelock");

        vm.prank(timelock);
        escrow.transferTimelock(newTimelock);
        assertEq(escrow.timelock(), timelock, "not effective until accepted");

        vm.prank(alice);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.acceptTimelock();

        vm.prank(newTimelock);
        escrow.acceptTimelock();
        assertEq(escrow.timelock(), newTimelock);
        assertEq(escrow.pendingTimelock(), address(0));
    }

    function test_penaltyDestinationsAreImmutable() public {
        assertEq(escrow.distributor(), address(distributor));
        assertEq(escrow.treasury(), treasury);

        (bool ok,) = address(escrow).call(abi.encodeWithSignature("setTreasury(address)", alice));
        assertFalse(ok);
        (ok,) = address(escrow).call(abi.encodeWithSignature("setDistributor(address)", alice));
        assertFalse(ok);
    }

    /// @dev PenaltyManager is deleted from the system (#11). No external contract is consulted.
    function test_noPenaltyManagerExists() public {
        (bool ok,) = address(escrow).call(abi.encodeWithSignature("penaltyManager()"));
        assertFalse(ok);
        (ok,) = address(escrow).call(abi.encodeWithSignature("setPenaltyManager(address)", alice));
        assertFalse(ok);
    }

    function test_constructorRejectsOutOfRangeParameters() public {
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        new VotingEscrow(address(wxdc), address(distributor), treasury, timelock, 5001, 2000);

        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        new VotingEscrow(address(wxdc), address(distributor), treasury, timelock, 5000, 5001);
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        new VotingEscrow(address(0), address(distributor), treasury, timelock, 5000, 2000);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        new VotingEscrow(address(wxdc), address(0), treasury, timelock, 5000, 2000);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        new VotingEscrow(address(wxdc), address(distributor), address(0), timelock, 5000, 2000);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        new VotingEscrow(address(wxdc), address(distributor), treasury, address(0), 5000, 2000);
    }

    function test_wrapperTierExistsButIsEmptyAtLaunch() public view {
        assertTrue(uint8(VotingEscrow.Tier.WRAPPER) == 2);
        assertEq(uint8(escrow.tierOf(address(distributor))), uint8(VotingEscrow.Tier.NONE));
    }
}
