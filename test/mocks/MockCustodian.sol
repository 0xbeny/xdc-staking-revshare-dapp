// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice A CUSTODIAN-tier contract: creates and holds its own locks, like a Safe with the
///         standard compatibility fallback handler.
contract MockCustodian is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @notice A contract that cannot receive an ERC721. Whitelisting it is a misconfiguration, and
///         `_safeMint` surfaces that at lock time rather than after funds are committed.
contract MockNonReceiver {}
