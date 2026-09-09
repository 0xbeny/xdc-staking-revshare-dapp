// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @title RevenueAdapterBase
/// @notice Shared skeleton for every revenue adapter. Adapters are immutable: their
///         `(source, tokens, committedBps, distributor, dappTreasury)` tuple is fixed at
///         construction and there is no setter, no owner and no upgrade path. Changing a
///         commitment means deploying a new adapter and re-registering it (§3.2).
abstract contract RevenueAdapterBase is Context {
    using SafeERC20 for IERC20;

    uint256 internal constant BPS = 10_000;

    /// @notice The dApp whose revenue this adapter commits.
    address public immutable SOURCE;
    /// @notice Immutable distribution target.
    address public immutable DISTRIBUTOR;
    /// @notice Where the uncommitted remainder goes.
    address public immutable DAPP_TREASURY;
    /// @notice Share of swept revenue committed to lockers, in basis points.
    uint16 public immutable COMMITTED_BPS;

    address[] private _tokens;
    mapping(address token => bool) private _supported;

    event Skimmed(address indexed token, uint256 total, uint256 committed, uint256 remainder);

    error ZeroAddress();
    error InvalidBps();
    error NoTokens();
    error UnsupportedToken(address token);
    error NothingToSkim();

    constructor(
        address source_,
        address distributor_,
        address dappTreasury_,
        uint16 committedBps_,
        address[] memory tokens_
    ) {
        if (source_ == address(0) || distributor_ == address(0) || dappTreasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (committedBps_ == 0 || committedBps_ > BPS) {
            revert InvalidBps();
        }
        if (tokens_.length == 0) {
            revert NoTokens();
        }

        SOURCE = source_;
        DISTRIBUTOR = distributor_;
        DAPP_TREASURY = dappTreasury_;
        COMMITTED_BPS = committedBps_;

        for (uint256 i = 0; i < tokens_.length; ++i) {
            if (tokens_[i] == address(0)) {
                revert ZeroAddress();
            }
            if (_supported[tokens_[i]]) {
                continue;
            }
            _supported[tokens_[i]] = true;
            _tokens.push(tokens_[i]);
        }
    }

    function supportedTokens() external view returns (address[] memory) {
        return _tokens;
    }

    function isSupported(address token) public view returns (bool) {
        return _supported[token];
    }

    function _requireSupported(address token) internal view {
        if (!_supported[token]) {
            revert UnsupportedToken(token);
        }
    }

    /// @dev Splits `total` held by this adapter and pushes the committed share to the
    ///      distributor. The remainder always leaves in the same transaction, so an adapter
    ///      never accumulates a balance between skims.
    function _splitAndForward(address token, uint256 total) internal returns (uint256 committed, uint256 remainder) {
        committed = (total * COMMITTED_BPS) / BPS;
        remainder = total - committed;

        if (committed > 0) {
            IERC20(token).forceApprove(DISTRIBUTOR, committed);
            IFeeDistributor(DISTRIBUTOR).notifyRevenue(token, committed);
        }
        if (remainder > 0) {
            IERC20(token).safeTransfer(DAPP_TREASURY, remainder);
        }

        emit Skimmed(token, total, committed, remainder);
    }
}
