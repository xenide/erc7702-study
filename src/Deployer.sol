// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Deployer
/// @notice ERC-7702 delegatee that enables EOAs to deploy contracts via CREATE/CREATE2
contract Deployer {
    event Deployed(address indexed deployed, bytes32 salt);

    /// @notice Deploy using CREATE (nonce-based address)
    function deploy(bytes memory initCode) external payable returns (address deployed) {
        assembly {
            deployed := create(callvalue(), add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "CREATE failed");
        emit Deployed(deployed, bytes32(0));
    }

    /// @notice Deploy using CREATE2 (deterministic address)
    function deploy2(bytes memory initCode, bytes32 salt) external payable returns (address deployed) {
        assembly {
            deployed := create2(callvalue(), add(initCode, 0x20), mload(initCode), salt)
        }
        require(deployed != address(0), "CREATE2 failed");
        emit Deployed(deployed, salt);
    }

    /// @notice Predict CREATE2 address without deploying
    function predictAddress(bytes memory initCode, bytes32 salt) external view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)))))
        );
    }

    receive() external payable {}
}
