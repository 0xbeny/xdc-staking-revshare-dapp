// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VotingEscrowSoulboundTest is Base {
    uint256 internal tokenId;

    function setUp() public override {
        super.setUp();
        tokenId = _lock(alice, 100_000 ether, 52 weeks);
    }

    function test_transferFromReverts() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        escrow.transferFrom(alice, bob, tokenId);
    }

    function test_safeTransferFromReverts() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        IERC721(address(escrow)).safeTransferFrom(alice, bob, tokenId);
    }

    function test_safeTransferFromWithDataReverts() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        escrow.safeTransferFrom(alice, bob, tokenId, "");
    }

    function test_approveReverts() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        escrow.approve(bob, tokenId);
    }

    function test_setApprovalForAllReverts() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        escrow.setApprovalForAll(bob, true);
    }

    /// @dev Option B (#9): there is no `wrapInto` and no transfer carve-out of any kind.
    function test_noWrapIntoFunctionExists() public {
        (bool ok,) = address(escrow).call(abi.encodeWithSignature("wrapInto(uint256,address)", tokenId, bob));
        assertFalse(ok, "wrapInto must not exist");
        (ok,) = address(escrow).call(abi.encodeWithSignature("wrapInto(uint256)", tokenId));
        assertFalse(ok, "wrapInto must not exist");
    }

    /// @dev Frozen as absent (#2): no split, no merge, in any signature shape.
    function test_noSplitOrMergeFunctionExists() public {
        string[4] memory sigs =
            ["split(uint256,uint256)", "merge(uint256,uint256)", "split(uint256[])", "merge(uint256)"];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(escrow).call(abi.encodeWithSignature(sigs[i], uint256(1), uint256(1)));
            assertFalse(ok, "split/merge must not exist");
        }
    }

    /// @dev A keeper operator gets extension rights only — never a transfer or a spend.
    function test_operatorCannotTransferOrWithdraw() public {
        vm.prank(alice);
        escrow.setOperator(keeper, true);

        vm.startPrank(keeper);
        vm.expectRevert(VotingEscrow.Soulbound.selector);
        escrow.transferFrom(alice, keeper, tokenId);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.withdraw(tokenId);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        escrow.emergencyExit(tokenId);
        vm.stopPrank();
    }

    function test_ownershipSurvivesWithdrawSoFinalizedClaimsStillWork() public {
        vm.warp(escrow.locked(tokenId).end);
        vm.prank(alice);
        escrow.withdraw(tokenId);
        assertEq(escrow.ownerOf(tokenId), alice, "positions are never burned");
    }
}
