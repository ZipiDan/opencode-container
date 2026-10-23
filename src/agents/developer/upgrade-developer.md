# Upgrade developer — procedimiento de actualización del agente developer

> **Meta-archivo: NO se despliega.** `agents_update.sh` solo copia archivos `.md`
> con `mode:` en el frontmatter (stage agents) y las skills bajo `skills/`
> (stage skills). Este archivo no tiene `mode:` ni vive en `skills/`, así que
> queda en el repo como documento de procedimiento. No le agregues `mode:`.

Este procedimiento lo ejecuta B.J. (o el operador) cuando las fuentes upstream
publican cambios. Es deliberadamente un **procedimiento guiado**, no un
script: las fuentes upstream (skills de agentes, guías de estilo) reestructuran
secciones y agregan reglas que deben adaptarse a nuestras convenciones opencode
(agente primario, skills on-demand, jerarquía de estilos), y eso requiere
criterio, no un `sed` ciego.

## Fuentes upstream

| Componente | Fuente upstream | Scope |
|------------|-----------------|-------|
| 7 skills de calidad | [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills) | `code-review-and-quality`, `code-simplification`, `test-driven-development`, `api-and-interface-design`, `incremental-implementation`, `frontend-ui-engineering` (los 6 adaptados) |
| Estilo: reglas custom | este repo | `skills/python-style/SKILL.md` (reglas propias, prioridad 1) |
| Estilo: PEP 8 | [peps.python.org/pep-0008](https://peps.python.org/pep-0008/) | prioridad 2 |
| Estilo: SOTA | [`martinholovsky/SOTA-skills`](https://github.com/martinholovsky/SOTA-skills) → `skills/sota-python/rules/` | prioridad 3 |
| Estilo: Google | [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html) | docstrings (prioridad 4) |

## Cuándo correrlo

- Cuando el operador lo pida ("actualizá el agente developer").
- Cuando `addyosmani/agent-skills` o `SOTA-skills` muestren cambios relevantes
  en los skills vendorizados (nuevas reglas, reorganización, correcciones).
- Cuando PEP 8 o la guía de Google cambien (raramente).

## Paso 0 — prerrequisitos

- Correr desde el repo (`/workspace`).
- `git`, `curl` y red disponible en el host.
- Definir el directorio temporal y recordar limpiarlo al final:

  ```bash
  TMP=/tmp/opencode/developer
  ```

## Paso 1 — fetch upstream

```bash
rm -rf "$TMP" && mkdir -p "$TMP" && \
git clone --depth 1 https://github.com/addyosmani/agent-skills.git "$TMP/agent-skills" && \
git clone --depth 1 https://github.com/martinholovsky/SOTA-skills.git "$TMP/sota-skills"
```

(PEP 8 y Google style: leer online; no hace falta clonar.)

## Paso 2 — diff estructurado

Comparar el vendor actual contra upstream:

```bash
# Skills de calidad
diff -ru src/agents/developer/skills \
     "$TMP/agent-skills/skills" | head -200

# Estilo SOTA (sota-python) contra la skill python-style
diff -ru src/agents/developer/skills/python-style \
     "$TMP/sota-skills/skills/sota-python/rules" | head -200
```

Revisar el `CHANGELOG.md`/commits recientes de ambos repos para detectar
cambios estructurales (skills nuevos, renombres, reglas nuevas).

## Paso 3 — re-vendorizar skills

Copiar el contenido upstream a las rutas del vendor, **aplicando el mapa de
reescrituras del Paso 4**:

```bash
SRC="$TMP/agent-skills/skills"
V=src/agents/developer/skills
cp -r $SRC/code-review-and-quality          $V/code-review/
cp -r $SRC/code-simplification              $V/code-simplification/
cp -r $SRC/test-driven-development          $V/test-driven-development/
cp -r $SRC/api-and-interface-design         $V/api-and-interface-design/
cp -r $SRC/incremental-implementation       $V/incremental-implementation/
cp -r $SRC/frontend-ui-engineering          $V/frontend-engineering/
```

Borrar del vendor cualquier skill que haya desaparecido upstream.
`skills/python-style/` es código nuestro (no se sobreescribe desde
`agent-skills`); sus cambios vienen del Paso 5.

## Paso 4 — mapa de reescrituras (aplicar SIEMPRE)

1. **Frontmatter de skills:** verificar que `name:` coincide con la carpeta y
   es `^[a-z0-9]+(-[a-z0-9]+)*$`. Mantener `description:` en inglés.
2. **Idioma:** los skills upstream están en inglés — **se mantienen en
   inglés** (el agente `developer` es bilingüe; sus reglas y skills viven en
   inglés, respuestas al usuario en su idioma).
3. **Tramos específicos del harness de Claude Code** — adaptar a opencode a
   mano (no con sed): `.claude/commands/*.md` → nota de que aquí los comandos
   son skills on-demand; referencias a plugins/hooks de Claude Code → nota de
   que no aplican; `claude` → `opencode`.
4. **Referencias a otras skills** — reescribir para apuntar a las skills
   vendorizadas (p. ej. `security-and-hardening` de upstream → nota de que la
   seguridad es responsabilidad del agente `cyberseguridad`, no del agente
   `developer`).
5. **Mantener SIEMPRE los bloques custom:** el núcleo de reglas en
   `developer.md`, la jerarquía de estilos (custom > PEP 8 > SOTA > Google)
   en `skills/python-style/SKILL.md`, y la separación de roles con
   `cyberseguridad`.
6. **Estándares personales del driver (prioridad máxima, nunca pisar):**
   estos estándares viven en el núcleo y en `python-style` y **no se
   reemplazan ni se degradan** por nada traído de upstream. Ante cualquier
   conflicto con reglas upstream, gana el estándar del driver:
   - **Naming:** Classes `PascalCase`, Functions `camelCase`, Variables
     `snake_case`; *context over length* (nombres concisos si el contexto
     hace obvio el significado).
   - **Strict DRY:** nunca copiar-pegar; si la lógica aparece **2 veces**,
     extraerla a una función reutilizable.
   - **Line length:** máximo **120 caracteres** (ignorar los límites
     estrictos de 79 de PEP 8; monitores anchos).
   - **Readability First:** código claro y mantenible; evitar one-liners
     crípticos de múltiples acciones.
   - **Comments:** bienvenidos y útiles como ayudas de memoria (`#` notas,
     alternativas comentadas, recordatorios al inicio del archivo);
     concisos; **nunca borrar comentarios existentes salvo pedido explícito
     del driver**.
   - **Engineering rules:** Road-Tested Code (robusto y práctico, evitar
     sobre-ingeniería), Diagnostics (analizar logs/contexto antes de
     cambiar), Next Traveler (documentar para futuros mantenedores).

## Paso 5 — actualizar el núcleo (`developer.md`) y el estilo (`skills/python-style/SKILL.md`)

`developer.md` y `skills/python-style/SKILL.md` son código nuestro
(opencode-específico), no se auto-generan. Plegar manualmente los cambios
relevantes de upstream:

- Nuevas reglas de calidad relevantes → secciones correspondientes del núcleo.
- Cambios en la jerarquía de estilos → `skills/python-style/SKILL.md`
  (manteniendo la prioridad: custom > PEP 8 > SOTA > Google).
- Conservar SIEMPRE: reglas core, **estándares personales del driver**
  (ver Paso 4.6 — naming, Strict DRY, línea 120, comments, engineering
  rules), separación de roles con `cyberseguridad` (el agente developer NO
  incluye reglas de ciberseguridad), estilo en inglés.
- Bumpear `version:` en el frontmatter de `developer.md` (es lo que hace
  visible el UPDATE en el stage agents de `agents_update.sh`).

## Paso 6 — validación previa al deploy

- Frontmatter de `developer.md` parseable: `name`, `mode: primary`,
  `description`, `version` entero.
- Cada skill referenciada existe en `skills/` y su `name:` coincide con la
  carpeta.
- Sin directivas solo-Claude-Code sin adaptar en los skills
  (`rg -n 'claude|\.claude|AskUserQuestion|--permission-mode' src/agents/developer`).
- Sin referencias rotas a skills no vendorizadas
  (`rg -n 'skills/' src/agents/developer`).
- `./src/agents_update.sh --check` muestra agentes + skills correctos.

## Paso 7 — deploy

```bash
./src/agents_update.sh --check   # revisar el diff
./src/agents_update.sh           # confirmar y aplicar
```

## Paso 8 — GATE DE SEGURIDAD (obligatorio, con el agente cyberseguridad)

> **Este paso es obligatorio** tanto al construir el agente por primera vez
> como en cada actualización. El agente `developer` no incluye reglas de
> ciberseguridad (eso es responsabilidad del agente `cyberseguridad`), pero
> todo lo que compone el agente **debe cumplir las normas de seguridad** que
> `cyberseguridad` valide antes de considerarse aprobado.

1. Cambiar al agente `cyberseguridad` en opencode.
2. Pedir auditoría del agente `developer` completo:
   - `src/agents/developer/developer.md`
   - `src/agents/developer/skills/**` (la skill `python-style` + los 6 skills)
   - `~/.config/opencode/agents/developer.md` y `~/.config/opencode/skills/`
     (los archivos desplegados)
3. Áreas de verificación mínimas:
   - **Prompt injection:** ningún skill ni regla debe contener instrucciones
     que puedan ser inyectadas/abusadas; texto de archivos y logs se trata
     como datos, nunca como órdenes.
   - **Instrucciones inyectables:** el agente no debe obedecer instrucciones
     embebidas en código que escribe o lee.
   - **Permisos coherentes:** los `permission:` del frontmatter deben ser los
     mínimos necesarios para el rol; nada de exfiltración de secretos.
   - **Separación de roles:** el agente developer NO audita seguridad ni
     contiene reglas de ciberseguridad; si algo de eso apareció en un skill o
     en el núcleo, es un hallazgo.
4. Si `cyberseguridad` reporta hallazgos → corregir y **re-ejecutar los pasos
   6-7** (validar y re-deployar) y re-auditar.
5. Solo tras la aprobación de `cyberseguridad` el agente se considera
   construido/actualizado.

## Paso 9 — limpieza (obligatorio)

Eliminar el clon temporal antes de dar por terminado el upgrade:

```bash
rm -rf "$TMP"
```

Verificar que quedó limpio:

```bash
test ! -e "$TMP" && echo "clon temporal eliminado"
```

> Si el procedimiento se interrumpió antes del Paso 9, borrar `$TMP` antes de
> re-correr: `rm -rf /tmp/opencode/developer`. El clon no debe quedar huérfano.

## Rollback

Todo el contenido del agente está versionado en git:

```bash
git checkout -- src/agents/developer && ./src/agents_update.sh --force
```