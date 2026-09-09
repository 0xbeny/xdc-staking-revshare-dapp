// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";

contract WeightFuzzTest is Base {
    /// @dev Invariant: `weight <= principal`, for every amount, duration and observation time.
    function testFuzz_weightNeverExceedsPrincipal(uint128 amount, uint16 weeksToLock, uint32 skipSeconds) public {
        amount = uint128(bound(amount, 1 ether, 1_000_000 ether));
        uint256 duration = bound(weeksToLock, 1, 104) * WEEK;
        uint256 tokenId = _lock(alice, amount, duration);

        vm.warp(block.timestamp + bound(skipSeconds, 0, 130 weeks));
        assertLe(escrow.balanceOfNFT(tokenId), amount);
    }

    /// @dev Invariant: `effectiveTime <= MAX_LOCK` however the round-up lands.
    function testFuzz_effectiveTimeIsAlwaysClamped(uint128 amount, uint16 weeksToLock, uint32 offset) public {
        amount = uint128(bound(amount, 1 ether, 1_000_000 ether));
        // Start anywhere inside a week so the round-up can overshoot.
        vm.warp(_epochStart(_currentEpoch()) + bound(offset, 0, WEEK - 1));
        uint256 duration = bound(weeksToLock, 1, 104) * WEEK;

        uint256 tokenId = _lock(alice, amount, duration);
        assertLe(escrow.effectiveTime(tokenId), MAX_LOCK);
    }

    /// @dev Invariant: the effective lock is never shorter than MIN_LOCK at creation.
    function testFuzz_effectiveLockIsAtLeastMinLock(uint128 amount, uint16 weeksToLock, uint32 offset) public {
        amount = uint128(bound(amount, 1 ether, 1_000_000 ether));
        vm.warp(_epochStart(_currentEpoch()) + bound(offset, 0, WEEK - 1));
        uint256 duration = bound(weeksToLock, 1, 104) * WEEK;

        uint256 tokenId = _lock(alice, amount, duration);
        assertGe(escrow.locked(tokenId).end - block.timestamp, MIN_LOCK);
        assertEq(escrow.locked(tokenId).end % WEEK, 0);
    }

    /// @dev The global aggregate equals the exact sum of positions, for arbitrary lock mixes.
    function testFuzz_totalSupplyEqualsSumOfPositions(
        uint128 amountA,
        uint128 amountB,
        uint16 weeksA,
        uint16 weeksB,
        uint32 offset,
        uint32 skipSeconds
    ) public {
        amountA = uint128(bound(amountA, 1 ether, 1_000_000 ether));
        amountB = uint128(bound(amountB, 1 ether, 1_000_000 ether));
        vm.warp(_epochStart(_currentEpoch()) + bound(offset, 0, WEEK - 1));

        uint256 a = _lock(alice, amountA, bound(weeksA, 1, 104) * WEEK);
        uint256 b = _lock(bob, amountB, bound(weeksB, 1, 104) * WEEK);

        vm.warp(block.timestamp + bound(skipSeconds, 0, 120 weeks));
        escrow.checkpoint();

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(a) + escrow.balanceOfNFT(b));
    }

    /// @dev Weight is monotonically non-increasing in time for an untouched lock.
    function testFuzz_weightDecaysMonotonically(uint128 amount, uint16 weeksToLock, uint32 step) public {
        amount = uint128(bound(amount, 1000 ether, 1_000_000 ether));
        uint256 tokenId = _lock(alice, amount, bound(weeksToLock, 1, 104) * WEEK);
        uint256 stepSize = bound(step, 1 hours, 8 weeks);

        uint256 previous = type(uint256).max;
        for (uint256 i; i < 20; ++i) {
            uint256 current = escrow.balanceOfNFT(tokenId);
            assertLe(current, previous);
            previous = current;
            vm.warp(block.timestamp + stepSize);
        }
    }

    /// @dev Extending never reduces weight; increasing the amount never reduces it either.
    function testFuzz_extendingAndIncreasingNeverReduceWeight(uint128 amount, uint16 weeksToLock, uint128 add) public {
        amount = uint128(bound(amount, 1000 ether, 1_000_000 ether));
        add = uint128(bound(add, 1 ether, 1_000_000 ether));
        uint256 duration = bound(weeksToLock, 1, 100) * WEEK;
        uint256 tokenId = _lock(alice, amount, duration);

        uint256 before = escrow.balanceOfNFT(tokenId);
        vm.startPrank(alice);
        wxdc.approve(address(escrow), add);
        escrow.increaseAmount(tokenId, add);
        uint256 afterIncrease = escrow.balanceOfNFT(tokenId);
        escrow.keepAtMaxLock(tokenId);
        vm.stopPrank();

        assertGe(afterIncrease, before);
        assertGe(escrow.balanceOfNFT(tokenId), afterIncrease);
    }
}
