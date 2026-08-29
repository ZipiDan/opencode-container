---
name: code-review
description: Review code against five axes (correctness, readability, architecture, security, performance) and emit categorized findings with severity labels, concrete fixes, and anti-rationalization refutations. Use when asked to review code, review a pull request, or audit a change for quality before merge.
---

# Code Review

Review code systematically against five axes. Produce findings with severity
labels and concrete fixes. This skill is for **reviewing** — it does not
modify code; it reports so the author can act.

## The five axes

1. **Correctness** — Does the code do what it says? Edge cases, error paths,
   race conditions, off-by-one, null/None handling.
2. **Readability & Simplicity** — Can another engineer understand it without
   an explanation? Descriptive names, straightforward control flow, no
   "clever" code.
3. **Architecture** — Does the change respect the system's design? Existing
   patterns, modules, dependencies, abstractions.
4. **Security** — Input validation, secrets, auth, parameterized queries,
   XSS encoding, command injection.
5. **Performance** — N+1 queries, unconstrained loops, sync where async is
   needed, unnecessary re-renders, missing pagination.

## Severity labels

| Prefix | Meaning | Action |
|--------|---------|--------|
| *(none)* | Required change | Author must resolve before merge |
| **Critical:** | Blocks merge | Vulnerability, data loss, broken functionality |
| **Nit:** | Minor, optional | Author may ignore |
| **Optional/Consider:** | Suggestion | Worth considering, not required |
| **FYI** | Informational only | No action |

## Finding format

```
`file:line` | severity | problem | concrete fix
```

Every **Critical** and **Required** finding must include a recommended fix,
not just a description.

## Structural remedies (concrete fixes)

When you flag a structural problem, propose the concrete fix:

- Replace a chain of conditionals with a typed model or explicit dispatcher.
- Collapse duplicated branches into a clearer flow.
- Separate orchestration from business logic.
- Move feature-specific logic out of a shared module.
- Reuse the canonical helper instead of a near-duplicate.
- Make a type boundary explicit so the branching disappears.
- Remove pass-through wrappers that add indirection without value.
- Extract helpers; split large files into focused modules.
- If a refactor moves complexity around instead of reducing it, say so —
  relocating complexity is not reducing it.

## Change sizing

- ~100 lines changed → Good. Reviewable in one sitting.
- ~300 lines changed → Acceptable if a single logical change.
- ~1000 lines changed → Too large. Ask to split it.
- Also watch file size, not just the diff: a very large single file (e.g.
  ~1000 total lines) is a signal to check cohesion — some modules
  legitimately justify it, so flag only when the module does several
  unrelated things.

## Anti-rationalizations (refute these excuses)

| Excuse | Reality |
|--------|---------|
| "It works, that's enough" | Code that works but is unreadable/insecure accrues compounding debt |
| "I wrote it, I know it's right" | Authors are blind to their own assumptions |
| "We'll clean it up later" | "Later" never comes. Review is the quality gate |
| "AI-generated code is probably fine" | AI code needs MORE scrutiny, not less |
| "Tests pass, so it's fine" | Tests are necessary but not sufficient |
| "The refactor makes it cleaner" | Relocating complexity is not reducing it |
| "It's just a version bump" | A bump is a behavior change you didn't write |

## Review workflow

1. Read the spec/requirements first, then the tests, then the code.
2. Review tests: do they test behavior or implementation details? Is there a
   test for each Critical/Required finding you might raise?
3. Walk each axis in order; do not skip security even for trivial changes.
4. Recognize what is done well — not everything is a finding.
5. Verdict: **APPROVE** or **REQUEST CHANGES** with a summary.

## Output template

```markdown
## Review Summary
**Verdict:** APPROVE | REQUEST CHANGES
### Critical Issues
### Required Changes
### Optional
### Nits
### What's Done Well
### Verification Story
```

## Red flags (signals the review process is broken)

- PRs merged without review.
- Reviews that only check whether tests pass.
- "LGTM" without evidence of a real review.
- Security changes without a security-focused review.
- Large PRs "too big to review".
- No regression tests in fixes.
- No severity labels on review comments.