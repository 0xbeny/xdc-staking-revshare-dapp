// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {FeeDistributor} from "../../src/FeeDistributor.sol";
import {VotingEscrow} from "../../src/VotingEscrow.sol";
import {ZapDepositor} from "../../src/ZapDepositor.sol";
import {PushAdapter} from "../../src/adapters/PushAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWXDC} from "../mocks/MockWXDC.sol";

/// @notice Drives the system through random-but-legal action sequences, tracking the ghost state
///         the invariants are asserted against.
contract Handler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant MAX_LOCK = 104 weeks;

    VotingEscrow public immutable ESCROW;
    ZapDepositor public immutable ZAP;
    FeeDistributor public immutable DISTRIBUTOR;
    PushAdapter public immutable PUSHER;
    MockWXDC public immutable WXDC;
    MockERC20 public immutable USDC;
    address public immutable DAPP;
    address public immutable TIMELOCK;
    address public immutable CAP_GUARDIAN;

    address[3] public actors;
    uint256[] public tokenIds;

    // Ghost state.
    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    uint256 public ghostPenalised;
    mapping(uint256 tokenId => uint256) public ghostMaxCursor;
    uint256 public cursorViolations;

    constructor(
        VotingEscrow escrow_,
        ZapDepositor zap_,
        FeeDistributor distributor_,
        PushAdapter pusher_,
        MockWXDC wxdc_,
        MockERC20 usdc_,
        address dapp_,
        address timelock_,
        address capGuardian_,
        address[3] memory actors_
    ) {
        ESCROW = escrow_;
        ZAP = zap_;
        DISTRIBUTOR = distributor_;
        PUSHER = pusher_;
        WXDC = wxdc_;
        USDC = usdc_;
        DAPP = dapp_;
        TIMELOCK = timelock_;
        CAP_GUARDIAN = capGuardian_;
        actors = actors_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _tokenId(uint256 seed) internal view returns (uint256) {
        if (tokenIds.length == 0) {
            return 0;
        }
        return tokenIds[seed % tokenIds.length];
    }

    function tokenIdCount() external view returns (uint256) {
        return tokenIds.length;
    }

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    function createLock(uint256 actorSeed, uint96 amount, uint8 weeksToLock) external {
        address actor = _actor(actorSeed);
        uint256 headroom = _stakingHeadroom();
        // Cap can be lowered below one MIN_LOCK; skip rather than revert under fail_on_revert.
        if (headroom < 1 ether) {
            return;
        }
        uint256 value = bound(amount, 1 ether, headroom < 500_000 ether ? headroom : 500_000 ether);
        uint256 duration = bound(weeksToLock, 1, 104) * WEEK;

        WXDC.mint(actor, value);
        vm.startPrank(actor);
        WXDC.approve(address(ZAP), value);
        uint256 tokenId = ZAP.lockWXDC(value, duration);
        vm.stopPrank();

        tokenIds.push(tokenId);
        ghostDeposited += value;
    }

    function increaseAmount(uint256 tokenSeed, uint96 amount) external {
        uint256 tokenId = _tokenId(tokenSeed);
        if (tokenId == 0 || ESCROW.closed(tokenId)) {
            return;
        }
        if (ESCROW.locked(tokenId).end <= block.timestamp) {
            return;
        }

        uint256 headroom = _stakingHeadroom();
        if (headroom < 1 ether) {
            return;
        }

        address owner = ESCROW.ownerOf(tokenId);
        uint256 value = bound(amount, 1 ether, headroom < 100_000 ether ? headroom : 100_000 ether);
        WXDC.mint(owner, value);

        vm.startPrank(owner);
        WXDC.approve(address(ESCROW), value);
        ESCROW.increaseAmount(tokenId, value);
        vm.stopPrank();
        ghostDeposited += value;
    }

    function _stakingHeadroom() internal view returns (uint256) {
        uint256 locked = ESCROW.totalLocked();
        uint256 cap = ESCROW.stakingCap();
        return cap > locked ? cap - locked : 0;
    }

    function extendLock(uint256 tokenSeed, uint8 weeksToAdd) external {
        uint256 tokenId = _tokenId(tokenSeed);
        if (tokenId == 0 || ESCROW.closed(tokenId)) {
            return;
        }
        VotingEscrow.Lock memory lock = ESCROW.locked(tokenId);
        if (lock.end <= block.timestamp) {
            return;
        }

        uint256 target = block.timestamp + bound(weeksToAdd, 1, 104) * WEEK;
        if (target <= lock.end) {
            return;
        }

        vm.prank(ESCROW.ownerOf(tokenId));
        ESCROW.increaseUnlockTime(tokenId, target);
    }

    function withdraw(uint256 tokenSeed) external {
        uint256 tokenId = _tokenId(tokenSeed);
        if (tokenId == 0 || ESCROW.closed(tokenId)) {
            return;
        }
        VotingEscrow.Lock memory lock = ESCROW.locked(tokenId);
        if (lock.amount == 0 || lock.end > block.timestamp) {
            return;
        }

        vm.prank(ESCROW.ownerOf(tokenId));
        ESCROW.withdraw(tokenId);
        ghostWithdrawn += lock.amount;
    }

    function emergencyExit(uint256 tokenSeed) external {
        uint256 tokenId = _tokenId(tokenSeed);
        if (tokenId == 0 || ESCROW.closed(tokenId)) {
            return;
        }
        VotingEscrow.Lock memory lock = ESCROW.locked(tokenId);
        if (lock.amount == 0 || lock.end <= block.timestamp) {
            return;
        }

        (uint256 returned, uint256 penalty,) = ESCROW.previewExit(tokenId);
        vm.prank(ESCROW.ownerOf(tokenId));
        ESCROW.emergencyExit(tokenId);
        ghostWithdrawn += returned;
        ghostPenalised += penalty;
    }

    function notifyRevenue(uint256 tokenSeed, uint96 amount, bool useUsdc) external {
        address token = useUsdc ? address(USDC) : address(WXDC);
        uint256 value = bound(amount, 1e6, 100_000e6);
        if (!useUsdc) {
            value = bound(amount, 0.01 ether, 10_000 ether);
        }

        if (useUsdc) {
            USDC.mint(DAPP, value);
        } else {
            WXDC.mint(DAPP, value);
        }
        vm.startPrank(DAPP);
        IERC20(token).approve(address(PUSHER), value);
        PUSHER.commitRevenue(token, value);
        vm.stopPrank();
        tokenSeed; // silence unused
    }

    function claim(uint256 tokenSeed, bool useUsdc) external {
        uint256 tokenId = _tokenId(tokenSeed);
        if (tokenId == 0) {
            return;
        }
        address token = useUsdc ? address(USDC) : address(WXDC);

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        vm.prank(ESCROW.ownerOf(tokenId));
        DISTRIBUTOR.claim(tokenId, tokens);

        uint256 cursor = DISTRIBUTOR.claimCursor(tokenId, token);
        if (cursor < ghostMaxCursor[tokenId]) {
            cursorViolations++;
        }
        if (cursor > ghostMaxCursor[tokenId]) {
            ghostMaxCursor[tokenId] = cursor;
        }
    }

    function settle(bool useUsdc, uint8 maxEpochs) external {
        DISTRIBUTOR.settle(useUsdc ? address(USDC) : address(WXDC), bound(maxEpochs, 1, 52));
    }

    function syncForfeiture(bool useUsdc) external {
        DISTRIBUTOR.syncForfeiture(useUsdc ? address(USDC) : address(WXDC));
    }

    function checkpoint() external {
        ESCROW.checkpoint();
    }

    function setPenaltyParams(uint16 cap, uint16 split) external {
        vm.startPrank(TIMELOCK);
        // Global penalty is monotonically non-increasing.
        ESCROW.setMaxPenaltyBps(bound(cap, 0, ESCROW.maxPenaltyBps()));
        ESCROW.setPenaltySplitBps(bound(split, 0, 5000));
        vm.stopPrank();
    }

    /// @dev Random legal staking-cap moves: raises always; decreases only above totalLocked.
    function setStakingCap(bool viaGuardian, uint256 rawCap) external {
        address admin = viaGuardian ? CAP_GUARDIAN : TIMELOCK;
        uint256 locked = ESCROW.totalLocked();
        uint256 current = ESCROW.stakingCap();

        uint256 newCap;
        if (rawCap % 2 == 0) {
            // Increase (or no-op): anywhere from current up.
            uint256 room = type(uint256).max - current;
            if (room == 0) {
                return;
            }
            newCap = current + bound(rawCap, 0, room > 1e24 ? 1e24 : room);
        } else {
            // Decrease: must keep newCap > totalLocked.
            if (locked >= current - 1 || current <= locked + 1) {
                return;
            }
            newCap = bound(rawCap, locked + 1, current - 1);
        }

        vm.prank(admin);
        ESCROW.setStakingCap(newCap);
    }

    function warp(uint32 secondsForward) external {
        vm.warp(block.timestamp + bound(secondsForward, 1 hours, 6 weeks));
    }
}
