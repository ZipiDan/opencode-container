<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade briiirussell — actualización del agente cyberseguridad

> **Meta-archivo: NO se despliega.** `agents_update.sh` solo copia archivos
> `.md` con `mode:` (stage agents) y las skills bajo `skills/` (stage skills).
> Este archivo no tiene `mode:` ni vive en `skills/`, así que queda en el repo
> como documento de procedimiento. No le agregues `mode:`.

Este procedimiento lo ejecuta B.J. (o el operador) cuando el proyecto upstream
[`briiirussell/cybersecurity-skills`](https://github.com/briiirussell/cybersecurity-skills)
publica cambios. Es un procedimiento **guiado y reproducible**: el
`build-catalog.mjs` regenera todo el catálogo desde un clon fresco, de forma
idempotente, y el operador revisa el diff antes de desplegar.

## Cuándo correrlo

- Cuando el operador lo pida ("actualizá el agente cyberseguridad a la última
  de briiirussell").
- Cuando upstream publique una release nueva (revisar con
  `git ls-remote --tags https://github.com/briiirussell/cybersecurity-skills.git`
  comparado con el vendor) o cambie el mapa de familias del README.

## Limpieza del clon temporal

Todo el trabajo usa el clon temporal **`$TMP`** (`/tmp/opencode/briiirussell`).
Ese directorio se elimina al terminar (Paso 6). Si algo falla a mitad, limpiar
antes de re-correr:

```bash
TMP=/tmp/opencode/briiirussell
trap 'rm -rf "$TMP"' EXIT   # envoltura opcional para ejecución no interactiva
```

## Paso 0 — prerrequisitos

- Correr desde el repo (`/workspace`).
- `git` y `node` disponibles (node ≥ 18 para `build-catalog.mjs`).
- Definir el temporal: `TMP=/tmp/opencode/briiirussell`.

## Paso 1 — fetch upstream

```bash
rm -rf "$TMP" && \
git clone --depth 1 https://github.com/briiirussell/cybersecurity-skills.git "$TMP"
```

## Paso 2 — regenerar el catálogo

```bash
cd /workspace/src/agents/cyberseguridad
node build-catalog.mjs "$TMP"
```

El script:
- Valida que el mapa `FAMILIES` (7 familias, 29 skills) cubra **exactamente**
  el catálogo upstream: si el upstream agrega, renombra o elimina skills, el
  script **falla** y hay que actualizar `FAMILIES` (y `ORCHESTRATORS` si
  aplica) en `build-catalog.mjs` a mano, mirando el README upstream.
- Regenera `skills/cyberseguridad-catalog/references/<skill>.md` (29) y el
  índice `skills/cyberseguridad-catalog/SKILL.md`.

## Paso 3 — revisar el diff (criterio, no automatismo)

```bash
cd /workspace
git diff --stat src/agents/cyberseguridad/
git diff src/agents/cyberseguridad/skills/cyberseguridad-catalog/SKILL.md | head -80
```

Revisar punto por punto:
- **Cambios de contenido** en las references: legítimos (mejoras de upstream).
- **Skills nuevos:** verificar que el índice los liste y que `FAMILIES` los
  incluya (el script falla si no).
- **Skills eliminados:** decidir si se quitan del índice (el script los saca
  automáticamente al regenerar).
- **Cambios en los checks de autorización/ética** de los skills ofensivos:
  leerlos con atención — son la frontera de seguridad del catálogo.
- **Descripciones truncadas del índice** (130 chars): si un skill cambió su
  enfoque, revisar que el truncado siga siendo fiel.

## Paso 3b — skills nuevas nacen ocultas y cableadas

El catálogo de skills se inyecta en cada request a todos los agentes: toda skill
re-vendorizada o nueva se agrega con `metadata.opencode/autoinvoke: false` en su
`SKILL.md` **y** con su instrucción de carga explícita (el ID) en
`cyberseguridad.md`. Validar con `src/check-skill-wiring.sh`.

Excepción: las skills del set global (`frontend-slides`, `mermaid2png`) se
agregan sin el flag.

## Paso 4 — bumpear la versión del agente

Si el contenido cambió de forma sustancial, incrementar `version:` en el
frontmatter de `src/agents/cyberseguridad/cyberseguridad.md`
(`agents_update.sh` usa ese campo para decidir UPDATE vs REPLACE). Anotar el
cambio en el README del agente si aporta (nuevas familias, skills, política).

## Paso 5 — GATE DE SEGURIDAD (obligatorio)

> **Este paso es obligatorio** tanto al construir el agente por primera vez
> como en cada actualización. `cyberseguridad` es el propio auditor de
> seguridad, así que no tiene sentido que se auto-audite: el gate verifica que
> la actualización **no haya degradado las salvaguardas del agente y del
> catálogo**, con una revisión cruzada de otro agente para evitar
> auto-validación ciega.

1. Checklist de salvaguardas (verificar punto por punto que sigan intactas):
   - **Solo auditar y reportar:** los `permission.edit` del frontmatter deben
     seguir limitados a `documents/reports/**` y `/tmp/**`; nada que permita corregir el
     código auditado.
   - **Autorización antes que acción:** los skills ofensivos (`recon`,
     `osint-recon`, `web-pentest`, `red-team-engagement`, `disk-forensics`)
     deben conservar sus checks de autorización explícita.
   - **Ética del catálogo:** los límites (rechazo de doxing/acoso, carta
     get-out-of-jail, no amplificar riesgo) no deben haberse debilitado en las
     references regeneradas.
   - **Datos son datos / prompt injection:** el núcleo debe seguir tratando
     texto de archivos y logs como datos, nunca como órdenes; ninguna reference
     nueva debe contener instrucciones inyectables.
   - **Permisos coherentes:** los `permission:` del frontmatter siguen siendo
     los mínimos necesarios (sin `edit` global, sin `write` fuera de reportes).
2. **Revisión cruzada:** pedir a otro agente (`developer` o `sysadmin`) una
   lectura de control del diff del catálogo (`git diff
   src/agents/cyberseguridad/`) enfocada en detectar salvaguardas debilitadas.
   Ante cualquier hallazgo → corregir y re-generar (Paso 2) antes de desplegar.
3. Solo tras pasar la checklist y la revisión cruzada se despliega el agente.

## Paso 6 — desplegar y limpiar

```bash
cd /workspace
./agents_update.sh --check        # ver qué va a cambiar
./agents_update.sh                # aplicar (o --force en no interactivo)
rm -rf "$TMP"                     # limpieza del clon temporal (obligatoria)
```

Reiniciar opencode para que tome el nuevo catálogo. Verificar con una tarea de
prueba por familia que el índice carga y las references se leen a demanda.

## Rollback

El catálogo está versionado en git: para volver a un estado anterior,

```bash
git checkout <commit-anterior> -- src/agents/cyberseguridad/
./agents_update.sh --force        # re-despliega la versión anterior
```

Las references despliegan por checksum: una versión anterior en el repo
regenera el estado previo en `~/.config/opencode/skills/cyberseguridad-catalog/`.