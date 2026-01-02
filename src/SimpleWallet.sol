// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title SimpleWallet
/// @notice Minimal wallet deployed by an EOA via ERC-7702 + CREATE2
contract SimpleWallet {
    address public immutable owner;
    uint256 public nonce;

    event Executed(address indexed target, uint256 value, bytes data);

    constructor(address _owner) payable {
        owner = _owner;
    }

    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        nonce++;
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "call failed");
        emit Executed(target, value, data);
        return result;
    }

    receive() external payable {}
}
