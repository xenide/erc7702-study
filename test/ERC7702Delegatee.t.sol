// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ERC7702Delegatee} from "../src/ERC7702Delegatee.sol";
import {Test, Vm, console} from "forge-std/Test.sol";

contract ERC7702DelegateeTest is Test {
    ERC7702Delegatee public delegatee;

    Vm.Wallet _alice;

    function setUp() public {
        _alice = vm.createWallet("alice");
        vm.deal(_alice.addr, 100 ether);

        delegatee = new ERC7702Delegatee();
        _delegate();
    }

    function _delegate() internal {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(delegatee), _alice.privateKey);
        vm.attachDelegation(signedDelegation);
    }

    function testDelegate() public {
        address aliceAddr = _alice.addr;

        uint256 aliceCodeSize;
        assembly {
            aliceCodeSize := extcodesize(aliceAddr)
        }
        assertEq(aliceCodeSize, 23); // 20 bytes of address + 3 magic bytes

        bytes32 aliceSlot0Value = vm.load(aliceAddr, 0);
        assertEq(aliceSlot0Value, 0); // In alice's storage slot it should be 0 and not written

        bytes32 delegateeSlot0Value = vm.load(address(delegatee), 0);
        assertEq(delegateeSlot0Value, bytes32(uint256(1))); // the delegatee's one should be the value initialized in the constructor

        ERC7702Delegatee(_alice.addr).setNumber(69);
        bytes32 aliceSlot0ValueAfter = vm.load(aliceAddr, 0);
        delegateeSlot0Value = vm.load(address(delegatee), 0);
        assertEq(aliceSlot0ValueAfter, bytes32(uint256(69)));
        assertEq(delegateeSlot0Value, bytes32(uint256(1))); // delegatee storage remains the same
    }

    // call Alice's address just like a contract
    function testRawCall() public {
        _alice.addr.call(abi.encodeWithSelector(ERC7702Delegatee.setNumber.selector, 69));
        bytes32 aliceSlot0Value = vm.load(address(_alice.addr), 0);
        assertEq(aliceSlot0Value, bytes32(uint256(69)));

        // Sending ETH to alice now will just revert as it doesn't have a receive / fallback function
        (bool success, ) = _alice.addr.call{value: 1 ether}("");
        assertFalse(success);
    }
}
