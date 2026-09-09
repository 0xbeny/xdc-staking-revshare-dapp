// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {Base} from "../Base.t.sol";
import {MockCustodian} from "../mocks/MockCustodian.sol";

contract ZapDepositorTest is Base {
    function test_zapCreatesLockFromNativeXDC() public {
        vm.prank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 100_000 ether}(alice, 52 weeks);

        assertEq(escrow.ownerOf(tokenId), alice);
        assertEq(escrow.locked(tokenId).amount, 100_000 ether);
        assertEq(wxdc.balanceOf(address(zap)), 0, "the zap never holds a balance");
    }

    function test_zapForAnotherBeneficiary() public {
        vm.prank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 1 ether}(bob, 4 weeks);
        assertEq(escrow.ownerOf(tokenId), bob);
    }

    /// @dev Eligibility is checked against the beneficiary, not the zap contract itself.
    function test_zapEnforcesBeneficiaryEligibility() public {
        MockCustodian custodian = new MockCustodian();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.IneligibleAccount.selector, address(custodian)));
        zap.zapCreateLock{value: 1 ether}(address(custodian), 4 weeks);
    }

    function test_zapIncreaseAmount() public {
        vm.startPrank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 100 ether}(alice, 52 weeks);
        zap.zapIncreaseAmount{value: 50 ether}(tokenId);
        vm.stopPrank();
        assertEq(escrow.locked(tokenId).amount, 150 ether);
    }

    function test_zapRejectsZeroValue() public {
        vm.startPrank(alice);
        vm.expectRevert(ZapDepositor.ZeroAmount.selector);
        zap.zapCreateLock{value: 0}(alice, 4 weeks);
        vm.stopPrank();
    }

    function test_constructorRejectsMismatchedEscrowToken() public {
        vm.expectRevert(ZapDepositor.EscrowTokenMismatch.selector);
        new ZapDepositor(address(usdc), address(escrow));
    }

    function test_zapHasNoOwnerOrSetters() public {
        string[3] memory sigs = ["owner()", "setEscrow(address)", "rescue(address)"];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(zap).call(abi.encodeWithSignature(sigs[i], address(1)));
            assertFalse(ok, "the zap is immutable and ownerless");
        }
    }
}
