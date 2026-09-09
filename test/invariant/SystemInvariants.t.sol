// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {Base} from "../Base.t.sol";
import {Handler} from "./Handler.sol";

/// @notice The named invariant set from spec §7, asserted against randomised action sequences.
contract SystemInvariantsTest is Base {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));

        handler = new Handler(escrow, distributor, pusher, wxdc, usdc, dapp, timelock, [alice, bob, carol]);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = Handler.createLock.selector;
        selectors[1] = Handler.increaseAmount.selector;
        selectors[2] = Handler.extendLock.selector;
        selectors[3] = Handler.withdraw.selector;
        selectors[4] = Handler.emergencyExit.selector;
        selectors[5] = Handler.notifyRevenue.selector;
        selectors[6] = Handler.claim.selector;
        selectors[7] = Handler.settle.selector;
        selectors[8] = Handler.syncForfeiture.selector;
        selectors[9] = Handler.checkpoint.selector;
        selectors[10] = Handler.warp.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev Principal safety: every unit of principal the escrow still owes is still held by it.
    function invariant_escrowHoldsExactlyItsOutstandingPrincipal() public view {
        assertEq(wxdc.balanceOf(address(escrow)), escrow.totalLocked());
    }

    /// @dev Principal in == principal out + principal still locked.
    function invariant_principalIsConserved() public view {
        assertEq(handler.ghostDeposited(), handler.ghostWithdrawn() + handler.ghostPenalised() + escrow.totalLocked());
    }

    /// @dev `weight <= principal` and `effectiveTime <= MAX_LOCK` for every live position.
    function invariant_weightNeverExceedsPrincipal() public view {
        uint256 n = handler.tokenIdCount();
        for (uint256 i; i < n; ++i) {
            uint256 tokenId = handler.tokenIds(i);
            VotingEscrow.Lock memory lock = escrow.locked(tokenId);
            assertLe(escrow.balanceOfNFT(tokenId), lock.amount);
            assertLe(escrow.effectiveTime(tokenId), MAX_LOCK);
        }
    }

    /// @dev The global aggregate is exactly the sum of the individual positions.
    function invariant_totalSupplyEqualsSumOfPositions() public view {
        uint256 n = handler.tokenIdCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += escrow.balanceOfNFT(handler.tokenIds(i));
        }
        assertEq(escrow.totalSupply(), sum);
    }

    /// @dev `penaltyBps <= min(positionCap, maxPenaltyBps) <= HARD_MAX_PENALTY_BPS`.
    function invariant_penaltyStaysWithinTheClamps() public view {
        assertLe(escrow.maxPenaltyBps(), escrow.HARD_MAX_PENALTY_BPS());
        assertLe(escrow.penaltySplitBps(), escrow.HARD_MAX_PENALTY_SPLIT_BPS());

        uint256 n = handler.tokenIdCount();
        for (uint256 i; i < n; ++i) {
            uint256 tokenId = handler.tokenIds(i);
            (,, uint256 bps) = escrow.previewExit(tokenId);
            assertLe(bps, escrow.effectivePenaltyCapBps(tokenId));
            assertLe(bps, escrow.HARD_MAX_PENALTY_BPS());
        }
    }

    /// @dev Conservation per token: the held balance always covers every outstanding obligation,
    ///      and claims never exceed notifications.
    function invariant_distributorConservesValue() public view {
        address[2] memory tokens = [address(usdc), address(wxdc)];
        for (uint256 i; i < 2; ++i) {
            address token = tokens[i];
            uint256 notified = distributor.totalNotified(token);
            uint256 claimed = distributor.totalClaimed(token);
            assertLe(claimed, notified, "claims never exceed notifications");
            assertEq(distributor.accounted(token), notified - claimed, "accounted == notified - claimed");
            assertGe(_balanceOf(token, address(distributor)), distributor.accounted(token), "balance covers it");
        }
    }

    /// @dev An epoch's forfeited weight can never exceed that epoch's snapshot supply, or a
    ///      settlement could move more than the whole pot into the forfeiture bucket.
    function invariant_exitedWeightNeverExceedsEpochSupply() public view {
        uint256 current = _currentEpoch();
        uint256 from = current > 60 ? current - 60 : 0;
        for (uint256 e = from; e <= current; ++e) {
            uint256 exited = escrow.exitedWeightByEpoch(e);
            if (exited == 0) {
                continue;
            }
            assertLe(exited, escrow.totalSupplyAtWeek(_epochStart(e)));
        }
    }

    /// @dev Claim cursors are monotonic: no epoch is ever replayed.
    function invariant_claimCursorsAreMonotonic() public view {
        assertEq(handler.cursorViolations(), 0);
    }

    /// @dev Settled epochs are always strictly in the past.
    function invariant_settlementNeverRunsAhead() public view {
        assertLe(distributor.settledEpoch(address(usdc)), _currentEpoch());
        assertLe(distributor.settledEpoch(address(wxdc)), _currentEpoch());
    }

    /// @dev The escrow's penalty destinations are the two immutable addresses and nothing else.
    function invariant_penaltyDestinationsAreImmutable() public view {
        assertEq(escrow.distributor(), address(distributor));
        assertEq(escrow.treasury(), treasury);
    }

    /// @dev No adapter or fee Safe ever accumulates a balance between actions.
    function invariant_adaptersHoldNoBalance() public view {
        assertEq(usdc.balanceOf(address(pusher)), 0);
        assertEq(wxdc.balanceOf(address(pusher)), 0);
        assertEq(usdc.balanceOf(address(splitter)), 0);
        assertEq(usdc.balanceOf(address(attestor)), 0);
    }

    function _balanceOf(address token, address who) internal view returns (uint256) {
        (, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        return abi.decode(ret, (uint256));
    }
}
