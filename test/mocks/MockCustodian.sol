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

/// @notice Rejects a mint that arrives before the lock and the owner list are written.
contract LockReadyCustodian is IERC721Receiver {
    error LockNotReady();

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        (bool lockOk, bytes memory lockData) =
            msg.sender.staticcall(abi.encodeWithSignature("locked(uint256)", tokenId));
        (bool listOk, bytes memory listData) =
            msg.sender.staticcall(abi.encodeWithSignature("tokensOfOwner(address)", address(this)));
        if (!lockOk || !listOk) {
            revert LockNotReady();
        }
        (uint128 amount,) = abi.decode(lockData, (uint128, uint64));
        if (amount == 0) {
            revert LockNotReady();
        }
        uint256[] memory ids = abi.decode(listData, (uint256[]));
        if (ids.length != 1 || ids[0] != tokenId) {
            revert LockNotReady();
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @notice A contract that cannot receive an ERC721. Whitelisting it is a misconfiguration, and
///         `_safeMint` surfaces that at lock time rather than after funds are committed.
contract MockNonReceiver {}
