// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Constants
/// @notice Single source for week length and basis-point scale used across the system.
library Constants {
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant BPS = 10_000;
}
