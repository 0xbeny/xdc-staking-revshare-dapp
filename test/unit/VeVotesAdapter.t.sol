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
        assertEq(votes.getVotes(alice), escrow.weightOf(alice));
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

    /// @dev The previous `getVotes` was `sum(balanceOfNFT)` over `tokensOfOwner`. This walks the
    ///      same mutations and timestamps and requires the account checkpoint to match that sum,
    ///      including after a position is closed and stays in the list.
    function test_accountWeightMatchesLegacyPerPositionSum() public {
        uint256[] memory marks = new uint256[](8);
        uint256 n;

        uint256 a0 = _lock(alice, 100_000 ether, 30 weeks);
        uint256 b0 = _lock(bob, 250_000 ether, MAX_LOCK);
        marks[n++] = block.timestamp;
        _assertAccountMatchesLegacy(alice);
        _assertAccountMatchesLegacy(bob);
        _assertAccountMatchesLegacy(carol);

        vm.warp(block.timestamp + 2 weeks + 3 days + 5 hours);
        uint256 a1 = _lock(alice, 40_000 ether, 52 weeks);
        marks[n++] = block.timestamp;
        _assertAccountMatchesLegacy(alice);

        vm.warp(block.timestamp + 4 weeks + 1 hours);
        marks[n++] = block.timestamp;
        vm.startPrank(alice);
        wxdc.approve(address(escrow), 10_000 ether);
        escrow.increaseAmount(a0, 10_000 ether);
        escrow.increaseUnlockTime(a1, block.timestamp + 80 weeks);
        vm.stopPrank();
        _assertAccountMatchesLegacy(alice);

        vm.warp(block.timestamp + 8 weeks);
        marks[n++] = block.timestamp;
        vm.startPrank(bob);
        escrow.setAutoExtend(b0, true);
        escrow.keepAtMaxLock(b0);
        vm.stopPrank();
        _assertAccountMatchesLegacy(bob);

        _completeEmergencyExit(alice, a0);
        marks[n++] = block.timestamp;
        _assertAccountMatchesLegacy(alice);
        assertEq(escrow.balanceOfNFT(a0), 0, "exited position contributes nothing");
        assertGt(escrow.tokensOfOwner(alice).length, 1, "exited id stays in the list");

        vm.warp(escrow.locked(a1).end + 1);
        marks[n++] = block.timestamp;
        _completeWithdraw(alice, a1);
        _assertAccountMatchesLegacy(alice);
        _assertAccountMatchesLegacy(bob);

        vm.warp(block.timestamp + 1 weeks + 2 days);
        marks[n++] = block.timestamp;
        _assertAccountMatchesLegacy(bob);
        assertEq(votes.getVotes(alice), 0, "alice has no live weight");

        for (uint256 i; i < n; ++i) {
            if (marks[i] >= block.timestamp) {
                continue;
            }
            assertEq(votes.getPastVotes(alice, marks[i]), _legacySumAt(alice, marks[i]), "alice past");
            assertEq(votes.getPastVotes(bob, marks[i]), _legacySumAt(bob, marks[i]), "bob past");
            assertEq(votes.getPastVotes(carol, marks[i]), 0, "carol past");
            assertEq(votes.getPastTotalSupply(marks[i]), escrow.totalSupplyAt(marks[i]), "supply past");
        }
    }

    function _assertAccountMatchesLegacy(address account) internal view {
        uint256 legacy = _legacySum(account);
        assertEq(escrow.weightOf(account), legacy, "weightOf");
        assertEq(votes.getVotes(account), legacy, "getVotes");
        assertEq(escrow.weightOf(alice) + escrow.weightOf(bob) + escrow.weightOf(carol), escrow.totalSupply());
    }

    /// @dev Exact previous adapter formula: sum `balanceOfNFT` over every id ever owned.
    function _legacySum(address account) internal view returns (uint256 total) {
        uint256[] memory ids = escrow.tokensOfOwner(account);
        for (uint256 i; i < ids.length; ++i) {
            total += escrow.balanceOfNFT(ids[i]);
        }
    }

    function _legacySumAt(address account, uint256 timestamp) internal view returns (uint256 total) {
        uint256[] memory ids = escrow.tokensOfOwner(account);
        for (uint256 i; i < ids.length; ++i) {
            total += escrow.balanceOfNFTAt(ids[i], timestamp);
        }
    }
}
