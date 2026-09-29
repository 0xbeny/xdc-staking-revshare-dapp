// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title VeVotesAdapter
/// @notice Read-only IVotes view over checkpointed veXDC weight (§3.5).
/// @dev Delegation does not exist in v1: weight is always self-held, because positions are
///      soulbound and per-tokenId. `delegate` reverts rather than silently no-op'ing.
///
///      Compatibility profile: timestamp clock; no delegation; `getPastVotes` /
///      `getPastTotalSupply` revert for `timepoint >= clock()` (ERC-5805). Voting weight is
///      the escrow's per-account checkpoint, so gas does not grow with `tokensOfOwner`.
contract VeVotesAdapter is IVotes {
    IVotingEscrow public immutable ESCROW;

    error DelegationNotSupported();
    error ZeroAddress();
    /// @dev ERC-5805 future / current lookup rejection.
    error ERC5805FutureLookup(uint256 timepoint, uint48 currentTimepoint);

    constructor(address escrow_) {
        if (escrow_ == address(0)) {
            revert ZeroAddress();
        }
        ESCROW = IVotingEscrow(escrow_);
    }

    function clock() public view returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function getVotes(address account) external view returns (uint256) {
        return ESCROW.weightOf(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        _requirePastTimepoint(timepoint);
        return ESCROW.weightOfAt(account, timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        _requirePastTimepoint(timepoint);
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

    function _requirePastTimepoint(uint256 timepoint) private view {
        uint48 current = clock();
        if (timepoint >= current) {
            revert ERC5805FutureLookup(timepoint, current);
        }
    }
}
