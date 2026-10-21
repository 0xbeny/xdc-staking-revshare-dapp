// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {RevenueAdapterBase} from "./RevenueAdapterBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mode A — Push. The dApp itself decides an amount and pushes it. The pushed amount is
///         by definition the committed amount, so it is forwarded whole.
contract PushAdapter is RevenueAdapterBase {
    using SafeERC20 for IERC20;

    event RevenuePushed(address indexed token, uint256 amount);

    error NotSource();

    constructor(
        address source_,
        address distributor_,
        address dappTreasury_,
        uint16 committedBps_,
        address[] memory tokens_
    ) RevenueAdapterBase(source_, distributor_, dappTreasury_, committedBps_, tokens_) {}

    /// @dev Restricted to the registered source so a third party cannot inflate a dApp's
    ///      lifetime contribution record.
    function commitRevenue(address token, uint256 amount) external nonReentrant {
        if (_msgSender() != SOURCE) {
            revert NotSource();
        }
        _requireSupported(token);
        if (amount == 0) {
            revert NothingToSkim();
        }

        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;

        IERC20(token).forceApprove(DISTRIBUTOR, received);
        // forge-lint: disable-next-line(reentrancy-no-eth)
        IFeeDistributor(DISTRIBUTOR).notifyRevenue(token, received);
        emit RevenuePushed(token, received);
    }
}
