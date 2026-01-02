# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a study/exploration repository for ERC-7702 (Set Code Authorization for EOAs). ERC-7702 allows EOAs to sign authorizations that attach contract code to their addresses, enabling smart contract logic execution while remaining EOAs.

## Commands

**Build contracts:**
```bash
forge build
```

**Run all tests:**
```bash
forge test
```

**Run single test:**
```bash
forge test --mt testDelegate
```

**Run tests with verbosity (show logs):**
```bash
forge test -vvv
```

**Format Solidity:**
```bash
forge fmt
```

**Run TypeScript scripts:**
```bash
npx tsx script/example.ts
```

## Architecture

### Foundry Configuration
- Solidity 0.8.33
- EVM version: `osaka` (required for ERC-7702 support)
- Ignored error codes: 2424, 5574

### Key ERC-7702 Concepts Demonstrated

**Delegation flow in tests (`test/ERC7702Delegatee.t.sol`):**
1. `vm.signDelegation(address, privateKey)` - Signs an ERC-7702 authorization
2. `vm.attachDelegation(signedDelegation)` - Attaches delegation to make EOA executable

**Storage behavior:**
- When calling functions on a delegated EOA, state changes occur in the EOA's storage, not the delegatee contract's
- Delegated EOAs have 23 bytes of code (20 bytes address + 3 magic bytes)

**Undelegation:**
- Sign delegation with `address(0)` to remove delegation

### TypeScript Scripts
Scripts in `script/` use viem to interact with ERC-7702 on Sepolia testnet. Requires configuring private key in `script/client.ts`.


## Style
Use comments sparingly when generating code.