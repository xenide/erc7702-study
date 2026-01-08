// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {SessionKeyDelegatee} from "../src/SessionKeyDelegatee.sol";
import {Test, Vm, console} from "forge-std/Test.sol";

contract SessionKeysTest is Test {
    SessionKeyDelegatee public delegatee;

    Vm.Wallet _owner;
    Vm.Wallet _sessionKey;

    // Simple counter contract for testing
    Counter public counter;

    function setUp() public {
        _owner = vm.createWallet("owner");
        _sessionKey = vm.createWallet("sessionKey");
        vm.deal(_owner.addr, 100 ether);
        vm.deal(_sessionKey.addr, 10 ether);

        delegatee = new SessionKeyDelegatee();
        counter = new Counter();

        _delegateOwner();
    }

    function _delegateOwner() internal {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(delegatee), _owner.privateKey);
        vm.attachDelegation(signedDelegation);
    }

    // ============ EIP-712 Signature Helpers ============

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SessionKeyDelegatee"),
                keccak256("1"),
                block.chainid,
                _owner.addr // Domain is the delegated EOA
            )
        );
    }

    function _signRegister(
        address sessionKey,
        uint256 validUntil,
        uint256 spendLimit,
        address[] memory allowedTargets,
        bytes4[] memory allowedSelectors,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "RegisterSessionKey(address sessionKey,uint256 validUntil,uint256 spendLimit,address[] allowedTargets,bytes4[] allowedSelectors,uint256 nonce)"
                ),
                sessionKey,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_owner.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signRevoke(address sessionKey, uint256 nonce) internal view returns (bytes memory) {
        bytes32 structHash =
            keccak256(abi.encode(keccak256("RevokeSessionKey(address sessionKey,uint256 nonce)"), sessionKey, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_owner.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signExecute(SessionKeyDelegatee.Call[] memory calls, uint256 nonce) internal view returns (bytes memory) {
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes32 structHash =
            keccak256(abi.encode(keccak256("Execute(bytes32 callsHash,uint256 nonce)"), callsHash, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_owner.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============ Registration Tests ============

    function test_RegisterSessionKey() public {
        address[] memory targets = new address[](1);
        targets[0] = address(counter);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Counter.increment.selector;

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);

        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        SessionKeyDelegatee.SessionKey memory sk =
            SessionKeyDelegatee(payable(_owner.addr)).getSessionKey(_sessionKey.addr);
        assertEq(sk.validUntil, block.timestamp + 1 days);
        assertEq(sk.spendLimit, 1 ether);
        assertEq(sk.spentAmount, 0);
        assertTrue(sk.isActive);
    }

    function test_RegisterSessionKey_InvalidSignature_Reverts() public {
        address[] memory targets = new address[](0);
        bytes4[] memory selectors = new bytes4[](0);

        // Sign with wrong key
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "RegisterSessionKey(address sessionKey,uint256 validUntil,uint256 spendLimit,address[] allowedTargets,bytes4[] allowedSelectors,uint256 nonce)"
                ),
                _sessionKey.addr,
                0
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_sessionKey.privateKey, digest); // Wrong signer!
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(SessionKeyDelegatee.InvalidSignature.selector);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, badSig);
    }

    // ============ Session Key Execution Tests ============

    function test_SessionKeyCanExecuteAllowedCall() public {
        // Register session key
        address[] memory targets = new address[](1);
        targets[0] = address(counter);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Counter.increment.selector;

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // Execute as session key
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] =
            SessionKeyDelegatee.Call({target: address(counter), value: 0, data: abi.encodeCall(Counter.increment, ())});

        vm.prank(_sessionKey.addr);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);

        assertEq(counter.count(), 1);
    }

    function test_SessionKeyCannotExceedSpendLimit() public {
        address[] memory targets = new address[](1);
        targets[0] = address(counter);
        bytes4[] memory selectors = new bytes4[](0); // Allow all selectors

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 0.5 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 0.5 ether, targets, selectors, sig);

        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] = SessionKeyDelegatee.Call({target: address(counter), value: 1 ether, data: ""});

        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.SpendLimitExceeded.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
    }

    function test_SessionKeyCannotCallUnauthorizedTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(counter);
        bytes4[] memory selectors = new bytes4[](0);

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // Try to call a different target
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] = SessionKeyDelegatee.Call({target: address(0xdead), value: 0, data: ""});

        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.TargetNotAllowed.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
    }

    function test_SessionKeyCannotCallUnauthorizedSelector() public {
        address[] memory targets = new address[](1);
        targets[0] = address(counter);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Counter.increment.selector; // Only increment allowed

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // Try to call reset() instead
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] =
            SessionKeyDelegatee.Call({target: address(counter), value: 0, data: abi.encodeCall(Counter.reset, ())});

        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.SelectorNotAllowed.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
    }

    function test_SessionKeyExpiresAfterValidUntil() public {
        address[] memory targets = new address[](0);
        bytes4[] memory selectors = new bytes4[](0);

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // Warp past expiry
        vm.warp(block.timestamp + 2 days);

        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] =
            SessionKeyDelegatee.Call({target: address(counter), value: 0, data: abi.encodeCall(Counter.increment, ())});

        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.SessionKeyExpired.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
    }

    // ============ Owner Execution Tests ============

    function test_OwnerCanExecuteAnything() public {
        // Owner can call any target with signature, no session key restrictions
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] =
            SessionKeyDelegatee.Call({target: address(counter), value: 0, data: abi.encodeCall(Counter.increment, ())});

        bytes memory sig = _signExecute(calls, 0);
        SessionKeyDelegatee(payable(_owner.addr)).execute(calls, sig);

        assertEq(counter.count(), 1);
    }

    // ============ Revocation Tests ============

    function test_OwnerCanRevokeSessionKey() public {
        // First register
        address[] memory targets = new address[](0);
        bytes4[] memory selectors = new bytes4[](0);
        bytes memory regSig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, regSig);

        // Verify active
        assertTrue(SessionKeyDelegatee(payable(_owner.addr)).isValidSessionKey(_sessionKey.addr));

        // Revoke (nonce is now 1 after registration)
        bytes memory revokeSig = _signRevoke(_sessionKey.addr, 1);
        SessionKeyDelegatee(payable(_owner.addr)).revokeSessionKey(_sessionKey.addr, revokeSig);

        // Verify revoked
        assertFalse(SessionKeyDelegatee(payable(_owner.addr)).isValidSessionKey(_sessionKey.addr));

        // Session key can no longer execute
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] = SessionKeyDelegatee.Call({target: address(counter), value: 0, data: ""});

        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.SessionKeyNotActive.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
    }

    // ============ Replay Protection Tests ============

    function test_ReplayProtection() public {
        address[] memory targets = new address[](0);
        bytes4[] memory selectors = new bytes4[](0);

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);

        // First registration succeeds
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // Replay with same signature fails (nonce changed)
        vm.expectRevert(SessionKeyDelegatee.InvalidSignature.selector);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);
    }

    // ============ Spend Tracking Tests ============

    function test_SpendLimitTracksAcrossMultipleCalls() public {
        address[] memory targets = new address[](1);
        targets[0] = address(counter);
        bytes4[] memory selectors = new bytes4[](0);

        bytes memory sig = _signRegister(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, 0);
        SessionKeyDelegatee(payable(_owner.addr))
            .registerSessionKey(_sessionKey.addr, block.timestamp + 1 days, 1 ether, targets, selectors, sig);

        // First call: spend 0.4 ether
        SessionKeyDelegatee.Call[] memory calls1 = new SessionKeyDelegatee.Call[](1);
        calls1[0] = SessionKeyDelegatee.Call({target: address(counter), value: 0.4 ether, data: ""});

        vm.prank(_sessionKey.addr);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls1);

        // Second call: spend 0.4 ether (total 0.8, under limit)
        vm.prank(_sessionKey.addr);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls1);

        // Third call: spend 0.4 ether (total 1.2, over limit)
        vm.prank(_sessionKey.addr);
        vm.expectRevert(SessionKeyDelegatee.SpendLimitExceeded.selector);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls1);

        // Verify spent amount
        SessionKeyDelegatee.SessionKey memory sk =
            SessionKeyDelegatee(payable(_owner.addr)).getSessionKey(_sessionKey.addr);
        assertEq(sk.spentAmount, 0.8 ether);
    }

    // ============ Exploit Tests ============

    /// @notice Demonstrates that the signature doesn't bind to permission parameters
    /// @dev The owner signs intending to grant LIMITED permissions, but an attacker
    ///      can use the same signature to register with UNLIMITED permissions
    function test_Exploit_SignatureDoesNotBindToPermissions() public {
        // === STEP 1: Owner intends to sign for RESTRICTED permissions ===
        address[] memory intendedTargets = new address[](1);
        intendedTargets[0] = address(counter); // Only allow counter contract

        bytes4[] memory intendedSelectors = new bytes4[](1);
        intendedSelectors[0] = Counter.increment.selector; // Only allow increment()

        uint256 intendedSpendLimit = 0.1 ether; // Only allow 0.1 ETH spending
        uint256 intendedValidUntil = block.timestamp + 1 hours; // Only valid for 1 hour

        // Owner signs the registration (thinking these restrictions will apply)
        bytes memory ownerSignature =
            _signRegister(_sessionKey.addr, intendedValidUntil, intendedSpendLimit, intendedTargets, intendedSelectors, 0);

        // === STEP 2: Attacker intercepts signature and registers with DIFFERENT params ===
        address[] memory attackerTargets = new address[](0); // Empty = ALL targets allowed!
        bytes4[] memory attackerSelectors = new bytes4[](0); // Empty = ALL selectors allowed!
        uint256 attackerSpendLimit = 1000 ether; // Massive spending limit!
        uint256 attackerValidUntil = block.timestamp + 365 days; // Valid for a year!

        // Attacker calls registerSessionKey with the owner's signature but different params
        // This SHOULD fail if the signature bound to the parameters... but it doesn't!
        // Now with the correct impl of `registerSessionKey`, the exploit will fail.
        vm.expectRevert(SessionKeyDelegatee.InvalidSignature.selector);
        SessionKeyDelegatee(payable(_owner.addr)).registerSessionKey(
            _sessionKey.addr,
            attackerValidUntil, // Different from what owner intended!
            attackerSpendLimit, // Different from what owner intended!
            attackerTargets, // Different from what owner intended!
            attackerSelectors, // Different from what owner intended!
            ownerSignature // Same signature the owner created
        );

        // === STEP 3: Verify the exploit worked ===
        SessionKeyDelegatee.SessionKey memory sk =
            SessionKeyDelegatee(payable(_owner.addr)).getSessionKey(_sessionKey.addr);

        // The session key was registered with ATTACKER's parameters, not owner's intent!
        assertEq(sk.spendLimit, 1000 ether, "Exploit: spendLimit was changed");
        assertEq(sk.validUntil, block.timestamp + 365 days, "Exploit: validUntil was changed");

        (address[] memory actualTargets, bytes4[] memory actualSelectors) =
            SessionKeyDelegatee(payable(_owner.addr)).getSessionKeyPermissions(_sessionKey.addr);
        assertEq(actualTargets.length, 0, "Exploit: targets were changed to allow all");
        assertEq(actualSelectors.length, 0, "Exploit: selectors were changed to allow all");

        // === STEP 4: Demonstrate the impact - session key can now do ANYTHING ===

        // Can call any target (not just counter)
        SessionKeyDelegatee.Call[] memory calls = new SessionKeyDelegatee.Call[](1);
        calls[0] = SessionKeyDelegatee.Call({
            target: address(0xdead), // Arbitrary target - owner intended only `counter`!
            value: 0,
            data: ""
        });
        vm.prank(_sessionKey.addr);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
        // ^ This succeeds when owner intended to restrict to only `counter`!

        // Can spend way more ETH than owner intended
        calls[0] = SessionKeyDelegatee.Call({
            target: address(counter),
            value: 50 ether, // Owner intended max 0.1 ETH!
            data: ""
        });
        vm.prank(_sessionKey.addr);
        SessionKeyDelegatee(payable(_owner.addr)).executeAsSessionKey(calls);
        // ^ This succeeds when owner intended max 0.1 ETH!
    }
}

// Simple counter contract for testing
contract Counter {
    uint256 public count;

    function increment() external {
        count++;
    }

    function reset() external {
        count = 0;
    }

    receive() external payable {}
}
