// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Base} from "../Base.t.sol";

/// @notice Conservation checks for exit / unvested forfeit forwarding.
///         `_settle` moves the exited slice of an epoch pot forward via `exitedWeightByEpoch`, and
///         `_creditUnvested` moves the `unvestedForfeitWeight` share forward; neither shrinks the
///         pot. These tests show the two moves never cover the same weight, so an epoch pot is
///         never over-committed and the last claimer is never short.
///
///         Every test asserts the CORRECT behaviour, so it fails if the double-count exists:
///          1. per epoch, payable weight + exited weight + unvested weight == snapshot supply
///             (each unit of weight is paid, forwarded by settle, or forwarded by harvest —
///             exactly once);
///          2. per epoch, paid-to-stayers + forwarded <= pot;
///          3. the distributor always holds at least what every position can still claim;
///          4. every position can drain its claims (the last claimer is never short) and
///             sum(claimed) <= totalNotified;
///          5. forfeited value is not stranded: it reaches the stayers up to rounding dust.
contract ForfeitAccountingTest is Base {
    address internal dave = makeAddr("dave");

    address[] internal owners;
    uint256[] internal ids;
    mapping(uint256 tokenId => uint256) internal claimedBy;

    uint256 internal constant R = 1000e6; // one week of USDC revenue

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _add(address who, uint256 amount, uint256 duration) internal returns (uint256 id) {
        if (wxdc.balanceOf(who) < amount) {
            wxdc.mint(who, amount);
        }
        id = _lock(who, amount, duration);
        owners.push(who);
        ids.push(id);
    }

    function _exit(uint256 i) internal {
        _completeEmergencyExit(owners[i], ids[i]);
    }

    function _settleAll(address token) internal {
        for (uint256 k; k < 4; ++k) {
            distributor.settle(token, 52);
        }
    }

    /// @dev Weight of `id` that the distributor will actually pay for epoch `e`.
    ///      An exit in `x` stops claims at `x - 7` (exclusive): `_claimEnd`.
    function _payableWeight(uint256 id, uint256 e) internal view returns (uint256) {
        uint256 x = escrow.exitEpoch(id);
        if (x != 0 && e + 7 >= x) {
            return 0;
        }
        return escrow.balanceOfNFTAt(id, _epochStart(e));
    }

    /// @dev The core check. Only meaningful for settled epochs.
    function _assertEpochConserved(address token, uint256 e) internal view {
        uint256 supply = escrow.totalSupplyAtWeek(_epochStart(e));
        uint256 pot = distributor.epochRevenue(token, e);
        if (supply == 0) {
            assertEq(pot, 0, "zero-supply epoch kept a pot after settlement");
            return;
        }
        uint256 sumW;
        uint256 paid;
        for (uint256 i; i < ids.length; ++i) {
            uint256 w = _payableWeight(ids[i], e);
            sumW += w;
            paid += (pot * w) / supply;
        }
        uint256 ex = escrow.exitedWeightByEpoch(e);
        uint256 un = escrow.unvestedForfeitWeight(e);
        // Disjoint and complete: no unit of weight is forwarded twice, none is stranded.
        assertEq(sumW + ex + un, supply, "weight paid/forwarded != supply (double count or strand)");
        uint256 moved = (pot * ex) / supply + (pot * un) / supply;
        assertLe(paid + moved, pot, "epoch pot over-committed");
    }

    function _assertAllSettledEpochsConserved(address token, uint256 fromEpoch) internal view {
        uint256 settled = distributor.settledEpoch(token);
        for (uint256 e = fromEpoch; e < settled; ++e) {
            _assertEpochConserved(token, e);
        }
    }

    /// @dev Balance and `accounted` cover every position's outstanding claim right now.
    function _assertSolvent(address token) internal view {
        uint256 owed;
        for (uint256 i; i < ids.length; ++i) {
            (uint256 amt,) = distributor.claimable(ids[i], token);
            owed += amt;
        }
        uint256 acc = distributor.accounted(token);
        assertGe(acc, owed, "accounted < outstanding claims (insolvent)");
        assertGe(IERC20(token).balanceOf(address(distributor)), acc, "balance < accounted");
        assertLe(distributor.totalClaimed(token), distributor.totalNotified(token), "claimed > notified");
        assertEq(acc, distributor.totalNotified(token) - distributor.totalClaimed(token), "accounted identity");
    }

    /// @dev Every position claims everything it can, starting from `start` (so any position
    ///      can be "last"). Reverts here would mean the last claimer is short.
    function _drain(address token, uint256 start) internal returns (uint256 total) {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256 n = ids.length;
        for (uint256 k; k < n; ++k) {
            uint256 i = (start + k) % n;
            for (uint256 guard; guard < 8; ++guard) {
                vm.prank(owners[i]);
                (uint256[] memory amounts, uint256 remaining) = distributor.claim(ids[i], tokens);
                claimedBy[ids[i]] += amounts[0];
                total += amounts[0];
                if (remaining == 0) {
                    break;
                }
            }
        }
        // After draining, nothing is owed and the books still balance.
        for (uint256 i; i < n; ++i) {
            (uint256 amt,) = distributor.claimable(ids[i], token);
            assertEq(amt, 0, "claimable left after drain");
        }
        _assertSolvent(token);
    }

    /// @dev Lets every forwarded slice land, get harvested, and vest.
    function _runOut(address token) internal {
        _nextEpoch();
        _settleAll(token);
        _warpEpochs(9);
        _settleAll(token);
        _warpEpochs(9);
        _settleAll(token);
    }

    /*//////////////////////////////////////////////////////////////
                (a) one exit inside a funded epoch
    //////////////////////////////////////////////////////////////*/

    function test_a_singleExit_remainingLockersDrainWholePot() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 52 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        uint256 c = _add(carol, 300_000 ether, 26 weeks);

        _nextEpoch();
        uint256 e = _currentEpoch();
        _notifyExact(address(usdc), R);
        _exit(2); // carol exits in the funded epoch: her slice of `e` is forfeited

        _nextEpoch();
        distributor.settle(address(usdc), 52);
        uint256 supply = escrow.totalSupplyAtWeek(_epochStart(e));
        uint256 slice = (R * escrow.exitedWeightByEpoch(e)) / supply;
        assertGt(slice, 0, "exit slice recorded");
        assertEq(distributor.epochRevenue(address(usdc), e), R, "settled pot is not shrunk (by design)");
        assertEq(distributor.epochRevenue(address(usdc), e + 1), slice, "slice forwarded exactly once");

        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        _assertSolvent(address(usdc));

        uint256 total = _drain(address(usdc), 0);
        assertEq(claimedBy[c], 0, "exiter received nothing from the forfeited epoch");
        assertLe(total, R, "paid more than notified");
        assertApproxEqAbs(total, R, 10, "forfeited slice reached the stayers");
    }

    /*//////////////////////////////////////////////////////////////
          (b) exit spanning the 7-epoch window (_creditUnvested fires)
    //////////////////////////////////////////////////////////////*/

    function test_b_exitAcrossVestingWindow_unvestedAndExitedAreDisjoint() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        uint256 c = _add(carol, 300_000 ether, 52 weeks);

        // Fund 9 consecutive epochs e0 .. e0+8, carol exits in e0+8 after its revenue.
        uint256 e0 = _currentEpoch() + 1;
        for (uint256 s; s < 9; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
            distributor.settle(address(usdc), 52); // interleave settlement, as keepers would
        }
        uint256 x = _currentEpoch();
        assertEq(x, e0 + 8);
        _exit(2);

        // Carol's weight is booked once per epoch: unvested for [x-7, x-1], exited for x.
        uint256 cw;
        for (uint256 e = e0; e <= x; ++e) {
            cw = escrow.balanceOfNFTAt(c, _epochStart(e));
            if (e == x) {
                assertEq(escrow.exitedWeightByEpoch(e), cw, "exit epoch -> exitedWeightByEpoch");
                assertEq(escrow.unvestedForfeitWeight(e), 0, "exit epoch not also unvested");
            } else if (e + 7 >= x) {
                assertEq(escrow.unvestedForfeitWeight(e), cw, "window epoch -> unvested");
                assertEq(escrow.exitedWeightByEpoch(e), 0, "window epoch not also exited");
            } else {
                assertEq(escrow.unvestedForfeitWeight(e), 0, "vested epoch not forfeited");
            }
        }

        _runOut(address(usdc));
        assertGe(distributor.unvestedForfeitCursor(address(usdc)), x, "harvest walked the window");
        _assertAllSettledEpochsConserved(address(usdc), first);
        _assertSolvent(address(usdc));

        uint256 expectedCarol = (R * escrow.balanceOfNFTAt(c, _epochStart(e0))) / escrow.totalSupplyAtWeek(_epochStart(e0));
        uint256 total = _drain(address(usdc), 2); // carol first, then alice, bob last
        assertEq(claimedBy[c], expectedCarol, "exiter keeps only the vested epoch e0");
        assertLe(total, 9 * R, "paid more than notified");
        assertApproxEqAbs(total, 9 * R, 60, "nothing stranded beyond dust");
    }

    /// @dev Same as (b), but nobody settles until long after the exit: harvest and settlement
    ///      then run in the same transaction over the same epochs.
    function test_b2_lateSettlement_sameTxSettleAndHarvest() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        _add(carol, 300_000 ether, 52 weeks);
        for (uint256 s; s < 9; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
        }
        _exit(2);
        _warpEpochs(12);
        _settleAll(address(usdc));
        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        _assertSolvent(address(usdc));
        uint256 total = _drain(address(usdc), 0);
        assertLe(total, 9 * R);
        assertApproxEqAbs(total, 9 * R, 60);
    }

    /*//////////////////////////////////////////////////////////////
                    (c) zero-supply carry-forward
    //////////////////////////////////////////////////////////////*/

    function test_c_zeroSupplyCarryThenExit() public {
        uint256 first = _currentEpoch();
        // Revenue before anyone is in a snapshot: epoch has zero supply.
        _notifyExact(address(usdc), R);
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        _add(carol, 300_000 ether, 52 weeks);

        _nextEpoch();
        _notifyExact(address(usdc), R);
        _exit(2); // carol exits in the epoch that also receives the carried pot
        _nextEpoch();
        distributor.settle(address(usdc), 52);
        assertEq(distributor.epochRevenue(address(usdc), first), 0, "zero-supply pot moved");
        assertEq(distributor.epochRevenue(address(usdc), first + 1), 2 * R, "carried + new");

        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        uint256 total = _drain(address(usdc), 1);
        assertLe(total, 2 * R);
        assertApproxEqAbs(total, 2 * R, 10);
    }

    /// @dev Everyone exits: every forwarded slice lands in zero-supply epochs and keeps
    ///      carrying until a new locker arrives, who then receives it once.
    function test_c2_everyoneExits_forfeitsCarryUntilNewLocker() public {
        uint256 first = _currentEpoch() + 1;
        uint256 a = _add(alice, 100_000 ether, 104 weeks);
        for (uint256 s; s < 3; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
        }
        _exit(0); // all three funded epochs are unvested or exited for alice
        _warpEpochs(3);
        _settleAll(address(usdc));

        uint256 d = _add(dave, 50_000 ether, 104 weeks);
        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        uint256 total = _drain(address(usdc), 0);
        assertEq(claimedBy[a], 0, "exiter paid nothing");
        assertLe(total, 3 * R, "paid more than notified");
        assertApproxEqAbs(claimedBy[d], 3 * R, 10, "newcomer receives the carried forfeits once");
    }

    /*//////////////////////////////////////////////////////////////
            (d) penalties synced into the next epoch (wxdc)
    //////////////////////////////////////////////////////////////*/

    function test_d_penaltyLandsInNextEpoch_withExitSliceOfSamePot() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        uint256 c = _add(carol, 300_000 ether, 104 weeks);

        _nextEpoch();
        uint256 e = _currentEpoch();
        _notifyExact(address(wxdc), 10_000 ether); // same token as the penalty
        uint256 toLockers;
        uint256 balBefore = wxdc.balanceOf(address(distributor));
        _exit(2);
        toLockers = wxdc.balanceOf(address(distributor)) - balBefore;
        assertGt(toLockers, 0, "penalty share arrived");

        uint256 credited = distributor.syncForfeiture(address(wxdc));
        assertEq(credited, toLockers);
        assertEq(distributor.epochRevenue(address(wxdc), e + 1), toLockers, "penalty in e+1");
        assertEq(escrow.balanceOfNFTAt(c, _epochStart(e + 1)), 0, "exiter not in e+1 snapshot");

        uint256 notified = distributor.totalNotified(address(wxdc));
        _runOut(address(wxdc));
        _assertAllSettledEpochsConserved(address(wxdc), first);
        uint256 total = _drain(address(wxdc), 0);
        assertEq(claimedBy[c], 0, "exiter receives none of its own penalty or slice");
        assertLe(total, notified);
        assertApproxEqAbs(total, notified, 10);
    }

    /// @dev Lazy sync: the penalty sits unaccounted for several epochs and is credited
    ///      wherever `currentEpoch + 1` is at sync time. Still never reaches the exiter.
    function test_d2_lazyPenaltySync() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        uint256 c = _add(carol, 300_000 ether, 104 weeks);
        _nextEpoch();
        _exit(2);
        _warpEpochs(3);
        _notifyExact(address(wxdc), 1 ether); // first touch syncs the penalty into current+1
        uint256 notified = distributor.totalNotified(address(wxdc));
        _runOut(address(wxdc));
        _assertAllSettledEpochsConserved(address(wxdc), first);
        uint256 total = _drain(address(wxdc), 2);
        assertEq(claimedBy[c], 0);
        assertLe(total, notified);
        assertApproxEqAbs(total, notified, 10);
    }

    /*//////////////////////////////////////////////////////////////
                    (e) several exits in one epoch
    //////////////////////////////////////////////////////////////*/

    function test_e_multipleExitsSameEpoch_plusOverlappingWindows() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        _add(carol, 300_000 ether, 52 weeks);
        _add(dave, 400_000 ether, 78 weeks);

        for (uint256 s; s < 5; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
        }
        _exit(1); // bob and carol in the same epoch
        _exit(2);
        for (uint256 s; s < 3; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
        }
        _exit(3); // dave later: his unvested window overlaps bob/carol's exit epoch

        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        _assertSolvent(address(usdc));
        uint256 total = _drain(address(usdc), 3);
        assertLe(total, 8 * R);
        assertApproxEqAbs(total, 8 * R, 80);
    }

    /// @dev Exit at exactly an epoch boundary second: the snapshot read and the supply read
    ///      must agree on whether the exiter is in that epoch.
    function test_e2_exitOnExactBoundary() public {
        uint256 first = _currentEpoch() + 1;
        _add(alice, 100_000 ether, 104 weeks);
        _add(bob, 200_000 ether, 104 weeks);
        for (uint256 s; s < 3; ++s) {
            _nextEpoch();
            _notifyExact(address(usdc), R);
        }
        vm.warp(_epochStart(_currentEpoch() + 1)); // exact boundary
        _exit(1);
        _notifyExact(address(usdc), R);
        _runOut(address(usdc));
        _assertAllSettledEpochsConserved(address(usdc), first);
        uint256 total = _drain(address(usdc), 0);
        assertLe(total, 4 * R);
        assertApproxEqAbs(total, 4 * R, 20);
    }

    /*//////////////////////////////////////////////////////////////
                              (f) fuzz
    //////////////////////////////////////////////////////////////*/

    function testFuzz_f_solvencyAndLastClaimerNeverShort(
        uint96[4] memory amounts,
        uint8[4] memory durWeeks,
        uint8[4] memory exitStep,
        uint40[12] memory revenue,
        uint8 settleMask,
        uint8 drainStart
    ) public {
        address[4] memory who = [alice, bob, carol, dave];
        uint256 first = _currentEpoch() + 1;
        for (uint256 i; i < 4; ++i) {
            uint256 amt = bound(uint256(amounts[i]), 1_000 ether, 1_000_000 ether);
            uint256 dur = bound(uint256(durWeeks[i]), 2, 104) * 1 weeks;
            _add(who[i], amt, dur);
        }
        uint256 notifiedUsdc;
        for (uint256 s; s < 12; ++s) {
            _nextEpoch();
            uint256 r = bound(uint256(revenue[s]), 0, 1e12);
            if (r > 0) {
                _notifyExact(address(usdc), r);
                notifiedUsdc += r;
            }
            for (uint256 i; i < 4; ++i) {
                if (exitStep[i] % 16 == s && escrow.exitEpoch(ids[i]) == 0 && !escrow.closed(ids[i])) {
                    if (escrow.locked(ids[i]).end > block.timestamp) {
                        _exit(i);
                    }
                }
            }
            if ((settleMask >> (s % 8)) & 1 == 1) {
                distributor.settle(address(usdc), 52);
                distributor.settle(address(wxdc), 52);
            }
        }
        _runOut(address(usdc));
        _settleAll(address(wxdc));

        _assertAllSettledEpochsConserved(address(usdc), first);
        _assertAllSettledEpochsConserved(address(wxdc), first);
        _assertSolvent(address(usdc));
        _assertSolvent(address(wxdc));

        uint256 paidUsdc = _drain(address(usdc), drainStart);
        _drain(address(wxdc), drainStart);
        assertLe(paidUsdc, notifiedUsdc, "usdc paid more than notified");
    }
}
