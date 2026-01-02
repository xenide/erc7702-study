// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title VulnerableVault
/// @notice A vault that incorrectly assumes tx.origin == msg.sender means "safe EOA call"
/// @dev This pattern was sometimes used pre-ERC7702 to prevent contract interactions.
///      Post-ERC7702, this assumption is BROKEN because EOAs can now have code.
contract VulnerableVault {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    error NoContractsAllowed(address txOrigin, address msgSender);

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Withdraw all funds - "protected" by tx.origin check
    /// @dev The tx.origin == msg.sender check was meant to ensure only EOAs can call.
    ///      This is vulnerable to reentrancy post-ERC7702!
    function withdraw() external {
        // This check used to "guarantee" no contract could call this function
        // because contracts have msg.sender != tx.origin
        // POST-ERC7702: A delegated EOA has tx.origin == msg.sender BUT can have code!
        require(tx.origin == msg.sender, NoContractsAllowed(tx.origin, msg.sender));

        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        // VULNERABLE: State change AFTER external call (CEI violation)
        // Combined with the broken tx.origin assumption, this enables reentrancy
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        balances[msg.sender] = 0;

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Check vault's total balance
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
