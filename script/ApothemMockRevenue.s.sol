// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeSplitter} from "../src/adapters/FeeSplitter.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Apothem helper: mint mock USDC to a registered FeeSplitter and skim.
///
/// Usage:
///   export USDC=0x...
///   export FEE_SPLITTER=0x...
///   export AMOUNT=1000000000   # 1000 USDC (6 decimals); optional, default 1000e6
///   forge script script/ApothemMockRevenue.s.sol:ApothemMockRevenue --rpc-url xdc_apothem \
///     --account deployer --broadcast
///
/// Or via Make (after wiring the target):
///   make simulate-apothem-revenue DEPLOYER_ACCOUNT=deployer
contract ApothemMockRevenue is Script {
    function run() external {
        address usdcAddr = vm.envAddress("USDC");
        address splitterAddr = vm.envAddress("FEE_SPLITTER");
        uint256 amount = vm.envOr("AMOUNT", uint256(1_000e6));

        require(usdcAddr.code.length > 0, "USDC missing code");
        require(splitterAddr.code.length > 0, "FEE_SPLITTER missing code");

        MockERC20 usdc = MockERC20(usdcAddr);
        FeeSplitter splitter = FeeSplitter(splitterAddr);

        uint16 bps = splitter.COMMITTED_BPS();
        uint256 expectedCommitted = (amount * uint256(bps)) / 10_000;

        vm.startBroadcast();
        usdc.mint(splitterAddr, amount);
        (uint256 committed, uint256 remainder) = splitter.skim(usdcAddr);
        vm.stopBroadcast();

        console2.log("=== Apothem mock revenue ===");
        console2.log("splitter            ", splitterAddr);
        console2.log("usdc                ", usdcAddr);
        console2.log("amount              ", amount);
        console2.log("committedBps        ", uint256(bps));
        console2.log("expectedCommitted   ", expectedCommitted);
        console2.log("skimmedCommitted    ", committed);
        console2.log("skimmedRemainder    ", remainder);
        require(committed == expectedCommitted, "committed mismatch");
    }
}
