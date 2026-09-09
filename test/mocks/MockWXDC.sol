// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Canonical WETH9-shaped wrapper, matching WXDC on XDC mainnet.
contract MockWXDC is ERC20 {
    error TransferFailed();

    constructor() ERC20("Wrapped XDC", "WXDC") {}

    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) {
            revert TransferFailed();
        }
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
