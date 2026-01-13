// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title BatchExecutor
/// @notice ERC-7702 delegatee enabling atomic batch transactions from an EOA
contract BatchExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function executeBatch(Call[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call{value: calls[i].value}(calls[i].data);

            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }

            results[i] = result;
        }
    }

    function executeBatchAllowFailure(Call[] calldata calls)
        external
        payable
        returns (bool[] memory successes, bytes[] memory results)
    {
        successes = new bool[](calls.length);
        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (successes[i], results[i]) = calls[i].target.call{value: calls[i].value}(calls[i].data);
        }
    }

    receive() external payable {}
}
