// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal Gnosis-Safe-shaped avatar with Zodiac module execution, for Mode B3 tests.
contract MockSafe {
    mapping(address module => bool) public isModuleEnabled;
    bool public execFails;

    error NotAModule();
    error OnlySelf();

    function enableModule(address module) external {
        isModuleEnabled[module] = true;
    }

    /// @dev Simulates a Safe whose module execution returns `false` (e.g. a guard rejecting it).
    function setExecFails(bool fails) external {
        execFails = fails;
    }

    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8)
        external
        returns (bool success)
    {
        if (!isModuleEnabled[msg.sender]) {
            revert NotAModule();
        }
        if (execFails) {
            return false;
        }
        (success,) = to.call{value: value}(data);
    }

    /// @dev Mode B2 grants an allowance from the Safe to the immutable PullAdapter.
    function approveToken(address token, address spender, uint256 amount) external {
        (bool ok,) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok, "approve failed");
    }

    receive() external payable {}
}
