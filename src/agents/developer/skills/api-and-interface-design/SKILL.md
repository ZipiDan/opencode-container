---
name: api-and-interface-design
description: Design APIs and interfaces with explicit contracts, boundary validation, stable naming (Hyrum's Law), and versioning. Use when designing APIs, public functions, classes, or module interfaces.
---

# API and Interface Design

Design the surfaces of your code — APIs, public functions, classes, module
boundaries — so they are stable, predictable, and hard to misuse.

## Explicit contracts

- Every public function documents its contract: what it accepts, what it
  returns, what it raises/throws, what its preconditions are.
- Make impossible states unrepresentable where you can (typed unions,
  discriminated unions, branded types, sealed classes).
- Validate at the boundary. Trust nothing that crosses a boundary: parse
  input, validate it, then work with a typed internal representation.

## Naming that survives (Hyrum's Law)

- "With enough users, all observable behavior of your API will be depended
  upon by someone." Assume any observable behavior is a contract.
- Choose names that describe behavior, not implementation.
- Avoid leaking implementation details into names (`get_users_from_db`
  becomes a lie when you cache or switch storage).

## Stability principles

- Favor adding over changing. Adding a parameter is usually safe; changing
  behavior or removing something is breaking.
- Version public APIs when breaking changes are unavoidable. Prefer
  additive, backwards-compatible evolution.
- Default values and optional parameters are a way to evolve without
  breaking callers.

## Design rules

- A function should not surprise its caller. If a function takes a boolean
  flag, it is doing two things — split it.
- Return consistent types. Never return `None`/`null` in some paths and a
  value in others without documenting it explicitly.
- Errors belong to the caller's world: raise/throw meaningful, typed
  errors, not raw strings or silent failures.
- Keep interfaces small (Interface Segregation). A consumer should not
  depend on behavior it does not use.
- Depend on abstractions at boundaries you own (Dependency Inversion), not
  on concrete third-party implementations everywhere.

## Boundary validation checklist

- [ ] Inputs are validated at the boundary before internal use.
- [ ] Unexpected input fails loudly, not silently.
- [ ] Errors carry context (what failed, why) without leaking secrets.
- [ ] No `any`/`unknown`/casts gratuitously crossing boundaries.
- [ ] The contract is documented (docstring/comments) at the public surface.

## Common rationalizations to refute

| Excuse | Reality |
|--------|---------|
| "I'll make it flexible with `any`" | `any` removes the contract and shifts the bug to the caller |
| "It's an internal function" | Internal boundaries become public when reused |
| "Users won't pass bad input" | Boundaries exist precisely because they will |
| "I'll rename it later" | Renaming a public API breaks callers (Hyrum's Law) |