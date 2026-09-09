// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRevenueRegistry {
    /// @notice Revenue commitment modes frozen in spec §3.2.
    enum Mode {
        NONE,
        PUSH, // A   — dApp pushes committed revenue directly.
        SPLITTER, // B   — fee receiver is the immutable splitter; permissionless skim.
        PULL_SAFE, // B2  — allowance-based pull from a dedicated fee Safe.
        ZODIAC_SAFE, // B3  — Zodiac module on a dedicated fee Safe.
        ATTESTATION // C   — atomic epoch attestation by a REPORTER.
    }

    struct AdapterInfo {
        address dapp;
        Mode mode;
        uint16 committedBps;
        uint32 version;
        bool active;
        bytes32 termsHash;
        uint64 registeredAt;
    }

    function isActiveAdapter(address adapter) external view returns (bool);
    function adapterInfo(address adapter) external view returns (AdapterInfo memory);
    function recordContribution(address adapter, address token, uint256 amount) external;
    function lifetimeContribution(address adapter, address token) external view returns (uint256);
}
