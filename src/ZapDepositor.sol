// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IWXDC} from "./interfaces/IWXDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ZapDepositor
/// @notice Immutable helper that turns native XDC into a veXDC position in one transaction.
/// @dev Holds no funds between calls and has no owner, no setter and no upgrade path.
///      Eligibility is enforced by the escrow against the *beneficiary*, not this contract.
contract ZapDepositor {
    using SafeERC20 for IERC20;

    IWXDC public immutable WXDC;
    IVotingEscrow public immutable ESCROW;

    event Zapped(address indexed beneficiary, uint256 indexed tokenId, uint256 amount, uint256 duration);
    event ZapIncreased(uint256 indexed tokenId, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error EscrowTokenMismatch();

    constructor(address wxdc_, address escrow_) {
        if (wxdc_ == address(0) || escrow_ == address(0)) {
            revert ZeroAddress();
        }
        if (IVotingEscrow(escrow_).token() != wxdc_) {
            revert EscrowTokenMismatch();
        }
        WXDC = IWXDC(wxdc_);
        ESCROW = IVotingEscrow(escrow_);
        IERC20(wxdc_).forceApprove(escrow_, type(uint256).max);
    }

    /// @notice Wraps `msg.value` and creates a lock owned by `beneficiary`.
    function zapCreateLock(address beneficiary, uint256 duration) external payable returns (uint256 tokenId) {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        if (beneficiary == address(0)) {
            revert ZeroAddress();
        }
        WXDC.deposit{value: msg.value}();
        tokenId = ESCROW.createLockFor(beneficiary, msg.value, duration);
        emit Zapped(beneficiary, tokenId, msg.value, duration);
    }

    /// @notice Wraps `msg.value` and adds it to an existing position.
    function zapIncreaseAmount(uint256 tokenId) external payable {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        WXDC.deposit{value: msg.value}();
        ESCROW.increaseAmount(tokenId, msg.value);
        emit ZapIncreased(tokenId, msg.value);
    }
}
