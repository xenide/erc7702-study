// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title SessionKeyDelegatee
/// @notice Delegatee enabling EOAs to grant limited permissions to session keys via EIP-712 signatures
contract SessionKeyDelegatee {
    struct SessionKey {
        uint256 validUntil;
        uint256 spendLimit;
        uint256 spentAmount;
        bool isActive;
    }

    struct SessionKeyPermissions {
        address[] allowedTargets;
        bytes4[] allowedSelectors;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    mapping(address => SessionKey) public sessionKeys;
    mapping(address => SessionKeyPermissions) internal sessionKeyPermissions;
    uint256 public nonce;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant REGISTER_TYPEHASH = keccak256(
        "RegisterSessionKey(address sessionKey,uint256 validUntil,uint256 spendLimit,address[] allowedTargets,bytes4[] allowedSelectors,uint256 nonce)"
    );
    bytes32 public constant EXECUTE_TYPEHASH = keccak256("Execute(bytes32 callsHash,uint256 nonce)");
    bytes32 public constant REVOKE_TYPEHASH = keccak256("RevokeSessionKey(address sessionKey,uint256 nonce)");

    event SessionKeyRegistered(
        address indexed sessionKey, uint256 validUntil, uint256 spendLimit, address[] allowedTargets
    );
    event SessionKeyRevoked(address indexed sessionKey);
    event SessionKeyExecuted(address indexed sessionKey, uint256 callCount, uint256 totalValue);
    event OwnerExecuted(uint256 callCount, uint256 totalValue);

    error InvalidSignature();
    error SessionKeyNotActive();
    error SessionKeyExpired();
    error SpendLimitExceeded();
    error TargetNotAllowed();
    error SelectorNotAllowed();
    error CallFailed(uint256 index, bytes reason);

    function registerSessionKey(
        address sessionKey,
        uint256 validUntil,
        uint256 spendLimit,
        address[] calldata allowedTargets,
        bytes4[] calldata allowedSelectors,
        bytes calldata ownerSignature
    ) external {
        bytes32 structHash = keccak256(
            abi.encode(REGISTER_TYPEHASH, sessionKey, validUntil, spendLimit, allowedTargets, allowedSelectors, nonce)
        );
        _verifyOwnerSignature(_hashTypedData(structHash), ownerSignature);

        ++nonce;
        sessionKeys[sessionKey] = SessionKey(validUntil, spendLimit, 0, true);
        sessionKeyPermissions[sessionKey] = SessionKeyPermissions(allowedTargets, allowedSelectors);

        emit SessionKeyRegistered(sessionKey, validUntil, spendLimit, allowedTargets);
    }

    function revokeSessionKey(address sessionKey, bytes calldata ownerSignature) external {
        bytes32 structHash = keccak256(abi.encode(REVOKE_TYPEHASH, sessionKey, nonce));
        _verifyOwnerSignature(_hashTypedData(structHash), ownerSignature);

        ++nonce;
        sessionKeys[sessionKey].isActive = false;
        delete sessionKeyPermissions[sessionKey];

        emit SessionKeyRevoked(sessionKey);
    }

    function execute(Call[] calldata calls, bytes calldata ownerSignature) external payable {
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, callsHash, nonce));
        _verifyOwnerSignature(_hashTypedData(structHash), ownerSignature);

        ++nonce;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
            (bool success, bytes memory returnData) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            if (!success) revert CallFailed(i, returnData);
        }

        emit OwnerExecuted(calls.length, totalValue);
    }

    function executeAsSessionKey(Call[] calldata calls) external payable {
        SessionKey storage sk = sessionKeys[msg.sender];

        if (!sk.isActive) revert SessionKeyNotActive();
        if (block.timestamp > sk.validUntil) revert SessionKeyExpired();

        SessionKeyPermissions storage perms = sessionKeyPermissions[msg.sender];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata c = calls[i];
            totalValue += c.value;

            if (!_isTargetAllowed(perms.allowedTargets, c.target)) revert TargetNotAllowed();
            if (c.data.length >= 4) {
                bytes4 selector = bytes4(c.data[:4]);
                if (!_isSelectorAllowed(perms.allowedSelectors, selector)) revert SelectorNotAllowed();
            }
        }

        if (sk.spentAmount + totalValue > sk.spendLimit) revert SpendLimitExceeded();
        sk.spentAmount += totalValue;

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returnData) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            if (!success) revert CallFailed(i, returnData);
        }

        emit SessionKeyExecuted(msg.sender, calls.length, totalValue);
    }

    function getSessionKey(address sessionKey) external view returns (SessionKey memory) {
        return sessionKeys[sessionKey];
    }

    function getSessionKeyPermissions(address sessionKey)
        external
        view
        returns (address[] memory allowedTargets, bytes4[] memory allowedSelectors)
    {
        SessionKeyPermissions storage perms = sessionKeyPermissions[sessionKey];
        return (perms.allowedTargets, perms.allowedSelectors);
    }

    function isValidSessionKey(address sessionKey) external view returns (bool) {
        SessionKey storage sk = sessionKeys[sessionKey];
        return sk.isActive && block.timestamp <= sk.validUntil;
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("SessionKeyDelegatee"), keccak256("1"), block.chainid, address(this))
        );
    }

    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _verifyOwnerSignature(bytes32 digest, bytes memory signature) internal view {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        address recovered = ecrecover(digest, v, r, s);
        if (recovered != address(this)) revert InvalidSignature();
    }

    function _isTargetAllowed(address[] storage allowedTargets, address target) internal view returns (bool) {
        if (allowedTargets.length == 0) return true;
        for (uint256 i = 0; i < allowedTargets.length; i++) {
            if (allowedTargets[i] == target) return true;
        }
        return false;
    }

    function _isSelectorAllowed(bytes4[] storage allowedSelectors, bytes4 selector) internal view returns (bool) {
        if (allowedSelectors.length == 0) return true;
        for (uint256 i = 0; i < allowedSelectors.length; i++) {
            if (allowedSelectors[i] == selector) return true;
        }
        return false;
    }

    receive() external payable {}
}
