// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title VulnerableVault
/// @notice Vault with broken tx.origin check - vulnerable to reentrancy post-ERC7702
/// @dev Pre-ERC7702, tx.origin == msg.sender implied EOA caller. Post-ERC7702, EOAs can have code.
contract VulnerableVault {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    error NoContractsAllowed(address txOrigin, address msgSender);

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Withdraw all funds - vulnerable due to CEI violation + broken tx.origin assumption
    function withdraw() external {
        require(tx.origin == msg.sender, NoContractsAllowed(tx.origin, msg.sender));

        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        balances[msg.sender] = 0;

        emit Withdraw(msg.sender, amount);
    }

    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
