// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
        uint256 cap = bound(globalCap, 0, 5000);
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

    /// @dev Governance can never raise an existing position's effective cap.
    function testFuzz_governanceCannotWorsenAnExistingPosition(uint16 capAtLock, uint16 capLater) public {
        uint256 first = bound(capAtLock, 0, 5000);
        uint256 second = bound(capLater, 0, 5000);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(first);
        uint256 tokenId = _lock(alice, 1000 ether, 52 weeks);
        uint256 effectiveBefore = escrow.effectivePenaltyCapBps(tokenId);

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(second);

        assertLe(escrow.effectivePenaltyCapBps(tokenId), effectiveBefore, "an existing cap can only improve");
    }

    /// @dev The weighted `increase_amount` rule: the new cap always sits between the old cap and
    ///      the current global, and old principal never enters worse terms than it had.
    function testFuzz_increaseAmountReweightsCapWithinBounds(
        uint128 principal,
        uint128 added,
        uint16 capAtLock,
        uint16 capLater
    ) public {
        principal = uint128(bound(principal, 1 ether, 1_000_000 ether));
        added = uint128(bound(added, 1 ether, 1_000_000 ether));
        uint256 oldCap = bound(capAtLock, 0, 5000);
        uint256 newGlobal = bound(capLater, 0, 5000);

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
        uint256 lo = oldCap < newGlobal ? oldCap : newGlobal;
        uint256 hi = oldCap < newGlobal ? newGlobal : oldCap;
        assertGe(resulting, lo == 0 ? 0 : lo - 1, "never below the cheaper of the two");
        assertLe(resulting, hi, "never above the dearer of the two");

        uint256 expected = (uint256(principal) * oldCap + uint256(added) * newGlobal) / (uint256(principal) + added);
        assertEq(resulting, expected, "exact weighted average");
    }

    /// @dev Extensions never change the cap, at any parameter setting.
    function testFuzz_extensionsNeverChangeTheCap(uint16 capAtLock, uint16 capLater, uint16 weeksToLock) public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(bound(capAtLock, 0, 5000));
        uint256 tokenId = _lock(alice, 1000 ether, bound(weeksToLock, 1, 50) * WEEK);
        uint256 capBefore = escrow.locked(tokenId).penaltyCapBps;

        vm.prank(timelock);
        escrow.setMaxPenaltyBps(bound(capLater, 0, 5000));

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
