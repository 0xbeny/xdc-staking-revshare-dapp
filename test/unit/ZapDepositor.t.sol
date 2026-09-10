// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {Base} from "../Base.t.sol";
import {MockCustodian} from "../mocks/MockCustodian.sol";

contract ZapDepositorTest is Base {
    event Zapped(
        address indexed depositor,
        address indexed beneficiary,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 duration
    );
    event ZapIncreased(address indexed depositor, uint256 indexed tokenId, uint256 amount);

    function test_zapCreatesLockOwnedByTheCaller() public {
        uint256 before = alice.balance;

        vm.prank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 100_000 ether}(52 weeks);

        assertEq(escrow.ownerOf(tokenId), alice, "the depositor is the owner");
        assertEq(escrow.locked(tokenId).amount, 100_000 ether);
        assertEq(before - alice.balance, 100_000 ether, "the caller's XDC was used");
        assertEq(wxdc.balanceOf(address(zap)), 0, "the zap never holds a balance");
        assertEq(address(zap).balance, 0);
    }

    function test_zapRecordsTheDepositorInTheEvent() public {
        vm.expectEmit(true, true, true, true, address(zap));
        emit Zapped(alice, alice, 1, 1 ether, 4 weeks);
        vm.prank(alice);
        zap.zapCreateLock{value: 1 ether}(4 weeks);
    }

    function test_zapForAnotherBeneficiaryRecordsBothParties() public {
        vm.expectEmit(true, true, true, true, address(zap));
        emit Zapped(alice, bob, 1, 1 ether, 4 weeks);

        vm.prank(alice);
        uint256 tokenId = zap.zapCreateLockFor{value: 1 ether}(bob, 4 weeks);

        assertEq(escrow.ownerOf(tokenId), bob, "bob owns it");
        assertEq(escrow.tokensOfOwner(alice).length, 0, "alice funded it but holds nothing");
    }

    /// @dev Eligibility is checked against the beneficiary, not the zap contract itself.
    function test_zapEnforcesBeneficiaryEligibility() public {
        MockCustodian custodian = new MockCustodian();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.IneligibleAccount.selector, address(custodian)));
        zap.zapCreateLockFor{value: 1 ether}(address(custodian), 4 weeks);
    }

    function test_zapIncreaseAmountByTheOwner() public {
        vm.startPrank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 100 ether}(52 weeks);

        vm.expectEmit(true, true, true, true, address(zap));
        emit ZapIncreased(alice, tokenId, 50 ether);
        zap.zapIncreaseAmount{value: 50 ether}(tokenId);
        vm.stopPrank();

        assertEq(escrow.locked(tokenId).amount, 150 ether);
    }

    /// @dev Adding principal re-weights the position's penalty cap, so only the owner may do it
    ///      through the zap. The escrow itself stays Curve-style permissionless so compounders
    ///      and gifters can still fund a position directly.
    function test_zapIncreaseAmountRejectsNonOwners() public {
        vm.prank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 100 ether}(52 weeks);

        uint256 capBefore = escrow.locked(tokenId).penaltyCapBps;
        vm.prank(bob);
        vm.expectRevert(ZapDepositor.NotPositionOwner.selector);
        zap.zapIncreaseAmount{value: 50 ether}(tokenId);

        assertEq(escrow.locked(tokenId).amount, 100 ether);
        assertEq(escrow.locked(tokenId).penaltyCapBps, capBefore, "a stranger cannot touch the cap via zap");
    }

    /// @dev Escrow `increaseAmount` is intentionally permissionless: a stranger may fund someone
    ///      else's position (and thereby re-weight the cap toward current global terms).
    function test_strangerCanFundIncreaseAmountDirectlyOnEscrow() public {
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(4000);

        vm.startPrank(alice);
        wxdc.approve(address(zap), 100 ether);
        uint256 tokenId = zap.lockWXDC(100 ether, 52 weeks);
        vm.stopPrank();

        uint256 capBefore = escrow.locked(tokenId).penaltyCapBps;
        assertEq(capBefore, 4000);

        // Global can only fall; stranger funding re-weights toward the cheaper current terms.
        vm.prank(timelock);
        escrow.setMaxPenaltyBps(2000);

        vm.startPrank(bob);
        wxdc.approve(address(escrow), 100 ether);
        escrow.increaseAmount(tokenId, 100 ether);
        vm.stopPrank();

        assertEq(escrow.ownerOf(tokenId), alice, "ownership unchanged");
        assertEq(escrow.locked(tokenId).amount, 200 ether);
        // newCap = (100e*4000 + 100e*2000) / 200e = 3000
        assertEq(escrow.locked(tokenId).penaltyCapBps, 3000);
        assertEq(wxdc.balanceOf(address(escrow)), escrow.totalLocked());
    }

    function test_zapRejectsZeroValue() public {
        vm.startPrank(alice);
        vm.expectRevert(ZapDepositor.ZeroAmount.selector);
        zap.zapCreateLock{value: 0}(4 weeks);
        vm.expectRevert(ZapDepositor.ZeroAmount.selector);
        zap.zapCreateLockFor{value: 0}(bob, 4 weeks);
        vm.stopPrank();
    }

    function test_zapRejectsZeroBeneficiary() public {
        vm.prank(alice);
        vm.expectRevert(ZapDepositor.ZeroAddress.selector);
        zap.zapCreateLockFor{value: 1 ether}(address(0), 4 weeks);
    }

    function test_strayNativeTransfersRevert() public {
        vm.prank(alice);
        (bool ok,) = address(zap).call{value: 1 ether}("");
        assertFalse(ok, "no receive(): stray XDC cannot get stuck here");
    }

    function test_constructorRejectsMismatchedEscrowToken() public {
        vm.expectRevert(ZapDepositor.EscrowTokenMismatch.selector);
        new ZapDepositor(address(usdc), address(escrow));
    }

    function test_lockWXDCCreatesLockOwnedByTheCaller() public {
        vm.startPrank(alice);
        wxdc.approve(address(zap), 50 ether);
        uint256 tokenId = zap.lockWXDC(50 ether, 26 weeks);
        vm.stopPrank();

        assertEq(escrow.ownerOf(tokenId), alice);
        assertEq(escrow.locked(tokenId).amount, 50 ether);
        assertEq(wxdc.balanceOf(address(zap)), 0);
    }

    function test_zapHasNoOwnerOrSetters() public {
        string[3] memory sigs = ["owner()", "setEscrow(address)", "rescue(address)"];
        for (uint256 i = 0; i < sigs.length; ++i) {
            (bool ok,) = address(zap).call(abi.encodeWithSignature(sigs[i], address(1)));
            assertFalse(ok, "the zap is immutable and ownerless");
        }
    }
}
