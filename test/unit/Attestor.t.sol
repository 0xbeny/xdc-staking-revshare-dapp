// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Attestor} from "../../src/adapters/Attestor.sol";
import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AttestorTest is Base {
    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));
        _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        vm.prank(reporter);
        usdc.approve(address(attestor), type(uint256).max);
    }

    function test_postRevenueIsAtomicRecordPlusTransfer() public {
        uint64 sourceEpoch = uint64(_currentEpoch() - 1);
        vm.prank(reporter);
        attestor.postRevenue(dapp, address(usdc), sourceEpoch, 5000e6, 0, keccak256("report"));

        Attestor.Record memory r = attestor.records(dapp, address(usdc), sourceEpoch);
        assertEq(r.net, 5000e6);
        assertEq(r.distributionEpoch, uint64(_currentEpoch()));
        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 5000e6);
        assertEq(usdc.balanceOf(address(attestor)), 0, "no custody between calls");
    }

    /// @dev Exactly one immutable record per (dapp, token, sourceEpoch). Duplicates revert; there
    ///      is no pre-finalization superseding.
    function test_duplicateRecordReverts() public {
        uint64 sourceEpoch = uint64(_currentEpoch() - 1);
        vm.startPrank(reporter);
        attestor.postRevenue(dapp, address(usdc), sourceEpoch, 5000e6, 0, "");
        vm.expectRevert(Attestor.DuplicateRecord.selector);
        attestor.postRevenue(dapp, address(usdc), sourceEpoch, 6000e6, 0, "");
        vm.stopPrank();
    }

    /// @dev The reporter can never choose a past distribution epoch — it is assigned at receipt.
    function test_reporterCannotChooseTheDistributionEpoch() public {
        uint64 oldSource = uint64(_currentEpoch() - 1);
        _nextEpoch();
        _nextEpoch();

        uint256 receiptEpoch = _currentEpoch();
        vm.prank(reporter);
        attestor.postRevenue(dapp, address(usdc), oldSource, 5000e6, 0, "");

        assertEq(distributor.epochRevenue(address(usdc), oldSource), 0, "sourceEpoch is metadata only");
        assertEq(distributor.epochRevenue(address(usdc), receiptEpoch), 5000e6, "receipt epoch decides");
    }

    function test_sourceEpochMustBeClosed() public {
        vm.prank(reporter);
        vm.expectRevert(Attestor.SourceEpochNotClosed.selector);
        attestor.postRevenue(dapp, address(usdc), uint64(_currentEpoch()), 1000e6, 0, "");
    }

    /// @dev Errors are corrected against a *later* source period, never by a clawback.
    function test_positiveAdjustmentAgainstALaterPeriodTransfersMore() public {
        uint64 first = uint64(_currentEpoch() - 1);
        vm.prank(reporter);
        attestor.postRevenue(dapp, address(usdc), first, 5000e6, 0, "");

        _nextEpoch();
        uint64 later = uint64(_currentEpoch() - 1);
        uint256 receiptEpoch = _currentEpoch();

        vm.prank(reporter);
        uint256 net = attestor.postRevenue(dapp, address(usdc), later, 4000e6, 1000e6, "under-reported earlier");

        assertEq(net, 5000e6);
        assertEq(distributor.epochRevenue(address(usdc), receiptEpoch), 5000e6);
    }

    function test_negativeAdjustmentOffsetsTheLaterTransferAndNeverClawsBack() public {
        uint64 first = uint64(_currentEpoch() - 1);
        vm.prank(reporter);
        attestor.postRevenue(dapp, address(usdc), first, 5000e6, 0, "");
        uint256 heldAfterFirst = usdc.balanceOf(address(distributor));

        _nextEpoch();
        uint64 later = uint64(_currentEpoch() - 1);

        vm.prank(reporter);
        uint256 net = attestor.postRevenue(dapp, address(usdc), later, 4000e6, -1000e6, "over-reported earlier");

        assertEq(net, 3000e6, "the correction is netted off the later transfer");
        assertGt(usdc.balanceOf(address(distributor)), heldAfterFirst, "the distributor is never drained");
    }

    function test_negativeNetReverts() public {
        vm.prank(reporter);
        vm.expectRevert(Attestor.NegativeNet.selector);
        attestor.postRevenue(dapp, address(usdc), uint64(_currentEpoch() - 1), 1000e6, -2000e6, "");
    }

    function test_zeroNetRecordsWithoutTransferring() public {
        uint64 sourceEpoch = uint64(_currentEpoch() - 1);
        vm.prank(reporter);
        attestor.postRevenue(dapp, address(usdc), sourceEpoch, 1000e6, -1000e6, "fully offset");

        assertTrue(attestor.posted(attestor.key(dapp, address(usdc), sourceEpoch)));
        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 0);
    }

    function test_onlyReporterRoleCanPost() public {
        bytes32 role = attestor.REPORTER_ROLE();
        uint64 sourceEpoch = uint64(_currentEpoch() - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        attestor.postRevenue(dapp, address(usdc), sourceEpoch, 1000e6, 0, "");
    }

    /// @dev The reporter is an AccessControl role administered by the timelock, like every other
    ///      role in the system: rotation is grant + revoke, and several reporters can coexist.
    function test_onlyTimelockAdministersTheReporterRole() public {
        bytes32 role = attestor.REPORTER_ROLE();
        bytes32 admin = attestor.DEFAULT_ADMIN_ROLE();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, admin));
        attestor.grantRole(role, alice);

        vm.startPrank(timelock);
        attestor.grantRole(role, bob);
        attestor.revokeRole(role, reporter);
        vm.stopPrank();

        assertTrue(attestor.hasRole(role, bob));
        assertFalse(attestor.hasRole(role, reporter));
    }

    function test_attestorHasNoUpgradePathAndNoMutableRecords() public {
        (bool ok,) = address(attestor).call(abi.encodeWithSignature("upgradeTo(address)", address(1)));
        assertFalse(ok);
        (ok,) = address(attestor)
            .call(
                abi.encodeWithSignature(
                    "amendRecord(address,address,uint64,uint256)", dapp, address(usdc), uint64(1), 1
                )
            );
        assertFalse(ok);
    }
}
