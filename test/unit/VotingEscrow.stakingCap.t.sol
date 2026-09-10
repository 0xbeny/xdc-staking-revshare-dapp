// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

/// @dev Global TVL staking cap: timelock or capGuardian may raise; decreases only when
///      `totalLocked < newCap`.
contract VotingEscrowStakingCapTest is Base {
    function test_defaultStakingCapIsUncapped() public view {
        assertEq(escrow.stakingCap(), type(uint256).max);
        assertEq(escrow.capGuardian(), guardian);
    }

    function test_timelockCanIncreaseStakingCap() public {
        vm.prank(timelock);
        escrow.setStakingCap(1_000_000 ether);
        assertEq(escrow.stakingCap(), 1_000_000 ether);

        vm.prank(timelock);
        escrow.setStakingCap(2_000_000 ether);
        assertEq(escrow.stakingCap(), 2_000_000 ether);
    }

    function test_guardianCanIncreaseStakingCap() public {
        vm.prank(timelock);
        escrow.setStakingCap(500_000 ether);

        vm.prank(guardian);
        escrow.setStakingCap(800_000 ether);
        assertEq(escrow.stakingCap(), 800_000 ether);
    }

    function test_strangerCannotSetStakingCap() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.NotCapAdmin.selector);
        escrow.setStakingCap(1 ether);
    }

    function test_decreaseRequiresTotalLockedStrictlyBelowNewCap() public {
        _lock(alice, 100 ether, 52 weeks);
        assertEq(escrow.totalLocked(), 100 ether);

        vm.prank(timelock);
        escrow.setStakingCap(1000 ether);

        // newCap == totalLocked → rejected
        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.StakingCapTooLow.selector);
        escrow.setStakingCap(100 ether);

        // newCap < totalLocked → rejected
        vm.prank(guardian);
        vm.expectRevert(VotingEscrow.StakingCapTooLow.selector);
        escrow.setStakingCap(50 ether);

        // newCap > totalLocked → allowed decrease
        vm.prank(timelock);
        escrow.setStakingCap(101 ether);
        assertEq(escrow.stakingCap(), 101 ether);
    }

    function test_createLockRevertsWhenCapWouldBeExceeded() public {
        vm.prank(timelock);
        escrow.setStakingCap(150 ether);

        _lock(alice, 100 ether, 52 weeks);

        vm.startPrank(bob);
        wxdc.approve(address(zap), 100 ether);
        vm.expectRevert(VotingEscrow.StakingCapExceeded.selector);
        zap.lockWXDC(51 ether, 52 weeks);
        vm.stopPrank();

        // Exactly filling the remaining headroom is fine.
        vm.startPrank(bob);
        zap.lockWXDC(50 ether, 52 weeks);
        vm.stopPrank();
        assertEq(escrow.totalLocked(), 150 ether);
    }

    function test_increaseAmountRevertsWhenCapWouldBeExceeded() public {
        vm.prank(timelock);
        escrow.setStakingCap(120 ether);

        uint256 tokenId = _lock(alice, 100 ether, 52 weeks);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 50 ether);
        vm.expectRevert(VotingEscrow.StakingCapExceeded.selector);
        escrow.increaseAmount(tokenId, 21 ether);

        escrow.increaseAmount(tokenId, 20 ether);
        vm.stopPrank();
        assertEq(escrow.totalLocked(), 120 ether);
    }

    function test_timelockCanRotateCapGuardian() public {
        address next = makeAddr("capGuardian2");
        vm.prank(timelock);
        escrow.setCapGuardian(next);
        assertEq(escrow.capGuardian(), next);

        vm.prank(guardian);
        vm.expectRevert(VotingEscrow.NotCapAdmin.selector);
        escrow.setStakingCap(1 ether);

        vm.prank(next);
        escrow.setStakingCap(1_000_000 ether);
        assertEq(escrow.stakingCap(), 1_000_000 ether);
    }

    function test_onlyTimelockRotatesCapGuardian() public {
        vm.prank(guardian);
        vm.expectRevert(VotingEscrow.NotTimelock.selector);
        escrow.setCapGuardian(alice);

        vm.prank(alice);
        vm.expectRevert(VotingEscrow.NotTimelock.selector);
        escrow.setCapGuardian(alice);
    }
}
