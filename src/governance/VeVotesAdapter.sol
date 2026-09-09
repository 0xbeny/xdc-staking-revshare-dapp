// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title VeVotesAdapter
/// @notice Read-only IVotes view over checkpointed veXDC weight (§3.5).
/// @dev Delegation does not exist in v1: weight is always self-held, because positions are
///      soulbound and per-tokenId. `delegate` reverts rather than silently no-op'ing.
contract VeVotesAdapter is IVotes {
    IVotingEscrow public immutable ESCROW;

    error DelegationNotSupported();
    error ZeroAddress();

    constructor(address escrow_) {
        if (escrow_ == address(0)) {
            revert ZeroAddress();
        }
        ESCROW = IVotingEscrow(escrow_);
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function getVotes(address account) external view returns (uint256 total) {
        uint256[] memory ids = ESCROW.tokensOfOwner(account);
        for (uint256 i; i < ids.length; ++i) {
            total += ESCROW.balanceOfNFT(ids[i]);
        }
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256 total) {
        uint256[] memory ids = ESCROW.tokensOfOwner(account);
        for (uint256 i; i < ids.length; ++i) {
            total += ESCROW.balanceOfNFTAt(ids[i], timepoint);
        }
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        return ESCROW.totalSupplyAt(timepoint);
    }

    function delegates(address account) external pure returns (address) {
        return account;
    }

    function delegate(address) external pure {
        revert DelegationNotSupported();
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert DelegationNotSupported();
    }
}
