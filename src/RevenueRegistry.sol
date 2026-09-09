// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRevenueRegistry} from "./interfaces/IRevenueRegistry.sol";
import {ISystemAccess} from "./interfaces/ISystemAccess.sol";
import {Constants} from "./libraries/Constants.sol";
import {Roles} from "./libraries/Roles.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title RevenueRegistry
/// @notice Metadata plane for the revenue standard: whitelisting, terms, mode, version and
///         lifetime contribution. It never holds funds and never holds an allowance (§3.2).
contract RevenueRegistry is IRevenueRegistry, ContextUpgradeable, UUPSUpgradeable {
    using SafeCast for uint256;

    bytes32 public constant DEFAULT_ADMIN_ROLE = Roles.DEFAULT_ADMIN;
    bytes32 public constant UPGRADER_ROLE = Roles.UPGRADER;
    bytes32 public constant REGISTRY_ADMIN_ROLE = Roles.REGISTRY_ADMIN;

    ISystemAccess public authority;
    address public distributor;

    mapping(address adapter => AdapterInfo) private _adapters;
    mapping(address adapter => mapping(address token => uint256)) public lifetimeContribution;
    mapping(address dapp => address[]) private _adaptersOfDapp;
    address[] private _allAdapters;

    // Reserved storage for future upgrades; intentionally never read.
    // forge-lint: disable-start(mixed-case-variable, unused-state-variables)
    // slither-disable-next-line unused-state
    uint256[40] private __gap;
    // forge-lint: disable-end(mixed-case-variable, unused-state-variables)

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
    error DistributorAlreadySet();

    constructor() {
        _disableInitializers();
    }

    function initialize(address authority_) external initializer {
        if (authority_ == address(0)) {
            revert ZeroAddress();
        }
        __UUPSUpgradeable_init();
        authority = ISystemAccess(authority_);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return authority.hasRole(address(this), role, account);
    }

    function _authorizeUpgrade(address) internal override onlyAuthorityRole(UPGRADER_ROLE) {}

    function setDistributor(address distributor_) external onlyAuthorityRole(DEFAULT_ADMIN_ROLE) {
        if (distributor_ == address(0)) {
            revert ZeroAddress();
        }
        if (distributor != address(0)) {
            revert DistributorAlreadySet();
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
    ) external onlyAuthorityRole(REGISTRY_ADMIN_ROLE) {
        if (adapter == address(0) || dapp == address(0)) {
            revert ZeroAddress();
        }
        if (mode == Mode.NONE) {
            revert InvalidMode();
        }
        // Mode C may record 0 bps as metadata; every fund-moving mode mirrors adapter
        // constructors and requires a positive commitment.
        if (committedBps > Constants.BPS || (mode != Mode.ATTESTATION && committedBps == 0)) {
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

    function deactivateAdapter(address adapter) external onlyAuthorityRole(REGISTRY_ADMIN_ROLE) {
        if (_adapters[adapter].dapp == address(0)) {
            revert UnknownAdapter();
        }
        _adapters[adapter].active = false;
        emit AdapterDeactivated(adapter);
    }

    function reactivateAdapter(address adapter) external onlyAuthorityRole(REGISTRY_ADMIN_ROLE) {
        if (_adapters[adapter].dapp == address(0)) {
            revert UnknownAdapter();
        }
        _adapters[adapter].active = true;
        emit AdapterReactivated(adapter);
    }

    /// @notice Terms are versioned metadata; changing them cannot change an adapter's hardcoded
    ///         on-chain behaviour. A new commitment means a new adapter.
    function updateTerms(address adapter, bytes32 termsHash, uint32 version)
        external
        onlyAuthorityRole(REGISTRY_ADMIN_ROLE)
    {
        AdapterInfo storage info = _adapters[adapter];
        if (info.dapp == address(0)) {
            revert UnknownAdapter();
        }
        emit TermsUpdated(adapter, info.termsHash, termsHash, version);
        info.termsHash = termsHash;
        info.version = version;
    }

    function recordContribution(address adapter, address token, uint256 amount) external {
        if (_msgSender() != distributor) {
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

    modifier onlyAuthorityRole(bytes32 role) {
        authority.checkRole(address(this), role, _msgSender());
        _;
    }
}
