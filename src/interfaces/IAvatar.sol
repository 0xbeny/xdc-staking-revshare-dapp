// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal Zodiac avatar surface (Gnosis Safe `execTransactionFromModule`).
interface IAvatar {
    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success);
}
