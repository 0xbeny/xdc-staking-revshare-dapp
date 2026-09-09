// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title EpochTime
/// @notice Week-aligned epoch arithmetic shared by the escrow and the distributor.
/// @dev Unix time 0 was a Thursday, so `t / WEEK * WEEK` is always Thursday 00:00 UTC,
///      which is the epoch boundary frozen in the v1 spec (§3.3).
library EpochTime {
    uint256 internal constant WEEK = 7 days;

    function epochOf(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / WEEK;
    }

    function startOfEpoch(uint256 epoch) internal pure returns (uint256) {
        return epoch * WEEK;
    }

    function floorWeek(uint256 timestamp) internal pure returns (uint256) {
        // Intentional floor-to-week: truncation is the point.
        // forge-lint: disable-next-line(divide-before-multiply)
        return (timestamp / WEEK) * WEEK;
    }

    function ceilWeek(uint256 timestamp) internal pure returns (uint256) {
        // Intentional ceil-to-week: truncation is the point.
        // forge-lint: disable-next-line(divide-before-multiply)
        return ((timestamp + WEEK - 1) / WEEK) * WEEK;
    }

    function currentEpoch() internal view returns (uint256) {
        return block.timestamp / WEEK;
    }
}
