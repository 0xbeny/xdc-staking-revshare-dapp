// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

/// @notice End-to-end: cap binds deposits, then a governed raise re-opens headroom.
contract StakingCapJourneyTest is Base {
    function test_capBindsThenTimelockRaisesAndUsersFillHeadroom() public {
        vm.prank(guardian);
        escrow.setStakingCap(200 ether);

        _lock(alice, 150 ether, 52 weeks);

        vm.startPrank(bob);
        wxdc.approve(address(zap), 100 ether);
        vm.expectRevert(VotingEscrow.StakingCapExceeded.selector);
        zap.lockWXDC(60 ether, 52 weeks);
        vm.stopPrank();

        vm.prank(timelock);
        escrow.setStakingCap(300 ether);

        vm.startPrank(bob);
        zap.lockWXDC(100 ether, 52 weeks);
        vm.stopPrank();

        assertEq(escrow.totalLocked(), 250 ether);
        assertLe(escrow.totalLocked(), escrow.stakingCap());
    }
}
