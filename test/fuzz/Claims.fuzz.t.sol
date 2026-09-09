// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";

contract ClaimsFuzzTest is Base {
    /// @dev A backlog claimed across arbitrary page sizes must total exactly the same as one
    ///      claimed in as few calls as possible: no epoch lost, none double-paid.
    function testFuzz_pagedClaimsSumToTheSameTotal(uint8 epochs, uint8 pages) public {
        uint256 n = bound(epochs, 1, 80);
        uint256 pageCount = bound(pages, 1, 12);

        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 104 weeks);
        uint256 b = _lock(bob, 100_000 ether, 104 weeks);
        _nextEpoch();

        for (uint256 i; i < n; ++i) {
            _notifyExact(address(usdc), 100e6);
            _nextEpoch();
        }

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256 total;
        for (uint256 i; i < pageCount + 4; ++i) {
            vm.prank(alice);
            (uint256[] memory amounts,) = distributor.claim(a, tokens);
            total += amounts[0];
        }

        uint256 bobTotal;
        for (uint256 i; i < 8; ++i) {
            vm.prank(bob);
            (uint256[] memory amounts,) = distributor.claim(b, tokens);
            bobTotal += amounts[0];
        }

        assertApproxEqAbs(total, bobTotal, 2, "page size never changes the payout");
        assertLe(total + bobTotal, n * 100e6, "never over-distribute");
        assertApproxEqAbs(total + bobTotal, n * 100e6, n + 2, "at most rounding dust remains");
    }

    /// @dev The sum of all claims can never exceed the sum of all notifications, whatever the
    ///      mix of lock sizes and durations.
    function testFuzz_claimsNeverExceedNotifications(
        uint128 amountA,
        uint128 amountB,
        uint16 weeksA,
        uint16 weeksB,
        uint8 epochs,
        uint64 revenuePerEpoch
    ) public {
        amountA = uint128(bound(amountA, 1000 ether, 1_000_000 ether));
        amountB = uint128(bound(amountB, 1000 ether, 1_000_000 ether));
        uint256 n = bound(epochs, 1, 40);
        uint256 rev = bound(revenuePerEpoch, 1e6, 1_000_000e6);

        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, amountA, bound(weeksA, 1, 104) * WEEK);
        uint256 b = _lock(bob, amountB, bound(weeksB, 1, 104) * WEEK);
        _nextEpoch();

        for (uint256 i; i < n; ++i) {
            _notifyExact(address(usdc), rev);
            _nextEpoch();
        }

        for (uint256 i; i < 3; ++i) {
            _claim(alice, a, address(usdc));
            _claim(bob, b, address(usdc));
        }

        assertLe(distributor.totalClaimed(address(usdc)), distributor.totalNotified(address(usdc)));
        assertEq(
            usdc.balanceOf(address(distributor)),
            distributor.accounted(address(usdc)),
            "held balance always equals accounted value"
        );
        assertEq(
            distributor.accounted(address(usdc)),
            distributor.totalNotified(address(usdc)) - distributor.totalClaimed(address(usdc))
        );
    }

    /// @dev Re-claiming after an arbitrary delay is always idempotent.
    function testFuzz_repeatedClaimsAreIdempotent(uint8 epochs, uint32 delay) public {
        uint256 n = bound(epochs, 1, 20);

        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 104 weeks);
        _nextEpoch();

        for (uint256 i; i < n; ++i) {
            _notifyExact(address(usdc), 500e6);
            _nextEpoch();
        }

        uint256 first = _claim(alice, a, address(usdc));
        vm.warp(block.timestamp + bound(delay, 0, 10 weeks));
        assertEq(_claim(alice, a, address(usdc)), 0, "no revenue means no payout, however long we wait");
        assertEq(first, n * 500e6);
    }

    /// @dev An exited position never draws from an epoch it was excluded from.
    function testFuzz_exitedPositionNeverClaimsPastItsExitEpoch(uint8 epochsBefore, uint8 epochsAfter) public {
        uint256 before = bound(epochsBefore, 1, 20);
        uint256 afterCount = bound(epochsAfter, 1, 20);

        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 104 weeks);
        uint256 b = _lock(bob, 100_000 ether, 104 weeks);
        _nextEpoch();

        for (uint256 i; i < before; ++i) {
            _notifyExact(address(usdc), 1000e6);
            _nextEpoch();
        }

        uint256 exitEpoch = _currentEpoch();
        vm.prank(alice);
        escrow.emergencyExit(a);

        for (uint256 i; i < afterCount; ++i) {
            _notifyExact(address(usdc), 1000e6);
            _nextEpoch();
        }

        _claim(alice, a, address(usdc));
        assertLe(distributor.claimCursor(a, address(usdc)), exitEpoch, "the cursor stops at the exit epoch");

        // And bob, who stayed, can always claim.
        assertGt(_claim(bob, b, address(usdc)), 0);
    }
}
