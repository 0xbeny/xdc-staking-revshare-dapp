// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract PenaltyFuzzTest is Base {
    /// @dev Invariant: `penaltyBps <= min(positionCap, maxPenaltyBps) <= HARD_MAX_PENALTY_BPS`.
    function testFuzz_penaltyIsAlwaysWithinTheClamps(
        uint128 amount,
        uint16 weeksToLock,
        uint32 offset,
        uint32 skipSeconds,
        uint16 globalCap
    ) public {
        amount = uint128(bound(amount, 1 ether, 1_000_000 ether));
        uint256 cap = bound(globalCap, 0, escrow.maxPenaltyBps());
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(cap);

        vm.warp(_epochStart(_currentEpoch()) + bound(offset, 0, WEEK - 1));
        uint256 tokenId = _lock(alice, amount, bound(weeksToLock, 1, 104) * WEEK);

        uint256 end = escrow.locked(tokenId).end;
        vm.warp(bound(skipSeconds, block.timestamp, end - 1));

        (uint256 returned, uint256 penalty, uint256 bps) = escrow.previewExit(tokenId);
        assertLe(bps, escrow.effectivePenaltyCapBps(tokenId));
        assertLe(bps, escrow.HARD_MAX_PENALTY_BPS());
        assertEq(returned + penalty, amount, "principal is fully accounted for");
    }

    /// @dev Governance can never raise the global cap, so existing effective caps only improve.
    function testFuzz_governanceCannotWorsenAnExistingPosition(uint16 capAtLock, uint16 capLater) public {
        uint256 first = bound(capAtLock, 0, escrow.maxPenaltyBps());
        uint256 second = bound(capLater, 0, first);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(first);
        uint256 tokenId = _lock(alice, 1000 ether, 52 weeks);
        uint256 effectiveBefore = escrow.effectivePenaltyCapBps(tokenId);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(second);

        assertLe(escrow.effectivePenaltyCapBps(tokenId), effectiveBefore, "an existing cap can only improve");
    }

    /// @dev Raise attempts always revert once the global is below the attempted value.
    function testFuzz_governanceCannotRaiseMaxPenaltyBps(uint16 lowerTo, uint16 attemptRaise) public {
        uint256 current = escrow.maxPenaltyBps();
        if (current == 0) {
            return;
        }
        uint256 lowered = bound(lowerTo, 0, current - 1);
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(lowered);

        uint256 raiseTo = bound(attemptRaise, lowered + 1, current);
        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setMaxPenaltyBps(raiseTo);
    }

    /// @dev The weighted `increase_amount` rule under a non-increasing global.
    function testFuzz_increaseAmountReweightsCapWithinBounds(
        uint128 principal,
        uint128 added,
        uint16 capAtLock,
        uint16 capLater
    ) public {
        principal = uint128(bound(principal, 1 ether, 1_000_000 ether));
        added = uint128(bound(added, 1 ether, 1_000_000 ether));
        uint256 oldCap = bound(capAtLock, 0, escrow.maxPenaltyBps());
        uint256 newGlobal = bound(capLater, 0, oldCap);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(oldCap);
        uint256 tokenId = _lock(alice, principal, 52 weeks);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(newGlobal);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), added);
        escrow.increaseAmount(tokenId, added);
        vm.stopPrank();

        uint256 resulting = escrow.locked(tokenId).penaltyCapBps;
        assertGe(resulting, newGlobal == 0 ? 0 : newGlobal - 1, "never below the cheaper of the two");
        assertLe(resulting, oldCap, "never above the dearer of the two");

        uint256 expected = (uint256(principal) * oldCap + uint256(added) * newGlobal) / (uint256(principal) + added);
        assertEq(resulting, expected, "exact weighted average");
        assertEq(escrow.effectivePenaltyCapBps(tokenId), resulting < newGlobal ? resulting : newGlobal);
    }

    /// @dev Extensions never change the cap, at any parameter setting.
    function testFuzz_extensionsNeverChangeTheCap(uint16 capAtLock, uint16 capLater, uint16 weeksToLock) public {
        uint256 first = bound(capAtLock, 0, escrow.maxPenaltyBps());
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(first);
        uint256 tokenId = _lock(alice, 1000 ether, bound(weeksToLock, 1, 50) * WEEK);
        uint256 capBefore = escrow.locked(tokenId).penaltyCapBps;

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(bound(capLater, 0, first));

        vm.prank(alice);
        escrow.keepAtMaxLock(tokenId);
        assertEq(escrow.locked(tokenId).penaltyCapBps, capBefore);
    }

    /// @dev The penalty split always sums back to the whole penalty, treasury share capped.
    function testFuzz_penaltySplitConservesTheWholePenalty(uint128 amount, uint16 splitBps, uint16 weeksToLock) public {
        amount = uint128(bound(amount, 1 ether, 1_000_000 ether));
        uint256 split = bound(splitBps, 0, 5000);
        vm.prank(timelock);
        escrow.setPenaltySplitBps(split);

        uint256 tokenId = _lock(alice, amount, bound(weeksToLock, 1, 104) * WEEK);
        (uint256 returned, uint256 penalty,) = escrow.previewExit(tokenId);

        uint256 aliceBefore = wxdc.balanceOf(alice);
        uint256 treasuryBefore = wxdc.balanceOf(treasury);
        uint256 distributorBefore = wxdc.balanceOf(address(distributor));

        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        uint256 toTreasury = wxdc.balanceOf(treasury) - treasuryBefore;
        uint256 toLockers = wxdc.balanceOf(address(distributor)) - distributorBefore;

        assertEq(wxdc.balanceOf(alice) - aliceBefore, returned);
        assertEq(toTreasury + toLockers, penalty, "the whole penalty is distributed");
        assertLe(toTreasury * 10_000, penalty * 5000 + 10_000, "treasury share is capped at 50%");
        assertEq(escrow.totalLocked(), 0, "principal fully accounted for");
    }
}
