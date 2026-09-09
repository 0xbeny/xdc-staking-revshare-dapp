// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Attestor} from "../src/adapters/Attestor.sol";
import {FeeSplitter} from "../src/adapters/FeeSplitter.sol";
import {PullAdapter} from "../src/adapters/PullAdapter.sol";
import {PushAdapter} from "../src/adapters/PushAdapter.sol";
import {ZodiacFeeModule} from "../src/adapters/ZodiacFeeModule.sol";
import {IRevenueRegistry} from "../src/interfaces/IRevenueRegistry.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys one immutable revenue adapter for a dApp.
///
/// The adapter is deployed here; **registering** it is a separate governance action, because
/// registration is what makes it able to notify revenue. `logRegistrationCall` prints the exact
/// calldata for the timelock to execute.
///
/// Required environment: DISTRIBUTOR, ADAPTER_MODE (A|B|B2|B3|C), DAPP, DAPP_TREASURY,
/// COMMITTED_BPS, REWARD_TOKENS. Modes B2/B3 also require FEE_SAFE. Mode C requires
/// SYSTEM_ACCESS and REPORTER (then a timelock `grantRole` on SystemAccess).
contract DeployAdapter is Script {
    error UnknownMode(string mode);
    error FeeSafeRequired();

    function run() external {
        string memory mode = vm.envString("ADAPTER_MODE");
        address distributor = vm.envAddress("DISTRIBUTOR");
        address[] memory tokens = vm.envAddress("REWARD_TOKENS", ",");

        vm.startBroadcast();
        address adapter;
        IRevenueRegistry.Mode registryMode;

        if (_eq(mode, "A")) {
            adapter = address(
                new PushAdapter(
                    vm.envAddress("DAPP"),
                    distributor,
                    vm.envAddress("DAPP_TREASURY"),
                    SafeCast.toUint16(vm.envUint("COMMITTED_BPS")),
                    tokens
                )
            );
            registryMode = IRevenueRegistry.Mode.PUSH;
        } else if (_eq(mode, "B")) {
            adapter = address(
                new FeeSplitter(
                    vm.envAddress("DAPP"),
                    distributor,
                    vm.envAddress("DAPP_TREASURY"),
                    SafeCast.toUint16(vm.envUint("COMMITTED_BPS")),
                    tokens
                )
            );
            registryMode = IRevenueRegistry.Mode.SPLITTER;
        } else if (_eq(mode, "B2")) {
            adapter = address(
                new PullAdapter(
                    vm.envAddress("DAPP"),
                    distributor,
                    vm.envAddress("DAPP_TREASURY"),
                    SafeCast.toUint16(vm.envUint("COMMITTED_BPS")),
                    tokens,
                    _feeSafe()
                )
            );
            registryMode = IRevenueRegistry.Mode.PULL_SAFE;
        } else if (_eq(mode, "B3")) {
            adapter = address(
                new ZodiacFeeModule(
                    vm.envAddress("DAPP"),
                    distributor,
                    vm.envAddress("DAPP_TREASURY"),
                    SafeCast.toUint16(vm.envUint("COMMITTED_BPS")),
                    tokens,
                    _feeSafe()
                )
            );
            registryMode = IRevenueRegistry.Mode.ZODIAC_SAFE;
        } else if (_eq(mode, "C")) {
            adapter = address(new Attestor(distributor, vm.envAddress("SYSTEM_ACCESS")));
            registryMode = IRevenueRegistry.Mode.ATTESTATION;
        } else {
            revert UnknownMode(mode);
        }
        vm.stopBroadcast();

        console2.log("adapter deployed:", adapter);
        console2.log("mode:", uint8(registryMode));
        console2.log("");
        console2.log("Next step (timelock action) - registry.registerAdapter calldata:");
        console2.logBytes(
            abi.encodeWithSignature(
                "registerAdapter(address,address,uint8,uint16,uint32,bytes32)",
                adapter,
                vm.envOr("DAPP", address(0)),
                uint8(registryMode),
                SafeCast.toUint16(vm.envOr("COMMITTED_BPS", uint256(0))),
                SafeCast.toUint32(vm.envOr("ADAPTER_VERSION", uint256(1))),
                vm.envOr("TERMS_HASH", bytes32(0))
            )
        );

        if (registryMode == IRevenueRegistry.Mode.ATTESTATION) {
            console2.log("");
            console2.log("Mode C: timelock must grant REPORTER on SystemAccess for this attestor:");
            console2.logBytes(
                abi.encodeWithSignature(
                    "grantRole(address,bytes32,address)",
                    adapter,
                    keccak256("REPORTER_ROLE"),
                    vm.envAddress("REPORTER")
                )
            );
        }

        if (registryMode == IRevenueRegistry.Mode.PULL_SAFE) {
            console2.log("");
            console2.log("Mode B2: the dedicated fee Safe must approve this adapter:");
            console2.logBytes(abi.encodeWithSignature("approve(address,uint256)", adapter, type(uint256).max));
        }
        if (registryMode == IRevenueRegistry.Mode.ZODIAC_SAFE) {
            console2.log("");
            console2.log("Mode B3: the dedicated fee Safe must enable this module:");
            console2.logBytes(abi.encodeWithSignature("enableModule(address)", adapter));
        }
    }

    function _feeSafe() internal view returns (address safe) {
        safe = vm.envOr("FEE_SAFE", address(0));
        if (safe == address(0)) {
            revert FeeSafeRequired();
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
