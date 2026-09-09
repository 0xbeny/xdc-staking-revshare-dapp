// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeDistributorForfeitureTest is Base {
    uint256 internal a;
    uint256 internal b;

    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));
        a = _lock(alice, 100_000 ether, 104 weeks);
        b = _lock(bob, 100_000 ether, 104 weeks);
        _nextEpoch();
    }

    /// @dev The penalty's locker share streams to remaining lockers from the next epoch on.
    function test_penaltyStreamsToRemainingLockersFromTheNextEpoch() public {
        uint256 exitEpoch = _currentEpoch();

        vm.prank(alice);
        escrow.emergencyExit(a);

        uint256 credited = distributor.syncForfeiture(address(wxdc));
        assertGt(credited, 0);
        assertEq(distributor.epochRevenue(address(wxdc), exitEpoch), 0, "never the epoch it exited in");
        assertEq(distributor.epochRevenue(address(wxdc), exitEpoch + 1), credited, "the first excluding epoch");

        _nextEpoch();
        _nextEpoch();
        assertEq(_claim(bob, b, address(wxdc)), credited, "the remaining locker takes it all");
    }

    /// @dev An exiting position can never receive its own forfeiture.
    function test_exitingPositionNeverReceivesItsOwnForfeiture() public {
        vm.prank(alice);
        escrow.emergencyExit(a);
        distributor.syncForfeiture(address(wxdc));

        _warpEpochs(3);
        assertEq(_claim(alice, a, address(wxdc)), 0, "the exited position gets nothing from the bucket");
    }

    /// @dev The in-progress epoch's share is forfeited; already-finalized rewards pay in full.
    function test_finalizedRewardsPayInFullAtExitButTheOpenEpochIsForfeited() public {
        // Epoch n-1: revenue that finalizes before the exit.
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        // Epoch n: revenue accrues, then alice exits mid-epoch.
        _notifyExact(address(usdc), 1000e6);
        uint256 exitEpoch = _currentEpoch();
        vm.prank(alice);
        escrow.emergencyExit(a);

        _nextEpoch();
        distributor.settle(address(usdc), 52);

        // Alice keeps her finalized epoch...
        assertApproxEqAbs(_claim(alice, a, address(usdc)), 500e6, 2, "finalized epoch pays in full");
        // ...and forfeits the open one.
        assertEq(distributor.exitForfeitMovements(address(usdc)), 500e6);

        _nextEpoch();
        // Bob gets his own half of epoch n plus alice's forfeited half.
        assertApproxEqAbs(_claim(bob, b, address(usdc)), 500e6 + 500e6 + 500e6, 4);
    }

    /// @dev Denominators are never modified post-snapshot.
    function test_denominatorIsUnchangedByAnExit() public {
        uint256 epoch = _currentEpoch();
        uint256 supplyBefore = escrow.totalSupplyAtWeek(_epochStart(epoch));

        _notifyExact(address(usdc), 1000e6);
        vm.prank(alice);
        escrow.emergencyExit(a);

        assertEq(escrow.totalSupplyAtWeek(_epochStart(epoch)), supplyBefore, "the snapshot is immutable");

        _nextEpoch();
        distributor.settle(address(usdc), 52);
        assertEq(distributor.epochRevenue(address(usdc), epoch), 1000e6, "the epoch's numerator is untouched too");
    }

    function test_syncForfeitureIsIdempotent() public {
        vm.prank(alice);
        escrow.emergencyExit(a);

        uint256 first = distributor.syncForfeiture(address(wxdc));
        assertGt(first, 0);
        assertEq(distributor.syncForfeiture(address(wxdc)), 0, "a second sync moves nothing");
    }

    /// @dev Self-healing: every claim syncs before it accrues, so a missed keeper sync only
    ///      delays the bucket — it can never strand it. The delayed credit lands in the epoch
    ///      after the sync, never retroactively in the exit epoch (§3.2 #8 applied to penalties).
    function test_missedSyncIsRecoveredOnTheNextClaim() public {
        vm.prank(alice);
        escrow.emergencyExit(a);

        _warpEpochs(4);
        // No explicit syncForfeiture call anywhere: the claim's own sync does the work, and
        // credits the *following* epoch, so this first call still pays nothing.
        assertEq(_claim(bob, b, address(wxdc)), 0);
        uint256 syncedInto = _currentEpoch() + 1;
        assertGt(distributor.epochRevenue(address(wxdc), syncedInto), 0, "credited, not stranded");

        _warpEpochs(2);
        assertGt(_claim(bob, b, address(wxdc)), 0, "recovered in full on the next round");
    }

    /// @dev A delayed sync never loses value; it only shifts which epoch's lockers receive it.
    function test_delayedSyncCreditsTheEpochAfterTheSyncNotTheExitEpoch() public {
        uint256 exitEpoch = _currentEpoch();
        vm.prank(alice);
        escrow.emergencyExit(a);

        _warpEpochs(5);
        uint256 credited = distributor.syncForfeiture(address(wxdc));
        assertGt(credited, 0);
        assertEq(distributor.epochRevenue(address(wxdc), exitEpoch + 1), 0, "not backdated");
        assertEq(distributor.epochRevenue(address(wxdc), _currentEpoch() + 1), credited);
    }

    function test_conservationHoldsAcrossExitsAndCarryForward() public {
        for (uint256 i; i < 3; ++i) {
            _notifyExact(address(usdc), 1000e6);
            _nextEpoch();
        }
        vm.prank(alice);
        escrow.emergencyExit(a);
        _warpEpochs(2);

        vm.prank(bob);
        escrow.emergencyExit(b);
        _warpEpochs(2);

        distributor.settle(address(usdc), 52);
        distributor.settle(address(wxdc), 52);
        _claim(alice, a, address(usdc));
        _claim(bob, b, address(usdc));
        _claim(bob, b, address(wxdc));

        address[2] memory tokens = [address(usdc), address(wxdc)];
        for (uint256 i; i < 2; ++i) {
            address token = tokens[i];
            assertEq(
                distributor.accounted(token),
                distributor.totalNotified(token) - distributor.totalClaimed(token),
                "accounted == notified - claimed"
            );
            assertGe(
                _balance(token, address(distributor)), distributor.accounted(token), "balance covers every obligation"
            );
        }
    }

    /// @dev Regression (found by the invariant fuzzer): a position created and exited inside the
    ///      same block as an epoch boundary is absent from that epoch's snapshot on both sides of
    ///      the fraction. Recording its pre-exit weight as forfeited would let the forfeited
    ///      slice exceed the epoch's whole pot.
    function test_sameBlockCreateAndExitForfeitsNothingAndCannotExceedThePot() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 epoch = _currentEpoch();

        uint256 flash = _lock(carol, 400_000 ether, 104 weeks);
        vm.prank(carol);
        escrow.emergencyExit(flash);

        uint256 supply = escrow.totalSupplyAtWeek(_epochStart(epoch));
        assertLe(escrow.exitedWeightByEpoch(epoch), supply, "forfeited weight can never exceed the snapshot");
        assertEq(escrow.exitedWeightByEpoch(epoch), 0, "absent from the snapshot entirely");

        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();
        distributor.settle(address(usdc), 52);

        assertEq(distributor.epochRevenue(address(usdc), epoch + 1), 0, "nothing moved forward");
        assertEq(distributor.exitForfeitMovements(address(usdc)), 0);
    }

    /// @dev The general form: the recorded exited weight of an epoch never exceeds its supply.
    function test_exitedWeightNeverExceedsTheEpochSupply() public {
        uint256 epoch = _currentEpoch();
        vm.prank(alice);
        escrow.emergencyExit(a);
        vm.prank(bob);
        escrow.emergencyExit(b);

        assertLe(escrow.exitedWeightByEpoch(epoch), escrow.totalSupplyAtWeek(_epochStart(epoch)));
    }

    function _balance(address token, address who) internal view returns (uint256) {
        return IERC20(token).balanceOf(who);
    }
}
