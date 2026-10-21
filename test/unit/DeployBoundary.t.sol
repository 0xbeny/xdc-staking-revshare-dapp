// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VeXDCDeployer} from "../../script/VeXDCDeployer.sol";
import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {Base} from "../Base.t.sol";

/// @dev Adversarial checks at Foundry broadcast boundaries that unit wiring cannot insert.
contract DeployBoundaryTest is Base {
    function test_attackerCannotCaptureDepositorBetweenEscrowAndZap() public {
        VotingEscrow fresh =
            new VotingEscrow(address(wxdc), address(distributor), treasury, timelock, guardian, 5000, 2000);
        assertEq(fresh.bootstrapAdmin(), address(this));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(VotingEscrow.NotAuthorized.selector);
        fresh.setDepositor(attacker);

        ZapDepositor localZap = new ZapDepositor(address(wxdc), address(fresh));
        fresh.setDepositor(address(localZap));
        assertEq(fresh.depositor(), address(localZap));
        assertEq(fresh.bootstrapAdmin(), address(0));

        vm.expectRevert(VotingEscrow.DepositorAlreadySet.selector);
        fresh.setDepositor(attacker);
    }

    /// @dev Chain 50 shares `validate` with the continue script. An EOA timelock must be refused
    ///      there. Apothem (chain 51) still accepts an EOA.
    function test_mainnetValidateRejectsAnEoaTimelock() public {
        VeXDCDeployer.Config memory config = _config(makeAddr("eoa-timelock"), address(feeSafe));

        vm.chainId(50);
        vm.expectRevert(
            abi.encodeWithSelector(VeXDCDeployer.GovernanceMustBeAContract.selector, "TIMELOCK", config.timelock)
        );
        this.validate(config);

        vm.chainId(51);
        this.validate(config);
    }

    function test_mainnetValidateRejectsAnEoaGuardian() public {
        VeXDCDeployer.Config memory config = _config(address(feeSafe), makeAddr("eoa-guardian"));

        vm.chainId(50);
        vm.expectRevert(
            abi.encodeWithSelector(VeXDCDeployer.GovernanceMustBeAContract.selector, "GUARDIAN", config.guardian)
        );
        this.validate(config);
    }

    function test_mainnetValidateRejectsASharedTimelockAndGuardian() public {
        VeXDCDeployer.Config memory config = _config(address(feeSafe), address(feeSafe));

        vm.chainId(50);
        vm.expectRevert(
            abi.encodeWithSelector(VeXDCDeployer.GovernanceMustBeAContract.selector, "TIMELOCK", config.timelock)
        );
        this.validate(config);
    }

    function validate(VeXDCDeployer.Config memory config) external view {
        VeXDCDeployer.validate(config);
    }

    function _config(address timelock_, address guardian_) internal view returns (VeXDCDeployer.Config memory config) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        config = VeXDCDeployer.Config({
            wxdc: address(wxdc),
            timelock: timelock_,
            guardian: guardian_,
            treasury: treasury,
            keeper: keeper,
            maxPenaltyBps: 5000,
            penaltySplitBps: 2000,
            rewardTokens: tokens
        });
    }
}
