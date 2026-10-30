<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade agent-builder — procedimiento de actualización

> **Meta-archivo: NO se despliega.** `agents_update.sh` solo copia archivos `.md`
> con `mode:` (stage agents) y las skills bajo `skills/` (stage skills).
> Este archivo no tiene `mode:` ni vive en `skills/`, así que queda en el
> repo como documento de procedimiento. No le agregues `mode:`.

Este procedimiento lo ejecuta B.J. (o el operador) cuando el workflow de
creación de agentes cambia (nueva Regla de Oro, cambios en `investigador`,
`developer` o `cyberseguridad`, o mejoras al `agent-architecture` skill).
Es deliberadamente guiado, no un script.

## Cuándo correrlo

- Cuando el operador lo pida ("actualizá agent-builder").
- Cuando `src/agents/investigador/`, `src/agents/developer/` o
  `src/agents/cyberseguridad/` cambien de forma relevante.
- Cuando la doctrina de Anthropic/OpenAI/Google sobre hooks/skills/.md cambie.

## Paso 0 — prerrequisitos

- Correr desde el repo (`/workspace`).
- `git`, `curl` y red disponible.
- Definir temporal: `TMP=/tmp/opencode/agent-builder-upgrade`.

## Paso 1 — diff estructurado

```bash
git diff --stat src/agents/agent-builder/
cat src/agents/agent-builder/agent-builder.md
cat src/agents/agent-builder/skills/agent-architecture/SKILL.md
cat src/agents/agent-builder/README.md
```

Revisar:
- Cambios en Regla de Oro / routing table.
- Cambios en permisos mínimos del frontmatter.
- Cambios en diagrama de flujo del README.

## Paso 2 — actualizar el cerebro (agent-builder.md) y la skill

`agent-builder.md` y `skills/agent-architecture/SKILL.md` son código nuestro:

- Nuevas reglas de enrutamiento → tabla Golden Rule.
- Cambios en workflow → diagrama Mermaid + pasos numerados.
- Conservar SIEMPRE: efímero en `/tmp` (no `documents/investigaciones/`), nunca auto-vendorizar
  (A* solo como opción), múltiples ciclos plan↔developer, gate final obligatorio,
  hook como bloque `## Guardrails`.
- Bumpear `version:` en frontmatter de `agent-builder.md`.

## Paso 2b — skills nuevas nacen ocultas y cableadas

El catálogo de skills se inyecta en cada request a todos los agentes: toda skill
re-vendorizada o nueva se agrega con `metadata.opencode/autoinvoke: false` en su
`SKILL.md` **y** con su instrucción de carga explícita (el ID) en
`agent-builder.md`. Validar con `src/check-skill-wiring.sh`.

Excepción: las skills del set global (`frontend-slides`, `mermaid2png`) se
agregan sin el flag.

## Paso 3 — mapa de reescrituras (si se vendoriza algo)

Si se incorpora referencia externa (ej. nueva doc Anthropic sobre hooks):

1. `CLAUDE.md` → `the agent-builder agent prompt`
2. `.claude/settings.json` → `permission.*` frontmatter
3. `.claude/hooks/*.sh` → nota `## Guardrails` (opcional plugin `tool.execute.before`)
4. `~/.claude` → `~/.config/opencode`

## Paso 4 — validación previa al deploy

- Frontmatter parseable: `name`, `mode: primary`, `description`, `version` entero.
- Skill referenciada existe y `name:` coincide con carpeta.
- Sin directivas Claude-Code sin adaptar (`rg -n 'claude|\.claude' src/agents/agent-builder`).
- `./src/agents_update.sh --check` muestra agents+skills correctos.

## Paso 5 — GATE DE SEGURIDAD (obligatorio, con cyberseguridad)

> Obligatorio tanto al crear como en cada actualización.

1. Cambiar a agente `cyberseguridad`.
2. Pedir auditoría de `src/agents/agent-builder/**` y copias desplegadas.
3. Áreas mínimas:
   - **Prompt injection:** ningún skill ni prompt contiene instrucciones inyectables.
   - **Permisos coherentes:** `edit/write` solo `/tmp/**` y `documents/reports/**`; nada global.
   - **Separación de roles:** agent-builder no audita seguridad (lo delega a cyberseguridad).
   - **Efímero:** no deja artefactos en `documents/investigaciones/` ni `/tmp` huérfanos.
4. Si hay hallazgos → corregir, re-validar (Paso 4), re-auditar.
5. Solo tras aprobación se despliega.

## Paso 6 — deploy

```bash
./src/agents_update.sh --check
./src/agents_update.sh          # confirmar
```

## Paso 7 — limpieza

```bash
rm -rf "$TMP"
test ! -e "$TMP" && echo "tmp limpio"
```

Si se interrumpió antes, borrar antes de re-correr: `rm -rf /tmp/opencode/agent-builder*`.

## Rollback

```bash
git checkout -- src/agents/agent-builder && ./src/agents_update.sh --force
```
