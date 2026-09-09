// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFeeDistributor} from "../../src/interfaces/IFeeDistributor.sol";

/// @notice A registrable adapter with no guards of its own, so the distributor's own input
///         validation can be exercised directly.
contract MockAdapter {
    IFeeDistributor public immutable DISTRIBUTOR;

    constructor(address distributor_) {
        DISTRIBUTOR = IFeeDistributor(distributor_);
    }

    function notify(address token, uint256 amount) external {
        DISTRIBUTOR.notifyRevenue(token, amount);
    }
}
