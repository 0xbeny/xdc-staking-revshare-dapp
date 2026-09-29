// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";

/// @dev M-6: a zero principal penalty must not let a one-week lock collect that week's fees.
contract FeeDistributorVestingTest is Base {
    function test_earlyExitForfeitsUnvestedYieldEvenWhenPenaltyIsZero() public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(0);

        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 aliceId = _lock(alice, 1_000_000 ether, 104 weeks);
        uint256 bobId = _lock(bob, 1_000_000 ether, 104 weeks);
        _nextEpoch();

        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        vm.prank(alice);
        escrow.emergencyExit(aliceId);
        assertEq(usdc.balanceOf(alice), 100_000_000e6, "exit does not pay the unvested week");

        _vest();
        assertEq(_claim(alice, aliceId, address(usdc)), 0, "early exit never collects the unvested week");
        uint256 bobGot = _claim(bob, bobId, address(usdc));
        // The forfeited half is credited into the epoch after this claim, so it vests one
        // window later.
        _warpEpochs(distributor.VESTING_EPOCHS() + 1);
        bobGot += _claim(bob, bobId, address(usdc));
        assertApproxEqAbs(bobGot, 1000e6, 2, "the stayer receives both halves");
    }

    function test_aPositionThatStaysClaimsAfterTheVest() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 id = _lock(alice, 100_000 ether, 104 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vm.prank(alice);
        (uint256[] memory tooSoon,) = distributor.claim(id, tokens);
        assertEq(tooSoon[0], 0, "the week is not claimable yet");

        _vest();
        assertEq(_claim(alice, id, address(usdc)), 1000e6);
    }

    /// @dev A week becomes claimable in epoch `e + 8`. Exiting in that same epoch must not
    ///      forfeit it again: the position can already have been paid.
    function test_exitInTheVestEpochDoesNotReplayAPaidWeek() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 aliceId = _lock(alice, 100_000 ether, 104 weeks);
        uint256 bobId = _lock(bob, 100_000 ether, 104 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();
        // One epoch was already closed above, so this lands on `earned + VESTING_EPOCHS`.
        _warpEpochs(distributor.VESTING_EPOCHS() - 1);

        assertEq(_claimRaw(alice, aliceId), 500e6, "the week has vested");
        vm.prank(alice);
        escrow.emergencyExit(aliceId);
        distributor.settle(address(usdc), 52);

        assertEq(distributor.exitForfeitMovements(address(usdc)), 0, "a paid week is not moved again");
        assertEq(_claimRaw(bob, bobId), 500e6, "the stayer keeps only his own half");
        assertApproxEqAbs(usdc.balanceOf(address(distributor)), 0, 2, "nothing left over");
    }

    /// @dev Forfeiture is not limited to the last eight epochs. A late settle still pays stayers.
    function test_lateSettleStillForwardsUnvestedYield() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 aliceId = _lock(alice, 100_000 ether, 104 weeks);
        uint256 bobId = _lock(bob, 100_000 ether, 104 weeks);
        _nextEpoch();

        for (uint256 i; i < 9; ++i) {
            _notifyExact(address(usdc), 1000e6);
            _nextEpoch();
        }
        vm.prank(alice);
        escrow.emergencyExit(aliceId);

        _warpEpochs(30);
        uint256 aliceGot;
        uint256 bobGot;
        for (uint256 i; i < 4; ++i) {
            aliceGot += _claimRaw(alice, aliceId);
            bobGot += _claimRaw(bob, bobId);
        }
        // The forward lands in the epoch after that settle, so it vests one window later.
        _warpEpochs(distributor.VESTING_EPOCHS() + 1);
        for (uint256 i; i < 4; ++i) {
            aliceGot += _claimRaw(alice, aliceId);
            bobGot += _claimRaw(bob, bobId);
        }

        assertApproxEqAbs(aliceGot + bobGot, 9000e6, 20, "every notified dollar reaches a locker");
        assertApproxEqAbs(usdc.balanceOf(address(distributor)), 0, 20, "nothing stranded");
        assertLt(aliceGot, bobGot, "the early exit keeps strictly less");
    }

    function _claimRaw(address who, uint256 tokenId) internal returns (uint256) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vm.prank(who);
        (uint256[] memory amounts,) = distributor.claim(tokenId, tokens);
        return amounts[0];
    }
}
