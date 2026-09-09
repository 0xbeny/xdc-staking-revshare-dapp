// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRevenueRegistry} from "./interfaces/IRevenueRegistry.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {EpochTime} from "./libraries/EpochTime.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeDistributor
/// @notice Weekly real-yield distribution against snapshotted ve weight.
///
/// @dev Frozen semantics implemented here:
///
///  * **Epoch rule (§3.3).** Revenue received during epoch `n` is allocated by the weights
///    snapshotted at the *start* of epoch `n`, and becomes claimable once `n` closes. Positions
///    created or increased during `n` first participate in `n+1`.
///
///  * **Attribution (§3.2 #8).** Revenue belongs to the distribution epoch in which this
///    contract actually receives it. There is no way for any caller to name a past epoch.
///
///  * **Bounded claims (§3.3 #3).** `claim` walks at most `MAX_EPOCHS_PER_CLAIM` finalized
///    epochs and advances a per-(position, token) cursor, reporting `remaining`.
///
///  * **Zero-supply carry-forward (§3.3 #12).** An epoch whose snapshot supply is zero moves its
///    whole pot to the next epoch. Never divide by zero, never sweep to treasury, never strand.
///
///  * **Forfeiture bucket (§3.3 / §3.4).** An exiting position forfeits its in-progress epoch
///    share. Settlement moves exactly `pot * exitedWeight / supply` into the *next* epoch's pot
///    without ever modifying the exited epoch's denominator, so an exiting position can never
///    receive its own forfeiture.
contract FeeDistributor is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant WEEK = 7 days;
    /// @notice Hard bound on epochs walked per claim call. No unbounded loop exists anywhere.
    uint256 public constant MAX_EPOCHS_PER_CLAIM = 52;
    /// @notice Pre-boundary keeper window (§5): the last two hours of an epoch.
    uint256 public constant KEEPER_WINDOW = 2 hours;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    IVotingEscrow public escrow;
    IRevenueRegistry public registry;

    /// @notice First epoch this distributor accounts for.
    uint256 public startEpoch;

    /// @notice Claim numerator for an epoch. Immutable once its epoch has been settled.
    mapping(address token => mapping(uint256 epoch => uint256)) public epochRevenue;
    /// @notice Tokens held on behalf of lockers. `balanceOf(this) - accounted` is unattributed.
    mapping(address token => uint256) public accounted;
    /// @notice Epochs strictly below this are final for the token.
    mapping(address token => uint256) public settledEpoch;

    mapping(address token => uint256) public totalNotified;
    mapping(address token => uint256) public totalClaimed;
    mapping(address token => uint256) public totalCarriedForward;
    mapping(address token => uint256) public totalForfeitedFromExits;

    mapping(uint256 epoch => uint256) public epochSupply;
    mapping(uint256 epoch => bool) public epochSupplyCached;

    mapping(uint256 tokenId => mapping(address token => uint256)) public claimCursor;

    mapping(address token => bool) public isRewardToken;
    mapping(address token => bool) public acceptingRevenue;
    address[] private _rewardTokens;

    mapping(uint256 tokenId => address) public recipientOf;
    mapping(uint256 tokenId => bool) public autoCompound;
    mapping(uint256 tokenId => bool) public keepAtMaxLock;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[40] private __gap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event EscrowSet(address indexed escrow);
    event RewardTokenAdded(address indexed token);
    event RewardTokenAccepting(address indexed token, bool accepting);
    event RevenueNotified(address indexed token, address indexed adapter, uint256 amount, uint256 distributionEpoch);
    event ForfeitureSynced(address indexed token, uint256 amount, uint256 creditedEpoch);
    event EpochSettled(address indexed token, uint256 indexed epoch, uint256 supply, uint256 pot, uint256 movedForward);
    event Claimed(
        uint256 indexed tokenId, address indexed token, address indexed to, uint256 amount, uint256 newCursor
    );
    event Compounded(uint256 indexed tokenId, uint256 amount);
    event RecipientSet(uint256 indexed tokenId, address recipient);
    event AutoCompoundSet(uint256 indexed tokenId, bool enabled);
    event KeepAtMaxLockSet(uint256 indexed tokenId, bool enabled);
    event KeeperExtended(uint256 indexed tokenId, bool success);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error EscrowAlreadySet();
    error EscrowNotSet();
    error NotAnActiveAdapter();
    error UnknownRewardToken();
    error TokenNotAccepting();
    error NotPositionOwner();
    error NotAuthorized();
    error StaleEpoch();
    error OutsideKeeperWindow();
    error NotOptedIn();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address registry_) external initializer {
        if (admin == address(0) || registry_ == address(0)) {
            revert ZeroAddress();
        }
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        registry = IRevenueRegistry(registry_);
        startEpoch = EpochTime.currentEpoch();
    }

    /// @dev The escrow is deployed after this proxy (it needs the distributor as an immutable
    ///      penalty destination), so it is wired in exactly once, by the admin, post-deploy.
    function setEscrow(address escrow_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (escrow_ == address(0)) {
            revert ZeroAddress();
        }
        if (address(escrow) != address(0)) {
            revert EscrowAlreadySet();
        }
        escrow = IVotingEscrow(escrow_);
        emit EscrowSet(escrow_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                              ADMIN / GUARD
    //////////////////////////////////////////////////////////////*/

    function addRewardToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (isRewardToken[token]) {
            return;
        }
        isRewardToken[token] = true;
        acceptingRevenue[token] = true;
        settledEpoch[token] = EpochTime.currentEpoch();
        _rewardTokens.push(token);
        emit RewardTokenAdded(token);
    }

    /// @dev Stops *new* revenue for a token. Already-notified revenue stays fully claimable —
    ///      there is no path that strands or reclaims it.
    function setAcceptingRevenue(address token, bool accepting) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isRewardToken[token]) {
            revert UnknownRewardToken();
        }
        acceptingRevenue[token] = accepting;
        emit RewardTokenAccepting(token, accepting);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function rewardTokens() external view returns (address[] memory) {
        return _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                                REVENUE IN
    //////////////////////////////////////////////////////////////*/

    /// @notice Called by a registered, active adapter. Attribution is the *receipt* epoch.
    function notifyRevenue(address token, uint256 amount) external nonReentrant whenNotPaused {
        if (!registry.isActiveAdapter(msg.sender)) {
            revert NotAnActiveAdapter();
        }
        if (!isRewardToken[token]) {
            revert UnknownRewardToken();
        }
        if (!acceptingRevenue[token]) {
            revert TokenNotAccepting();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Attribute any unaccounted balance first so a penalty transfer is never mistaken for
        // adapter revenue, and vice versa.
        _syncForfeiture(token);

        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;

        uint256 epoch = EpochTime.currentEpoch();
        accounted[token] += received;
        epochRevenue[token][epoch] += received;
        totalNotified[token] += received;

        registry.recordContribution(msg.sender, token, received);
        emit RevenueNotified(token, msg.sender, received, epoch);
    }

    /// @notice Attributes any unaccounted balance (escrow penalties, donations) to `currentEpoch + 1`.
    /// @dev Permissionless and idempotent. Credited to the next epoch because the exiting position
    ///      is excluded from every snapshot from `currentEpoch + 1` onward.
    function syncForfeiture(address token) public returns (uint256 credited) {
        if (!isRewardToken[token]) {
            revert UnknownRewardToken();
        }
        return _syncForfeiture(token);
    }

    function _syncForfeiture(address token) internal returns (uint256 credited) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 acc = accounted[token];
        if (balance <= acc) {
            return 0;
        }
        credited = balance - acc;

        uint256 epoch = EpochTime.currentEpoch() + 1;
        accounted[token] = balance;
        epochRevenue[token][epoch] += credited;
        totalNotified[token] += credited;
        totalForfeitedFromExits[token] += credited;
        emit ForfeitureSynced(token, credited, epoch);
    }

    /*//////////////////////////////////////////////////////////////
                               SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Finalizes up to `maxEpochs` closed epochs for `token`. Permissionless, bounded.
    function settle(address token, uint256 maxEpochs) public returns (uint256 newSettledEpoch) {
        if (!isRewardToken[token]) {
            revert UnknownRewardToken();
        }
        _syncForfeiture(token);

        uint256 cursor = settledEpoch[token];
        uint256 current = EpochTime.currentEpoch();
        uint256 processed;

        while (cursor < current && processed < maxEpochs) {
            uint256 supply = _supplyFor(cursor);
            uint256 pot = epochRevenue[token][cursor];
            uint256 movedForward;

            if (supply == 0) {
                // Nobody could ever claim this epoch: carry the whole pot forward.
                if (pot > 0) {
                    epochRevenue[token][cursor] = 0;
                    epochRevenue[token][cursor + 1] += pot;
                    totalCarriedForward[token] += pot;
                    movedForward = pot;
                }
            } else if (pot > 0) {
                uint256 exited = escrow.exitedWeightByEpoch(cursor);
                if (exited > 0) {
                    // Move the exited slice forward *without* touching this epoch's numerator or
                    // denominator: remaining lockers still claim `pot * w / supply`.
                    movedForward = (pot * exited) / supply;
                    if (movedForward > 0) {
                        epochRevenue[token][cursor + 1] += movedForward;
                        totalForfeitedFromExits[token] += movedForward;
                    }
                }
            }

            emit EpochSettled(token, cursor, supply, pot, movedForward);
            unchecked {
                ++cursor;
                ++processed;
            }
        }

        settledEpoch[token] = cursor;
        return cursor;
    }

    function _supplyFor(uint256 epoch) internal returns (uint256 supply) {
        if (epochSupplyCached[epoch]) {
            return epochSupply[epoch];
        }
        uint256 start = EpochTime.startOfEpoch(epoch);
        supply = escrow.totalSupplyAtWeek(start);
        if (start <= block.timestamp) {
            // A past week boundary is immutable, so it is safe to memoize.
            epochSupply[epoch] = supply;
            epochSupplyCached[epoch] = true;
        }
    }

    function _supplyForView(uint256 epoch) internal view returns (uint256) {
        if (epochSupplyCached[epoch]) {
            return epochSupply[epoch];
        }
        return escrow.totalSupplyAtWeek(EpochTime.startOfEpoch(epoch));
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims up to `MAX_EPOCHS_PER_CLAIM` finalized epochs per token.
    /// @return amounts Per-token amount transferred to the position's recipient.
    /// @return remaining Finalized epochs still unclaimed across `tokens`; call again if non-zero.
    function claim(uint256 tokenId, address[] calldata tokens)
        external
        nonReentrant
        whenNotPaused
        returns (uint256[] memory amounts, uint256 remaining)
    {
        address to = _recipient(tokenId);
        amounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            (uint256 amount, uint256 left) = _accrue(tokenId, tokens[i]);
            remaining += left;
            amounts[i] = amount;
            if (amount > 0) {
                accounted[tokens[i]] -= amount;
                totalClaimed[tokens[i]] += amount;
                IERC20(tokens[i]).safeTransfer(to, amount);
            }
            emit Claimed(tokenId, tokens[i], to, amount, claimCursor[tokenId][tokens[i]]);
        }
    }

    /// @notice Claims the escrow token and folds it straight back into the position.
    /// @dev Never extends duration and never changes the penalty cap beyond the weighted
    ///      `increase_amount` rule. Degrades to a plain claim once the lock is closed or expired.
    function claimAndLock(uint256 tokenId) public nonReentrant whenNotPaused returns (uint256 amount) {
        address owner = escrow.ownerOf(tokenId);
        if (msg.sender != owner && !escrow.isOperator(owner, msg.sender)) {
            if (!(hasRole(KEEPER_ROLE, msg.sender) && autoCompound[tokenId])) {
                revert NotAuthorized();
            }
        }
        return _compound(tokenId);
    }

    function _compound(uint256 tokenId) internal returns (uint256 amount) {
        address token = escrow.token();
        (amount,) = _accrue(tokenId, token);
        if (amount == 0) {
            return 0;
        }

        accounted[token] -= amount;
        totalClaimed[token] += amount;

        IVotingEscrow.Lock memory lock = escrow.locked(tokenId);
        if (lock.amount == 0 || lock.end <= block.timestamp) {
            IERC20(token).safeTransfer(_recipient(tokenId), amount);
            emit Claimed(tokenId, token, _recipient(tokenId), amount, claimCursor[tokenId][token]);
            return amount;
        }

        IERC20(token).forceApprove(address(escrow), amount);
        escrow.increaseAmount(tokenId, amount);
        emit Compounded(tokenId, amount);
    }

    function _accrue(uint256 tokenId, address token) internal returns (uint256 amount, uint256 remaining) {
        if (!isRewardToken[token]) {
            revert UnknownRewardToken();
        }
        settle(token, MAX_EPOCHS_PER_CLAIM);

        uint256 cursor = _cursor(tokenId, token);
        uint256 finalEpoch = _finalEpoch(tokenId);
        uint256 limit = settledEpoch[token];
        if (finalEpoch < limit) {
            limit = finalEpoch;
        }

        uint256 processed;
        while (cursor < limit && processed < MAX_EPOCHS_PER_CLAIM) {
            uint256 supply = _supplyFor(cursor);
            if (supply > 0) {
                uint256 pot = epochRevenue[token][cursor];
                if (pot > 0) {
                    uint256 weight = escrow.balanceOfNFTAt(tokenId, EpochTime.startOfEpoch(cursor));
                    if (weight > 0) {
                        amount += (pot * weight) / supply;
                    }
                }
            }
            unchecked {
                ++cursor;
                ++processed;
            }
        }
        claimCursor[tokenId][token] = cursor;

        uint256 claimableThrough = _finalEpoch(tokenId);
        uint256 current = EpochTime.currentEpoch();
        if (claimableThrough > current) {
            claimableThrough = current;
        }
        remaining = claimableThrough > cursor ? claimableThrough - cursor : 0;
    }

    /// @notice Read-only estimate. Call `settle` first for an exact figure after an exit epoch.
    function claimable(uint256 tokenId, address token) external view returns (uint256 amount, uint256 remaining) {
        uint256 cursor = _cursor(tokenId, token);
        uint256 finalEpoch = _finalEpoch(tokenId);
        uint256 limit = settledEpoch[token];
        if (finalEpoch < limit) {
            limit = finalEpoch;
        }

        uint256 processed;
        while (cursor < limit && processed < MAX_EPOCHS_PER_CLAIM) {
            uint256 supply = _supplyForView(cursor);
            if (supply > 0) {
                uint256 pot = epochRevenue[token][cursor];
                if (pot > 0) {
                    uint256 weight = escrow.balanceOfNFTAt(tokenId, EpochTime.startOfEpoch(cursor));
                    if (weight > 0) {
                        amount += (pot * weight) / supply;
                    }
                }
            }
            unchecked {
                ++cursor;
                ++processed;
            }
        }
        uint256 claimableThrough = _finalEpoch(tokenId);
        uint256 current = EpochTime.currentEpoch();
        if (claimableThrough > current) {
            claimableThrough = current;
        }
        remaining = claimableThrough > cursor ? claimableThrough - cursor : 0;
    }

    function _cursor(uint256 tokenId, address token) internal view returns (uint256) {
        uint256 cursor = claimCursor[tokenId][token];
        if (cursor != 0) {
            return cursor;
        }
        uint256 first = escrow.createdEpoch(tokenId) + 1;
        return first > startEpoch ? first : startEpoch;
    }

    /// @dev An exited position keeps every already-finalized epoch and loses everything from its
    ///      exit epoch onward — that slice is exactly what settlement moves to the bucket.
    function _finalEpoch(uint256 tokenId) internal view returns (uint256) {
        uint256 exit = escrow.exitEpoch(tokenId);
        return exit == 0 ? type(uint256).max : exit;
    }

    function _recipient(uint256 tokenId) internal view returns (address) {
        address to = recipientOf[tokenId];
        return to == address(0) ? escrow.ownerOf(tokenId) : to;
    }

    /*//////////////////////////////////////////////////////////////
                            POSITION SETTINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Custody / cash-flow separation. No transfers exist, so there is no reset logic.
    function setRecipient(uint256 tokenId, address to) external {
        if (msg.sender != escrow.ownerOf(tokenId)) {
            revert NotPositionOwner();
        }
        recipientOf[tokenId] = to;
        emit RecipientSet(tokenId, to);
    }

    function setAutoCompound(uint256 tokenId, bool enabled) external {
        if (msg.sender != escrow.ownerOf(tokenId)) {
            revert NotPositionOwner();
        }
        autoCompound[tokenId] = enabled;
        emit AutoCompoundSet(tokenId, enabled);
    }

    function setKeepAtMaxLock(uint256 tokenId, bool enabled) external {
        if (msg.sender != escrow.ownerOf(tokenId)) {
            revert NotPositionOwner();
        }
        keepAtMaxLock[tokenId] = enabled;
        emit KeepAtMaxLockSet(tokenId, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                                 KEEPER
    //////////////////////////////////////////////////////////////*/

    /// @notice Pre-boundary window (§5 step 2): re-extend opted-in positions so the boundary
    ///         snapshot sees full weight. A missed window is never retroactively corrected.
    function batchKeepAtMaxLock(uint256[] calldata tokenIds, uint256 expectedEpoch)
        external
        onlyRole(KEEPER_ROLE)
        whenNotPaused
    {
        uint256 current = EpochTime.currentEpoch();
        if (current != expectedEpoch) {
            revert StaleEpoch();
        }
        uint256 epochEnd = EpochTime.startOfEpoch(current + 1);
        if (block.timestamp + KEEPER_WINDOW < epochEnd) {
            revert OutsideKeeperWindow();
        }

        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (!keepAtMaxLock[tokenId]) {
                emit KeeperExtended(tokenId, false);
                continue;
            }
            try escrow.keepAtMaxLock(tokenId) {
                emit KeeperExtended(tokenId, true);
            } catch {
                emit KeeperExtended(tokenId, false);
            }
        }
    }

    /// @notice Post-boundary batch (§5 step 4). Compounds first earn in the *next* snapshot.
    function batchCompound(uint256[] calldata tokenIds, uint256 expectedEpoch)
        external
        nonReentrant
        onlyRole(KEEPER_ROLE)
        whenNotPaused
    {
        if (EpochTime.currentEpoch() != expectedEpoch) {
            revert StaleEpoch();
        }
        for (uint256 i; i < tokenIds.length; ++i) {
            if (!autoCompound[tokenIds[i]]) {
                continue;
            }
            _compound(tokenIds[i]);
        }
    }
}
