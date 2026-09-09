// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract VotingEscrowWeightTest is Base {
    /// @dev Spec §3.1 #1: a nominal 104-week lock whose aligned unlock lands at ~104.9 weeks
    ///      earns exactly 1.0x weight — never more.
    function test_clamp_maxLockNeverExceedsOnePointZeroWeight() public {
        // Start deliberately mid-week so the round-up overshoots MAX_LOCK.
        vm.warp(_epochStart(_currentEpoch()) + 3 days + 7 hours);

        uint256 amount = 100_000 ether;
        uint256 tokenId = _lock(alice, amount, MAX_LOCK);

        VotingEscrow.Lock memory lock = escrow.locked(tokenId);
        assertGt(lock.end - block.timestamp, MAX_LOCK, "setup: unlock must overshoot MAX_LOCK");

        uint256 weight = escrow.balanceOfNFT(tokenId);
        // forge-lint: disable-next-line(divide-before-multiply)
        assertEq(weight, (amount / MAX_LOCK) * MAX_LOCK, "weight is clamped at exactly 1.0x");
        assertLe(weight, amount, "invariant: weight <= principal");
    }

    function test_clamp_weightStaysFlatThenDecaysLinearly() public {
        vm.warp(_epochStart(_currentEpoch()) + 3 days);
        uint256 tokenId = _lock(alice, 100_000 ether, MAX_LOCK);
        uint256 end = escrow.locked(tokenId).end;
        uint256 activation = end - MAX_LOCK;

        uint256 flat = escrow.balanceOfNFT(tokenId);

        // Flat while the clamp binds.
        vm.warp(activation - 1);
        assertEq(escrow.balanceOfNFT(tokenId), flat, "clamped region must be flat");
        vm.warp(activation);
        assertEq(escrow.balanceOfNFT(tokenId), flat, "clamp releases continuously");

        // Then linear.
        vm.warp(activation + MAX_LOCK / 2);
        assertApproxEqRel(escrow.balanceOfNFT(tokenId), flat / 2, 1e12, "half-life at half of MAX_LOCK");

        vm.warp(end);
        assertEq(escrow.balanceOfNFT(tokenId), 0, "zero at expiry");
    }

    function test_weightNeverExceedsPrincipal() public {
        uint256[5] memory durations = [MIN_LOCK, 4 weeks, 52 weeks, 103 weeks, MAX_LOCK];
        for (uint256 i; i < durations.length; ++i) {
            uint256 tokenId = _lock(alice, 1000 ether, durations[i]);
            assertLe(escrow.balanceOfNFT(tokenId), 1000 ether);
        }
    }

    /// @dev The critical accounting property: the global aggregate equals the exact sum of the
    ///      per-position weights, at every point in time, including inside the clamped region.
    function test_totalSupplyEqualsSumOfPositionsAcrossTime() public {
        vm.warp(_epochStart(_currentEpoch()) + 2 days + 5 hours);

        uint256[] memory ids = new uint256[](4);
        ids[0] = _lock(alice, 100_000 ether, MAX_LOCK); // clamped at creation
        ids[1] = _lock(bob, 50_000 ether, 52 weeks);
        ids[2] = _lock(carol, 12_345 ether, MIN_LOCK);
        vm.warp(block.timestamp + 3 weeks + 11 hours);
        ids[3] = _lock(alice, 7777 ether, 103 weeks);

        for (uint256 step; step < 40; ++step) {
            vm.warp(block.timestamp + 3 weeks + 1 days);
            escrow.checkpoint();

            uint256 sum;
            for (uint256 i; i < ids.length; ++i) {
                sum += escrow.balanceOfNFT(ids[i]);
            }
            assertEq(escrow.totalSupply(), sum, "global bias must equal the sum of positions");
        }
    }

    function test_totalSupplyAtWeek_matchesHistoricalSum() public {
        vm.warp(_epochStart(_currentEpoch()) + 1 days);
        uint256 a = _lock(alice, 100_000 ether, MAX_LOCK);
        uint256 b = _lock(bob, 40_000 ether, 30 weeks);

        uint256 startEpoch = _currentEpoch();
        _warpEpochs(40);
        escrow.checkpoint();

        for (uint256 e = startEpoch; e < startEpoch + 40; ++e) {
            uint256 ts = _epochStart(e);
            uint256 expected = escrow.balanceOfNFTAt(a, ts) + escrow.balanceOfNFTAt(b, ts);
            assertEq(escrow.totalSupplyAtWeek(ts), expected, "week snapshot must match position sum");
        }
    }

    function test_balanceOfNFTAt_readsHistoricalStateNotCurrent() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        uint256 t0 = block.timestamp;
        uint256 w0 = escrow.balanceOfNFT(tokenId);

        vm.warp(t0 + 10 weeks);
        vm.startPrank(alice);
        wxdc.approve(address(escrow), 100_000 ether);
        escrow.increaseAmount(tokenId, 100_000 ether);
        vm.stopPrank();

        assertEq(escrow.balanceOfNFTAt(tokenId, t0), w0, "past weight must be unaffected by a later increase");
        assertGt(escrow.balanceOfNFT(tokenId), w0);
    }

    function test_balanceOfNFTAt_isZeroBeforeCreationAndAfterExpiry() public {
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 1 weeks);
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        uint256 end = escrow.locked(tokenId).end;

        assertEq(escrow.balanceOfNFTAt(tokenId, t0), 0);
        assertEq(escrow.balanceOfNFTAt(tokenId, end), 0);
        assertEq(escrow.balanceOfNFTAt(tokenId, end + 52 weeks), 0);
    }

    function test_extendingRestoresWeight() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        uint256 initial = escrow.balanceOfNFT(tokenId);

        vm.warp(block.timestamp + 26 weeks);
        assertLt(escrow.balanceOfNFT(tokenId), initial);

        vm.prank(alice);
        escrow.keepAtMaxLock(tokenId);
        // forge-lint: disable-next-line(divide-before-multiply)
        assertEq(escrow.balanceOfNFT(tokenId), (100_000 ether / MAX_LOCK) * MAX_LOCK);
    }

    function test_checkpointIsIdempotentWithinABlock() public {
        _lock(alice, 100_000 ether, 52 weeks);
        uint256 epochBefore = escrow.epoch();
        escrow.checkpoint();
        escrow.checkpoint();
        assertEq(escrow.epoch(), epochBefore);
    }

    function test_supplyDropsToZeroWhenEverythingExpires() public {
        _lock(alice, 100_000 ether, 4 weeks);
        _lock(bob, 50_000 ether, 8 weeks);

        vm.warp(block.timestamp + 20 weeks);
        escrow.checkpoint();
        assertEq(escrow.totalSupply(), 0);
    }

    function test_dustAmountBelowMaxLockHasZeroWeight() public {
        // MAX_LOCK is ~6.29e7 seconds; anything below that truncates to a zero slope.
        uint256 tokenId = _lock(alice, MAX_LOCK - 1, MAX_LOCK);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.totalSupply(), 0);
    }

    /// @dev The pure formula, exercised directly: truncated slope, clamp, expiry, dust.
    function test_weightAt_pureFormula() public view {
        uint256 amount = 104 ether;
        uint256 slope = amount / MAX_LOCK;
        uint256 end = 1000 * WEEK;

        assertEq(escrow.weightAt(amount, end, end - MAX_LOCK), slope * MAX_LOCK, "full weight at exactly MAX_LOCK");
        assertEq(escrow.weightAt(amount, end, end - MAX_LOCK - 3 days), slope * MAX_LOCK, "clamped beyond it");
        assertEq(escrow.weightAt(amount, end, end - 52 weeks), slope * 52 weeks, "linear inside it");
        assertEq(escrow.weightAt(amount, end, end), 0, "zero at expiry");
        assertEq(escrow.weightAt(amount, end, end + 1), 0, "zero after expiry");
        assertEq(escrow.weightAt(0, end, end - 1), 0, "zero amount");
        assertEq(escrow.weightAt(MAX_LOCK - 1, end, end - 1), 0, "dust below one slope unit");
    }

    function test_userPointHistory_recordsEveryMutationAndOverwritesWithinABlock() public {
        uint256 tokenId = _lock(alice, 100 ether, 52 weeks);
        assertEq(escrow.userPointHistoryLength(tokenId), 1);

        // Same block: the point is overwritten, not appended.
        vm.startPrank(alice);
        wxdc.approve(address(escrow), 100 ether);
        escrow.increaseAmount(tokenId, 50 ether);
        assertEq(escrow.userPointHistoryLength(tokenId), 1, "same-timestamp mutations overwrite");
        assertEq(escrow.userPointAt(tokenId, 0).amount, 150 ether);

        // Later block: appended.
        vm.warp(block.timestamp + 1 days);
        escrow.increaseAmount(tokenId, 50 ether);
        vm.stopPrank();
        assertEq(escrow.userPointHistoryLength(tokenId), 2);
        assertEq(escrow.userPointAt(tokenId, 1).amount, 200 ether);
        assertEq(escrow.userPointAt(tokenId, 1).ts, block.timestamp);
        assertEq(escrow.userPointAt(tokenId, 0).amount, 150 ether, "history is immutable");
    }
}
