// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VeVotesAdapter} from "../../src/governance/VeVotesAdapter.sol";
import {Base} from "../Base.t.sol";

contract VeVotesAdapterTest is Base {
    function test_votesAggregateAllPositionsOfAnOwner() public {
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        uint256 b = _lock(alice, 50_000 ether, 104 weeks);

        assertEq(votes.getVotes(alice), escrow.balanceOfNFT(a) + escrow.balanceOfNFT(b));
        assertEq(votes.getVotes(bob), 0);
    }

    function test_pastVotesReadCheckpointedHistory() public {
        uint256 a = _lock(alice, 100_000 ether, 52 weeks);
        uint256 t0 = block.timestamp;
        uint256 w0 = votes.getVotes(alice);

        vm.warp(t0 + 26 weeks);
        assertLt(votes.getVotes(alice), w0, "weight decays");
        assertEq(votes.getPastVotes(alice, t0), w0, "history is immutable");
        assertEq(votes.getPastVotes(alice, t0), escrow.balanceOfNFTAt(a, t0));
    }

    function test_pastTotalSupplyMatchesTheEscrow() public {
        _lock(alice, 100_000 ether, 52 weeks);
        _lock(bob, 40_000 ether, 20 weeks);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 10 weeks);
        escrow.checkpoint();
        assertEq(votes.getPastTotalSupply(t0), escrow.totalSupplyAt(t0));
    }

    function test_pastVotesRejectFutureAndCurrentTimepoints() public {
        _lock(alice, 100_000 ether, 52 weeks);
        uint48 nowTs = votes.clock();

        vm.expectRevert(abi.encodeWithSelector(VeVotesAdapter.ERC5805FutureLookup.selector, uint256(nowTs), nowTs));
        votes.getPastVotes(alice, nowTs);

        vm.expectRevert(abi.encodeWithSelector(VeVotesAdapter.ERC5805FutureLookup.selector, uint256(nowTs) + 1, nowTs));
        votes.getPastTotalSupply(uint256(nowTs) + 1);
    }

    function test_clockIsTimestampBased() public view {
        assertEq(votes.clock(), uint48(block.timestamp));
        assertEq(votes.CLOCK_MODE(), "mode=timestamp");
    }

    /// @dev v1 has no delegation: weight is always self-held.
    function test_delegationIsExplicitlyUnsupported() public {
        assertEq(votes.delegates(alice), alice);

        vm.prank(alice);
        vm.expectRevert(VeVotesAdapter.DelegationNotSupported.selector);
        votes.delegate(bob);

        vm.prank(alice);
        vm.expectRevert(VeVotesAdapter.DelegationNotSupported.selector);
        votes.delegateBySig(bob, 0, 0, 0, bytes32(0), bytes32(0));
    }

    function test_votesAdapterIsReadOnly() public {
        (bool ok,) = address(votes).call(abi.encodeWithSignature("setEscrow(address)", address(1)));
        assertFalse(ok);
    }
}
