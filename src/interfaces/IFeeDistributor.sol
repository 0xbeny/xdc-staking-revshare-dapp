// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFeeDistributor {
    function notifyRevenue(address token, uint256 amount) external;
    function syncForfeiture(address token) external returns (uint256 credited);
    function claimable(uint256 tokenId, address token) external view returns (uint256 amount, uint256 remaining);
    function claim(uint256 tokenId, address[] calldata tokens)
        external
        returns (uint256[] memory amounts, uint256 remaining);
}
