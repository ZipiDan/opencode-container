---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: test-driven-development
description: Test-driven development workflow — RED-GREEN-REFACTOR, DAMP over DRY in tests, Prove-It pattern for bugs, test pyramid 80/15/5. Use when writing new functionality with tests or fixing a bug that needs a regression test first.
metadata:
  opencode/autoinvoke: false
---

# Test-Driven Development

Follow the RED-GREEN-REFACTOR cycle. Write a failing test first, make it
pass with the simplest implementation, then refactor while keeping tests
green.

## The cycle

1. **RED** — Write a failing test that expresses the desired behavior.
   Run it and watch it fail for the right reason (not because of a typo).
2. **GREEN** — Write the simplest code that makes the test pass. No
   speculative generality.
3. **REFACTOR** — Clean up the code (see `code-simplification`) while
   keeping the test green. The refactor step is where code quality happens.

## Prove-It pattern (for bugs)

When fixing a bug:

1. Write a test that **reproduces** the bug first. Watch it fail.
2. Apply the fix. Watch the test pass.
3. Keep the test as a regression guard.

This proves the fix actually addresses the reported behavior.

## DAMP over DRY in tests

- **D**escriptive **A**nd **M**eaningful **P**hrases over DRY in tests.
- Tests must read as specifications: `test_should_reject_empty_username`,
  not `test_validation_case_3`.
- Some duplication in tests is acceptable when it keeps each test
  self-contained and readable. Do not over-abstract test setup into
  incomprehensible helpers.

## Test pyramid (80/15/5)

- ~80% unit tests (fast, isolated, no I/O).
- ~15% integration tests (real components working together).
- ~5% end-to-end tests (full user journeys).

## Prefer real implementations over mocks

- Real implementations > fakes > stubs > mocks.
- Mock only at architectural boundaries you own. Never mock what you are
  trying to verify.

## Arrange-Act-Assert

Structure every test in three clear phases:

```python
def test_user_can_reset_password():
    # Arrange
    user = create_user()
    # Act
    user.reset_password("newpass")
    # Assert
    assert user.can_login("newpass")
```

## Anti-patterns to avoid

- Tests that depend on implementation details instead of behavior.
- Testing only the happy path; edge cases are where bugs live.
- `sleep()` calls to wait for async work — use explicit waits/events.
- Asserting nothing (tests that pass no matter what).
- Skipping tests "temporarily" — a skipped test is a bug you are hiding.

## Common rationalizations to refute

| Excuse | Reality |
|--------|---------|
| "I'll add tests later" | "Later" never comes |
| "This is too simple to test" | Simple code is exactly what regression tests protect |
| "The code is too complex to test" | That is a smell the design needs to change |
| "I'll test it manually" | Manual testing does not scale or protect future changes |