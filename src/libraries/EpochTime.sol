// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Constants} from "./Constants.sol";

/// @title EpochTime
/// @notice Week-aligned epoch arithmetic shared by the escrow and the distributor.
/// @dev Unix time 0 was a Thursday, so `t / WEEK * WEEK` is always Thursday 00:00 UTC,
///      which is the epoch boundary frozen in the v1 spec (§3.3).
library EpochTime {
    function epochOf(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / Constants.WEEK;
    }

    function startOfEpoch(uint256 epoch) internal pure returns (uint256) {
        return epoch * Constants.WEEK;
    }

    function floorWeek(uint256 timestamp) internal pure returns (uint256) {
        // Intentional floor-to-week: truncation is the point.
        // forge-lint: disable-next-line(divide-before-multiply)
        return (timestamp / Constants.WEEK) * Constants.WEEK;
    }

    function ceilWeek(uint256 timestamp) internal pure returns (uint256) {
        // Intentional ceil-to-week: truncation is the point.
        // forge-lint: disable-next-line(divide-before-multiply)
        return ((timestamp + Constants.WEEK - 1) / Constants.WEEK) * Constants.WEEK;
    }

    function currentEpoch() internal view returns (uint256) {
        return block.timestamp / Constants.WEEK;
    }
}
