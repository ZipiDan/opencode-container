---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: incremental-implementation
description: Implement features in small, verifiable, behavior-preserving steps. Simplicity First (the simplest thing that works), scope discipline (do not clean up adjacent code), and verifiable progress. Use when implementing a feature or a new piece of functionality.
---

# Incremental Implementation

Implement features in small, verifiable steps that preserve behavior and
keep the change reviewable.

## Rule 0: Simplicity First

- "What is the simplest thing that could work?" Start there.
- Add complexity only when a concrete need appears, not in anticipation.
- The first working version should be the smallest change that satisfies
  the requirement.

## Rule 0.5: Scope discipline

- **Do NOT clean up code adjacent to your change.** That is a separate diff.
- One step = one logical change. If a change exceeds ~300 lines, split it
  into reviewable pieces.
- When you notice pre-existing problems, note them for the user but do not
  fix them in this change unless asked.

## Working small

- Aim for changes you can verify in a few minutes each: a small function, a
  single behavior, one edge case at a time.
- Keep each step behavior-preserving or behavior-adding, never both
  mixed silently.
- ~100 lines changed is comfortable; ~1000 lines is too large — split it.

## Verifiable progress

- After each step, verify: does it still run? Do existing tests pass? Does
  the new behavior actually work?
- Run the project's lint, type check, and tests after every step when they
  exist — do not batch failures.
- If a step cannot be verified in isolation, say so and propose how to make
  it verifiable.

## When to use feature flags

- Feature flags are for risky or partially-shippable changes, not a default.
- Use safe defaults: fail closed, log clearly, allow quick rollback.
- Prefer merging small shippable increments over long-lived branches.

## Anti-patterns

- Big-bang rewrites. Replacing 1000 lines "to do it right" is a risk, not a
  virtue.
- Refactoring and feature work in the same diff.
- "While I'm here..." scope creep.
- Changes that cannot be rolled back or verified.

## Common rationalizations to refute

| Excuse | Reality |
|--------|---------|
| "I'll do the whole thing at once" | Large diffs are where bugs and merge conflicts live |
| "I'll clean this up while I'm here" | Adjacent cleanup belongs in its own change |
| "It works, that's enough" | Verify, then deliver — working is not proof |
| "I'll refactor after it ships" | Refactor now while the context is fresh |