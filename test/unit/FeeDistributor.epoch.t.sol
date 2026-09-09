// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {Base} from "../Base.t.sol";

contract FeeDistributorEpochTest is Base {
    /// @dev Frozen epoch rule (§3.3): revenue received during `n` is allocated by weights
    ///      snapshotted at the start of `n`, and is claimable only after `n` closes.
    function test_revenueIsAllocatedByStartOfEpochSnapshot() public {
        vm.warp(_epochStart(_currentEpoch() + 1)); // align
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);

        _nextEpoch(); // alice is now in the snapshot of this epoch
        uint256 epoch = _currentEpoch();
        _notifyExact(address(usdc), 10_000e6);
        assertEq(distributor.epochRevenue(address(usdc), epoch), 10_000e6);

        // Not claimable while the epoch is open.
        (uint256 pending,) = distributor.claimable(a, address(usdc));
        assertEq(pending, 0, "an open epoch is never claimable");

        _nextEpoch();
        assertEq(_claim(alice, a, address(usdc)), 10_000e6, "sole locker takes the whole pot");
    }

    /// @dev A position created mid-epoch `n` first participates in `n+1`.
    function test_midEpochLockDoesNotEarnTheEpochItJoined() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();

        // Bob joins mid-epoch, after this epoch's snapshot was taken.
        uint256 b = _lock(bob, 100_000 ether, 52 weeks);
        _notifyExact(address(usdc), 10_000e6);
        _nextEpoch();

        assertEq(_claim(alice, a, address(usdc)), 10_000e6, "alice takes the whole epoch");
        assertEq(_claim(bob, b, address(usdc)), 0, "bob was not in the snapshot");
    }

    /// @dev Attribution is frozen to receipt time (§3.2 #8): a skim landing 10 seconds into
    ///      epoch n+1 is epoch n+1 revenue, period.
    function test_lateSkimIsNextEpochRevenueNotRetroactive() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        uint256 epochN = _currentEpoch();

        // Boundary crosses, then the keeper sweeps 10 seconds late.
        vm.warp(_epochStart(epochN + 1) + 10);
        _notifyExact(address(usdc), 10_000e6);

        assertEq(distributor.epochRevenue(address(usdc), epochN), 0, "never retroactive");
        assertEq(distributor.epochRevenue(address(usdc), epochN + 1), 10_000e6);
    }

    function test_proRataSplitAcrossTwoPositions() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 300_000 ether, 52 weeks);
        uint256 b = _lock(bob, 100_000 ether, 52 weeks);
        _nextEpoch();

        _notifyExact(address(usdc), 4000e6);
        _nextEpoch();

        uint256 gotAlice = _claim(alice, a, address(usdc));
        uint256 gotBob = _claim(bob, b, address(usdc));
        assertApproxEqAbs(gotAlice, 3000e6, 1);
        assertApproxEqAbs(gotBob, 1000e6, 1);
        assertLe(gotAlice + gotBob, 4000e6, "never over-distribute");
    }

    /// @dev Longer locks earn more per unit of principal — time-weighting, not size-weighting.
    function test_longerLockEarnsMoreForTheSamePrincipal() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 long_ = _lock(alice, 100_000 ether, 104 weeks);
        uint256 short_ = _lock(bob, 100_000 ether, 4 weeks);
        _nextEpoch();

        _notifyExact(address(usdc), 10_000e6);
        _nextEpoch();

        assertGt(_claim(alice, long_, address(usdc)), _claim(bob, short_, address(usdc)) * 20);
    }

    /*//////////////////////////////////////////////////////////////
                      ZERO-SUPPLY CARRY-FORWARD (#12)
    //////////////////////////////////////////////////////////////*/

    function test_zeroSupplyEpochCarriesRevenueForward() public {
        vm.warp(_epochStart(_currentEpoch() + 1));

        // No positions exist at all: this epoch's snapshot supply is zero.
        uint256 emptyEpoch = _currentEpoch();
        _notifyExact(address(usdc), 5000e6);
        assertEq(escrow.totalSupplyAtWeek(_epochStart(emptyEpoch)), 0);

        _nextEpoch();
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        _nextEpoch();

        distributor.settle(address(usdc), 52);
        assertEq(distributor.epochRevenue(address(usdc), emptyEpoch), 0, "the empty epoch was drained");
        // Two hops: the empty creation epoch and the epoch alice joined mid-way.
        assertEq(distributor.carryForwardMovements(address(usdc)), 10_000e6);
        assertEq(distributor.totalNotified(address(usdc)), 5000e6, "carry-forward moves value, it never mints it");

        assertEq(_claim(alice, a, address(usdc)), 5000e6, "nothing stranded, nothing swept to treasury");
    }

    function test_carryForwardChainsAcrossConsecutiveEmptyEpochs() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();
        _notifyExact(address(usdc), 2000e6);
        _nextEpoch();
        _notifyExact(address(usdc), 3000e6);
        _nextEpoch();

        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        _nextEpoch();

        distributor.settle(address(usdc), 52);
        assertEq(_claim(alice, a, address(usdc)), 6000e6, "all three empty epochs chained forward");
    }

    function test_settleNeverDividesByZero() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        _notifyExact(address(usdc), 1000e6);
        _warpEpochs(10);
        distributor.settle(address(usdc), 52);
        assertEq(distributor.settledEpoch(address(usdc)), _currentEpoch());
    }

    /*//////////////////////////////////////////////////////////////
                                ADAPTERS
    //////////////////////////////////////////////////////////////*/

    function test_onlyRegisteredActiveAdaptersCanNotify() public {
        vm.startPrank(alice);
        usdc.approve(address(distributor), 1000e6);
        vm.expectRevert(FeeDistributor.NotAnActiveAdapter.selector);
        distributor.notifyRevenue(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(timelock);
        registry.deactivateAdapter(address(pusher));

        vm.startPrank(dapp);
        usdc.approve(address(pusher), 1000e6);
        vm.expectRevert(FeeDistributor.NotAnActiveAdapter.selector);
        pusher.commitRevenue(address(usdc), 1000e6);
        vm.stopPrank();
    }

    function test_unknownRewardTokenIsRejected() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        vm.expectRevert(FeeDistributor.UnknownRewardToken.selector);
        distributor.syncForfeiture(address(0xBEEF));
    }

    function test_pausedDistributorRejectsRevenueAndClaims() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        vm.prank(guardian);
        distributor.pause();

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vm.prank(alice);
        vm.expectRevert();
        distributor.claim(a, tokens);

        vm.prank(timelock);
        distributor.unpause();
        assertEq(_claim(alice, a, address(usdc)), 1000e6);
    }

    function test_lifetimeContributionIsRecorded() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        assertEq(registry.lifetimeContribution(address(pusher), address(usdc)), 1000e6);
    }
}
