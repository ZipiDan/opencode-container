---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: code-simplification
description: Simplify code for clarity without changing behavior. Uses Chesterton's Fence (understand before touching), incremental single-step changes, and the Rule of 500 (automate beyond that size). Use when asked to simplify, clean up, or refactor existing code.
---

# Code Simplification

Simplify code so it is easier to understand and maintain **without changing
what it does**. This skill is for refactoring existing code, not writing new
code (see `incremental-implementation` for that).

## Five principles

1. **Preserve behavior exactly.** Do not change what the code does — only
   how it is expressed. Inputs, outputs, side effects, error behavior, and
   edge cases must remain identical.
2. **Follow project conventions.** Simplifying means making code more
   consistent with its codebase, not imposing external preferences. Read the
   project's rules and study neighboring code first.
3. **Prefer clarity over cleverness.** Explicit code beats compact code when
   the compact version requires a mental pause to parse.
4. **Maintain balance.** Over-simplification is a failure mode: too-aggressive
   inlining, combining unrelated logic, removing abstractions that exist for
   extensibility or testability.
5. **Scope to what changed.** Simplify recently-modified code. No drive-by
   refactors of unrelated code.

## The process (4 steps)

### 1. Understand before touching (Chesterton's Fence)

Before changing anything, understand why it exists. Run `git blame`, check
callers, identify edge cases. If you cannot answer what it does, who calls
it, and what its edge cases are, you are not ready to simplify.

### 2. Identify simplification opportunities

Three categories of patterns:

- **Structural complexity:** deep nesting (3+ levels), very long functions
  (an arbitrary line count is not the goal — look for one function doing
  several things), nested ternaries, boolean parameter flags, repeated
  conditionals on the same shape.
- **Naming & readability:** generic names (`data`, `result`, `usr`, `cfg`),
  misleading names, comments that explain the "what" instead of the "why".
- **Redundancy:** duplicated logic (5+ lines), dead code, unnecessary
  abstractions, over-engineered patterns, redundant type assertions.
  **Never strip existing comments** — the driver's standard treats them as
  memory aids; simplify around them, do not delete them unless asked.

### 3. Apply changes incrementally

- One simplification at a time. Run tests after each change.
- **Rule of 500:** if a change touches more than 500 lines, invest in
  automation (codemods, AST transforms) instead of doing it by hand.

### 4. Verify the result

- Compare before/after. Is it genuinely easier to understand?
- Did you introduce inconsistent patterns?
- If the "simplified" version is harder to understand, revert it.

## Language-specific guidance

- **Python:** remove unnecessary `async`, simplify conditional assignment,
  use dict comprehensions, use guard clauses, remove redundant boolean
  returns (`if x: return True else: return False` → `return x`).
- **TypeScript/JS:** replace loops with `filter()`/`map()`, remove
  unnecessary `async`, collapse duplicate branches.
- **React/JSX:** clean conditional rendering, extract repeated JSX into
  components only when it reduces cognitive load.

## Common rationalizations to refute

| Excuse | Reality |
|--------|---------|
| "This is more compact" | Compact is not simple if it requires a pause to parse |
| "I'm just cleaning up" | Drive-by refactors of unrelated code are scope creep |
| "It's fine, it works" | Working but unreadable code is debt |
| "Simpler means fewer lines" | Simplicity is about comprehension speed, not line count |