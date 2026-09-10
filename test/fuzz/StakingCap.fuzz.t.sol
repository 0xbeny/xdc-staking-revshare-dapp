// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract StakingCapFuzzTest is Base {
    function testFuzz_decreaseNeverSetsCapAtOrBelowTotalLocked(uint128 deposited, uint128 targetCap) public {
        uint256 amount = bound(deposited, escrow.MIN_LOCK_AMOUNT(), 1_000_000 ether);
        _lock(alice, amount, 52 weeks);

        uint256 newCap = bound(targetCap, 0, amount); // <= totalLocked
        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.StakingCapTooLow.selector);
        escrow.setStakingCap(newCap);
    }

    function testFuzz_decreaseAllowedStrictlyAboveTotalLocked(uint128 deposited, uint128 headroom) public {
        uint256 amount = bound(deposited, escrow.MIN_LOCK_AMOUNT(), 500_000 ether);
        _lock(alice, amount, 52 weeks);

        // First lower from max to a high ceiling so the second call is a true decrease path.
        vm.prank(timelock);
        escrow.setStakingCap(amount + 10_000_000 ether);

        uint256 extra = bound(headroom, 1, 1_000_000 ether);
        uint256 newCap = amount + extra;
        vm.prank(guardian);
        escrow.setStakingCap(newCap);
        assertEq(escrow.stakingCap(), newCap);
        assertGt(escrow.stakingCap(), escrow.totalLocked());
    }

    function testFuzz_depositsNeverExceedStakingCap(uint128 first, uint128 second, uint128 cap) public {
        uint256 cap_ = bound(cap, escrow.MIN_LOCK_AMOUNT(), 2_000_000 ether);
        vm.prank(timelock);
        escrow.setStakingCap(cap_);

        uint256 a = bound(first, escrow.MIN_LOCK_AMOUNT(), cap_);
        _lock(alice, a, 52 weeks);

        uint256 remaining = cap_ - a;
        if (remaining < escrow.MIN_LOCK_AMOUNT()) {
            return;
        }
        uint256 b = bound(second, escrow.MIN_LOCK_AMOUNT(), remaining + escrow.MIN_LOCK_AMOUNT());
        vm.startPrank(bob);
        wxdc.approve(address(zap), b);
        if (a + b > cap_) {
            vm.expectRevert(VotingEscrow.StakingCapExceeded.selector);
            zap.lockWXDC(b, 52 weeks);
        } else {
            zap.lockWXDC(b, 52 weeks);
            assertLe(escrow.totalLocked(), cap_);
        }
        vm.stopPrank();
    }

    function testFuzz_onlyCapAdminsCanRaise(address caller, uint256 newCap) public {
        vm.assume(caller != timelock && caller != guardian);
        newCap = bound(newCap, 1, type(uint128).max);

        // Start from a finite cap so raise is meaningful.
        vm.prank(timelock);
        escrow.setStakingCap(1 ether);

        vm.prank(caller);
        vm.expectRevert(VotingEscrow.NotCapAdmin.selector);
        escrow.setStakingCap(newCap + 1 ether);
    }
}
