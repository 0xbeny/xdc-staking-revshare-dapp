// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {PushAdapter} from "../../src/adapters/PushAdapter.sol";
import {IRevenueRegistry} from "../../src/interfaces/IRevenueRegistry.sol";
import {Base} from "../Base.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract FeeDistributorClaimTest is Base {
    uint256 internal a;

    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));
        a = _lock(alice, 100_000 ether, 104 weeks);
        _nextEpoch();
    }

    function test_claimIsBoundedAndReportsRemaining() public {
        // 60 epochs of revenue against a MAX_EPOCHS_PER_CLAIM of 52.
        vm.prank(alice);
        escrow.setAutoExtend(a, true);
        for (uint256 i; i < 60; ++i) {
            _notifyExact(address(usdc), 100e6);
            _intoKeeperWindow();
            vm.prank(alice);
            escrow.keepAtMaxLock(a);
            _nextEpoch();
        }
        _vest();

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(alice);
        (uint256[] memory first, uint256 remaining) = distributor.claim(a, tokens);
        assertGt(remaining, 0, "more epochs remain");
        assertGe(remaining, 8, "unsettled closed epochs past the 52-bound still signal a backlog");
        assertGt(first[0], 0);
        // The first page is bounded by MAX_EPOCHS_PER_CLAIM on both the settle walk and the
        // claim walk, so it can never cover all 60 epochs in one call.
        assertLe(first[0], 52 * 100e6, "a single call never exceeds the per-call bound");
        assertLt(first[0], 60 * 100e6, "one call cannot drain a 60-epoch backlog");

        vm.prank(alice);
        (uint256[] memory second, uint256 remaining2) = distributor.claim(a, tokens);
        assertEq(remaining2, 0, "the cursor caught up");
        assertEq(first[0] + second[0], 60 * 100e6, "no epoch lost or double-paid across pages");

        // Mid-epoch after a full catch-up: open epoch must not keep remaining sticky.
        (uint256 viewAmount, uint256 viewRemaining) = distributor.claimable(a, address(usdc));
        assertEq(viewAmount, 0);
        assertEq(viewRemaining, 0);
    }

    function test_repeatedClaimsAreIdempotent() public {
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();
        _vest();

        assertEq(_claim(alice, a, address(usdc)), 1000e6);
        assertEq(_claim(alice, a, address(usdc)), 0, "a second claim pays nothing");
        assertEq(_claim(alice, a, address(usdc)), 0);
    }

    function test_cursorIsMonotonic() public {
        for (uint256 i; i < 5; ++i) {
            _notifyExact(address(usdc), 100e6);
            _nextEpoch();
        }
        _vest();
        uint256 before = distributor.claimCursor(a, address(usdc));
        _claim(alice, a, address(usdc));
        uint256 mid = distributor.claimCursor(a, address(usdc));
        assertGt(mid, before);
        _claim(alice, a, address(usdc));
        assertGe(distributor.claimCursor(a, address(usdc)), mid);
    }

    function test_claimIsPermissionlessButPaysTheRecipient() public {
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        uint256 before = usdc.balanceOf(alice);
        // A third party triggers the claim; funds still go to the position's recipient.
        _vest();
        _claim(carol, a, address(usdc));
        assertEq(usdc.balanceOf(alice) - before, 1000e6);
    }

    function test_setRecipientSplitsCustodyFromCashFlow() public {
        vm.prank(alice);
        distributor.setRecipient(a, carol);

        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();

        uint256 before = usdc.balanceOf(carol);
        _vest();
        _claim(alice, a, address(usdc));
        assertEq(usdc.balanceOf(carol) - before, 1000e6);
    }

    function test_onlyOwnerSetsPositionFlags() public {
        vm.startPrank(bob);
        vm.expectRevert(FeeDistributor.NotPositionOwner.selector);
        distributor.setRecipient(a, bob);
        vm.expectRevert(FeeDistributor.NotPositionOwner.selector);
        distributor.setAutoCompound(a, true);
        vm.stopPrank();
    }

    function test_claimMultipleTokensInOneCall() public {
        _notifyExact(address(usdc), 1000e6);
        _notifyExact(address(wxdc), 5 ether);
        _nextEpoch();
        _vest();

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(wxdc);

        vm.prank(alice);
        (uint256[] memory amounts,) = distributor.claim(a, tokens);
        assertEq(amounts[0], 1000e6);
        assertEq(amounts[1], 5 ether);
    }

    function test_claimAndLockFoldsRewardsBackIntoThePosition() public {
        _notifyExact(address(wxdc), 500 ether);
        _nextEpoch();
        _vest();

        uint256 principalBefore = escrow.locked(a).amount;
        vm.prank(alice);
        uint256 compounded = distributor.claimAndLock(a);

        assertEq(compounded, 500 ether);
        assertEq(escrow.locked(a).amount, principalBefore + 500 ether);
    }

    /// @dev "compound at/after expiry degrades to plain claim"
    function test_claimAndLockAfterExpiryDegradesToPlainClaim() public {
        uint256 short_ = _lock(bob, 100_000 ether, MIN_LOCK);
        _nextEpoch();
        _notifyExact(address(wxdc), 100 ether);
        _nextEpoch();
        _nextEpoch();

        assertLe(escrow.locked(short_).end, block.timestamp, "setup: expired");
        _vest();
        uint256 before = wxdc.balanceOf(bob);
        vm.prank(bob);
        uint256 amount = distributor.claimAndLock(short_);
        assertGt(amount, 0);
        assertEq(wxdc.balanceOf(bob) - before, amount, "paid out instead of compounded");
    }

    function test_claimAndLockRequiresAuthorisation() public {
        _notifyExact(address(wxdc), 100 ether);
        _nextEpoch();

        vm.prank(bob);
        vm.expectRevert(FeeDistributor.NotAuthorized.selector);
        distributor.claimAndLock(a);

        vm.prank(alice);
        escrow.setAutoExtend(a, true);
        vm.prank(bob);
        vm.expectRevert(FeeDistributor.NotAuthorized.selector);
        distributor.claimAndLock(a);

        vm.prank(alice);
        distributor.claimAndLock(a);
    }

    function test_claimableViewMatchesTheActualClaim() public {
        for (uint256 i; i < 4; ++i) {
            _notifyExact(address(usdc), 250e6);
            _nextEpoch();
        }
        _vest();
        distributor.settle(address(usdc), 52);

        (uint256 expected,) = distributor.claimable(a, address(usdc));
        assertEq(_claim(alice, a, address(usdc)), expected);
    }

    /// @dev After the cursor has caught every closed epoch, `remaining` must be 0 even mid-epoch
    ///      — the open epoch is never part of the backlog signal.
    function test_remainingIsZeroWhenCaughtUpMidEpoch() public {
        _notifyExact(address(usdc), 1000e6);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);
        // Still inside the open epoch that just started; two closed epochs of revenue.

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(alice);
        (, uint256 remaining) = distributor.claim(a, tokens);
        assertEq(remaining, 0, "open epoch must not keep remaining sticky");

        (uint256 amount, uint256 remainingView) = distributor.claimable(a, address(usdc));
        assertEq(amount, 0);
        assertEq(remainingView, 0, "claimable agrees mid-epoch");
    }

    function test_conservationOfValuePerToken() public {
        uint256 b = _lock(bob, 40_000 ether, 52 weeks);
        _nextEpoch();

        for (uint256 i; i < 6; ++i) {
            _notifyExact(address(usdc), 1000e6);
            _nextEpoch();
        }

        _vest();
        _claim(alice, a, address(usdc));
        _claim(bob, b, address(usdc));

        uint256 claimed = distributor.totalClaimed(address(usdc));
        uint256 notified = distributor.totalNotified(address(usdc));
        assertLe(claimed, notified, "never over-distribute");
        assertEq(
            usdc.balanceOf(address(distributor)),
            distributor.accounted(address(usdc)),
            "held balance always equals accounted value"
        );
        assertEq(distributor.accounted(address(usdc)), notified - claimed);
    }

    function test_aTokenAddedLateStartsAtTheAddEpoch() public {
        _warpEpochs(80);
        (MockERC20 late,) = _listLateToken();
        uint256 added = distributor.settledEpoch(address(late));

        address[] memory tokens = new address[](1);
        tokens[0] = address(late);
        vm.prank(alice);
        distributor.claim(a, tokens);

        assertEq(distributor.claimCursor(a, address(late)), added, "one claim skips the empty history");
        assertEq(
            distributor.unvestedForfeitCursor(address(late)), added, "harvest skips epochs before the token existed"
        );
    }

    function test_aLateTokensFirstEpochIsPaidAndItsForfeitureForwarded() public {
        _warpEpochs(80);
        uint256 b = _lock(bob, 100_000 ether, 104 weeks);
        uint256 c = _lock(carol, 100_000 ether, 104 weeks);
        _nextEpoch();

        (MockERC20 late, PushAdapter latePusher) = _listLateToken();
        late.mint(dapp, 1000 ether);
        vm.startPrank(dapp);
        late.approve(address(latePusher), 1000 ether);
        latePusher.commitRevenue(address(late), 1000 ether);
        vm.stopPrank();

        _nextEpoch();
        _completeEmergencyExit(bob, b);
        for (uint256 i; i < 2 * distributor.VESTING_EPOCHS() + 1; ++i) {
            _nextEpoch();
            distributor.settle(address(late), 52);
        }

        assertEq(_claim(bob, b, address(late)), 0, "the leaver forfeits the unvested add epoch");
        uint256 paid = _claim(alice, a, address(late)) + _claim(carol, c, address(late));
        assertApproxEqAbs(paid, 1000 ether, 5, "the add epoch and its forfeited slice reach the stayers");
        assertEq(late.balanceOf(address(distributor)), distributor.accounted(address(late)));
    }

    function _listLateToken() internal returns (MockERC20 late, PushAdapter adapter) {
        late = new MockERC20("Late", "LATE", 18);
        address[] memory one = new address[](1);
        one[0] = address(late);
        adapter = new PushAdapter(dapp, address(distributor), dappTreasury, 10_000, one);
        vm.startPrank(timelock);
        distributor.addRewardToken(address(late));
        registry.registerAdapter(address(adapter), dapp, IRevenueRegistry.Mode.PUSH, 10_000, 1, "late");
        vm.stopPrank();
    }
}
