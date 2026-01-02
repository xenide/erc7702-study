// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, Vm, console} from "forge-std/Test.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";

/// @title BatchTransactionTest
/// @notice Demonstrates the UX improvement of ERC-7702 batch transactions
contract BatchTransactionTest is Test {
    BatchExecutor public batchExecutor;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockDEX public dex;

    Vm.Wallet _alice;

    uint256 constant SWAP_AMOUNT = 100 ether;

    function setUp() public {
        _alice = vm.createWallet("alice");
        vm.deal(_alice.addr, 10 ether);

        // Deploy contracts
        batchExecutor = new BatchExecutor();
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        dex = new MockDEX(tokenA, tokenB);

        // Give Alice some tokenA
        tokenA.mint(_alice.addr, 1000 ether);

        // Give DEX some tokenB for swaps
        tokenB.mint(address(dex), 10000 ether);
    }

    /// @notice The OLD way: Two separate transactions required
    function test_OldWay_TwoTransactions() public {
        console.log("=== OLD WAY: Two Transactions ===");

        // Transaction 1: Approve
        vm.prank(_alice.addr, _alice.addr);
        tokenA.approve(address(dex), SWAP_AMOUNT);
        console.log("TX 1: Approved DEX to spend tokenA");

        // Transaction 2: Swap
        vm.prank(_alice.addr, _alice.addr);
        dex.swap(SWAP_AMOUNT);
        console.log("TX 2: Swapped tokenA for tokenB");

        // Verify result
        assertEq(tokenB.balanceOf(_alice.addr), SWAP_AMOUNT * 2); // 1:2 ratio
        console.log("Alice received:", tokenB.balanceOf(_alice.addr) / 1e18, "tokenB");
    }

    /// @notice The NEW way: Single atomic transaction with ERC-7702!
    function test_NewWay_SingleBatchTransaction() public {
        console.log("=== NEW WAY: Single Batch Transaction ===");

        // Delegate Alice's EOA to BatchExecutor
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(batchExecutor), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        // Verify delegation
        assertEq(_alice.addr.code.length, 23);
        console.log("Alice's EOA delegated to BatchExecutor");

        // Build batch calls
        BatchExecutor.Call[] memory calls = _buildApproveAndSwapCalls();

        // Execute batch as Alice (single transaction!)
        vm.prank(_alice.addr, _alice.addr);
        BatchExecutor(payable(_alice.addr)).executeBatch(calls);
        console.log("TX 1: Approved AND Swapped in single transaction!");

        // Verify result
        assertEq(tokenB.balanceOf(_alice.addr), SWAP_AMOUNT * 2);
        console.log("Alice received:", tokenB.balanceOf(_alice.addr) / 1e18, "tokenB");
    }

    /// @notice Build the batch calls for approve + swap
    function _buildApproveAndSwapCalls() internal view returns (BatchExecutor.Call[] memory calls) {
        // Create an array of 2 calls:
        // 1. Approve the DEX to spend SWAP_AMOUNT of tokenA
        // 2. Call swap(SWAP_AMOUNT) on the DEX
        //
        // Each Call struct has:
        //   - target: the contract address to call
        //   - value: ETH to send (0 for these calls)
        //   - data: the encoded function call (use abi.encodeWithSelector or abi.encodeCall)
        calls = new BatchExecutor.Call[](2);
        calls[0] = BatchExecutor.Call({
            target: address(tokenA), value: 0, data: abi.encodeCall(MockERC20.approve, (address(dex), SWAP_AMOUNT))
        });
        calls[1] =
            BatchExecutor.Call({target: address(dex), value: 0, data: abi.encodeCall(MockDEX.swap, (SWAP_AMOUNT))});
    }

    /// @notice Bonus: Batch with ETH transfer included
    function test_BatchWithETH() public {
        // Delegate Alice's EOA
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(batchExecutor), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        address recipient = makeAddr("recipient");

        // Build calls: send ETH + approve + swap
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](3);

        // Call 0: Send 1 ETH to recipient
        calls[0] = BatchExecutor.Call({target: recipient, value: 1 ether, data: ""});

        // Call 1: Approve
        calls[1] = BatchExecutor.Call({
            target: address(tokenA), value: 0, data: abi.encodeCall(MockERC20.approve, (address(dex), SWAP_AMOUNT))
        });

        // Call 2: Swap
        calls[2] =
            BatchExecutor.Call({target: address(dex), value: 0, data: abi.encodeCall(MockDEX.swap, (SWAP_AMOUNT))});

        // Execute batch
        vm.prank(_alice.addr, _alice.addr);
        BatchExecutor(payable(_alice.addr)).executeBatch{value: 1 ether}(calls);

        // Verify all three operations succeeded
        assertEq(recipient.balance, 1 ether);
        assertEq(tokenB.balanceOf(_alice.addr), SWAP_AMOUNT * 2);

        console.log("Sent 1 ETH + Approved + Swapped in ONE transaction!");
    }

    /// @notice Show atomicity: if swap fails, approval is reverted too
    function test_Atomicity_AllOrNothing() public {
        // Delegate Alice's EOA
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(batchExecutor), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        // Try to swap more than Alice has
        uint256 tooMuch = 5000 ether;

        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](2);
        calls[0] = BatchExecutor.Call({
            target: address(tokenA), value: 0, data: abi.encodeCall(MockERC20.approve, (address(dex), tooMuch))
        });
        calls[1] = BatchExecutor.Call({target: address(dex), value: 0, data: abi.encodeCall(MockDEX.swap, (tooMuch))});

        // This should revert entirely - approval should NOT persist
        vm.prank(_alice.addr, _alice.addr);
        vm.expectRevert("ERC20: insufficient balance");
        BatchExecutor(payable(_alice.addr)).executeBatch(calls);

        // Verify approval was NOT set (atomicity!)
        assertEq(tokenA.allowance(_alice.addr, address(dex)), 0);
        console.log("Failed batch reverted entirely - no partial state changes!");
    }
}
