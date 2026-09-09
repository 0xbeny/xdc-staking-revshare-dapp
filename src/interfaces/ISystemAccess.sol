// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ISystemAccess
/// @notice Central, per-target role registry for the veXDC periphery.
/// @dev Targets are contract addresses (`FeeDistributor`, `RevenueRegistry`, `Attestor`, …).
///      Role ids come from `Roles`. The hub's own `DEFAULT_ADMIN_ROLE` (timelock) grants/revokes.
interface ISystemAccess {
    event TargetRoleGranted(address indexed target, bytes32 indexed role, address indexed account, address sender);
    event TargetRoleRevoked(address indexed target, bytes32 indexed role, address indexed account, address sender);

    function hasRole(address target, bytes32 role, address account) external view returns (bool);

    function grantRole(address target, bytes32 role, address account) external;

    function revokeRole(address target, bytes32 role, address account) external;

    function renounceRole(address target, bytes32 role, address callerConfirmation) external;

    function getRoleMemberCount(address target, bytes32 role) external view returns (uint256);

    function getRoleMember(address target, bytes32 role, uint256 index) external view returns (address);

    /// @dev Reverts with OpenZeppelin's `AccessControlUnauthorizedAccount` if missing.
    function checkRole(address target, bytes32 role, address account) external view;
}
