// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RevenueAdapterBase} from "./RevenueAdapterBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mode B2 — PullAdapter on a *dedicated fee Safe*. The Safe grants an allowance to this
///         immutable adapter only. `skim` sweeps the Safe's full balance: committed →
///         distributor, remainder → dApp treasury.
/// @dev Unified B2/B3 invariant (§3.2 #7): after a successful sweep the fee Safe's balance is
///      zero, so everything that ever enters that address is definitionally revenue. This is
///      also why the Safe must be dedicated — commingled treasury capital must never be taxed.
contract PullAdapter is RevenueAdapterBase {
    using SafeERC20 for IERC20;

    /// @notice The dedicated fee Safe. Must not be a general treasury Safe.
    address public immutable FEE_SAFE;

    constructor(
        address source_,
        address distributor_,
        address dappTreasury_,
        uint16 committedBps_,
        address[] memory tokens_,
        address feeSafe_
    ) RevenueAdapterBase(source_, distributor_, dappTreasury_, committedBps_, tokens_) {
        if (feeSafe_ == address(0)) {
            revert ZeroAddress();
        }
        FEE_SAFE = feeSafe_;
    }

    function skim(address token) external returns (uint256 committed, uint256 remainder) {
        _requireSupported(token);
        uint256 balance = IERC20(token).balanceOf(FEE_SAFE);
        if (balance == 0) {
            revert NothingToSkim();
        }

        IERC20(token).safeTransferFrom(FEE_SAFE, address(this), balance);
        return _splitAndForward(token, IERC20(token).balanceOf(address(this)));
    }
}
