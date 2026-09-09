// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Roles
/// @notice The single source of truth for every AccessControl role id in the system.
///
/// @dev Role matrix (spec §4). `DEFAULT_ADMIN_ROLE` (0x00) administers every role below and is
///      held by the timelock alone once deployment hands over.
///
///      | Role            | Holder    | Contract(s)                    | Can                                          |
///      |-----------------|-----------|--------------------------------|----------------------------------------------|
///      | DEFAULT_ADMIN   | timelock  | FeeDistributor, RevenueRegistry, Attestor | grant/revoke roles, unpause, add reward tokens, wire the escrow once |
///      | UPGRADER        | timelock  | FeeDistributor, RevenueRegistry | authorise a UUPS upgrade                     |
///      | REGISTRY_ADMIN  | timelock  | RevenueRegistry                | register / deactivate adapters, update terms |
///      | PAUSER          | guardian  | FeeDistributor                 | pause the periphery (never the escrow)       |
///      | KEEPER          | Hermes    | FeeDistributor                 | pre-boundary re-extensions, compound batches |
///      | REPORTER        | reporter  | Attestor                       | post Mode C attestations                     |
///
///      The immutable `VotingEscrow` deliberately does not use AccessControl: it has exactly one
///      privileged actor (`timelock`, two-step transferable) whose powers are clamped by
///      constants, and nothing there is ever delegated.
library Roles {
    bytes32 internal constant UPGRADER = keccak256("UPGRADER_ROLE");
    bytes32 internal constant PAUSER = keccak256("PAUSER_ROLE");
    bytes32 internal constant KEEPER = keccak256("KEEPER_ROLE");
    bytes32 internal constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN_ROLE");
    bytes32 internal constant REPORTER = keccak256("REPORTER_ROLE");
}
