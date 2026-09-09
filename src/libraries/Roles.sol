// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Roles
/// @notice Role id constants. Membership lives in `SystemAccess` (per target contract).
///
/// @dev Role matrix (spec §4). `SystemAccess.DEFAULT_ADMIN_ROLE` (timelock) grants/revokes every
///      target role below. Query who can act where with
///      `systemAccess.hasRole(target, role, account)` and enumerate via `getRoleMember*`.
///
///      | Role            | Holder    | Target                         | Can                                          |
///      |-----------------|-----------|--------------------------------|----------------------------------------------|
///      | DEFAULT_ADMIN   | timelock  | FeeDistributor, RevenueRegistry | unpause, add reward tokens, one-shot wiring  |
///      | UPGRADER        | timelock  | FeeDistributor, RevenueRegistry | authorise a UUPS upgrade                     |
///      | REGISTRY_ADMIN  | timelock  | RevenueRegistry                | register / deactivate adapters, update terms |
///      | PAUSER          | guardian  | FeeDistributor                 | pause the periphery (never the escrow)       |
///      | KEEPER          | Hermes    | FeeDistributor                 | pre-boundary re-extensions, compound batches |
///      | REPORTER        | reporter  | Attestor                       | post Mode C attestations                     |
///
///      Hub admin (timelock on `SystemAccess` itself) is the only address that can grant/revoke.
///      The immutable `VotingEscrow` deliberately does not use SystemAccess: it has exactly one
///      privileged actor (`timelock`, two-step transferable) whose powers are clamped by
///      constants, and nothing there is ever delegated.
library Roles {
    bytes32 internal constant DEFAULT_ADMIN = 0x00;
    bytes32 internal constant UPGRADER = keccak256("UPGRADER_ROLE");
    bytes32 internal constant PAUSER = keccak256("PAUSER_ROLE");
    bytes32 internal constant KEEPER = keccak256("KEEPER_ROLE");
    bytes32 internal constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN_ROLE");
    bytes32 internal constant REPORTER = keccak256("REPORTER_ROLE");
}
