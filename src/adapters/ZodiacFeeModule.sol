// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAvatar} from "../interfaces/IAvatar.sol";
import {RevenueAdapterBase} from "./RevenueAdapterBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mode B3 — Zodiac module on a *dedicated fee Safe* (§3.2 #7).
/// @dev B3 never operates on a general treasury Safe. The module's only power over the Safe is
///      to move a supported token out of it, in full, split by the immutable committed bps.
///      After a successful sweep the fee Safe's balance is zero — the same invariant as B2.
contract ZodiacFeeModule is RevenueAdapterBase {
    /// @notice The dedicated fee Safe this module is installed on.
    address public immutable FEE_SAFE;

    error SafeExecutionFailed();
    /// @notice Safe `exec` returned success but the fee Safe was not emptied / adapter did not
    ///         receive the pre-skim balance (e.g. a token that returns `false` on `transfer`).
    error SweepIncomplete();

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

    function skim(address token) external nonReentrant returns (uint256 committed, uint256 remainder) {
        _requireSupported(token);
        uint256 balance = IERC20(token).balanceOf(FEE_SAFE);
        if (balance == 0) {
            revert NothingToSkim();
        }

        uint256 before = IERC20(token).balanceOf(address(this));
        bool ok = IAvatar(FEE_SAFE)
            .execTransactionFromModule(token, 0, abi.encodeCall(IERC20.transfer, (address(this), balance)), 0);
        if (!ok) {
            revert SafeExecutionFailed();
        }

        // Raw `transfer` via the Safe does not go through SafeERC20. Tokens that return `false`
        // (or otherwise fail to move the full balance) must not look like a successful skim.
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        if (IERC20(token).balanceOf(FEE_SAFE) != 0 || received != balance) {
            revert SweepIncomplete();
        }

        return _splitAndForward(token, received);
    }
}
