// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRevenueRegistry} from "./interfaces/IRevenueRegistry.sol";
import {Roles} from "./libraries/Roles.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title RevenueRegistry
/// @notice Metadata plane for the revenue standard: whitelisting, terms, mode, version and
///         lifetime contribution. It never holds funds and never holds an allowance (§3.2).
contract RevenueRegistry is IRevenueRegistry, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeCast for uint256;

    bytes32 public constant UPGRADER_ROLE = Roles.UPGRADER;
    bytes32 public constant REGISTRY_ADMIN_ROLE = Roles.REGISTRY_ADMIN;

    address public distributor;

    mapping(address adapter => AdapterInfo) private _adapters;
    mapping(address adapter => mapping(address token => uint256)) public lifetimeContribution;
    mapping(address dapp => address[]) private _adaptersOfDapp;
    address[] private _allAdapters;

    // Reserved storage for future upgrades; intentionally never read.
    // forge-lint: disable-next-line(mixed-case-variable, unused-state-variables)
    uint256[40] private __gap;

    event DistributorSet(address indexed distributor);
    event AdapterRegistered(
        address indexed adapter, address indexed dapp, Mode mode, uint16 committedBps, uint32 version, bytes32 termsHash
    );
    event AdapterDeactivated(address indexed adapter);
    event AdapterReactivated(address indexed adapter);
    event TermsUpdated(address indexed adapter, bytes32 oldTerms, bytes32 newTerms, uint32 version);
    event ContributionRecorded(address indexed adapter, address indexed token, uint256 amount);

    error ZeroAddress();
    error AlreadyRegistered();
    error UnknownAdapter();
    error NotDistributor();
    error InvalidMode();
    error InvalidBps();

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        if (admin == address(0)) {
            revert ZeroAddress();
        }
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function setDistributor(address distributor_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (distributor_ == address(0)) {
            revert ZeroAddress();
        }
        distributor = distributor_;
        emit DistributorSet(distributor_);
    }

    /// @notice Whitelists an immutable adapter. The adapter itself hardcodes
    ///         `(source, tokens, committedBps, distributor, dappTreasury)` — this record is the
    ///         human-readable mirror of those hardcoded terms.
    function registerAdapter(
        address adapter,
        address dapp,
        Mode mode,
        uint16 committedBps,
        uint32 version,
        bytes32 termsHash
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (adapter == address(0) || dapp == address(0)) {
            revert ZeroAddress();
        }
        if (mode == Mode.NONE) {
            revert InvalidMode();
        }
        if (committedBps > 10_000) {
            revert InvalidBps();
        }
        if (_adapters[adapter].dapp != address(0)) {
            revert AlreadyRegistered();
        }

        _adapters[adapter] = AdapterInfo({
            dapp: dapp,
            mode: mode,
            committedBps: committedBps,
            version: version,
            active: true,
            termsHash: termsHash,
            registeredAt: block.timestamp.toUint64()
        });
        _adaptersOfDapp[dapp].push(adapter);
        _allAdapters.push(adapter);
        emit AdapterRegistered(adapter, dapp, mode, committedBps, version, termsHash);
    }

    function deactivateAdapter(address adapter) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (_adapters[adapter].dapp == address(0)) {
            revert UnknownAdapter();
        }
        _adapters[adapter].active = false;
        emit AdapterDeactivated(adapter);
    }

    function reactivateAdapter(address adapter) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (_adapters[adapter].dapp == address(0)) {
            revert UnknownAdapter();
        }
        _adapters[adapter].active = true;
        emit AdapterReactivated(adapter);
    }

    /// @notice Terms are versioned metadata; changing them cannot change an adapter's hardcoded
    ///         on-chain behaviour. A new commitment means a new adapter.
    function updateTerms(address adapter, bytes32 termsHash, uint32 version) external onlyRole(REGISTRY_ADMIN_ROLE) {
        AdapterInfo storage info = _adapters[adapter];
        if (info.dapp == address(0)) {
            revert UnknownAdapter();
        }
        emit TermsUpdated(adapter, info.termsHash, termsHash, version);
        info.termsHash = termsHash;
        info.version = version;
    }

    function recordContribution(address adapter, address token, uint256 amount) external {
        if (msg.sender != distributor) {
            revert NotDistributor();
        }
        lifetimeContribution[adapter][token] += amount;
        emit ContributionRecorded(adapter, token, amount);
    }

    function isActiveAdapter(address adapter) external view returns (bool) {
        return _adapters[adapter].active;
    }

    function adapterInfo(address adapter) external view returns (AdapterInfo memory) {
        return _adapters[adapter];
    }

    function adaptersOfDapp(address dapp) external view returns (address[] memory) {
        return _adaptersOfDapp[dapp];
    }

    function allAdapters() external view returns (address[] memory) {
        return _allAdapters;
    }
}
