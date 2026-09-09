// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeeDistributorKeeperTest is Base {
    uint256 internal a;

    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));
        a = _lock(alice, 100_000 ether, 52 weeks);

        vm.startPrank(alice);
        distributor.setKeepAtMaxLock(a, true);
        distributor.setAutoCompound(a, true);
        escrow.setOperator(address(distributor), true);
        vm.stopPrank();

        _nextEpoch();
    }

    function _intoKeeperWindow() internal {
        vm.warp(_epochStart(_currentEpoch() + 1) - 1 hours);
    }

    function _ids() internal view returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    /// @dev §5 step 2/3: the extension runs *before* the boundary, so the snapshot for n+1 sees
    ///      full weight.
    function test_keepAtMaxLockRunsPreBoundaryAndIsSnapshottedAtFullWeight() public {
        _intoKeeperWindow();
        uint256 epoch = _currentEpoch();

        vm.prank(keeper);
        distributor.batchKeepAtMaxLock(_ids(), epoch);

        uint256 nextStart = _epochStart(epoch + 1);
        vm.warp(nextStart);
        escrow.checkpoint();

        uint256 full = (100_000 ether / MAX_LOCK) * MAX_LOCK;
        assertApproxEqRel(escrow.totalSupplyAtWeek(nextStart), full, 1e15, "snapshotted at full weight");
    }

    function test_keepAtMaxLockRevertsOutsideTheWindow() public {
        // Start of the epoch — far from the boundary.
        vm.warp(_epochStart(_currentEpoch()) + 1);
        vm.prank(keeper);
        vm.expectRevert(FeeDistributor.OutsideKeeperWindow.selector);
        distributor.batchKeepAtMaxLock(_ids(), _currentEpoch());
    }

    function test_keeperTxIsEpochGuardedAgainstStaleSubmission() public {
        _intoKeeperWindow();
        vm.prank(keeper);
        vm.expectRevert(FeeDistributor.StaleEpoch.selector);
        distributor.batchKeepAtMaxLock(_ids(), _currentEpoch() - 1);
    }

    /// @dev A missed window is never retroactively corrected: that week's decayed weight stands.
    function test_missedWindowIsNeverRetroactivelyCorrected() public {
        uint256 missedEpoch = _currentEpoch();
        uint256 boundary = _epochStart(missedEpoch + 1);

        // Keeper does nothing. Boundary passes.
        vm.warp(boundary + 1);
        escrow.checkpoint();
        uint256 decayed = escrow.totalSupplyAtWeek(boundary);

        // Keeper catches up in the *next* window.
        vm.warp(_epochStart(_currentEpoch() + 1) - 1 hours);
        vm.prank(keeper);
        distributor.batchKeepAtMaxLock(_ids(), _currentEpoch());

        assertEq(escrow.totalSupplyAtWeek(boundary), decayed, "the missed snapshot is immutable");
    }

    function test_onlyKeeperRoleCanRunBatches() public {
        _intoKeeperWindow();
        bytes32 role = distributor.KEEPER_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        distributor.batchKeepAtMaxLock(_ids(), _currentEpoch());
    }

    function test_keeperSkipsPositionsThatDidNotOptIn() public {
        uint256 b = _lock(bob, 100_000 ether, 52 weeks);
        uint256 endBefore = escrow.locked(b).end;

        _intoKeeperWindow();
        uint256[] memory ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;

        vm.prank(keeper);
        distributor.batchKeepAtMaxLock(ids, _currentEpoch());

        assertEq(escrow.locked(b).end, endBefore, "an un-opted-in position is untouched");
        assertGt(escrow.locked(a).end, _epochStart(_currentEpoch()) + 52 weeks);
    }

    /// @dev A revert inside one position must not take the whole batch down.
    function test_keeperBatchToleratesIndividualFailures() public {
        // Revoke the operator right so alice's extension reverts inside the batch.
        vm.prank(alice);
        escrow.setOperator(address(distributor), false);

        _intoKeeperWindow();
        vm.prank(keeper);
        distributor.batchKeepAtMaxLock(_ids(), _currentEpoch()); // must not revert
    }

    /// @dev §5 step 4: compounds first earn in the *next* snapshot.
    function test_autoCompoundRunsPostBoundaryAndEarnsFromTheNextSnapshot() public {
        _notifyExact(address(wxdc), 500 ether);
        _nextEpoch();

        uint256 epoch = _currentEpoch();
        uint256 principalBefore = escrow.locked(a).amount;
        uint256 snapshotBefore = escrow.totalSupplyAtWeek(_epochStart(epoch));

        vm.prank(keeper);
        distributor.batchCompound(_ids(), epoch);

        assertEq(escrow.locked(a).amount, principalBefore + 500 ether);
        assertEq(escrow.totalSupplyAtWeek(_epochStart(epoch)), snapshotBefore, "this epoch's snapshot is closed");
    }

    function test_batchCompoundIsEpochGuarded() public {
        vm.prank(keeper);
        vm.expectRevert(FeeDistributor.StaleEpoch.selector);
        distributor.batchCompound(_ids(), _currentEpoch() + 1);
    }

    function test_batchCompoundSkipsPositionsThatDidNotOptIn() public {
        uint256 b = _lock(bob, 100_000 ether, 52 weeks);
        _nextEpoch();
        _notifyExact(address(wxdc), 500 ether);
        _nextEpoch();

        uint256 bPrincipal = escrow.locked(b).amount;
        uint256[] memory ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;

        vm.prank(keeper);
        distributor.batchCompound(ids, _currentEpoch());
        assertEq(escrow.locked(b).amount, bPrincipal, "un-opted-in positions are untouched");
    }
}
