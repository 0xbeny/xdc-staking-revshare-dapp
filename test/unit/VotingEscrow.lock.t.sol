// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {Base} from "../Base.t.sol";
import {MockCustodian, MockNonReceiver} from "../mocks/MockCustodian.sol";

contract VotingEscrowLockTest is Base {
    function test_createLock_roundsUnlockUpToWeekBoundary() public {
        uint256 tokenId = _lock(alice, 100_000 ether, 52 weeks);
        VotingEscrow.Lock memory lock = escrow.locked(tokenId);

        assertEq(lock.end % WEEK, 0, "unlock must sit on a week boundary");
        assertGe(lock.end - block.timestamp, 52 weeks, "rounding must never shorten the lock");
        assertLt(lock.end - block.timestamp, 52 weeks + WEEK, "rounding must not overshoot a week");
        assertEq(escrow.ownerOf(tokenId), alice);
        assertEq(lock.amount, 100_000 ether);
    }

    function test_createLock_effectiveLockAlwaysAtLeastMinLock() public {
        uint256 tokenId = _lock(alice, 1 ether, MIN_LOCK);
        VotingEscrow.Lock memory lock = escrow.locked(tokenId);
        assertGe(lock.end - block.timestamp, MIN_LOCK);
    }

    function test_createLock_revertsOnUnalignedDuration() public {
        vm.startPrank(alice);
        wxdc.approve(address(zap), 1 ether);
        vm.expectRevert(VotingEscrow.DurationNotWeekAligned.selector);
        zap.lockWXDC(1 ether, 8 days);
        vm.stopPrank();
    }

    function test_createLock_revertsOutsideRange() public {
        vm.startPrank(alice);
        wxdc.approve(address(zap), 2 ether);
        vm.expectRevert(VotingEscrow.DurationOutOfRange.selector);
        zap.lockWXDC(1 ether, 105 weeks);
        vm.expectRevert(VotingEscrow.DurationOutOfRange.selector);
        zap.lockWXDC(1 ether, 0);
        vm.stopPrank();
    }

    function test_createLock_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ZapDepositor.ZeroAmount.selector);
        zap.lockWXDC(0, 4 weeks);
    }

    function test_directEscrowMintRevertsForNonDepositor() public {
        vm.startPrank(alice);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.NotDepositor.selector);
        escrow.createLockFor(alice, 1 ether, 4 weeks);
        vm.stopPrank();
    }

    function test_createLockFor_checksEligibilityOfBeneficiaryNotFunder() public {
        MockCustodian custodian = new MockCustodian();

        // A contract with no tier cannot be a beneficiary...
        vm.startPrank(alice);
        wxdc.approve(address(zap), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.IneligibleAccount.selector, address(custodian)));
        zap.lockWXDCFor(address(custodian), 1 ether, 4 weeks);
        vm.stopPrank();

        // ...until governance grants it a tier.
        vm.prank(timelock);
        escrow.setTier(address(custodian), VotingEscrow.Tier.CUSTODIAN);

        vm.startPrank(alice);
        wxdc.approve(address(zap), 1 ether);
        uint256 tokenId = zap.lockWXDCFor(address(custodian), 1 ether, 4 weeks);
        vm.stopPrank();
        assertEq(escrow.ownerOf(tokenId), address(custodian));
    }

    /// @dev Whitelisting a contract that cannot hold an ERC721 is a misconfiguration; the mint
    ///      reverts before principal is committed rather than stranding it afterwards.
    function test_createLockFor_whitelistedNonReceiverStillReverts() public {
        MockNonReceiver bad = new MockNonReceiver();
        vm.prank(timelock);
        escrow.setTier(address(bad), VotingEscrow.Tier.CUSTODIAN);

        vm.startPrank(alice);
        wxdc.approve(address(zap), 1 ether);
        vm.expectRevert();
        zap.lockWXDCFor(address(bad), 1 ether, 4 weeks);
        vm.stopPrank();
    }

    function test_createLockFor_eoaNeedsNoWhitelist() public {
        vm.startPrank(alice);
        wxdc.approve(address(zap), 1 ether);
        uint256 tokenId = zap.lockWXDCFor(bob, 1 ether, 4 weeks);
        vm.stopPrank();
        assertEq(escrow.ownerOf(tokenId), bob);
    }

    function test_increaseAmount_addsPrincipalAndWeight() public {
        uint256 tokenId = _lock(alice, 100 ether, 52 weeks);
        uint256 weightBefore = escrow.balanceOfNFT(tokenId);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 100 ether);
        escrow.increaseAmount(tokenId, 100 ether);
        vm.stopPrank();

        assertEq(escrow.locked(tokenId).amount, 200 ether);
        assertApproxEqRel(escrow.balanceOfNFT(tokenId), weightBefore * 2, 1e12);
        assertEq(escrow.totalLocked(), 200 ether);
    }

    function test_increaseUnlockTime_extendsAndRoundsUp() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        uint256 oldEnd = escrow.locked(tokenId).end;

        vm.prank(alice);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 20 weeks);

        uint256 newEnd = escrow.locked(tokenId).end;
        assertGt(newEnd, oldEnd);
        assertEq(newEnd % WEEK, 0);
    }

    function test_increaseUnlockTime_revertsWhenNotLater() public {
        uint256 tokenId = _lock(alice, 100 ether, 20 weeks);
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.UnlockNotLater.selector);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 4 weeks);
    }

    function test_increaseUnlockTime_revertsBeyondMaxLock() public {
        uint256 tokenId = _lock(alice, 100 ether, 20 weeks);
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.UnlockTooFar.selector);
        escrow.increaseUnlockTime(tokenId, block.timestamp + MAX_LOCK + 1);
    }

    function test_increaseUnlockTime_onlyOwnerOrOperator() public {
        uint256 tokenId = _lock(alice, 100 ether, 20 weeks);

        vm.prank(bob);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 40 weeks);

        vm.prank(alice);
        escrow.setOperator(bob, true);
        vm.prank(bob);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 40 weeks);
        assertGt(escrow.locked(tokenId).end, block.timestamp + 39 weeks);
    }

    function test_withdraw_returnsFullPrincipalAfterExpiry() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        uint256 balanceBefore = wxdc.balanceOf(alice);

        vm.warp(escrow.locked(tokenId).end);
        vm.prank(alice);
        escrow.withdraw(tokenId);

        assertEq(wxdc.balanceOf(alice) - balanceBefore, 100 ether);
        assertEq(escrow.totalLocked(), 0);
        assertTrue(escrow.closed(tokenId));
    }

    function test_withdraw_revertsBeforeExpiry() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockNotExpired.selector);
        escrow.withdraw(tokenId);
    }

    function test_withdraw_revertsForNonOwner() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);
        vm.prank(bob);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.withdraw(tokenId);
    }

    function test_closedPositionCannotBeReused() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);
        vm.prank(alice);
        escrow.withdraw(tokenId);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.LockClosed.selector);
        escrow.increaseAmount(tokenId, 1 ether);
        vm.stopPrank();
    }

    function test_multiplePositionsPerUserReplaceSplitMerge() public {
        uint256 short_ = _lock(alice, 100 ether, 4 weeks);
        uint256 long_ = _lock(alice, 100 ether, 104 weeks);

        uint256[] memory ids = escrow.tokensOfOwner(alice);
        assertEq(ids.length, 2);
        assertGt(escrow.balanceOfNFT(long_), escrow.balanceOfNFT(short_));
    }

    function test_specNamedAliasesWork() public {
        vm.startPrank(address(zap));
        // Alias is still depositor-gated; the zap holds WXDC from a prior user transfer in real
        // flows. Here the test contract is not the zap — exercise increase aliases after a zap mint.
        vm.stopPrank();

        uint256 tokenId = _lock(alice, 1 ether, 4 weeks);
        vm.startPrank(alice);
        wxdc.approve(address(escrow), 1 ether);
        escrow.increase_amount(tokenId, 1 ether);
        escrow.increase_unlock_time(tokenId, block.timestamp + 20 weeks);
        vm.stopPrank();
        assertEq(escrow.locked(tokenId).amount, 2 ether);
    }
}
