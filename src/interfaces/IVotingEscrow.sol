// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Read/write surface of the immutable VotingEscrow that peripheral contracts rely on.
interface IVotingEscrow {
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

    function token() external view returns (address);
    function distributor() external view returns (address);
    function treasury() external view returns (address);
    function acceptsLockGifts(address account) external view returns (bool);

    function MAX_LOCK() external view returns (uint256);
    function MIN_LOCK() external view returns (uint256);
    function MIN_LOCK_AMOUNT() external view returns (uint256);
    function HARD_MAX_PENALTY_BPS() external view returns (uint256);

    function maxPenaltyBps() external view returns (uint256);
    function penaltySplitBps() external view returns (uint256);
    function stakingCap() external view returns (uint256);
    function capGuardian() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);
    function locked(uint256 tokenId) external view returns (Lock memory);
    function createdEpoch(uint256 tokenId) external view returns (uint256);
    function firstEligibleEpoch(uint256 tokenId) external view returns (uint256);
    function exitEpoch(uint256 tokenId) external view returns (uint256);
    function exitedWeightByEpoch(uint256 epoch) external view returns (uint256);
    function isOperator(address owner, address operator) external view returns (bool);

    function balanceOfNFT(uint256 tokenId) external view returns (uint256);
    function balanceOfNFTAt(uint256 tokenId, uint256 timestamp) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);
    function totalSupplyAtWeek(uint256 weekStart) external view returns (uint256);
    function tokensOfOwner(address owner) external view returns (uint256[] memory);

    function checkpoint() external;
    function createLockFor(address beneficiary, uint256 amount, uint256 duration) external returns (uint256 tokenId);
    function increaseAmount(uint256 tokenId, uint256 amount) external;
    function increaseUnlockTime(uint256 tokenId, uint256 newUnlock) external;
    function keepAtMaxLock(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function emergencyExit(uint256 tokenId) external;
}
