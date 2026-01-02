// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title BatchExecutor
/// @notice ERC-7702 delegatee that enables batch transactions from an EOA
/// @dev When an EOA delegates to this contract, they can execute multiple calls atomically
contract BatchExecutor {
    /// @notice Represents a single call in a batch
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Execute multiple calls in a single transaction
    /// @param calls Array of calls to execute
    /// @return results Array of return data from each call
    function executeBatch(Call[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call{value: calls[i].value}(calls[i].data);

            if (!success) {
                // Bubble up the revert reason
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }

            results[i] = result;
        }
    }

    /// @notice Execute multiple calls, allowing some to fail
    /// @param calls Array of calls to execute
    /// @return successes Array of success booleans
    /// @return results Array of return data from each call
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

    /// @notice Allow receiving ETH
    receive() external payable {}
}
