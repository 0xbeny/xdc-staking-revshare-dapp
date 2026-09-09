// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {EpochTime} from "../../src/libraries/EpochTime.sol";
import {Base} from "../Base.t.sol";

/// @dev Locks the shared WEEK/BPS constants so escrow, distributor, and epoch math cannot drift.
contract ConstantsTest is Base {
    function test_weekIsSharedAcrossEscrowDistributorAndEpochTime() public view {
        assertEq(escrow.WEEK(), 7 days);
        assertEq(distributor.WEEK(), 7 days);
        assertEq(escrow.WEEK(), distributor.WEEK());
        assertEq(EpochTime.epochOf(7 days), 1);
        assertEq(EpochTime.startOfEpoch(1), escrow.WEEK());
    }

    function test_bpsIsTenThousandEverywhere() public view {
        assertEq(escrow.BPS(), 10_000);
        assertEq(splitter.COMMITTED_BPS() <= 10_000, true);
        // Registry and adapters must reject above the same scale (exercised in unit tests);
        // the numeric source of truth is Constants.BPS.
        assertEq(Constants.BPS, 10_000);
        assertEq(Constants.WEEK, 7 days);
    }
}
