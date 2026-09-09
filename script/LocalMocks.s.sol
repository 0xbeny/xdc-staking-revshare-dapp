// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockSafe} from "../test/mocks/MockSafe.sol";
import {MockWXDC} from "../test/mocks/MockWXDC.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Local-only: deploys mock WXDC/USDC and two Safe-shaped governance contracts so the
///         real `Deploy` script can be rehearsed on anvil exactly as it will run on mainnet.
contract LocalMocks is Script {
    function run() external {
        vm.startBroadcast();
        MockWXDC wxdc = new MockWXDC();
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockSafe timelock = new MockSafe();
        MockSafe guardian = new MockSafe();
        vm.stopBroadcast();

        console2.log("export WXDC=%s", address(wxdc));
        console2.log("export USDC=%s", address(usdc));
        console2.log("export TIMELOCK=%s", address(timelock));
        console2.log("export GUARDIAN=%s", address(guardian));
        console2.log("export REWARD_TOKENS=%s,%s", address(wxdc), address(usdc));
    }
}
