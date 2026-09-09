// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice All five revenue modes feeding one epoch, plus a full lifecycle around it.
contract MultiDappRevenueTest is Base {
    function test_allFiveModesFeedTheSameEpochAndConserveValue() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 104 weeks);
        uint256 b = _lock(bob, 100_000 ether, 52 weeks);
        _nextEpoch();

        uint256 epoch = _currentEpoch();
        uint256 expected;

        // Mode A — push (100% committed).
        vm.startPrank(dapp);
        usdc.approve(address(pusher), 1000e6);
        pusher.commitRevenue(address(usdc), 1000e6);
        vm.stopPrank();
        expected += 1000e6;

        // Mode B — splitter (30% committed).
        deal(address(usdc), address(splitter), 10_000e6);
        splitter.skim(address(usdc));
        expected += 3000e6;

        // Mode B2 — pull from a dedicated fee Safe (25% committed).
        deal(address(usdc), address(feeSafe), 8000e6);
        puller.skim(address(usdc));
        expected += 2000e6;

        // Mode B3 — Zodiac module on a dedicated fee Safe (25% committed).
        deal(address(usdc), address(feeSafeB3), 8000e6);
        zodiac.skim(address(usdc));
        expected += 2000e6;

        // Mode C — atomic attestation against a closed source period.
        vm.startPrank(reporter);
        usdc.approve(address(attestor), type(uint256).max);
        attestor.postRevenue(dapp, address(usdc), uint64(epoch - 1), 4000e6, 0, keccak256("q1"));
        vm.stopPrank();
        expected += 4000e6;

        assertEq(distributor.epochRevenue(address(usdc), epoch), expected, "one epoch, five sources");

        // Every adapter and fee Safe is empty afterwards.
        assertEq(usdc.balanceOf(address(splitter)), 0);
        assertEq(usdc.balanceOf(address(puller)), 0);
        assertEq(usdc.balanceOf(address(zodiac)), 0);
        assertEq(usdc.balanceOf(address(pusher)), 0);
        assertEq(usdc.balanceOf(address(attestor)), 0);
        assertEq(usdc.balanceOf(address(feeSafe)), 0, "B2 fee Safe swept to zero");
        assertEq(usdc.balanceOf(address(feeSafeB3)), 0, "B3 fee Safe swept to zero");

        _nextEpoch();
        uint256 gotA = _claim(alice, a, address(usdc));
        uint256 gotB = _claim(bob, b, address(usdc));
        assertApproxEqAbs(gotA + gotB, expected, 4, "the epoch is fully distributed");
        assertGt(gotA, gotB, "the longer lock earns more");
    }

    function test_lifecycleAcrossManyEpochsWithMixedUserBehaviour() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 200_000 ether, 104 weeks);
        uint256 b = _lock(bob, 100_000 ether, 26 weeks);
        uint256 c = _lock(carol, 50_000 ether, 4 weeks);
        _nextEpoch();

        vm.startPrank(alice);
        distributor.setAutoCompound(a, true);
        escrow.setOperator(address(distributor), true);
        vm.stopPrank();

        uint256[] memory compoundIds = new uint256[](1);
        compoundIds[0] = a;

        for (uint256 i; i < 12; ++i) {
            _notifyExact(address(usdc), 5000e6);
            _notifyExact(address(wxdc), 400 ether);
            _nextEpoch();
            vm.prank(keeper);
            distributor.batchCompound(compoundIds, _currentEpoch());
        }

        // Carol's short lock expired: she withdraws principal in full and still claims her
        // finalized epochs afterwards.
        vm.prank(carol);
        escrow.withdraw(c);
        assertEq(wxdc.balanceOf(carol), 100_000_000 ether);
        assertGt(_claim(carol, c, address(usdc)), 0, "finalized claims survive a withdrawal");

        // Bob exits early and forfeits his in-progress epoch.
        vm.prank(bob);
        escrow.emergencyExit(b);
        distributor.syncForfeiture(address(wxdc));

        _warpEpochs(2);
        _claim(alice, a, address(usdc));
        _claim(bob, b, address(usdc));

        // Conservation across the whole run.
        address[2] memory tokens = [address(usdc), address(wxdc)];
        for (uint256 i; i < 2; ++i) {
            address token = tokens[i];
            assertEq(
                distributor.accounted(token),
                distributor.totalNotified(token) - distributor.totalClaimed(token),
                "accounted == notified - claimed"
            );
            assertGe(IERC20(token).balanceOf(address(distributor)), distributor.accounted(token));
            assertLe(distributor.totalClaimed(token), distributor.totalNotified(token));
        }

        // Alice compounded, so her principal grew without her ever extending the lock's duration.
        assertGt(escrow.locked(a).amount, 200_000 ether);
    }

    /// @dev A guardian pause freezes the periphery but never the escrow's exit doors.
    function test_guardianPauseNeverTouchesPrincipal() public {
        vm.warp(_epochStart(_currentEpoch() + 1));
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        uint256 b = _lock(bob, 100_000 ether, 4 weeks);
        _nextEpoch();
        _notifyExact(address(usdc), 1000e6);

        vm.prank(guardian);
        distributor.pause();

        // Early exit still works, at the immutable terms.
        (uint256 returned,,) = escrow.previewExit(a);
        vm.prank(alice);
        escrow.emergencyExit(a);
        assertEq(wxdc.balanceOf(alice), 100_000_000 ether - 100_000 ether + returned);

        // And so does a matured withdrawal.
        vm.warp(escrow.locked(b).end);
        vm.prank(bob);
        escrow.withdraw(b);
        assertEq(wxdc.balanceOf(bob), 100_000_000 ether);
    }
}
