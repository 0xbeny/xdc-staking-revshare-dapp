// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISystemAccess} from "./interfaces/ISystemAccess.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title SystemAccess
/// @notice Immutable hub for periphery roles. One place to grant, revoke, and enumerate who can
///         act on which contract — so ops/monitoring never have to scrape N AccessControl stores.
///
/// @dev `VotingEscrow` stays outside this hub (clamped `timelock` only). This contract is not
///      upgradeable: a buggy ACL would otherwise brick every consumer at once with no escape
///      other than migrating those consumers.
contract SystemAccess is ISystemAccess, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address target => mapping(bytes32 role => mapping(address account => bool))) private _has;
    mapping(address target => mapping(bytes32 role => EnumerableSet.AddressSet)) private _members;

    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) {
            revert ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function hasRole(address target, bytes32 role, address account) public view returns (bool) {
        return _has[target][role][account];
    }

    function checkRole(address target, bytes32 role, address account) external view {
        if (!_has[target][role][account]) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, role);
        }
    }

    function grantRole(address target, bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (target == address(0) || account == address(0)) {
            revert ZeroAddress();
        }
        if (_has[target][role][account]) {
            return;
        }
        _has[target][role][account] = true;
        _members[target][role].add(account);
        emit TargetRoleGranted(target, role, account, _msgSender());
    }

    function revokeRole(address target, bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _remove(target, role, account);
    }

    function renounceRole(address target, bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }
        _remove(target, role, _msgSender());
    }

    function getRoleMemberCount(address target, bytes32 role) external view returns (uint256) {
        return _members[target][role].length();
    }

    function getRoleMember(address target, bytes32 role, uint256 index) external view returns (address) {
        return _members[target][role].at(index);
    }

    function _remove(address target, bytes32 role, address account) private {
        if (!_has[target][role][account]) {
            return;
        }
        _has[target][role][account] = false;
        _members[target][role].remove(account);
        emit TargetRoleRevoked(target, role, account, _msgSender());
    }
}
