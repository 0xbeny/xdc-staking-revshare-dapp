// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "../test/mocks/MockERC20.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Apothem prep: deploys mock USDC (and optional governance placeholders via env).
///         Uses the canonical Apothem WXDC at `WXDC` — do not redeploy WXDC on Apothem.
///
/// Usage:
///   forge script script/ApothemMocks.s.sol:ApothemMocks --rpc-url xdc_apothem \
///     --account deployer --broadcast
contract ApothemMocks is Script {
    function run() external {
        address wxdc = vm.envAddress("WXDC");
        require(wxdc.code.length > 0, "WXDC must be an existing contract on Apothem");

        vm.startBroadcast();
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        // Mint test USDC to the deployer for revenue / reward rehearsals.
        usdc.mint(msg.sender, 1_000_000e6);
        vm.stopBroadcast();

        console2.log("=== Apothem mocks ===");
        console2.log("export WXDC=%s", wxdc);
        console2.log("export USDC=%s", address(usdc));
        console2.log("export REWARD_TOKENS=%s,%s", wxdc, address(usdc));
        console2.log("Set TIMELOCK / GUARDIAN / TREASURY / KEEPER to your Apothem EOAs, then:");
        console2.log("  make deploy-apothem");
    }
}
