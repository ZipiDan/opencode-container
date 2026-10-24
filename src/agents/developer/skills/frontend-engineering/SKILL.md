---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: frontend-engineering
description: Frontend/UI engineering with component architecture, composition over configuration, separation of data fetching from presentation, and colocation. Use for frontend work, UI components, or web interfaces.
---

# Frontend Engineering

Build frontends that are maintainable, consistent, and easy to reason about.
These rules apply to any UI stack (React, Vue, Svelte, vanilla, etc.).

## Component architecture

- **Composition over configuration.** Compose small components instead of
  building one big component controlled by many props/config flags.
- One component = one responsibility. If a component does more than one
  thing, split it.
- Components should be small: if one exceeds ~200 lines, look for a natural
  split.

## Separation of concerns

- **Separate data fetching from presentation.** A presentational component
  receives data and renders it; a container/loader component fetches and
  passes it down. Do not bury network calls inside render logic.
- Keep state as close as possible to where it is used. Lift state up only
  when genuinely shared.
- Side effects (fetch, storage, analytics) live at explicit boundaries, not
  scattered through render paths.

## Colocation

- Keep a component's related files (styles, tests, helpers) next to it.
- If a file is only used by one component, put it with that component, not
  in a shared folder.
- No global "junk drawer" folders for UI (`components/common/`, `ui/`)
  where unrelated things accumulate.

## Naming and structure

- Component names = nouns in PascalCase (`UserProfileCard`).
- Props are a contract: name them for what they mean, not where they come
  from.
- Boolean props read as questions (`isLoading`, `hasError`).
- Follow the project's existing component conventions before imposing new
  ones.

## Accessibility and robustness

- Render with sensible defaults; never assume data is present — handle
  empty, loading, and error states explicitly.
- Keyboard accessibility and semantic HTML are part of quality, not an
  afterthought.
- Guard against race conditions: ignore stale async responses (token or
  abort).

## Anti-patterns (the "AI aesthetic" of code smells)

- One giant component doing fetching + state + rendering + styling.
- Prop-drilling deep chains where a shared context or colocated state is
  clearer.
- `useMemo`/`useCallback` applied to everything "just in case".
- Copy-pasted JSX blocks that differ in one prop — parameterize or
  componentize.
- Over-nested conditionals in render paths — extract early returns or small
  components.

## Common rationalizations to refute

| Excuse | Reality |
|--------|---------|
| "It's just UI, it's fine" | UI is where users experience quality |
| "I'll memoize everything for performance" | Premature memoization adds complexity and bugs |
| "This component is one-off, it can be big" | One-off big components become reused big components |
| "I'll add the loading state later" | "Later" ships broken states to users |