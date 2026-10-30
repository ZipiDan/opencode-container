---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: python-style
description: "Style and code-quality reference for the developer agent. Priority hierarchy: custom rules > PEP 8 > SOTA sota-python > Google (docstrings). Language-agnostic in spirit — maps to Python, TypeScript/JS, Go, Rust. Load before writing or modifying code."
metadata:
  opencode/autoinvoke: false
---

# Python Style Reference

Style and code-quality rules for the `developer` agent. These rules are
**language-agnostic in spirit**: when writing in another language, apply the
corresponding convention where it makes sense.

## Priority hierarchy

When a rule conflicts, apply them in this order:

1. **Custom rules** (this file) — the agent's own rules. **Highest priority.**
2. **PEP 8** — the official Python style guide (naming, functions, classes,
   comments, imports). https://peps.python.org/pep-0008/
3. **SOTA `sota-python`** — idioms, typing, tooling (uv/ruff/mypy), pitfalls.
4. **Google Python Style Guide** — docstrings only (Args/Returns/Raises).

## Custom rules

### Functions

- One function = one responsibility.
- Functions are usually short, but length is not a goal: a function may
  exceed 20 lines when its single task is genuinely complex and there is no
  duplicated logic. Split when it does more than one thing, not because of
  size alone.
- Keep the parameter list minimal, but do not force arbitrary limits: a
  function may need more than 4 parameters by nature. When the list grows
  beyond what is readable, group related arguments into an options object,
  a dataclass, or named config; use `*args`/`**kwargs`/variadics where the
  language supports them.
- Use verbs for function names (`get_user`, `validate_input`).
- Use guard clauses and early returns; avoid deep nesting.
- Prefer explicit arguments over boolean flags (`process(data, verbose=True)`
  is a smell; split into `process(data)` and `process_verbose(data)` or use
  an options object).
- Prefer pure functions when there is no state to encapsulate.
- **Strict DRY:** never copy-paste code. If logic appears twice, extract it
  into a reusable function.

### Classes

- Use classes only when there is real state, encapsulation, or tightly
  coupled behavior that functions alone cannot express cleanly.
- If a class can be replaced by a function or a module of functions, do it.
- Keep classes small and single-responsibility. A class name needing 3+
  words to describe its job is doing too much or too little.
- Prefer dataclasses for simple data containers; reserve custom `__init__`
  for classes that need real logic.
- Composition over inheritance. Favor small interfaces over deep hierarchies.

### Variables

- **Driver's personal convention:** variables and functions `snake_case`
  (Python) / `camelCase` (TS/JS, Go), classes `PascalCase`, constants
  `UPPER_CASE`.
- Names proportional to scope: loop variable `i` is fine; a module-level
  `list_of_active_users_filtered_by_subscription_status` is not — use
  `active_subscribers`.
- Avoid single-letter names outside tight loops and mathematical formulas.
- Boolean variables read as yes/no questions: `is_active`, `has_access`.
- Do not shadow builtins (`list`, `dict`, `type`, `id`) or imported names.

### Comments and docstrings

- **Comments are welcome and useful** — memory aids: `#` notes,
  commented-out alternatives, reminders at the top of a file. Keep them
  concise and clear; too much information clutters the code.
- **Never strip existing comments unless the driver explicitly asks.**
- Prefer commenting the **why** (reason, intent) over restating the what.
- No section banners or docstrings that merely repeat the function name.
- Docstrings for public APIs, in Google format (Args/Returns/Raises),
  concise and factual.

### Modules and imports

- Organize modules by domain, not by role. No `utils.py`, `helpers.py`,
  or `common.py` junk drawers — put code where it is used.
- Imports order: stdlib → third-party → local, each group separated by a
  blank line. Sort alphabetically within each group.
- Import what you use; no wildcard imports (`from x import *`).
- A module reaching ~300 lines is a signal to check cohesion, not a hard
  limit: cohesive modules (a domain object, a dense algorithm, a complete
  set of related helpers) may legitimately exceed it. Split only when the
  module does several unrelated things.

### Anti-patterns

- No `AbstractFactoryProviderManager`-style names.
- No interfaces/types for a single implementation.
- No wrappers that delegate without adding behavior.
- No premature abstraction: extracting logic that merely looks similar but
  encodes different rules couples unrelated code. Extraction is for genuine
  knowledge duplication (the driver's standard: if logic appears twice,
  extract it).
- No global mutable state unless the architecture already requires it.

### Ruff configuration (driver's baseline)

When a Python project ships a ruff config, ensure it carries the driver's
baseline unless the project already defines a deliberate lint policy of its own:

- `ruff.toml`:
  ```toml
  line-length = 120

  [lint]
  ignore = ["I001", "RUF023"]
  ```
- `pyproject.toml`:
  ```toml
  [tool.ruff]
  line-length = 120

  [tool.ruff.lint]
  ignore = ["I001", "RUF023"]
  ```

Rationale: the driver's standard is 120 columns (AGENTS.md) while ruff's
default is 88 (E501); `I001` (isort) reorders imports and normalizes blank
lines after imports; `RUF023` sorts the `__slots__` tuple alphabetically.
Both are purely cosmetic and conflict with the driver's semantic `__slots__`
ordering — they do not affect correctness.

## PEP 8 essentials (secondary)

- 4-space indentation, no tabs. **Line length: max 120 characters** (driver's
  standard; ignore strict 79-char PEP8 limits — wide monitors).
- Two blank lines around top-level definitions, one inside a class.
- Comparisons to `None` use `is` / `is not`, never `==`.
- Prefer `pathlib` over `os.path` for new code.

## SOTA `sota-python` essentials (tertiary)

- Use type hints (PEP 484) on all public functions; run `mypy` if configured.
- Use `ruff` for linting and formatting (replaces flake8/black/isort).
- Prefer dataclasses over hand-written boilerplate; TypedDict for dict shapes.
- Watch out for mutable default arguments, closures in loops, and
  sync-ORM-in-async bugs.

## Google style (docstrings only)

- Module docstring: one-line summary at the top of each file.
- Function/class docstrings use Args/Returns/Raises sections.
- Keep docstrings imperative and factual; no marketing language.

## Applying to other languages

The custom rules above are written for Python but express general software
engineering principles. When writing in another language, map each rule to
the target language's convention:

| Concept | Python | TypeScript/JS | Go | Rust |
|---------|--------|---------------|----|------|
| Variable/function | `snake_case` | `camelCase` | `camelCase` | `snake_case` |
| Class/type | `PascalCase` | `PascalCase` | `PascalCase` | `PascalCase` |
| Constant | `UPPER_CASE` | `UPPER_CASE` | `UPPER_CASE` | `SCREAMING_SNAKE` |
| One-responsibility functions | ✓ | ✓ | ✓ | ✓ |
| Strict DRY (extract at 2 occurrences) | ✓ | ✓ | ✓ | ✓ |
| Comments welcome as memory aids | ✓ | ✓ | ✓ | ✓ |
| Max line length 120 | ✓ | ✓ | ✓ | ✓ |
| No junk-drawer modules | ✓ | ✓ | ✓ | ✓ |