// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IWXDC} from "./interfaces/IWXDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @title ZapDepositor
/// @notice Immutable helper that turns native XDC into a veXDC position in one transaction.
///
/// @dev The depositor is always `_msgSender()`: the account whose XDC is wrapped and the
///      account recorded in every event. Holds no funds between calls and has no owner, no
///      setter, no `receive()` and no upgrade path — stray XDC sent here reverts.
///
///      Eligibility is enforced by the escrow against the *beneficiary*, never this contract.
contract ZapDepositor is Context {
    using SafeERC20 for IERC20;

    IWXDC public immutable WXDC;
    IVotingEscrow public immutable ESCROW;

    event Zapped(
        address indexed depositor,
        address indexed beneficiary,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 duration
    );
    event ZapIncreased(address indexed depositor, uint256 indexed tokenId, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error EscrowTokenMismatch();
    error NotPositionOwner();

    constructor(address wxdc_, address escrow_) {
        if (wxdc_ == address(0) || escrow_ == address(0)) {
            revert ZeroAddress();
        }
        if (IVotingEscrow(escrow_).token() != wxdc_) {
            revert EscrowTokenMismatch();
        }
        WXDC = IWXDC(wxdc_);
        ESCROW = IVotingEscrow(escrow_);
        // The escrow is immutable and the zap never holds a balance between calls, so a
        // one-time unlimited allowance is the conventional choice for immutable periphery.
        IERC20(wxdc_).forceApprove(escrow_, type(uint256).max);
    }

    /// @notice Wraps `msg.value` and creates a lock owned by the caller.
    function zapCreateLock(uint256 duration) external payable returns (uint256 tokenId) {
        return _zapCreateLock(_msgSender(), duration);
    }

    /// @notice Wraps `msg.value` and creates a lock owned by `beneficiary`, funded by the caller.
    /// @dev For custodial and gift flows. The escrow checks eligibility against `beneficiary`.
    function zapCreateLockFor(address beneficiary, uint256 duration) external payable returns (uint256 tokenId) {
        if (beneficiary == address(0)) {
            revert ZeroAddress();
        }
        return _zapCreateLock(beneficiary, duration);
    }

    /// @notice Wraps `msg.value` and adds it to a position the caller owns.
    /// @dev Owner-only on purpose: adding principal re-weights the position's grandfathered
    ///      penalty cap (spec §3.4), and only the owner can consent to that.
    function zapIncreaseAmount(uint256 tokenId) external payable {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        if (ESCROW.ownerOf(tokenId) != _msgSender()) {
            revert NotPositionOwner();
        }
        WXDC.deposit{value: msg.value}();
        ESCROW.increaseAmount(tokenId, msg.value);
        emit ZapIncreased(_msgSender(), tokenId, msg.value);
    }

    function _zapCreateLock(address beneficiary, uint256 duration) private returns (uint256 tokenId) {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        WXDC.deposit{value: msg.value}();
        tokenId = ESCROW.createLockFor(beneficiary, msg.value, duration);
        emit Zapped(_msgSender(), beneficiary, tokenId, msg.value, duration);
    }
}
