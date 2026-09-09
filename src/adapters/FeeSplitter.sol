// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RevenueAdapterBase} from "./RevenueAdapterBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mode B — FeeSplitter (default). The dApp points its fee receiver at this contract;
///         anyone may `skim`. The splitter is the fee receiver, so its whole balance is
///         definitionally revenue and leaves in full on every skim.
contract FeeSplitter is RevenueAdapterBase {
    constructor(
        address source_,
        address distributor_,
        address dappTreasury_,
        uint16 committedBps_,
        address[] memory tokens_
    ) RevenueAdapterBase(source_, distributor_, dappTreasury_, committedBps_, tokens_) {}

    /// @notice Permissionless. Sweeps the full balance: committed → distributor, rest → dApp.
    function skim(address token) external returns (uint256 committed, uint256 remainder) {
        _requireSupported(token);
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            revert NothingToSkim();
        }
        return _splitAndForward(token, balance);
    }
}
