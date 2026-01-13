// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MockERC20} from "./MockERC20.sol";

/// @title MockDEX
/// @notice Simple DEX that swaps tokenA for tokenB at 1:2 ratio
contract MockDEX {
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    uint256 public constant EXCHANGE_RATE = 2;

    event Swap(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor(MockERC20 _tokenA, MockERC20 _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function swap(uint256 amountIn) external returns (uint256 amountOut) {
        tokenA.transferFrom(msg.sender, address(this), amountIn);

        amountOut = amountIn * EXCHANGE_RATE;
        tokenB.transfer(msg.sender, amountOut);

        emit Swap(msg.sender, amountIn, amountOut);
    }

    function getAmountOut(uint256 amountIn) external pure returns (uint256) {
        return amountIn * EXCHANGE_RATE;
    }
}
