// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EpochTime} from "./libraries/EpochTime.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title VotingEscrow — soulbound veXDC
/// @notice Immutable core of the veXDC system. Holds all user principal, owns the penalty
///         formula, the penalty parameters (behind immutable clamps) and the two immutable
///         penalty destinations. Nothing outside this contract can move principal.
///
/// @dev Documented diffs from the Curve/Velodrome `VotingEscrow` reference this forks:
///
///      1. **Effective-time clamp (spec §3.1).** Unlock times round UP to a week boundary, so
///         `end - now` can exceed `MAX_LOCK` by up to `WEEK - 1`. Weight is therefore
///         `slope * min(end - t, MAX_LOCK)` rather than `slope * (end - t)`. Globally this is
///         modelled as a *deferred slope activation*: a lock contributes a flat
///         `slope * MAX_LOCK` bias with zero slope until `end - MAX_LOCK`, at which point its
///         slope switches on. Both `end` and `end - MAX_LOCK` are week-aligned (MAX_LOCK is a
///         whole number of weeks), so both land on the existing `slopeChanges` schedule.
///
///      2. **Weight uses the truncated slope everywhere.** `weight = (amount / MAX_LOCK) * eff`.
///         Using the same truncated slope for the per-position read and the global aggregate
///         makes the sum of positions *exactly* equal to total supply, which the distributor's
///         conservation invariant depends on. It also gives `weight <= principal` for free.
///
///      3. **Per-position user history stores the lock, not a (bias, slope) pair.** Historic
///         weight is recomputed from `(amount, end)` with the same clamped formula, so a
///         position's past weight can never drift from the formula.
///
///      4. **No block-number interpolation.** Time-based weighting only (spec §3.1).
///
///      5. **No split, no merge, no `wrapInto`, no transfer carve-out** (spec §3.1 #2/#9).
///
///      6. **Positions are never burned.** A withdrawn or exited position keeps its tokenId and
///         owner with a zeroed lock, so already-finalized reward claims survive the exit.
contract VotingEscrow is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using EpochTime for uint256;

    /// @notice Contract eligibility tiers (spec §3.1 #10). EOAs are never listed.
    enum Tier {
        NONE,
        CUSTODIAN,
        WRAPPER
    }

    struct Lock {
        uint128 amount;
        uint64 end;
        uint64 penaltyCapBps;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant WEEK = 7 days;
    uint256 public constant MIN_LOCK = 1 weeks;
    uint256 public constant MAX_LOCK = 104 weeks;
    uint256 public constant BPS = 10_000;

    /// @notice Hard ceiling on the tunable penalty cap. Immutable, unreachable by governance.
    uint256 public constant HARD_MAX_PENALTY_BPS = 5000;
    /// @notice Hard ceiling on the treasury share of a forfeiture. Immutable.
    uint256 public constant HARD_MAX_PENALTY_SPLIT_BPS = 5000;

    /// @notice Upper bound on weeks traversed by a single checkpoint pass (~4.9 years).
    uint256 private constant MAX_WEEK_STEPS = 255;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    address public immutable token;
    /// @notice Immutable penalty destination: the lockers' forfeiture bucket.
    address public immutable distributor;
    /// @notice Immutable penalty destination: protocol treasury.
    address public immutable treasury;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Only the timelock may touch clamped parameters or the eligibility whitelist.
    address public timelock;
    address public pendingTimelock;

    /// @notice Tunable within [0, HARD_MAX_PENALTY_BPS].
    uint256 public maxPenaltyBps;
    /// @notice Treasury share of a forfeiture, tunable within [0, HARD_MAX_PENALTY_SPLIT_BPS].
    uint256 public penaltySplitBps;

    uint256 public totalLocked;
    uint256 private _nextTokenId = 1;

    mapping(uint256 tokenId => Lock) private _locked;
    mapping(uint256 tokenId => uint256) public createdEpoch;
    /// @notice First epoch whose start-of-epoch snapshot can include this position.
    /// @dev A position created mid-epoch `n` first participates in `n+1`; one created exactly on
    ///      a week boundary is already inside epoch `n`'s snapshot, so it participates in `n`.
    ///      Getting this wrong in either direction breaks conservation: too late strands the
    ///      position's slice of an epoch it was counted in, too early pays out of a denominator
    ///      it was absent from.
    mapping(uint256 tokenId => uint256) public firstEligibleEpoch;
    mapping(uint256 tokenId => uint256) public exitEpoch;
    mapping(uint256 tokenId => bool) public closed;

    /// @notice Sum of the epoch-start weights of every position that exited during an epoch.
    mapping(uint256 epoch => uint256) public exitedWeightByEpoch;

    /// @notice Contract eligibility tiers (spec §3.1 #10). EOAs need no entry.
    mapping(address account => Tier) public tierOf;

    /// @notice Opt-in keeper rights. Grants `increaseUnlockTime` only — never principal.
    mapping(address owner => mapping(address operator => bool)) private _operators;

    mapping(address owner => uint256[]) private _ownedTokens;

    struct UserPoint {
        uint128 amount;
        uint64 end;
        uint64 ts;
    }

    struct GlobalPoint {
        int128 bias;
        int128 slope;
        uint64 ts;
    }

    mapping(uint256 tokenId => UserPoint[]) private _userPointHistory;

    uint256 public epoch;
    mapping(uint256 epochIndex => GlobalPoint) public pointHistory;
    /// @notice Signed slope delta applied when crossing a week boundary. Carries both the
    ///         deferred activation (+slope) and the expiry (-slope) of every lock.
    mapping(uint256 weekStart => int128) public slopeChanges;

    mapping(uint256 weekStart => uint256) private _weekSupply;
    mapping(uint256 weekStart => bool) private _weekSupplyCached;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(uint256 indexed tokenId, address indexed provider, uint256 amount, uint256 unlockTime);
    event LockExtended(uint256 indexed tokenId, uint256 oldUnlock, uint256 newUnlock);
    event Withdraw(uint256 indexed tokenId, address indexed to, uint256 amount);
    event EmergencyExit(
        uint256 indexed tokenId,
        address indexed to,
        uint256 returned,
        uint256 penalty,
        uint256 toLockers,
        uint256 toTreasury,
        uint256 penaltyBps
    );
    event PenaltyCapUpdated(uint256 tokenId, uint256 oldCap, uint256 newCap);
    event GlobalCheckpoint(uint256 indexed epochIndex, int128 bias, int128 slope, uint256 ts);
    event MaxPenaltyBpsSet(uint256 oldValue, uint256 newValue);
    event PenaltySplitBpsSet(uint256 oldValue, uint256 newValue);
    event TierSet(address indexed account, Tier tier);
    event OperatorSet(address indexed owner, address indexed operator, bool approved);
    event TimelockTransferStarted(address indexed from, address indexed to);
    event TimelockTransferred(address indexed from, address indexed to);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotTimelock();
    error NotAuthorized();
    error ZeroAddress();
    error ZeroAmount();
    error DurationNotWeekAligned();
    error DurationOutOfRange();
    error LockNotFound();
    error LockClosed();
    error LockExpired();
    error LockNotExpired();
    error UnlockNotLater();
    error UnlockTooFar();
    error IneligibleAccount(address account);
    error ParameterOutOfRange();
    error Soulbound();
    error HistoryStale();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address token_,
        address distributor_,
        address treasury_,
        address timelock_,
        uint256 maxPenaltyBps_,
        uint256 penaltySplitBps_
    ) ERC721("veXDC Staking Position", "veXDC") {
        if (token_ == address(0) || distributor_ == address(0) || treasury_ == address(0) || timelock_ == address(0)) {
            revert ZeroAddress();
        }
        if (maxPenaltyBps_ > HARD_MAX_PENALTY_BPS || penaltySplitBps_ > HARD_MAX_PENALTY_SPLIT_BPS) {
            revert ParameterOutOfRange();
        }
        token = token_;
        distributor = distributor_;
        treasury = treasury_;
        timelock = timelock_;
        maxPenaltyBps = maxPenaltyBps_;
        penaltySplitBps = penaltySplitBps_;

        pointHistory[0] = GlobalPoint({bias: 0, slope: 0, ts: block.timestamp.toUint64()});
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyTimelock() {
        if (msg.sender != timelock) {
            revert NotTimelock();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          GOVERNANCE (CLAMPED)
    //////////////////////////////////////////////////////////////*/

    /// @notice Penalty parameters live here, behind immutable clamps (spec §3.1 #11).
    ///         There is no PenaltyManager and `emergencyExit` makes no external call for them.
    function setMaxPenaltyBps(uint256 newValue) external onlyTimelock {
        if (newValue > HARD_MAX_PENALTY_BPS) {
            revert ParameterOutOfRange();
        }
        emit MaxPenaltyBpsSet(maxPenaltyBps, newValue);
        maxPenaltyBps = newValue;
    }

    function setPenaltySplitBps(uint256 newValue) external onlyTimelock {
        if (newValue > HARD_MAX_PENALTY_SPLIT_BPS) {
            revert ParameterOutOfRange();
        }
        emit PenaltySplitBpsSet(penaltySplitBps, newValue);
        penaltySplitBps = newValue;
    }

    /// @notice Contract eligibility. EOAs are never listed; contracts need CUSTODIAN or WRAPPER.
    function setTier(address account, Tier tier) external onlyTimelock {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        tierOf[account] = tier;
        emit TierSet(account, tier);
    }

    function transferTimelock(address newTimelock) external onlyTimelock {
        if (newTimelock == address(0)) {
            revert ZeroAddress();
        }
        pendingTimelock = newTimelock;
        emit TimelockTransferStarted(timelock, newTimelock);
    }

    function acceptTimelock() external {
        if (msg.sender != pendingTimelock) {
            revert NotAuthorized();
        }
        emit TimelockTransferred(timelock, msg.sender);
        timelock = msg.sender;
        pendingTimelock = address(0);
    }

    /*//////////////////////////////////////////////////////////////
                          SOULBOUND ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Option B (spec §3.1 #9): there is no transfer path and no carve-out of any kind.
    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @notice Keeper rights for `increaseUnlockTime` only. Never a transfer or spend right.
    function setOperator(address operator, bool approved) external {
        if (operator == address(0)) {
            revert ZeroAddress();
        }
        _operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
    }

    function isOperator(address owner, address operator) public view returns (bool) {
        return _operators[owner][operator];
    }

    /*//////////////////////////////////////////////////////////////
                            WEIGHT FORMULA
    //////////////////////////////////////////////////////////////*/

    /// @notice Weight of a lock at an arbitrary timestamp, with the effective-time clamp.
    /// @dev `slope = amount / MAX_LOCK` (truncated once), `weight = slope * min(end - t, MAX_LOCK)`.
    ///      Consequences: `weight <= amount` always, and the sum over positions equals total supply.
    function weightAt(uint256 amount, uint256 end, uint256 timestamp) public pure returns (uint256) {
        if (end <= timestamp || amount == 0) {
            return 0;
        }
        uint256 effective = end - timestamp;
        if (effective > MAX_LOCK) {
            effective = MAX_LOCK;
        }
        // Deliberate divide-before-multiply: the truncated slope is the canonical unit of
        // weight, so the per-position read and the global aggregate agree to the wei.
        // forge-lint: disable-next-line(divide-before-multiply)
        return (amount / MAX_LOCK) * effective;
    }

    /// @notice `min(unlock - now, MAX_LOCK)` — the single clamped time used by weight and penalty.
    function effectiveTime(uint256 tokenId) public view returns (uint256) {
        Lock memory lock = _locked[tokenId];
        if (lock.end <= block.timestamp) {
            return 0;
        }
        uint256 remaining = lock.end - block.timestamp;
        return remaining > MAX_LOCK ? MAX_LOCK : remaining;
    }

    /*//////////////////////////////////////////////////////////////
                              CHECKPOINTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Permissionless. Advances global history and fills the week-boundary supply cache.
    function checkpoint() external {
        _globalCheckpoint();
    }

    function _globalCheckpoint() internal {
        uint256 epoch_ = epoch;
        GlobalPoint memory last = pointHistory[epoch_];
        if (last.ts == block.timestamp) {
            return;
        }

        int128 bias = last.bias;
        int128 slope = last.slope;
        uint256 lastTs = last.ts;
        uint256 ti = EpochTime.floorWeek(lastTs);

        for (uint256 i = 0; i < MAX_WEEK_STEPS; ++i) {
            ti += WEEK;
            int128 dSlope = 0;
            uint256 t = ti;
            if (t > block.timestamp) {
                t = block.timestamp;
            } else {
                dSlope = slopeChanges[ti];
            }

            // `t - lastTs` is at most one week; slope*seconds stays far inside int128.
            // forge-lint: disable-next-line(unsafe-typecast)
            bias -= slope * int128(uint128(t - lastTs));
            if (bias < 0) {
                bias = 0;
            }
            slope += dSlope;
            if (slope < 0) {
                slope = 0;
            }
            lastTs = t;

            unchecked {
                ++epoch_;
            }
            pointHistory[epoch_] = GlobalPoint({bias: bias, slope: slope, ts: t.toUint64()});

            // Only memoize a boundary that is strictly in the past. A boundary equal to
            // `block.timestamp` is still mutable: a lock created later in the same block would
            // count towards `balanceOfNFTAt` but be missing from a value frozen here, which
            // would desynchronise the distributor's numerator from its denominator.
            if (t == ti && ti < block.timestamp) {
                // `bias` is clamped to >= 0 above, so the cast cannot wrap.
                // forge-lint: disable-next-line(unsafe-typecast)
                _weekSupply[ti] = uint256(uint128(bias));
                _weekSupplyCached[ti] = true;
            }
            if (t == block.timestamp) {
                break;
            }
        }

        epoch = epoch_;
        emit GlobalCheckpoint(epoch_, bias, slope, lastTs);
    }

    /// @dev Adds (`sign = 1`) or removes (`sign = -1`) a lock's contribution to the *current*
    ///      global point and to the future slope schedule.
    function _applyLock(uint128 amount, uint64 end, int128 sign) private {
        if (end <= block.timestamp || amount == 0) {
            return;
        }
        // `amount` is a uint128 field, so `amount / MAX_LOCK` always fits an int128.
        // forge-lint: disable-next-line(unsafe-typecast)
        int128 slope = int128(uint128(amount / uint128(MAX_LOCK)));
        if (slope == 0) {
            return;
        }

        uint256 activation = uint256(end) - MAX_LOCK;
        GlobalPoint storage p = pointHistory[epoch];

        int128 biasDelta;
        int128 slopeDelta;
        if (activation <= block.timestamp) {
            biasDelta = slope * int128(uint128(uint256(end) - block.timestamp));
            slopeDelta = slope;
        } else {
            // Deferred activation: flat at `slope * MAX_LOCK` until the clamp stops binding.
            // MAX_LOCK is a compile-time constant of ~6.3e7 seconds.
            // forge-lint: disable-next-line(unsafe-typecast)
            biasDelta = slope * int128(uint128(MAX_LOCK));
            slopeDelta = 0;
            slopeChanges[activation] += sign * slope;
        }
        slopeChanges[uint256(end)] -= sign * slope;

        p.bias += sign * biasDelta;
        p.slope += sign * slopeDelta;
        if (p.bias < 0) {
            p.bias = 0;
        }
        if (p.slope < 0) {
            p.slope = 0;
        }
    }

    function _pushUserPoint(uint256 tokenId, uint128 amount, uint64 end) private {
        UserPoint[] storage history = _userPointHistory[tokenId];
        uint256 len = history.length;
        uint64 nowTs = block.timestamp.toUint64();
        if (len > 0 && history[len - 1].ts == nowTs) {
            history[len - 1] = UserPoint({amount: amount, end: end, ts: nowTs});
        } else {
            history.push(UserPoint({amount: amount, end: end, ts: nowTs}));
        }
    }

    /// @dev Every lock mutation funnels through here: advance history, swap the contribution,
    ///      record the new user point.
    function _rewriteLock(uint256 tokenId, Lock memory oldLock, Lock memory newLock) private {
        _globalCheckpoint();
        if (pointHistory[epoch].ts != block.timestamp) {
            revert HistoryStale();
        }

        _applyLock(oldLock.amount, oldLock.end, -1);
        _applyLock(newLock.amount, newLock.end, 1);

        _locked[tokenId] = newLock;
        _pushUserPoint(tokenId, newLock.amount, newLock.end);
    }

    /*//////////////////////////////////////////////////////////////
                                 READS
    //////////////////////////////////////////////////////////////*/

    function locked(uint256 tokenId) external view returns (Lock memory) {
        return _locked[tokenId];
    }

    function balanceOfNFT(uint256 tokenId) public view returns (uint256) {
        Lock memory lock = _locked[tokenId];
        return weightAt(lock.amount, lock.end, block.timestamp);
    }

    function balanceOfNFTAt(uint256 tokenId, uint256 timestamp) public view returns (uint256) {
        UserPoint[] storage history = _userPointHistory[tokenId];
        uint256 len = history.length;
        if (len == 0 || history[0].ts > timestamp) {
            return 0;
        }

        uint256 lo = 0;
        uint256 hi = len - 1;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (history[mid].ts <= timestamp) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        UserPoint memory point = history[lo];
        return weightAt(point.amount, point.end, timestamp);
    }

    function totalSupply() external view returns (uint256) {
        return totalSupplyAt(block.timestamp);
    }

    function totalSupplyAt(uint256 timestamp) public view returns (uint256) {
        uint256 target = _findEpoch(timestamp);
        GlobalPoint memory p = pointHistory[target];
        if (p.ts > timestamp) {
            return 0;
        }

        int128 bias = p.bias;
        int128 slope = p.slope;
        uint256 lastTs = p.ts;
        uint256 ti = EpochTime.floorWeek(lastTs);

        for (uint256 i = 0; i < MAX_WEEK_STEPS; ++i) {
            ti += WEEK;
            int128 dSlope = 0;
            uint256 t = ti;
            if (t > timestamp) {
                t = timestamp;
            } else {
                dSlope = slopeChanges[ti];
            }
            // `t - lastTs` is at most one week; slope*seconds stays far inside int128.
            // forge-lint: disable-next-line(unsafe-typecast)
            bias -= slope * int128(uint128(t - lastTs));
            if (bias < 0) {
                return 0;
            }
            slope += dSlope;
            if (slope < 0) {
                slope = 0;
            }
            lastTs = t;
            if (t == timestamp) {
                break;
            }
        }
        // `bias` is clamped to >= 0 above, so the int128 -> uint128 cast cannot wrap.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(uint128(bias));
    }

    /// @notice O(1) for any week boundary already crossed by a checkpoint.
    function totalSupplyAtWeek(uint256 weekStart) public view returns (uint256) {
        if (_weekSupplyCached[weekStart]) {
            return _weekSupply[weekStart];
        }
        return totalSupplyAt(weekStart);
    }

    function _findEpoch(uint256 timestamp) private view returns (uint256) {
        uint256 lo = 0;
        uint256 hi = epoch;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (pointHistory[mid].ts <= timestamp) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    function userPointHistoryLength(uint256 tokenId) external view returns (uint256) {
        return _userPointHistory[tokenId].length;
    }

    function userPointAt(uint256 tokenId, uint256 index) external view returns (UserPoint memory) {
        return _userPointHistory[tokenId][index];
    }

    /*//////////////////////////////////////////////////////////////
                                LOCKING
    //////////////////////////////////////////////////////////////*/

    function createLock(uint256 amount, uint256 duration) external returns (uint256) {
        return createLockFor(msg.sender, amount, duration);
    }

    /// @notice Creates a soulbound position for `beneficiary`, funded by `msg.sender`.
    /// @dev Eligibility is checked against the beneficiary, never the funder (spec §3.1).
    function createLockFor(address beneficiary, uint256 amount, uint256 duration)
        public
        nonReentrant
        returns (uint256 tokenId)
    {
        if (beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (duration % WEEK != 0) {
            revert DurationNotWeekAligned();
        }
        if (duration < MIN_LOCK || duration > MAX_LOCK) {
            revert DurationOutOfRange();
        }
        _requireEligible(beneficiary);

        uint256 unlock = EpochTime.ceilWeek(block.timestamp + duration);
        if (unlock - block.timestamp < MIN_LOCK) {
            revert DurationOutOfRange();
        }

        tokenId = _nextTokenId++;
        _safeMint(beneficiary, tokenId);
        _ownedTokens[beneficiary].push(tokenId);
        createdEpoch[tokenId] = EpochTime.currentEpoch();
        firstEligibleEpoch[tokenId] = EpochTime.epochOf(EpochTime.ceilWeek(block.timestamp));

        Lock memory newLock =
            Lock({amount: amount.toUint128(), end: unlock.toUint64(), penaltyCapBps: maxPenaltyBps.toUint64()});
        _rewriteLock(tokenId, Lock({amount: 0, end: 0, penaltyCapBps: 0}), newLock);

        totalLocked += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(tokenId, msg.sender, amount, unlock);
    }

    /// @notice Adds principal to an existing position and re-weights its grandfathered penalty cap.
    /// @dev Cap rule (spec §3.4 #5): `newCap = (oldPrincipal*oldCap + added*currentGlobal) / newPrincipal`.
    ///      Old principal keeps its terms exactly; new principal enters at current terms.
    function increaseAmount(uint256 tokenId, uint256 amount) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        Lock memory oldLock = _requireOpenLock(tokenId);
        if (oldLock.end <= block.timestamp) {
            revert LockExpired();
        }

        uint256 oldPrincipal = oldLock.amount;
        uint256 newPrincipal = oldPrincipal + amount;
        uint256 newCap = (oldPrincipal * oldLock.penaltyCapBps + amount * maxPenaltyBps) / newPrincipal;

        Lock memory newLock =
            Lock({amount: newPrincipal.toUint128(), end: oldLock.end, penaltyCapBps: newCap.toUint64()});
        _rewriteLock(tokenId, oldLock, newLock);

        totalLocked += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        if (newCap != oldLock.penaltyCapBps) {
            emit PenaltyCapUpdated(tokenId, oldLock.penaltyCapBps, newCap);
        }
        emit Deposit(tokenId, msg.sender, amount, oldLock.end);
    }

    /// @notice Extends a lock. Never changes the position's penalty cap (spec §3.4).
    /// @param newUnlock Absolute timestamp; rounded UP to the next week boundary.
    function increaseUnlockTime(uint256 tokenId, uint256 newUnlock) public nonReentrant {
        Lock memory oldLock = _requireOpenLock(tokenId);
        address owner = _requireOwned(tokenId);
        if (msg.sender != owner && !_operators[owner][msg.sender]) {
            revert NotAuthorized();
        }
        if (oldLock.end <= block.timestamp) {
            revert LockExpired();
        }
        if (newUnlock > block.timestamp + MAX_LOCK) {
            revert UnlockTooFar();
        }

        uint256 unlock = EpochTime.ceilWeek(newUnlock);
        if (unlock <= oldLock.end) {
            revert UnlockNotLater();
        }

        Lock memory newLock =
            Lock({amount: oldLock.amount, end: unlock.toUint64(), penaltyCapBps: oldLock.penaltyCapBps});
        _rewriteLock(tokenId, oldLock, newLock);

        emit LockExtended(tokenId, oldLock.end, unlock);
    }

    /// @notice Keeper convenience: re-extend to the maximum. Cap is untouched by construction.
    function keepAtMaxLock(uint256 tokenId) external {
        increaseUnlockTime(tokenId, block.timestamp + MAX_LOCK);
    }

    /*//////////////////////////////////////////////////////////////
                          EXIT PATHS (PRINCIPAL)
    //////////////////////////////////////////////////////////////*/

    /// @notice Full principal after expiry. Unconditional under any periphery state.
    function withdraw(uint256 tokenId) external nonReentrant {
        address owner = _requireOwned(tokenId);
        if (msg.sender != owner) {
            revert NotAuthorized();
        }
        Lock memory lock = _requireOpenLock(tokenId);
        if (lock.end > block.timestamp) {
            revert LockNotExpired();
        }

        uint256 amount = lock.amount;
        _rewriteLock(tokenId, lock, Lock({amount: 0, end: 0, penaltyCapBps: lock.penaltyCapBps}));
        closed[tokenId] = true;
        totalLocked -= amount;

        IERC20(token).safeTransfer(owner, amount);
        emit Withdraw(tokenId, owner, amount);
    }

    /// @notice Early exit against a penalty. Reads only escrow storage — no external call for
    ///         parameters or logic, so it cannot be bricked by any other contract (spec §2).
    function emergencyExit(uint256 tokenId) external nonReentrant {
        address owner = _requireOwned(tokenId);
        if (msg.sender != owner) {
            revert NotAuthorized();
        }
        Lock memory lock = _requireOpenLock(tokenId);
        if (lock.end <= block.timestamp) {
            revert LockNotExpired();
        }

        (uint256 returned, uint256 penalty, uint256 penaltyBps) = _quoteExit(lock);
        uint256 toTreasury = (penalty * penaltySplitBps) / BPS;

        _rewriteLock(tokenId, lock, Lock({amount: 0, end: 0, penaltyCapBps: lock.penaltyCapBps}));
        // Recorded *after* the rewrite so the figure is read from exactly the state the
        // distributor will later read. If the position was created and exited inside the same
        // block as the epoch boundary, the rewrite overwrites its snapshot point and the global
        // point alike, so it is absent from both the numerator and the denominator and nothing
        // is forfeited. Reading before the rewrite would record a weight the snapshot no longer
        // contains, letting the forfeited slice exceed the epoch's pot.
        _recordExit(tokenId);
        closed[tokenId] = true;
        totalLocked -= lock.amount;

        IERC20 erc20 = IERC20(token);
        if (returned > 0) {
            erc20.safeTransfer(owner, returned);
        }
        if (penalty - toTreasury > 0) {
            erc20.safeTransfer(distributor, penalty - toTreasury);
        }
        if (toTreasury > 0) {
            erc20.safeTransfer(treasury, toTreasury);
        }

        emit EmergencyExit(tokenId, owner, returned, penalty, penalty - toTreasury, toTreasury, penaltyBps);
    }

    /// @dev The in-progress epoch share is forfeited: record the snapshot weight this position
    ///      holds at the start of the current epoch, as the distributor will read it, so that
    ///      settlement moves exactly that slice into the forfeiture bucket without ever touching
    ///      the epoch's denominator.
    function _recordExit(uint256 tokenId) private {
        uint256 currentEpoch_ = EpochTime.currentEpoch();
        uint256 snapshotWeight = balanceOfNFTAt(tokenId, EpochTime.startOfEpoch(currentEpoch_));
        if (snapshotWeight > 0) {
            exitedWeightByEpoch[currentEpoch_] += snapshotWeight;
        }
        exitEpoch[tokenId] = currentEpoch_;
    }

    function _quoteExit(Lock memory lock) private view returns (uint256 returned, uint256 penalty, uint256 penaltyBps) {
        uint256 remaining = lock.end - block.timestamp;
        uint256 eff = remaining > MAX_LOCK ? MAX_LOCK : remaining;
        uint256 cap = lock.penaltyCapBps < maxPenaltyBps ? lock.penaltyCapBps : maxPenaltyBps;
        penaltyBps = (cap * eff) / MAX_LOCK;
        penalty = (uint256(lock.amount) * penaltyBps) / BPS;
        returned = lock.amount - penalty;
    }

    /// @notice Quote for the UI: what an early exit costs right now.
    function previewExit(uint256 tokenId)
        external
        view
        returns (uint256 returned, uint256 penalty, uint256 penaltyBps)
    {
        Lock memory lock = _locked[tokenId];
        if (lock.amount == 0 || lock.end <= block.timestamp) {
            return (lock.amount, 0, 0);
        }
        return _quoteExit(lock);
    }

    /// @notice Effective cap for a position: global reductions apply immediately, increases never do.
    function effectivePenaltyCapBps(uint256 tokenId) external view returns (uint256) {
        uint256 cap = _locked[tokenId].penaltyCapBps;
        return cap < maxPenaltyBps ? cap : maxPenaltyBps;
    }

    /*//////////////////////////////////////////////////////////////
                          SPEC-NAMED ALIASES
    //////////////////////////////////////////////////////////////*/

    function create_lock_for(address beneficiary, uint256 amount, uint256 duration) external returns (uint256) {
        return createLockFor(beneficiary, amount, duration);
    }

    function increase_amount(uint256 tokenId, uint256 amount) external {
        increaseAmount(tokenId, amount);
    }

    function increase_unlock_time(uint256 tokenId, uint256 newUnlock) external {
        increaseUnlockTime(tokenId, newUnlock);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _requireOpenLock(uint256 tokenId) private view returns (Lock memory lock) {
        _requireOwned(tokenId);
        if (closed[tokenId]) {
            revert LockClosed();
        }
        lock = _locked[tokenId];
        if (lock.amount == 0) {
            revert LockNotFound();
        }
    }

    /// @dev Protocol-support policy, not a cryptographic guarantee (spec §3.1 #10): a
    ///      counterfactual CREATE2 address has no code today and may have code tomorrow.
    ///      Soulbound positions + per-tokenId claims bound the residual risk to what a
    ///      custodian already has. Monitored off-chain, not claimed impossible.
    function _requireEligible(address account) private view {
        if (account.code.length == 0) {
            return;
        }
        if (tierOf[account] == Tier.NONE) {
            revert IneligibleAccount(account);
        }
    }

    /// @dev Position ownership is append-only: transfers do not exist.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) {
            revert Soulbound();
        }
    }
}
