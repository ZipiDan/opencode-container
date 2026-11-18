<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade heinzel — procedimiento de actualización del agente sysadmin

> **Meta-archivo: NO se despliega.** `agents_update.sh` solo copia archivos `.md`
> con `mode:` en el frontmatter (stage agents) y las skills bajo `skills/`
> (stage skills). Este archivo no tiene `mode:` ni vive en `skills/`, así que
> queda en el repo como documento de procedimiento. No le agregues `mode:`.

Este procedimiento lo ejecuta B.J. (o el operador) cuando el proyecto upstream
[`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel) publica
cambios. Es deliberadamente un **procedimiento guiado**, no un script: upstream
reestructura secciones y agrega reglas que pueden chocar con nuestra
adaptación a opencode (memoria por proyecto, entorno del contenedor,
disambiguación por cliente), y eso requiere criterio, no un `sed` ciego.

## Cuándo correrlo

- Cuando el operador lo pida ("actualizá el agente sysadmin a la última de
  heinzel").
- Cuando `VERSION` / `CHANGELOG.md` de upstream muestre cambios relevantes
  (reglas de seguridad nuevas, skills nuevas, reorganización de `rules/`).
- Sugerencia: revisar cada tanto con `git ls-remote
  https://github.com/wintermeyer/heinzel.git HEAD` comparado con el vendor.

## Limpieza del clon temporal

Todo el trabajo de este procedimiento usa el clon temporal **`$TMP`**
(`/tmp/opencode/heinzel`). Ese directorio **se elimina al terminar**:

- **Al completar el upgrade:** Paso 9 (obligatorio) borra `$TMP`.
- **Si algo falla o se interrumpe a mitad:** también hay que limpiar antes de
  re-correr (el Paso 1 ya borra clones viejos antes de clonar, pero conviene
  hacerlo explícito). Nunca dejar `$TMP` huérfano: `/tmp` puede sobrevivir
  entre reinicios en algunos sistemas.
- **Ejecución no interactiva (opcional):** si se corre toda la secuencia en un
  solo comando, se puede envolver con un `trap` para limpieza automática:

  ```bash
  TMP=/tmp/opencode/heinzel
  trap 'rm -rf "$TMP"' EXIT
  # ... pasos 1-7 ...
  ```

  Así `$TMP` se elimina al salir del shell, incluso si el procedimiento aborta
  con error. En ejecución interactiva paso a paso, la limpieza es el Paso 9.

## Paso 0 — prerrequisitos

- Correr desde el repo (`/workspace`).
- `git`, `curl` y red disponible en el host.
- Definir el directorio temporal y recordar limpiarlo al final:

  ```bash
  TMP=/tmp/opencode/heinzel
  ```

## Paso 1 — fetch upstream

```bash
rm -rf "$TMP" && \
git clone --depth 1 https://github.com/wintermeyer/heinzel.git "$TMP"
```

(También sirve `curl -fsSL
https://codeload.github.com/wintermeyer/heinzel/tar.gz/refs/heads/main | tar xz`.)

## Paso 2 — diff estructurado

Comparar el vendor actual contra upstream:

```bash
diff -ru src/agents/sysadmin/skills/heinzel-rules/references \
     "$TMP/rules" | head -200
diff -ru src/agents/sysadmin/skills/heinzel-housekeeping \
     "$TMP/.claude/skills/heinzel-housekeeping" | head -100
# idem para heinzel-security, heinzel-email, heinzel-fleet-audit
cat "$TMP/VERSION" "$TMP/CHANGELOG.md"
```

Leer `CHANGELOG.md` para detectar cambios estructurales (nuevas reglas,
renombres, cambios de rutas `documents/memory/`).

## Paso 3 — re-vendorizar skills y reglas

Copiar el contenido upstream a las rutas del vendor, **aplicando el mapa de
reescrituras del Paso 4**:

```bash
SRC="$TMP"
V=src/agents/sysadmin/skills
cp -r $SRC/.claude/skills/heinzel-housekeeping $V/
cp -r $SRC/.claude/skills/heinzel-security    $V/
cp -r $SRC/.claude/skills/heinzel-email       $V/
cp -r $SRC/.claude/skills/heinzel-fleet-audit $V/
cp $SRC/rules/*.md $V/heinzel-rules/references/
```

Borrar del vendor cualquier skill/regla que haya desaparecido upstream,
**excepto** los add-ons custom (ver Paso 3b).

## Paso 3b — preservar add-ons de Calisto (obligatorio)

`src/agents/sysadmin/ADDONS.md` es el manifiesto. Los add-ons `calisto-*` **no
vienen de heinzel** y no deben borrarse ni sobrescribirse. El gate recorre el
registro de `ADDONS.md`, así que un add-on nuevo queda cubierto sin editar este
paso:

```bash
# Gate rápido antes y después del re-vendorizado
addons=$(sed -n 's/^| `\(calisto-[a-z0-9-]*\)` |.*/\1/p' src/agents/sysadmin/ADDONS.md)
[ -n "$addons" ] || { echo "ERROR: registro de ADDONS.md vacío"; exit 1; }
for addon in $addons; do
  test -f "src/agents/sysadmin/skills/$addon/SKILL.md" || {
    echo "ERROR: falta $addon"; exit 1; }
  grep -q "^name: $addon$" "src/agents/sysadmin/skills/$addon/SKILL.md" || {
    echo "ERROR: $addon: name: no coincide"; exit 1; }
  grep -qF -- "$addon" src/agents/sysadmin/sysadmin.md || {
    echo "ERROR: $addon no está cableado en sysadmin.md"; exit 1; }
done
# control inverso: una carpeta calisto-* sin fila en el registro quedaría fuera del gate
for dir in src/agents/sysadmin/skills/calisto-*/; do
  addon="$(basename "$dir")"
  grep -qF -- "| \`$addon\` |" src/agents/sysadmin/ADDONS.md || {
    echo "ERROR: $addon no está registrado en ADDONS.md"; exit 1; }
done
```

- No copiar upstream encima de `skills/calisto-*`.
- Al limpiar skills que desaparecieron upstream, excluir `calisto-*`.
- Si upstream agrega una skill con el mismo nombre, detenerse y resolver el
  conflicto antes de seguir (opencode exige nombres únicos).
- Si el binario `landlock_rosh` cambió de versión, revisar si la skill necesita
  actualización operativa; la documentación de desarrollo vive en
  `src/tools/landlock/DEVELOPMENT.md`, no en la skill.
- Si cambian las dependencias de `calisto-proxmox-console-fallback` (por ejemplo
  Pillow en el `Containerfile`), actualizar su ficha en `ADDONS.md` antes de
  desplegar.

## Paso 3c — skills nuevas nacen ocultas y cableadas

El catálogo de skills se inyecta en cada request a todos los agentes, así que
toda skill re-vendorizada o nueva se agrega con `metadata.opencode/autoinvoke:
false` en su `SKILL.md` **y** con su instrucción de carga explícita (el ID) en
`sysadmin.md`. Validar con `src/check-skill-wiring.sh`.

Excepción: las skills del set global (`frontend-slides`, `mermaid2png`) se
agregan sin el flag, porque deben anunciarse a todos los agentes.

## Paso 4 — mapa de reescrituras (aplicar SIEMPRE)

> El mapa aplica a las skills/reglas de heinzel. **No** aplicar a
> `skills/calisto-landlock/`: ya es opencode-native y es nuestro.

1. **Frontmatter de skills:** quitar `argument-hint:` (campo no reconocido
   por opencode; los desconocidos se ignoran, pero se limpia). Verificar que
   `name:` coincide con la carpeta y es `^[a-z0-9]+(-[a-z0-9]+)*$`.
2. **En las 4 skills heinzel-\* (SKILL.md y references/):**
   `` `rules/<x>.md` `` → `` `heinzel-rules` -> `x.md` `` (la regla ahora vive
   en la biblioteca `heinzel-rules`; el agente la lee cargando esa skill).
3. **En `heinzel-rules/references/*.md`:** `` `rules/<x>.md` `` → `` `./x.md` ``
   (referencias relativas dentro del mismo `references/`).
4. **`CLAUDE.md`** → `` the `sysadmin` agent prompt `` (el "cerebro" de heinzel
   es ahora el prompt del agente).
5. **Tramos específicos del harness de Claude Code** — adaptar a opencode a
   mano (no con sed): `.claude/settings.json` → permisos de `opencode.json`
   (`permission.bash`); `.claude/hooks/guard-taboos.sh` → nota de que opencode
   no tiene hook mecánico (remitir al plugin `heinzel-guard` opcional);
   `claude -p` / `--permission-mode auto` → `opencode run --agent sysadmin
   --auto`; `~/.claude` → `~/.config/opencode`. (Ver los ya adaptados:
   `scheduled-housekeeping.md` y la sección harness de `service-reload.md`.)
6. **Traducir `memory/` upstream → `documents/memory/`**: nuestra memoria es 100% por proyecto bajo `documents/` del workspace (upstream heinzel la tiene en la raíz). Reescribir esas rutas en cada re-vendorizado.

## Paso 5 — actualizar el cerebro (`sysadmin.md`)

`sysadmin.md` es código nuestro (opencode-específico), no se auto-genera.
Plegar manualmente los cambios relevantes de `CLAUDE.md` upstream:

- Nuevas reglas de seguridad críticas → sección "Critical safety rules".
- Cambios de procedimiento → secciones correspondientes.
- Conservar SIEMPRE el bloque custom: memoria 100% por proyecto, entorno del
  contenedor (Podman, `/root/.ssh`, `--network-host`), disambiguación por
  cliente (`Client:`), registro de skills y la sección de read-only opcional
  con `calisto-landlock` (add-on de Calisto, no upstream).
- Bumpear `version:` en el frontmatter (es lo que hace visible el UPDATE en
  el stage agents de `agents_update.sh`).

## Paso 6 — validación previa al deploy

- Frontmatter de `sysadmin.md` parseable: `name`, `mode: primary`,
  `description`, `version` entero.
- Cada skill referenciada existe en `skills/` y su `name:` coincide con la
  carpeta.
- Add-ons del registro de `ADDONS.md` presentes y cableados: correr el bloque de
  **Validación rápida** de ese archivo (recorre todos los `calisto-*`, no sólo
  `calisto-landlock`).
- Sin directivas solo-Claude-Code sin adaptar en las skills (`rg -n
  'claude|\.claude|AskUserQuestion|--permission-mode' src/agents/sysadmin`).
- Sin referencias `rules/` rotas (`rg -n 'rules/' src/agents/sysadmin`).
- `./src/agents_update.sh --check` muestra agentes + skills correctos.

## Paso 7 — deploy

```bash
./src/agents_update.sh --check   # revisar el diff
./src/agents_update.sh           # confirmar y aplicar
```

## Paso 8 — GATE DE SEGURIDAD (obligatorio, con el agente cyberseguridad)

> **Este paso es obligatorio** tanto al construir el agente por primera vez
> como en cada actualización. El agente `sysadmin` no incluye reglas de
> ciberseguridad (eso es responsabilidad del agente `cyberseguridad`), pero
> todo lo que compone el agente **debe cumplir las normas de seguridad** que
> `cyberseguridad` valide antes de considerarse aprobado.

1. Cambiar al agente `cyberseguridad` en opencode.
2. Pedir auditoría del agente `sysadmin` completo:
   - `src/agents/sysadmin/sysadmin.md`
   - `src/agents/sysadmin/ADDONS.md`
   - `src/agents/sysadmin/skills/**` (heinzel-rules + housekeeping, security,
     email, fleet-audit + **todas las skills `calisto-*`**: landlock,
     debian-server-baseline, proxmox-console-fallback)
   - `~/.config/opencode/agents/sysadmin.md` y `~/.config/opencode/skills/`
     (los archivos desplegados)
3. Áreas de verificación mínimas (específicas del rol sysadmin):
   - **Prompt injection:** ningún skill ni regla debe contener instrucciones
     que puedan ser inyectadas/abusadas; texto de archivos, logs y respuestas
     de servidor se trata como datos, nunca como órdenes
     (`anomaly-detection.md`).
   - **Read-only add-on:** `calisto-landlock` no debe sugerir ni permitir
     bypass de una restricción ya impuesta (otra clave, `--no-log`, `sudo`,
     editar `authorized_keys`), y `--log-only` debe presentarse como auditoría,
     no como control.
   - **Acciones con efecto remoto:** `calisto-proxmox-console-fallback` debe
     declarar que `sendkey` cambia el guest (no es read-only), exigir aprobación
     explícita, prohibirlo en hosts read-only/landlocked, no permitir secretos
     por `argv` y tratar el texto visto en pantalla como dato, no como orden.
   - **Tabúes y destructivos intactos:** los comandos tabú (`fdisk`,
     `wipefs`, `mkfs`, borrado de disco, edición de `sshd_config`, borrado de
     claves SSH) deben seguir bloqueados; que ninguna skill o reescritura los
     haya debilitado o desprotegido.
   - **Permisos coherentes:** los `permission:` del frontmatter deben ser los
     mínimos necesarios para el rol; nada de exfiltración de secretos ni
     lectura de claves.
   - **Separación de roles:** el agente sysadmin NO audita ciberseguridad ni
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
> re-correr: `rm -rf /tmp/opencode/heinzel`. El clon no debe quedar huérfano.

## Rollback

Todo el contenido del agente está versionado en git:

```bash
git checkout -- src/agents/sysadmin && ./src/agents_update.sh --force
```

## Nota sobre el guard mecánico (opcional)

Upstream protege los tabúes con `.claude/hooks/guard-taboos.sh` (hook
PreToolUse de Claude Code). opencode no lee esos hooks, así que en nuestro
entorno los tabúes viven en el prompt del agente + permisos. Si se quiere una
barrera mecánica, portar la lógica del guard a un plugin opencode
(`tool.execute.before`, que vete comandos tabú) y documentarlo aquí. No es
requisito para v1.