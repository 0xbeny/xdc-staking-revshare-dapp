// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";

contract WithdrawalCooldownTest is Base {
    function setUp() public override {
        super.setUp();
        // Restore the production default the suite normally zeroes for convenience.
        vm.prank(timelock);
        escrow.setWithdrawalCooldown(1 days);
    }

    function test_defaultCooldownIs24Hours() public {
        VotingEscrow fresh =
            new VotingEscrow(address(wxdc), address(distributor), treasury, timelock, guardian, 5000, 2000);
        assertEq(fresh.withdrawalCooldown(), 1 days);
        assertEq(fresh.HARD_MAX_WITHDRAWAL_COOLDOWN(), 7 days);
    }

    function test_timelockCanTuneCooldownWithinClamp() public {
        vm.prank(timelock);
        escrow.setWithdrawalCooldown(12 hours);
        assertEq(escrow.withdrawalCooldown(), 12 hours);

        vm.prank(timelock);
        vm.expectRevert(VotingEscrow.ParameterOutOfRange.selector);
        escrow.setWithdrawalCooldown(8 days);
    }

    function test_matureWithdrawRequiresCooldown() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);

        vm.prank(alice);
        escrow.withdraw(tokenId); // arms request, does not pay yet
        assertEq(wxdc.balanceOf(alice), 100_000_000 ether - 100 ether, "no payout on first call");
        (uint64 readyAt, VotingEscrow.ExitKind kind,,,) = _exitRequest(tokenId);
        assertEq(uint8(kind), uint8(VotingEscrow.ExitKind.Withdraw));
        assertEq(readyAt, block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.CooldownActive.selector, uint256(readyAt)));
        escrow.withdraw(tokenId);

        vm.warp(readyAt);
        uint256 before = wxdc.balanceOf(alice);
        vm.prank(alice);
        escrow.withdraw(tokenId);
        assertEq(wxdc.balanceOf(alice) - before, 100 ether);
        assertTrue(escrow.closed(tokenId));
    }

    function test_readyAtIsSnapshottedAgainstLaterCooldownChanges() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);

        vm.prank(alice);
        escrow.requestWithdraw(tokenId);
        (uint64 readyAt,,,,) = _exitRequest(tokenId);
        assertEq(readyAt, block.timestamp + 1 days);

        // Governance lengthens the cooldown mid-flight — pending request is unaffected.
        vm.prank(timelock);
        escrow.setWithdrawalCooldown(7 days);

        (uint64 readyAtAfter,,,,) = _exitRequest(tokenId);
        assertEq(readyAtAfter, readyAt, "pending readyAt is immutable");

        vm.warp(readyAt);
        uint256 before = wxdc.balanceOf(alice);
        vm.prank(alice);
        escrow.withdraw(tokenId);
        assertEq(wxdc.balanceOf(alice) - before, 100 ether);
    }

    function test_emergencyExitSnapshotsPenaltyAtRequest() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        vm.warp(block.timestamp + 26 weeks);

        (uint256 returnedNow, uint256 penaltyNow,) = escrow.previewExit(tokenId);

        vm.prank(alice);
        escrow.emergencyExit(tokenId); // request + snapshot

        // Time passes; live quote would change, but payout uses the snapshot.
        vm.warp(block.timestamp + 1 days);
        uint256 before = wxdc.balanceOf(alice);
        vm.prank(alice);
        escrow.emergencyExit(tokenId);

        assertEq(wxdc.balanceOf(alice) - before, returnedNow);
        assertEq(escrow.totalLocked(), 0);
        // Penalty left the escrow (lockers + treasury).
        assertEq(returnedNow + penaltyNow, 100_000 ether);
    }

    function test_cancelExitRequestAllowsNewPath() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);

        vm.prank(alice);
        escrow.requestWithdraw(tokenId);
        vm.prank(alice);
        escrow.cancelExitRequest(tokenId);

        vm.prank(timelock);
        escrow.setWithdrawalCooldown(0);
        vm.prank(alice);
        escrow.withdraw(tokenId);
        assertTrue(escrow.closed(tokenId));
    }

    function test_pendingExitBlocksIncreaseAmount() public {
        uint256 tokenId = _lock(alice, 100 ether, 52 weeks);
        vm.prank(alice);
        escrow.requestEmergencyExit(tokenId);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.ExitPending.selector);
        escrow.increaseAmount(tokenId, 1 ether);
        vm.stopPrank();
    }

    function _exitRequest(uint256 tokenId)
        internal
        view
        returns (uint64 readyAt, VotingEscrow.ExitKind kind, uint128 returned, uint128 toLockers, uint128 toTreasury)
    {
        uint64 penaltyBps;
        (readyAt, kind, returned, toLockers, toTreasury, penaltyBps) = escrow.exitRequest(tokenId);
        penaltyBps; // silence
    }
}
