// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {VeXDCDeployer} from "../script/VeXDCDeployer.sol";
import {FeeDistributor} from "../src/FeeDistributor.sol";
import {RevenueRegistry} from "../src/RevenueRegistry.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {ZapDepositor} from "../src/ZapDepositor.sol";
import {Attestor} from "../src/adapters/Attestor.sol";
import {FeeSplitter} from "../src/adapters/FeeSplitter.sol";
import {PullAdapter} from "../src/adapters/PullAdapter.sol";
import {PushAdapter} from "../src/adapters/PushAdapter.sol";
import {ZodiacFeeModule} from "../src/adapters/ZodiacFeeModule.sol";
import {VeVotesAdapter} from "../src/governance/VeVotesAdapter.sol";
import {IRevenueRegistry} from "../src/interfaces/IRevenueRegistry.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSafe} from "./mocks/MockSafe.sol";
import {MockWXDC} from "./mocks/MockWXDC.sol";

/// @notice Shared deployment harness: the exact wiring order used by the mainnet script.
abstract contract Base is Test {
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant MAX_LOCK = 104 weeks;
    uint256 internal constant MIN_LOCK = 1 weeks;

    // Deterministic starting point: Thursday 2026-01-01 00:00:00 UTC is not a week boundary,
    // which is exactly what we want — the system must not assume it starts aligned.
    uint256 internal constant GENESIS = 1_767_225_600; // 2026-01-01 00:00:00 UTC

    address internal timelock = makeAddr("timelock");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal keeper = makeAddr("keeper");
    address internal reporter = makeAddr("reporter");
    address internal dapp = makeAddr("dapp");
    address internal dappTreasury = makeAddr("dappTreasury");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    MockWXDC internal wxdc;
    MockERC20 internal usdc;

    VotingEscrow internal escrow;
    FeeDistributor internal distributor;
    RevenueRegistry internal registry;
    ZapDepositor internal zap;
    VeVotesAdapter internal votes;

    FeeSplitter internal splitter;
    PushAdapter internal pusher;
    PullAdapter internal puller;
    ZodiacFeeModule internal zodiac;
    Attestor internal attestor;
    MockSafe internal feeSafe;
    MockSafe internal feeSafeB3;

    function setUp() public virtual {
        vm.warp(GENESIS);

        wxdc = new MockWXDC();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Same wiring as the mainnet script: temporary admin deploys, wires, hands over, renounces.
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wxdc);
        rewardTokens[1] = address(usdc);

        VeXDCDeployer.Config memory config = VeXDCDeployer.Config({
            wxdc: address(wxdc),
            timelock: timelock,
            guardian: guardian,
            treasury: treasury,
            keeper: keeper,
            maxPenaltyBps: 5000,
            penaltySplitBps: 2000,
            rewardTokens: rewardTokens
        });

        VeXDCDeployer.Deployment memory d = VeXDCDeployer.deploy(config, address(this));
        VeXDCDeployer.handOverToGovernance(d, config, address(this));
        string memory failure = VeXDCDeployer.verify(d, config, address(this));
        require(bytes(failure).length == 0, failure);

        registry = d.registry;
        distributor = d.distributor;
        escrow = d.escrow;
        zap = d.zap;
        votes = d.votes;

        _deployAdapters();
        _fund();
    }

    function _deployAdapters() internal {
        address[] memory tokens = new address[](2);
        tokens[0] = address(wxdc);
        tokens[1] = address(usdc);

        feeSafe = new MockSafe();
        feeSafeB3 = new MockSafe();

        splitter = new FeeSplitter(dapp, address(distributor), dappTreasury, 3000, tokens);
        pusher = new PushAdapter(dapp, address(distributor), dappTreasury, 10_000, tokens);
        puller = new PullAdapter(dapp, address(distributor), dappTreasury, 2500, tokens, address(feeSafe));
        zodiac = new ZodiacFeeModule(dapp, address(distributor), dappTreasury, 2500, tokens, address(feeSafeB3));
        attestor = new Attestor(address(distributor), timelock, reporter);

        feeSafe.approveToken(address(wxdc), address(puller), type(uint256).max);
        feeSafe.approveToken(address(usdc), address(puller), type(uint256).max);
        feeSafeB3.enableModule(address(zodiac));

        vm.startPrank(timelock);
        registry.registerAdapter(address(splitter), dapp, IRevenueRegistry.Mode.SPLITTER, 3000, 1, "terms-b");
        registry.registerAdapter(address(pusher), dapp, IRevenueRegistry.Mode.PUSH, 10_000, 1, "terms-a");
        registry.registerAdapter(address(puller), dapp, IRevenueRegistry.Mode.PULL_SAFE, 2500, 1, "terms-b2");
        registry.registerAdapter(address(zodiac), dapp, IRevenueRegistry.Mode.ZODIAC_SAFE, 2500, 1, "terms-b3");
        registry.registerAdapter(address(attestor), dapp, IRevenueRegistry.Mode.ATTESTATION, 10_000, 1, "terms-c");
        vm.stopPrank();
    }

    function _fund() internal {
        address[4] memory users = [alice, bob, carol, dapp];
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 100_000_000 ether);
            wxdc.mint(users[i], 100_000_000 ether);
            usdc.mint(users[i], 100_000_000e6);
        }
        wxdc.mint(reporter, 100_000_000 ether);
        usdc.mint(reporter, 100_000_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _lock(address who, uint256 amount, uint256 duration) internal returns (uint256 tokenId) {
        vm.startPrank(who);
        wxdc.approve(address(escrow), amount);
        tokenId = escrow.createLock(amount, duration);
        vm.stopPrank();
    }

    function _notify(address token, uint256 amount) internal {
        deal(token, address(splitter), amount * 10_000 / 3000 + 1);
        vm.prank(keeper);
        splitter.skim(token);
    }

    /// @dev Pushes an exact amount into the current epoch's pot via the 100%-committed adapter.
    function _notifyExact(address token, uint256 amount) internal {
        deal(token, dapp, IERC20(token).balanceOf(dapp) + amount);
        vm.startPrank(dapp);
        IERC20(token).approve(address(pusher), amount);
        pusher.commitRevenue(token, amount);
        vm.stopPrank();
    }

    function _currentEpoch() internal view returns (uint256) {
        return block.timestamp / WEEK;
    }

    function _epochStart(uint256 epoch) internal pure returns (uint256) {
        return epoch * WEEK;
    }

    /// @dev Warps to the start of the next epoch, plus one second.
    function _nextEpoch() internal {
        vm.warp(_epochStart(_currentEpoch() + 1) + 1);
    }

    function _warpEpochs(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            _nextEpoch();
        }
    }

    function _claim(address who, uint256 tokenId, address token) internal returns (uint256) {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        vm.prank(who);
        (uint256[] memory amounts,) = distributor.claim(tokenId, tokens);
        return amounts[0];
    }
}
