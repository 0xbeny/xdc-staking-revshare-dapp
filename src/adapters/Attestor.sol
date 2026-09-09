// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {EpochTime} from "../libraries/EpochTime.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Attestor
/// @notice Mode C — atomic epoch attestation (§3.2 #6).
///
/// @dev Exactly one immutable record per `(dapp, token, sourceEpoch)`. The record and the fund
///      transfer are a single atomic transaction; duplicates revert. There is no pre-finalization
///      superseding and no mutable state on a record.
///
///      Errors are corrected by posting a signed adjustment against a *later* source period:
///      a positive adjustment transfers additional funds, a negative adjustment offsets against
///      that later transfer. Nothing is ever clawed back from the distributor.
///
///      `sourceEpoch` is metadata for dashboards and reconciliation. `distributionEpoch` is
///      assigned at receipt and can never be chosen by the reporter (§3.2 #8).
contract Attestor {
    using SafeERC20 for IERC20;

    struct Record {
        address dapp;
        address token;
        uint64 sourceEpoch;
        uint64 distributionEpoch;
        uint256 gross;
        int256 adjustment;
        uint256 net;
        bytes32 metadataHash;
        uint64 postedAt;
    }

    address public immutable DISTRIBUTOR;
    /// @notice Only the timelock may rotate the reporter. There is no upgrade path.
    address public immutable TIMELOCK;

    address public reporter;
    mapping(bytes32 key => Record) private _records;
    mapping(bytes32 key => bool) public posted;
    mapping(address dapp => mapping(address token => uint256)) public lifetimeNet;
    bytes32[] private _keys;

    event RevenuePosted(
        address indexed dapp,
        address indexed token,
        uint64 indexed sourceEpoch,
        uint64 distributionEpoch,
        uint256 gross,
        int256 adjustment,
        uint256 net,
        bytes32 metadataHash
    );
    event ReporterSet(address indexed oldReporter, address indexed newReporter);

    error ZeroAddress();
    error NotReporter();
    error NotTimelock();
    error DuplicateRecord();
    error SourceEpochNotClosed();
    error NegativeNet();

    constructor(address distributor_, address timelock_, address reporter_) {
        if (distributor_ == address(0) || timelock_ == address(0) || reporter_ == address(0)) {
            revert ZeroAddress();
        }
        DISTRIBUTOR = distributor_;
        TIMELOCK = timelock_;
        reporter = reporter_;
    }

    function setReporter(address newReporter) external {
        if (msg.sender != TIMELOCK) {
            revert NotTimelock();
        }
        if (newReporter == address(0)) {
            revert ZeroAddress();
        }
        emit ReporterSet(reporter, newReporter);
        reporter = newReporter;
    }

    function key(address dapp, address token, uint64 sourceEpoch) public pure returns (bytes32) {
        // Readability over the marginal gas saving of an assembly hash.
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encode(dapp, token, sourceEpoch));
    }

    /// @notice Posts one atomic attestation. Funds move in the same transaction as the record.
    /// @param sourceEpoch The period the revenue relates to. Metadata only; must already be closed.
    /// @param gross The attested gross amount for that period.
    /// @param adjustment A signed correction for an *earlier* period, settled against this one.
    function postRevenue(
        address dapp,
        address token,
        uint64 sourceEpoch,
        uint256 gross,
        int256 adjustment,
        bytes32 metadataHash
    ) external returns (uint256 net) {
        if (msg.sender != reporter) {
            revert NotReporter();
        }
        if (dapp == address(0)) {
            revert ZeroAddress();
        }
        if (sourceEpoch >= EpochTime.currentEpoch()) {
            revert SourceEpochNotClosed();
        }

        bytes32 k = key(dapp, token, sourceEpoch);
        if (posted[k]) {
            revert DuplicateRecord();
        }

        // `gross` is bounded by an ERC20 supply; the int256 cast cannot wrap in practice and
        // an overflowing value would revert on the transfer below regardless.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedNet = int256(gross) + adjustment;
        if (signedNet < 0) {
            revert NegativeNet();
        }
        // Checked non-negative on the line above.
        // forge-lint: disable-next-line(unsafe-typecast)
        net = uint256(signedNet);

        uint64 distributionEpoch = uint64(EpochTime.currentEpoch());
        posted[k] = true;
        _records[k] = Record({
            dapp: dapp,
            token: token,
            sourceEpoch: sourceEpoch,
            distributionEpoch: distributionEpoch,
            gross: gross,
            adjustment: adjustment,
            net: net,
            metadataHash: metadataHash,
            postedAt: uint64(block.timestamp)
        });
        _keys.push(k);
        lifetimeNet[dapp][token] += net;

        if (net > 0) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), net);
            IERC20(token).forceApprove(DISTRIBUTOR, net);
            IFeeDistributor(DISTRIBUTOR).notifyRevenue(token, net);
        }

        emit RevenuePosted(dapp, token, sourceEpoch, distributionEpoch, gross, adjustment, net, metadataHash);
    }

    function records(address dapp, address token, uint64 sourceEpoch) external view returns (Record memory) {
        return _records[key(dapp, token, sourceEpoch)];
    }

    function recordCount() external view returns (uint256) {
        return _keys.length;
    }

    function recordAt(uint256 index) external view returns (Record memory) {
        return _records[_keys[index]];
    }
}
