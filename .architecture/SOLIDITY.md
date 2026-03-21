# SOLIDITY.md

This repository follows a **Solidity smart contract architecture** for EVM-compatible chains.

Goals:
- security-first contract development
- deterministic, auditable state transitions
- upgrade-safe storage and deployment workflows
- strong verification before mainnet deployment

## Core rules

- Keep protocol invariants explicit and testable.
- Separate contract logic from off-chain orchestration.
- Prefer battle-tested OpenZeppelin primitives over custom cryptography.
- Treat every external call and token interaction as adversarial.

## Suggested structure

```text
contracts/
  src/
  script/
  test/
  lib/
```

## Contract rules

- Use checks-effects-interactions by default.
- Use custom errors over long revert strings.
- Emit events for all state-changing operations.
- Keep access control explicit and least-privilege.
- Never rely on unbounded loops for critical paths.

## Tooling rules

- Use TypeScript/Node for deployment and automation scripts.
- Keep compiler and dependency versions pinned.
- Verify bytecode and metadata for all production deployments.

## Testing and verification

- Require unit, fuzz, and invariant testing.
- Run static analysis before merge.
- Validate upgrade paths and storage layout compatibility.
- Rehearse deployment on testnet/fork before production.

When in doubt:

**Choose the simpler contract design that preserves safety and auditability.**
