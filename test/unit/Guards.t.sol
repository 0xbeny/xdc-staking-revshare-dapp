// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {RevenueRegistry} from "../../src/RevenueRegistry.sol";
import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {FeeSplitter} from "../../src/adapters/FeeSplitter.sol";
import {PullAdapter} from "../../src/adapters/PullAdapter.sol";
import {PushAdapter} from "../../src/adapters/PushAdapter.sol";
import {RevenueAdapterBase} from "../../src/adapters/RevenueAdapterBase.sol";
import {ZodiacFeeModule} from "../../src/adapters/ZodiacFeeModule.sol";
import {VeVotesAdapter} from "../../src/governance/VeVotesAdapter.sol";
import {IRevenueRegistry} from "../../src/interfaces/IRevenueRegistry.sol";
import {Base} from "../Base.t.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";
import {MockFalseReturnERC20, MockFeeOnTransferERC20} from "../mocks/MockWeirdERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Every input-validation and state guard across the system, one test each. Kept in
///         one file so a reviewer can see the whole revert surface at a glance.
contract GuardsTest is Base {
    address[] internal tokens;

    function setUp() public override {
        super.setUp();
        tokens.push(address(wxdc));
        tokens.push(address(usdc));
    }

    /*//////////////////////////////////////////////////////////////
                              VOTING ESCROW
    //////////////////////////////////////////////////////////////*/

    function test_escrow_zeroAddressGuards() public {
        vm.startPrank(timelock);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        escrow.setTier(address(0), VotingEscrow.Tier.CUSTODIAN);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        escrow.transferTimelock(address(0));
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        escrow.setOperator(address(0), true);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.ZeroAddress.selector);
        escrow.createLockFor(address(0), 1 ether, 4 weeks);
        vm.stopPrank();
    }

    function test_escrow_increaseAmountRejectsZero() public {
        uint256 tokenId = _lock(alice, 1 ether, 4 weeks);
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.ZeroAmount.selector);
        escrow.increaseAmount(tokenId, 0);
    }

    function test_escrow_expiredLockCannotBeIncreasedOrExtended() public {
        uint256 tokenId = _lock(alice, 1 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);

        vm.startPrank(alice);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.LockExpired.selector);
        escrow.increaseAmount(tokenId, 1 ether);
        vm.expectRevert(VotingEscrow.LockExpired.selector);
        escrow.increaseUnlockTime(tokenId, block.timestamp + 8 weeks);
        vm.stopPrank();

        assertEq(escrow.effectiveTime(tokenId), 0, "no effective time left once expired");
    }

    function test_escrow_previewExitOnExpiredAndClosedPositions() public {
        uint256 tokenId = _lock(alice, 100 ether, 4 weeks);
        vm.warp(escrow.locked(tokenId).end);

        (uint256 returned, uint256 penalty, uint256 bps) = escrow.previewExit(tokenId);
        assertEq(returned, 100 ether, "expired: the whole principal comes back");
        assertEq(penalty, 0);
        assertEq(bps, 0);

        vm.prank(alice);
        escrow.withdraw(tokenId);
        (returned, penalty, bps) = escrow.previewExit(tokenId);
        assertEq(returned, 0, "closed: nothing left to quote");
        assertEq(penalty, 0);
    }

    function test_escrow_totalSupplyBeforeGenesisIsZero() public view {
        assertEq(escrow.totalSupplyAt(GENESIS - 1), 0);
    }

    /// @dev The safety valve behind MAX_WEEK_STEPS: after more than 255 idle weeks a single
    ///      checkpoint cannot catch up, mutations refuse to run against stale history, and the
    ///      permissionless `checkpoint()` heals it in bounded steps.
    function test_escrow_staleHistoryIsRefusedThenHealedByCheckpoint() public {
        _lock(alice, 1 ether, 4 weeks);
        vm.warp(block.timestamp + 300 weeks);

        vm.startPrank(bob);
        wxdc.approve(address(escrow), 1 ether);
        vm.expectRevert(VotingEscrow.HistoryStale.selector);
        escrow.createLock(1 ether, 4 weeks);
        vm.stopPrank();

        escrow.checkpoint(); // 255 weeks
        escrow.checkpoint(); // the rest
        (,, uint64 ts) = escrow.pointHistory(escrow.epoch());
        assertEq(ts, block.timestamp, "history caught up");

        _lock(bob, 1 ether, 4 weeks);
    }

    /*//////////////////////////////////////////////////////////////
                             FEE DISTRIBUTOR
    //////////////////////////////////////////////////////////////*/

    function test_distributor_initializeRejectsZeroAddresses() public {
        FeeDistributor impl = new FeeDistributor();
        vm.expectRevert(FeeDistributor.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(FeeDistributor.initialize, (address(0), address(registry))));
        vm.expectRevert(FeeDistributor.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(FeeDistributor.initialize, (timelock, address(0))));
    }

    function test_distributor_adminZeroAddressGuards() public {
        FeeDistributor impl = new FeeDistributor();
        FeeDistributor fresh = FeeDistributor(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeCall(FeeDistributor.initialize, (timelock, address(registry)))
                )
            )
        );
        vm.startPrank(timelock);
        vm.expectRevert(FeeDistributor.ZeroAddress.selector);
        fresh.setEscrow(address(0));
        vm.expectRevert(FeeDistributor.ZeroAddress.selector);
        fresh.addRewardToken(address(0));
        vm.stopPrank();
    }

    function test_distributor_addRewardTokenIsIdempotent() public {
        uint256 before = distributor.rewardTokens().length;
        vm.prank(timelock);
        distributor.addRewardToken(address(usdc));
        assertEq(distributor.rewardTokens().length, before);
    }

    function test_distributor_unknownTokenIsRejectedOnEveryPath() public {
        address unknown = address(new MockERC20("X", "X", 18));
        uint256 tokenId = _lock(alice, 1 ether, 4 weeks);

        vm.prank(timelock);
        vm.expectRevert(FeeDistributor.UnknownRewardToken.selector);
        distributor.setAcceptingRevenue(unknown, false);

        vm.expectRevert(FeeDistributor.UnknownRewardToken.selector);
        distributor.settle(unknown, 1);

        address[] memory one = new address[](1);
        one[0] = unknown;
        vm.prank(alice);
        vm.expectRevert(FeeDistributor.UnknownRewardToken.selector);
        distributor.claim(tokenId, one);

        // An active adapter notifying a token the distributor does not know.
        address[] memory unk = new address[](1);
        unk[0] = unknown;
        FeeSplitter odd = new FeeSplitter(dapp, address(distributor), dappTreasury, 5000, unk);
        vm.prank(timelock);
        registry.registerAdapter(address(odd), dapp, IRevenueRegistry.Mode.SPLITTER, 5000, 1, "");
        MockERC20(unknown).mint(address(odd), 1 ether);
        vm.expectRevert(FeeDistributor.UnknownRewardToken.selector);
        odd.skim(unknown);
    }

    function test_distributor_tokenNotAcceptingAndZeroAmount() public {
        MockAdapter raw = new MockAdapter(address(distributor));
        vm.prank(timelock);
        registry.registerAdapter(address(raw), dapp, IRevenueRegistry.Mode.PUSH, 10_000, 1, "");

        vm.expectRevert(FeeDistributor.ZeroAmount.selector);
        raw.notify(address(usdc), 0);

        vm.prank(timelock);
        distributor.setAcceptingRevenue(address(usdc), false);
        vm.expectRevert(FeeDistributor.TokenNotAccepting.selector);
        raw.notify(address(usdc), 1);
    }

    function test_distributor_claimAndLockWithNothingPendingReturnsZero() public {
        uint256 tokenId = _lock(alice, 1 ether, 4 weeks);
        vm.prank(alice);
        assertEq(distributor.claimAndLock(tokenId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             REVENUE REGISTRY
    //////////////////////////////////////////////////////////////*/

    function test_registry_zeroAddressGuards() public {
        RevenueRegistry impl = new RevenueRegistry();
        vm.expectRevert(RevenueRegistry.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(RevenueRegistry.initialize, (address(0))));

        vm.prank(timelock);
        vm.expectRevert(RevenueRegistry.ZeroAddress.selector);
        registry.setDistributor(address(0));
    }

    function test_registry_unknownAdapterIsRejectedOnEveryPath() public {
        address ghost = makeAddr("ghost");
        vm.startPrank(timelock);
        vm.expectRevert(RevenueRegistry.UnknownAdapter.selector);
        registry.deactivateAdapter(ghost);
        vm.expectRevert(RevenueRegistry.UnknownAdapter.selector);
        registry.reactivateAdapter(ghost);
        vm.expectRevert(RevenueRegistry.UnknownAdapter.selector);
        registry.updateTerms(ghost, "x", 2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PERIPHERY CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    function test_periphery_constructorsRejectZeroAddresses() public {
        vm.expectRevert(ZapDepositor.ZeroAddress.selector);
        new ZapDepositor(address(0), address(escrow));
        vm.expectRevert(ZapDepositor.ZeroAddress.selector);
        new ZapDepositor(address(wxdc), address(0));

        vm.expectRevert(VeVotesAdapter.ZeroAddress.selector);
        new VeVotesAdapter(address(0));

        vm.expectRevert(RevenueAdapterBase.ZeroAddress.selector);
        new PullAdapter(dapp, address(distributor), dappTreasury, 2500, tokens, address(0));
        vm.expectRevert(RevenueAdapterBase.ZeroAddress.selector);
        new ZodiacFeeModule(dapp, address(distributor), dappTreasury, 2500, tokens, address(0));

        address[] memory withZero = new address[](1);
        withZero[0] = address(0);
        vm.expectRevert(RevenueAdapterBase.ZeroAddress.selector);
        new FeeSplitter(dapp, address(distributor), dappTreasury, 3000, withZero);
    }

    function test_zap_increaseRejectsZeroValue() public {
        vm.startPrank(alice);
        uint256 tokenId = zap.zapCreateLock{value: 1 ether}(4 weeks);
        vm.expectRevert(ZapDepositor.ZeroAmount.selector);
        zap.zapIncreaseAmount{value: 0}(tokenId);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 ADAPTERS
    //////////////////////////////////////////////////////////////*/

    function test_pushAdapterRejectsZeroAmount() public {
        vm.prank(dapp);
        vm.expectRevert(RevenueAdapterBase.NothingToSkim.selector);
        pusher.commitRevenue(address(usdc), 0);
    }

    function test_zodiacModuleRejectsEmptySafeAndFailedExecution() public {
        vm.expectRevert(RevenueAdapterBase.NothingToSkim.selector);
        zodiac.skim(address(usdc));

        deal(address(usdc), address(feeSafeB3), 1000e6);
        feeSafeB3.setExecFails(true);
        vm.expectRevert(ZodiacFeeModule.SafeExecutionFailed.selector);
        zodiac.skim(address(usdc));
        assertEq(usdc.balanceOf(address(feeSafeB3)), 1000e6, "a failed execution moves nothing");
    }

    function test_zodiacModuleRevertsWhenTransferReturnsFalse() public {
        MockFalseReturnERC20 weird = new MockFalseReturnERC20();
        address[] memory one = new address[](1);
        one[0] = address(weird);

        MockSafe safe = new MockSafe();
        ZodiacFeeModule module = new ZodiacFeeModule(dapp, address(distributor), dappTreasury, 2500, one, address(safe));
        safe.enableModule(address(module));

        weird.mint(address(safe), 1000 ether);
        vm.expectRevert(ZodiacFeeModule.SweepIncomplete.selector);
        module.skim(address(weird));
        assertEq(weird.balanceOf(address(safe)), 1000 ether, "funds stay in the fee Safe");
        assertEq(weird.balanceOf(address(module)), 0);
    }

    function test_escrowRejectsFeeOnTransferDeposits() public {
        MockFeeOnTransferERC20 fot = new MockFeeOnTransferERC20(1000); // 10% fee
        VotingEscrow local = new VotingEscrow(address(fot), address(distributor), treasury, timelock, 5000, 2000);

        fot.mint(alice, 10 ether);
        vm.startPrank(alice);
        fot.approve(address(local), 10 ether);
        vm.expectRevert(VotingEscrow.IncompleteTransfer.selector);
        local.createLock(10 ether, 4 weeks);
        vm.stopPrank();

        assertEq(local.totalLocked(), 0);
        assertEq(fot.balanceOf(address(local)), 0);
    }

    function test_escrowRejectsFeeOnTransferIncreaseAmount() public {
        MockFeeOnTransferERC20 fot = new MockFeeOnTransferERC20(0);
        VotingEscrow local = new VotingEscrow(address(fot), address(distributor), treasury, timelock, 5000, 2000);

        fot.mint(alice, 20 ether);
        vm.startPrank(alice);
        fot.approve(address(local), type(uint256).max);
        uint256 tokenId = local.createLock(10 ether, 4 weeks);
        fot.setFeeBps(1000);
        vm.expectRevert(VotingEscrow.IncompleteTransfer.selector);
        local.increaseAmount(tokenId, 5 ether);
        vm.stopPrank();

        assertEq(local.locked(tokenId).amount, 10 ether);
        assertEq(local.totalLocked(), 10 ether);
    }
}
