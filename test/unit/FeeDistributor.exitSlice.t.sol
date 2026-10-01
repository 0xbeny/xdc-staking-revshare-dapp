// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "../Base.t.sol";

contract ExitSliceGuardTest is Base {
    function test_anExitLargerThanSupplyDoesNotMoveMoreThanThePot() public {
        _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
        uint256 pot = 1000e6;
        _notifyExact(address(usdc), pot);
        uint256 funded = _currentEpoch();
        _nextEpoch();

        vm.mockCall(
            address(escrow), abi.encodeWithSelector(escrow.exitedWeightByEpoch.selector), abi.encode(uint256(150))
        );
        vm.mockCall(
            address(escrow), abi.encodeWithSelector(escrow.totalSupplyAtWeek.selector), abi.encode(uint256(100))
        );
        distributor.settle(address(usdc), 52);

        assertEq(distributor.epochRevenue(address(usdc), funded), pot, "the funded epoch keeps its pot");
        assertEq(distributor.epochRevenue(address(usdc), funded + 1), 0, "an oversized slice is not forwarded");
    }
}
