// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Test, Vm, console} from "forge-std/Test.sol";
import {Deployer} from "../src/Deployer.sol";
import {SimpleWallet} from "../src/SimpleWallet.sol";

/// @title Create2FromEOATest
/// @notice Demonstrates that a delegated EOA can deploy contracts via CREATE2
contract Create2FromEOATest is Test {
    Deployer public deployer;
    Vm.Wallet _alice;

    function setUp() public {
        _alice = vm.createWallet("alice");
        vm.deal(_alice.addr, 10 ether);
        deployer = new Deployer();
    }

    function test_EOA_DeploysViaCreate2() public {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(deployer), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        bytes32 salt = bytes32(uint256(1));
        bytes memory initCode = abi.encodePacked(type(SimpleWallet).creationCode, abi.encode(_alice.addr));

        // Predict address using the contract's function (called on Alice's EOA!)
        address predicted = Deployer(payable(_alice.addr)).predictAddress(initCode, salt);
        console.log("Predicted address:", predicted);

        // Deploy
        vm.prank(_alice.addr, _alice.addr);
        address deployed = Deployer(payable(_alice.addr)).deploy2(initCode, salt);
        console.log("Deployed address:", deployed);

        assertEq(predicted, deployed, "prediction should match");

        // Verify the wallet works and Alice owns it
        SimpleWallet wallet = SimpleWallet(payable(deployed));
        assertEq(wallet.owner(), _alice.addr);
        console.log("Wallet owner:", wallet.owner());
    }

    function test_DeployerIsEOA_NotDelegatee() public {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(deployer), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        bytes32 salt = bytes32(uint256(42));
        bytes memory initCode = abi.encodePacked(type(SimpleWallet).creationCode, abi.encode(_alice.addr));

        // Compute address manually - the deployer is Alice's EOA, NOT the delegatee contract!
        address manualPrediction = _computeCreate2Address(_alice.addr, salt, initCode);

        vm.prank(_alice.addr, _alice.addr);
        address deployed = Deployer(payable(_alice.addr)).deploy2(initCode, salt);

        assertEq(manualPrediction, deployed, "EOA should be the deployer");
        console.log("Confirmed: EOA address", _alice.addr, "is the deployer");
    }

    function test_SameCodeDifferentDeployer_DifferentAddress() public {
        bytes32 salt = bytes32(uint256(123));
        bytes memory initCode = abi.encodePacked(type(SimpleWallet).creationCode, abi.encode(_alice.addr));

        // Deploy from the delegatee contract directly
        address fromDelegatee = deployer.deploy2(initCode, salt);
        console.log("Deployed from delegatee contract:", fromDelegatee);

        // Deploy from Alice's EOA (same salt, same code)
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(deployer), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        vm.prank(_alice.addr, _alice.addr);
        address fromEOA = Deployer(payable(_alice.addr)).deploy2(initCode, salt);
        console.log("Deployed from Alice's EOA:", fromEOA);

        // Same code, same salt, but DIFFERENT addresses because deployer differs!
        assertTrue(fromDelegatee != fromEOA, "addresses should differ");
        console.log("Different deployers = different CREATE2 addresses");
    }

    /// @notice Compute CREATE2 address: keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))
    /// TODO(human): Implement the CREATE2 address derivation formula
    function _computeCreate2Address(address deployerAddr, bytes32 salt, bytes memory initCode)
        internal
        pure
        returns (address)
    {

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployerAddr, salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }

    function test_DeployWithETH() public {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(deployer), _alice.privateKey);
        vm.attachDelegation(signedDelegation);

        bytes32 salt = bytes32(uint256(999));
        bytes memory initCode = abi.encodePacked(type(SimpleWallet).creationCode, abi.encode(_alice.addr));

        vm.prank(_alice.addr, _alice.addr);
        address deployed = Deployer(payable(_alice.addr)).deploy2{value: 1 ether}(initCode, salt);

        assertEq(deployed.balance, 1 ether);
        console.log("Deployed wallet with 1 ETH initial balance");
    }
}
