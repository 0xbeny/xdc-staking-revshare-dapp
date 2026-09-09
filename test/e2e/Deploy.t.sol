// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Deploy} from "../../script/Deploy.s.sol";
import {VeXDCDeployer} from "../../script/VeXDCDeployer.sol";
import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";
import {MockWXDC} from "../mocks/MockWXDC.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Runs the real deployment script against a local chain and checks the outcome the
///         way a launch reviewer would.
/// @dev This test drives `Deploy.s.sol` through the same environment variables it reads in
///      production, which requires the env/file cheatcodes the linter flags as unsafe. That is
///      the point of the test, so the rule is disabled for this file only.
// forge-lint: disable-start(unsafe-cheatcode)
contract DeployScriptTest is Test {
    MockWXDC internal wxdc;
    MockERC20 internal usdc;
    MockSafe internal timelock;
    MockSafe internal guardian;
    address internal treasury = makeAddr("treasury");
    address internal keeper = makeAddr("keeper");

    function setUp() public {
        wxdc = new MockWXDC();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        timelock = new MockSafe();
        guardian = new MockSafe();

        vm.setEnv("WXDC", vm.toString(address(wxdc)));
        vm.setEnv("TIMELOCK", vm.toString(address(timelock)));
        vm.setEnv("GUARDIAN", vm.toString(address(guardian)));
        vm.setEnv("TREASURY", vm.toString(treasury));
        vm.setEnv("KEEPER", vm.toString(keeper));
        vm.setEnv("MAX_PENALTY_BPS", "5000");
        vm.setEnv("PENALTY_SPLIT_BPS", "2000");
        vm.setEnv("REWARD_TOKENS", string.concat(vm.toString(address(wxdc)), ",", vm.toString(address(usdc))));
    }

    /// @dev `vm.setEnv` mutates the shared process environment, so every env-driven scenario
    ///      runs sequentially inside this one test rather than racing across parallel tests.
    function test_deployScript_preflightGuardsThenHappyPath() public {
        // One script instance reused for every guard: `expectRevert` must directly precede the
        // reverting call, and a CREATE in between would consume it.
        Deploy script = new Deploy();

        // Guard: a penalty cap above the hard clamp is refused before anything is deployed.
        vm.setEnv("MAX_PENALTY_BPS", "5001");
        vm.expectRevert(
            abi.encodeWithSelector(VeXDCDeployer.InvalidConfig.selector, "maxPenaltyBps > HARD_MAX_PENALTY_BPS")
        );
        script.run();
        vm.setEnv("MAX_PENALTY_BPS", "5000");

        // Guard: a 6-decimal token is not a wrapped native.
        vm.setEnv("WXDC", vm.toString(address(usdc)));
        vm.expectRevert(abi.encodeWithSelector(VeXDCDeployer.InvalidConfig.selector, "wxdc decimals != 18"));
        script.run();
        vm.setEnv("WXDC", vm.toString(address(wxdc)));

        // Guard: on chain id 50 the governance seats must be contracts, never EOAs.
        address eoa = makeAddr("eoa-timelock");
        vm.chainId(50);
        vm.setEnv("TIMELOCK", vm.toString(eoa));
        vm.expectRevert(abi.encodeWithSelector(Deploy.GovernanceMustBeAContract.selector, "TIMELOCK", eoa));
        script.run();
        vm.setEnv("TIMELOCK", vm.toString(address(timelock)));
        vm.chainId(31_337);

        // Happy path.
        script.run();

        string memory path = string.concat("./deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        VotingEscrow escrow = VotingEscrow(vm.parseJsonAddress(json, ".votingEscrow"));
        FeeDistributor distributor = FeeDistributor(vm.parseJsonAddress(json, ".feeDistributor"));

        assertEq(escrow.token(), address(wxdc));
        assertEq(escrow.distributor(), address(distributor));
        assertEq(escrow.timelock(), address(timelock));
        assertEq(escrow.treasury(), treasury);
        assertEq(escrow.maxPenaltyBps(), 5000);
        assertEq(escrow.penaltySplitBps(), 2000);

        assertTrue(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertTrue(distributor.hasRole(distributor.PAUSER_ROLE(), address(guardian)));
        assertTrue(distributor.hasRole(distributor.KEEPER_ROLE(), keeper));
        assertTrue(distributor.isRewardToken(address(wxdc)));
        assertTrue(distributor.isRewardToken(address(usdc)));

        // The deploying account keeps nothing.
        address deployer = address(script);
        assertFalse(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(distributor.hasRole(distributor.UPGRADER_ROLE(), deployer));
        assertFalse(distributor.hasRole(distributor.PAUSER_ROLE(), deployer));
        assertFalse(distributor.hasRole(distributor.KEEPER_ROLE(), deployer));
        vm.removeFile(path);
    }

    function _good() internal view returns (VeXDCDeployer.Config memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        return VeXDCDeployer.Config({
            wxdc: address(wxdc),
            timelock: address(timelock),
            guardian: address(guardian),
            treasury: treasury,
            keeper: keeper,
            maxPenaltyBps: 5000,
            penaltySplitBps: 2000,
            rewardTokens: tokens
        });
    }

    function test_validateRejectsEveryBadField() public {
        VeXDCDeployer.validate(_good());

        VeXDCDeployer.Config memory bad;

        bad = _good();
        bad.wxdc = address(0);
        _expectInvalid(bad, "wxdc");

        bad = _good();
        bad.wxdc = makeAddr("not-a-contract");
        _expectInvalid(bad, "wxdc is not a contract");

        bad = _good();
        bad.timelock = address(0);
        _expectInvalid(bad, "timelock");

        bad = _good();
        bad.guardian = address(0);
        _expectInvalid(bad, "guardian");

        bad = _good();
        bad.treasury = address(0);
        _expectInvalid(bad, "treasury");

        bad = _good();
        bad.keeper = address(0);
        _expectInvalid(bad, "keeper");

        bad = _good();
        bad.maxPenaltyBps = 5001;
        _expectInvalid(bad, "maxPenaltyBps > HARD_MAX_PENALTY_BPS");

        bad = _good();
        bad.penaltySplitBps = 5001;
        _expectInvalid(bad, "penaltySplitBps > 50%");

        bad = _good();
        bad.rewardTokens = new address[](0);
        _expectInvalid(bad, "no reward tokens");
    }

    function _expectInvalid(VeXDCDeployer.Config memory c, string memory reason) internal {
        vm.expectRevert(abi.encodeWithSelector(VeXDCDeployer.InvalidConfig.selector, reason));
        this.validateExternal(c);
    }

    function validateExternal(VeXDCDeployer.Config memory c) external view {
        VeXDCDeployer.validate(c);
    }
}
// forge-lint: disable-end(unsafe-cheatcode)
