# Developer agent

Senior software developer that writes clean, maintainable, and well-structured
code. The agent applies a strict set of quality rules on every code change,
independent of the programming language, with a style hierarchy for Python
that also maps to other languages.

## Files

| File | Purpose |
|------|---------|
| `developer.md` | The primary agent: code quality rules (always active), style reference pointer, skill routing |
| `skills/python-style/SKILL.md` | Style reference with a priority hierarchy (custom rules > PEP 8 > SOTA > Google), loaded as a skill |
| `skills/` | Seven on-demand quality skills (python-style, code-review, code-simplification, test-driven-development, api-and-interface-design, incremental-implementation, frontend-engineering) |
| `upgrade-developer.md` | Update procedure from upstream sources (meta-doc, not deployed) |

## Style hierarchy integration

`skills/python-style/SKILL.md` defines the style rules applied on every write.
The hierarchy of sources and their priority:

| Priority | Source | Scope |
|----------|--------|-------|
| 1 | **Custom rules** (`python-style.md` + driver's personal standards) | Functions, classes, variables, comments, modules, imports |
| 2 | **PEP 8** | Official Python style standard (naming, comments, imports) |
| 3 | **SOTA `sota-python`** | Idioms, typing, tooling (uv/ruff/mypy), pitfalls |
| 4 | **Google Python Style Guide** | Docstrings only (Args/Returns/Raises) |

**Driver's personal standards** are the highest-priority custom rules and are
never overridden by upstream changes (see `upgrade-developer.md`, step 4.6):

- **Naming:** Classes `PascalCase`, Functions `camelCase`, Variables
  `snake_case`; *context over length*.
- **Strict DRY:** never copy-paste; if logic appears twice, extract it.
- **Line length:** max 120 characters (ignore strict 79-char PEP8 limits).
- **Readability First:** clear, maintainable code; no cryptic multi-action
  one-liners.
- **Comments:** welcome as memory aids; concise; never strip existing
  comments unless the driver explicitly asks.
- **Engineering rules:** Road-Tested Code, Diagnostics, Next Traveler.

The custom rules are language-agnostic in spirit: `skills/python-style/SKILL.md`
includes a mapping table (Python / TypeScript / Go / Rust) so the same
principles apply to other languages when the convention corresponds.

This hierarchy is **re-evaluated on every update**: when upstream sources
(PEP 8, SOTA, Google) change, the diff is folded into
`skills/python-style/SKILL.md` without breaking the priority order. See
`upgrade-developer.md`.

## Skills (on demand)

The seven skills adapt concepts from [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)
to this agent's conventions. They are loaded only when the task matches:

| Skill | When to use |
|-------|-------------|
| `python-style` | Before writing or modifying code (style hierarchy) |
| `code-review` | Reviewing code against 5 axes with severity labels |
| `code-simplification` | Simplifying code without changing behavior |
| `test-driven-development` | Writing new functionality with tests |
| `api-and-interface-design` | Designing APIs, interfaces, public functions |
| `incremental-implementation` | Implementing a feature in small verifiable steps |
| `frontend-engineering` | Frontend/UI work |

## Security (gate with `cyberseguridad`)

The `developer` agent **does not include cybersecurity rules** — that is the
job of the `cyberseguridad` agent. However, **every construction and every
update** of this agent (files, skills, commands) must pass a security audit
by the `cyberseguridad` agent before it is considered approved. The audit
checks for, among others: prompt injection, injectable instructions, coherent
permissions, and secret exfiltration. See `upgrade-developer.md` for the gate
step.

## Versioning

- `developer.md` carries `version: N` (integer) in its frontmatter.
- Bump the version when agent content changes in the repo.
- `agents_update.sh` compares installed version vs repo version plus checksum
  (`sha256sum`) to detect local edits.