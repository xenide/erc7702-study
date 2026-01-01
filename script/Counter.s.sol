// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

contract CounterScript is Script {
    address public _eoa = address(0x85073D34FB2e76c838D23CcEe105be5e66E26303);

    function setUp() public {
        uint256 lForkId = vm.createFork("https://sepolia.infura.io/v3/b9794ad1ddf84dfb8c34d6bb5dca2001");
        vm.selectFork(lForkId);
    }

    function run() public {
        // vm.startBroadcast();
        _printExtCode();
        _printStorageSlot();
        // vm.stopBroadcast();
    }

    function _printExtCode() internal {
        address eoa = _eoa;

        uint256 lCodeSize;
        bytes memory lExtCode;
        assembly ("memory-safe") {
            lCodeSize := extcodesize(eoa)

            if gt(lCodeSize, 0) {
                let ptr := mload(0x40)

                // stores the code size of EOA into memory
                mstore(ptr, lCodeSize)
                lExtCode := ptr

                // We start 0x20 later cuz the first 32 bytes contain the code size
                // Cuz for the `bytes memory` type, the EVM needs to know how long the bytes are, and that is the
                // stored as the first 32 bytes of `lExtCode`
                extcodecopy(eoa, add(ptr, 0x20), 0, lCodeSize)

                // update the free memory pointer, round up next 32 bytes
                mstore(0x40, add(add(ptr, 0x20), and(add(lCodeSize, 0x1f), not(0x1f))))
            }
        }
        console.log("extcodesize", lCodeSize);

        if (lCodeSize > 0) {
            console.logBytes(lExtCode);
        } else {
            console.log("No code at the address.");
        }
    }

    function _printStorageSlot() internal {
        bytes32 lData = vm.load(_eoa, 0);
        console.logBytes32(lData);
    }
}
