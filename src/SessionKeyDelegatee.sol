// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title SessionKeyDelegatee
/// @notice Delegatee contract enabling EOAs to grant limited permissions to session keys
/// @dev When an EOA delegates to this contract, it gains session key management capabilities.
///      Owner authentication uses EIP-712 signatures since tx.origin checks are unreliable post-ERC7702.
contract SessionKeyDelegatee {
    // ============ Structs ============

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

    // ============ Storage ============
    // Note: This storage lives in the delegating EOA's address space, not this contract's

    mapping(address => SessionKey) public sessionKeys;
    mapping(address => SessionKeyPermissions) internal sessionKeyPermissions;
    uint256 public nonce;

    // ============ EIP-712 Constants ============

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant REGISTER_TYPEHASH = keccak256(
        "RegisterSessionKey(address sessionKey,uint256 validUntil,uint256 spendLimit,address[] allowedTargets,bytes4[] allowedSelectors,uint256 nonce)"
    );

    bytes32 public constant EXECUTE_TYPEHASH = keccak256("Execute(bytes32 callsHash,uint256 nonce)");

    bytes32 public constant REVOKE_TYPEHASH = keccak256("RevokeSessionKey(address sessionKey,uint256 nonce)");

    // ============ Events ============

    event SessionKeyRegistered(
        address indexed sessionKey, uint256 validUntil, uint256 spendLimit, address[] allowedTargets
    );
    event SessionKeyRevoked(address indexed sessionKey);
    event SessionKeyExecuted(address indexed sessionKey, uint256 callCount, uint256 totalValue);
    event OwnerExecuted(uint256 callCount, uint256 totalValue);

    // ============ Errors ============

    error InvalidSignature();
    error SessionKeyNotActive();
    error SessionKeyExpired();
    error SpendLimitExceeded();
    error TargetNotAllowed();
    error SelectorNotAllowed();
    error CallFailed(uint256 index, bytes reason);

    // ============ EIP-712 Helpers ============

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("SessionKeyDelegatee"), keccak256("1"), block.chainid, address(this))
        );
    }

    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _verifyOwnerSignature(bytes32 digest, bytes memory signature) internal view {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        address recovered = ecrecover(digest, v, r, s);
        // Owner is address(this) - the delegating EOA
        if (recovered != address(this)) revert InvalidSignature();
    }

    function _splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // ============ Owner Functions (Signature Required) ============

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
        bytes32 digest = _hashTypedData(structHash);
        _verifyOwnerSignature(digest, ownerSignature);

        ++nonce;
        SessionKey memory key = SessionKey(validUntil, spendLimit, 0, true);
        SessionKeyPermissions memory permissions = SessionKeyPermissions(allowedTargets, allowedSelectors);

        sessionKeys[sessionKey] = key;
        sessionKeyPermissions[sessionKey] = permissions;
        emit SessionKeyRegistered(sessionKey, validUntil, spendLimit, allowedTargets);
    }

    function revokeSessionKey(address sessionKey, bytes calldata ownerSignature) external {
        bytes32 structHash = keccak256(abi.encode(REVOKE_TYPEHASH, sessionKey, nonce));
        bytes32 digest = _hashTypedData(structHash);
        _verifyOwnerSignature(digest, ownerSignature);

        nonce++;
        sessionKeys[sessionKey].isActive = false;
        delete sessionKeyPermissions[sessionKey];

        emit SessionKeyRevoked(sessionKey);
    }

    function execute(Call[] calldata calls, bytes calldata ownerSignature) external payable {
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, callsHash, nonce));
        bytes32 digest = _hashTypedData(structHash);
        _verifyOwnerSignature(digest, ownerSignature);

        nonce++;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
            (bool success, bytes memory returnData) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            if (!success) revert CallFailed(i, returnData);
        }

        emit OwnerExecuted(calls.length, totalValue);
    }

    // ============ Session Key Functions ============

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

    // ============ View Functions ============

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

    // ============ Internal Helpers ============

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
