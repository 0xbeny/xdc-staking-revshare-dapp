// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";

/// @notice The spec §9 user journey, end to end, with the illustrative economics:
///         5,300 USDC + 18,000 WXDC per weekly epoch against ~25M total ve.
contract UserJourneyTest is Base {
    uint256 internal constant USDC_PER_EPOCH = 5300e6;
    uint256 internal constant WXDC_PER_EPOCH = 18_000 ether;

    /// @dev A whale sized so that alice's 100k XDC / 52w position is ~0.2% of ~25M total ve.
    uint256 internal whalePosition;

    function _seedTotalSupply() internal {
        // Alice's 52-week lock on 100k gives ~50,000 ve. For that to be 0.2%, total must be 25M.
        whalePosition = _lock(carol, 25_000_000 ether, 104 weeks);
    }

    function _epochRevenue() internal {
        _notifyExact(address(usdc), USDC_PER_EPOCH);
        _notifyExact(address(wxdc), WXDC_PER_EPOCH);
    }

    function test_fullJourney_lockEarnClaimEndgame() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        _seedTotalSupply();

        // 1. Lock: 100k XDC via the zap, 52 weeks — deliberately mid-epoch.
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        uint256 position = zap.zapCreateLock{value: 100_000 ether}(alice, 52 weeks);

        assertEq(escrow.locked(position).end % WEEK, 0, "rounds up to the next Thursday boundary");
        assertGe(escrow.locked(position).end - block.timestamp, 52 weeks);
        // ~50,000 ve, plus up to one week of round-up (52w -> at most 52w+6d of 104w).
        assertApproxEqRel(escrow.balanceOfNFT(position), 50_000 ether, 0.02e18, "~50,000 ve initial weight");
        assertEq(escrow.locked(position).penaltyCapBps, 5000, "cap snapshots at the current global");

        // 2. First epoch: a mid-epoch lock first earns at the next start-of-epoch snapshot.
        _epochRevenue();
        _nextEpoch();
        distributor.settle(address(usdc), 52);
        (uint256 pending,) = distributor.claimable(position, address(usdc));
        assertEq(pending, 0, "nothing from the epoch it joined");
        assertEq(distributor.claimCursor(position, address(usdc)), 0);

        // 3. Earning: hold a ~0.2% share for ten epochs. Alice re-extends her 52-week profile
        //    each week; the whale sits at max lock so total supply stays roughly stable.
        vm.prank(carol);
        distributor.setKeepAtMaxLock(whalePosition, true);
        vm.prank(carol);
        escrow.setOperator(address(distributor), true);

        uint256[] memory ids = new uint256[](1);
        ids[0] = whalePosition;

        for (uint256 i; i < 10; ++i) {
            _epochRevenue();
            // Pre-boundary keeper window (§5 step 2): re-extensions land before the snapshot.
            vm.warp(_epochStart(_currentEpoch() + 1) - 1 hours);
            vm.prank(keeper);
            distributor.batchKeepAtMaxLock(ids, _currentEpoch());
            vm.prank(alice);
            escrow.increaseUnlockTime(position, block.timestamp + 52 weeks);
            _nextEpoch();
        }

        assertApproxEqRel(
            escrow.balanceOfNFT(position) * 1e18 / escrow.totalSupply(), 0.002e18, 0.05e18, "~0.2% share held"
        );

        // 4. Receiving: one cursor-bounded claim covers the whole ten-week backlog.
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(wxdc);

        vm.prank(alice);
        (uint256[] memory got, uint256 remaining) = distributor.claim(position, tokens);
        assertEq(remaining, 0, "a 10-week backlog fits comfortably in one call");

        // Spec §9 step 3: ~106 USDC + ~360 WXDC over ten weeks at a ~0.2% share.
        assertApproxEqRel(got[0], 106e6, 0.05e18, "~106 USDC over ten epochs");
        assertApproxEqRel(got[1], 360 ether, 0.05e18, "~360 WXDC over ten epochs");

        // 5. Endgame: early exit at week 26 of 52.
        uint256 unlock = escrow.locked(position).end;
        vm.warp(unlock - 26 weeks);
        (uint256 returned, uint256 penalty, uint256 penaltyBps) = escrow.previewExit(position);
        assertEq(penaltyBps, 1250, "50% cap x 26/104");
        assertEq(returned, 87_500 ether, "87,500 XDC back");

        uint256 balanceBefore = wxdc.balanceOf(alice);
        vm.prank(alice);
        escrow.emergencyExit(position);
        assertEq(wxdc.balanceOf(alice) - balanceBefore, returned);

        // Forfeits stream to the remaining locker from the next epoch.
        uint256 credited = distributor.syncForfeiture(address(wxdc));
        assertEq(credited, penalty - (penalty * 2000 / 10_000));
        _nextEpoch();
        _nextEpoch();
        assertGt(_claim(carol, whalePosition, address(wxdc)), credited * 99 / 100);
    }

    /// @dev Without re-extension the share decays: ~0.19% by week 10, halved by week 26.
    function test_passiveDecayVersusKeepAtMaxLock() public {
        vm.warp(_epochStart(_currentEpoch() + 1));

        uint256 passive = _lock(alice, 100_000 ether, 52 weeks);
        uint256 active = _lock(bob, 100_000 ether, 52 weeks);
        uint256 startWeight = escrow.balanceOfNFT(passive);

        vm.startPrank(bob);
        distributor.setKeepAtMaxLock(active, true);
        escrow.setOperator(address(distributor), true);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](1);
        ids[0] = active;

        for (uint256 i; i < 26; ++i) {
            vm.warp(_epochStart(_currentEpoch() + 1) - 1 hours);
            vm.prank(keeper);
            distributor.batchKeepAtMaxLock(ids, _currentEpoch());
            _nextEpoch();
        }

        assertApproxEqRel(escrow.balanceOfNFT(passive), startWeight / 2, 0.02e18, "halved by week 26");
        assertGt(escrow.balanceOfNFT(active), startWeight, "the re-extended position sits at full weight");
    }

    /// @dev Multiple maturity profiles are multiple positions — split/merge is structurally absent.
    function test_multiplePositionsGiveMultipleMaturityProfiles() public {
        vm.warp(_epochStart(_currentEpoch() + 1));

        uint256 shortP = _lock(alice, 50_000 ether, 4 weeks);
        uint256 longP = _lock(alice, 50_000 ether, 104 weeks);
        _nextEpoch();

        _notifyExact(address(usdc), 10_000e6);
        _nextEpoch();

        uint256 shortEarned = _claim(alice, shortP, address(usdc));
        uint256 longEarned = _claim(alice, longP, address(usdc));
        assertGt(longEarned, shortEarned * 20);
        assertApproxEqAbs(shortEarned + longEarned, 10_000e6, 2);

        // The short position matures and returns full principal while the long one keeps earning.
        vm.warp(escrow.locked(shortP).end);
        vm.prank(alice);
        escrow.withdraw(shortP);
        assertEq(escrow.locked(longP).amount, 50_000 ether);
    }
}
