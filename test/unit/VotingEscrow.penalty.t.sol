// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract VotingEscrowPenaltyTest is Base {
    function test_penalty_scalesWithEffectiveTime() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);

        // Spec §9 step 5: at week 26 of 52 the effective time is 26 weeks -> 50% * 26/104 = 12.5%.
        vm.warp(escrow.locked(tokenId).end - 26 weeks);
        (uint256 returned, uint256 penalty, uint256 penaltyBps) = escrow.previewExit(tokenId);

        assertEq(penaltyBps, 1250, "12.5% at 26 weeks remaining with a 50% cap");
        assertEq(penalty, 12_500 ether);
        assertEq(returned, 87_500 ether);
    }

    function test_penalty_isContinuousToZeroAtExpiry() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end - 1);
        (, uint256 penalty, uint256 bps) = escrow.previewExit(tokenId);
        assertEq(bps, 0, "no floor: the penalty decays continuously to zero");
        assertEq(penalty, 0);
    }

    function test_penalty_usesClampedEffectiveTime() public {
        vm.warp(_epochStart(_currentEpoch()) + 3 days);
        uint256 tokenId = _lock(alice, 100_000 ether, MAX_LOCK);
        assertGt(escrow.locked(tokenId).end - block.timestamp, MAX_LOCK, "setup: overshoots MAX_LOCK");

        (,, uint256 bps) = escrow.previewExit(tokenId);
        assertEq(bps, escrow.maxPenaltyBps(), "clamped: never exceeds maxPenaltyBps");
        assertLe(bps, escrow.HARD_MAX_PENALTY_BPS());
    }

    function test_emergencyExit_splitsPenalty80_20() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        vm.warp(escrow.locked(tokenId).end - 52 weeks);

        (uint256 returned, uint256 penalty,) = escrow.previewExit(tokenId);
        uint256 aliceBefore = wxdc.balanceOf(alice);
        uint256 treasuryBefore = wxdc.balanceOf(treasury);
        uint256 distributorBefore = wxdc.balanceOf(address(distributor));

        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        assertEq(wxdc.balanceOf(alice) - aliceBefore, returned);
        assertEq(wxdc.balanceOf(treasury) - treasuryBefore, penalty * 2000 / 10_000, "20% to treasury");
        assertEq(
            wxdc.balanceOf(address(distributor)) - distributorBefore,
            penalty - (penalty * 2000 / 10_000),
            "80% to lockers"
        );
        assertEq(escrow.totalLocked(), 0);
    }

    function test_emergencyExit_recordsExitEpochAndForfeitedWeight() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        escrow.checkpoint();

        uint256 epoch = _currentEpoch();
        uint256 snapshotWeight = escrow.balanceOfNFTAt(tokenId, _epochStart(epoch));

        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        assertEq(escrow.exitEpoch(tokenId), epoch);
        assertEq(escrow.exitedWeightByEpoch(epoch), snapshotWeight);
    }

    function test_emergencyExit_positionCreatedMidEpochForfeitsNothingForThatEpoch() public {
        vm.warp(_epochStart(_currentEpoch()) + 3 days);
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        uint256 epoch = _currentEpoch();

        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        assertEq(escrow.exitedWeightByEpoch(epoch), 0, "it was never in this epoch's snapshot");
        assertEq(escrow.firstEligibleEpoch(tokenId), epoch + 1);
    }

    /// @dev A position created exactly on a week boundary *is* in that epoch's snapshot, so it
    ///      is eligible for that epoch and forfeits that epoch's slice when it exits later.
    function test_emergencyExit_positionCreatedOnBoundaryForfeitsThatEpoch() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        uint256 epoch = _currentEpoch();

        assertEq(escrow.firstEligibleEpoch(tokenId), epoch, "already inside this epoch's snapshot");

        // A later block in the same epoch: the boundary snapshot is now immutable.
        vm.warp(block.timestamp + 1 days);
        uint256 snapshotWeight = escrow.balanceOfNFTAt(tokenId, _epochStart(epoch));
        assertGt(snapshotWeight, 0);

        vm.prank(alice);
        escrow.emergencyExit(tokenId);
        assertEq(escrow.exitedWeightByEpoch(epoch), snapshotWeight);
        assertEq(escrow.exitedWeightByEpoch(epoch), escrow.totalSupplyAtWeek(_epochStart(epoch)));
    }

    /// @dev Creating and exiting inside the same block as the boundary removes the position from
    ///      both sides of the fraction, so there is nothing to forfeit.
    function test_emergencyExit_sameBlockAsBoundaryForfeitsNothing() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        uint256 epoch = _currentEpoch();

        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        assertEq(escrow.exitedWeightByEpoch(epoch), 0);
        assertEq(escrow.totalSupplyAtWeek(_epochStart(epoch)), 0);
    }

    function test_emergencyExit_revertsAfterExpiry() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockNotExpired.selector);
        escrow.emergencyExit(tokenId);
    }

    function test_emergencyExit_onlyOwner() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        vm.prank(bob);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.emergencyExit(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                            GRANDFATHERING (#5)
    //////////////////////////////////////////////////////////////*/

    function test_grandfathering_globalDecreaseAppliesImmediately() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        assertEq(escrow.locked(tokenId).penaltyCapBps, 5000);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        assertEq(escrow.effectivePenaltyCapBps(tokenId), 1000, "reductions apply immediately");
        assertEq(escrow.locked(tokenId).penaltyCapBps, 5000, "stored cap is unchanged");
    }

    function test_maxPenaltyBpsIsMonotonicallyNonIncreasing() public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        assertEq(escrow.maxPenaltyBps(), 1000);

        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setMaxPenaltyBps(1001);

        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setMaxPenaltyBps(5000);

        // Same value is a no-op increase of zero — allowed.
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        assertEq(escrow.maxPenaltyBps(), 1000);
    }

    /// @dev Stateful sequence the old fuzz suite missed: lower → raise attempt must not worsen.
    function test_grandfathering_governanceCannotRaiseAfterLowering() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        uint256 effectiveAtLow = escrow.effectivePenaltyCapBps(tokenId);
        assertEq(effectiveAtLow, 1000);

        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setMaxPenaltyBps(4000);

        assertEq(escrow.effectivePenaltyCapBps(tokenId), effectiveAtLow, "raise attempt left economics untouched");
    }

    /// @dev create @ 10% → global cannot jump to 50%; adding principal uses current (≤) global.
    function test_increaseAmount_afterGlobalDropPreservesEffectiveEconomics() public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        uint256 tokenId = _lock(alice, 100 ether, 52 weeks);

        // Further drop, then add principal — weighted avg, effective still min(stored, global).
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(500);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 100 ether);
        escrow.increaseAmount(tokenId, 100 ether);
        vm.stopPrank();

        // (100*1000 + 100*500) / 200 = 750
        assertEq(escrow.locked(tokenId).penaltyCapBps, 750);
        assertEq(escrow.effectivePenaltyCapBps(tokenId), 500);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(200);
        assertEq(escrow.effectivePenaltyCapBps(tokenId), 200, "further reductions still help");
    }

    function test_increaseAmount_oldPrincipalKeepsItsTermsExactly() public {
        uint256 tokenId = _lock(alice, 100 ether, 52 weeks); // cap 5000

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 100 ether);
        escrow.increaseAmount(tokenId, 100 ether);
        vm.stopPrank();

        // (100*5000 + 100*1000) / 200 = 3000
        assertEq(escrow.locked(tokenId).penaltyCapBps, 3000, "weighted average, not a silent worsening");
        // Global is still 1000, so the effective cap is the better of the two.
        assertEq(escrow.effectivePenaltyCapBps(tokenId), 1000);
    }

    function test_extensionsNeverChangeTheCap() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 20 weeks);
        uint256 capBefore = escrow.locked(tokenId).penaltyCapBps;

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);

        vm.startPrank(alice);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 52 weeks);
        escrow.keepAtMaxLock(tokenId);
        vm.stopPrank();

        assertEq(escrow.locked(tokenId).penaltyCapBps, capBefore, "a keeper convenience flag is not consent");
    }

    function test_keeperExtensionNeverChangesTheCap() public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(1000);
        uint256 tokenId = _lock(alice, 100_000 ether, 20 weeks);

        vm.prank(alice);
        escrow.setOperator(keeper, true);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(500);

        vm.prank(keeper);
        escrow.keepAtMaxLock(tokenId);

        assertEq(escrow.locked(tokenId).penaltyCapBps, 1000);
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAMPS
    //////////////////////////////////////////////////////////////*/

    function test_governanceCannotExceedHardClamps() public {
        vm.startPrank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setMaxPenaltyBps(5001);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setPenaltySplitBps(5001);
        vm.stopPrank();
    }

    function test_onlyTimelockCanTouchParameters() public {
        vm.startPrank(alice);
        vm.expectRevert(VotingEscrow.NotTimelock.selector);
        escrow.setMaxPenaltyBps(100);
        vm.expectRevert(VotingEscrow.NotTimelock.selector);
        escrow.setPenaltySplitBps(100);
        vm.expectRevert(VotingEscrow.NotTimelock.selector);
        escrow.setTier(alice, VotingEscrow.Tier.CUSTODIAN);
        vm.stopPrank();
    }

    /// @dev Principal-safety property: `emergencyExit` must survive a fully hostile periphery.
    function test_emergencyExitWorksWhileDistributorIsPaused() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        vm.prank(guardian);
        distributor.pause();

        vm.prank(alice);
        escrow.emergencyExit(tokenId);
        assertEq(escrow.totalLocked(), 0);
    }

    function test_withdrawWorksWhileDistributorIsPaused() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 4 weeks);
        vm.prank(guardian);
        distributor.pause();

        vm.warp(escrow.locked(tokenId).end);
        vm.prank(alice);
        escrow.withdraw(tokenId);
        assertEq(wxdc.balanceOf(alice), 100_000_000 ether);
    }
}
