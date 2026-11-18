<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Add-ons de Calisto (no upstream)

Este archivo **no se despliega** (no tiene `mode:` ni vive en `skills/`). Es el
manifiesto de los componentes que no vienen de [`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel)
y que **deben sobrevivir** a cualquier re-vendorización o regeneración del
agente `sysadmin`.

## Registro

| Add-on | Origen | Archivos | Se despliega | Preservar en upgrade |
|---|---|---|---|---|
| `calisto-landlock` | Calisto | `src/agents/sysadmin/skills/calisto-landlock/**` + referencia en `sysadmin.md` | Sí, como skill global | Sí: no borrar ni sobrescribir |
| `calisto-debian-server-baseline` | Calisto | `src/agents/sysadmin/skills/calisto-debian-server-baseline/**` + referencia en `sysadmin.md` | Sí, como skill global | Sí: no borrar ni sobrescribir |
| `calisto-proxmox-console-fallback` | Calisto + Bj | `src/agents/sysadmin/skills/calisto-proxmox-console-fallback/**` + referencia en `sysadmin.md` | Sí, como skill global | Sí: no borrar ni sobrescribir |

## `calisto-landlock`

- **Qué es:** procedimiento operativo para ofrecer, desplegar, verificar y
  respetar el acceso read-only por kernel con `landlock_rosh`.
- **No es de heinzel:** no lo copies desde upstream, no lo pises con una skill
  homónima y no lo borres cuando limpies skills que desaparecieron de heinzel.
- **Depende de:** el binario `landlock_rosh` en `src/tools/landlock_rosh` y su
  fuente en `src/tools/landlock/crate/`. Si el binario cambia de versión, la
  skill solo se actualiza si cambia el comportamiento operativo.
- **Documentación de desarrollo:** `src/tools/landlock/DEVELOPMENT.md` (no
  duplicar en la skill).
- **Licencia:** MPL-2.0, igual que el resto del código propio del repo. Es un
  add-on de Calisto, no de heinzel: no se borra ni se sobrescribe en el
  re-vendorizado.

## `calisto-debian-server-baseline`

- **Qué es:** baseline estándar del driver para un servidor Debian/Ubuntu:
  timezone `America/Montevideo`, paquetes base (`net-tools`, `htop`, `iotop`,
  `neovim`, `tmux`, `lvm2`, `bash-completion`) y PS1 propio, con chequeos
  idempotentes y las trampas del ejecutar remoto (escapado de heredoc, `tput`
  sin PTY).
- **No es de heinzel:** mismo trato que `calisto-landlock` — no se copia desde
  upstream, no se pisa con una skill homónima y no se borra al limpiar skills
  que desaparecieron de heinzel.
- **Se oculta del catálogo:** lleva `metadata.opencode/autoinvoke: false`. Se
  carga por ID y `sysadmin.md` la nombra explícitamente.
- **Licencia:** MPL-2.0, igual que el resto del código propio del repo.

## `calisto-proxmox-console-fallback`

- **Qué es:** acceso de **último recurso** a una VM de Proxmox VE cuando SSH,
  `qemu-guest-agent` y la consola serie fallaron: captura del framebuffer por el
  monitor QEMU (`screendump`) y escritura por `sendkey`. Incluye el diagnóstico
  del OpenSSH legacy (4.3 / solo SHA1), que es la causa habitual detrás de
  "antes entraba y ahora no".
- **No es de heinzel:** mismo trato que los otros add-ons — no se copia desde
  upstream, no se pisa con una skill homónima y no se borra al limpiar skills
  que desaparecieron de heinzel.
- **Origen:** hand-off de una sesión de diagnóstico (2026-11-17, Calisto + Bj),
  adaptado al ruleset antes de entrar al repo: `sendkey` declarado como acción
  con aprobación explícita, sin datos del cliente y con el gatillo acotado a
  "las tres vías de texto fallaron con evidencia".
- **Dependencias:** `qm` / `qm monitor` en el nodo (root por SSH) y Pillow en el
  intérprete del sistema (`python3-pil` por apt, declarado en `src/Containerfile`)
  para convertir el PPM a PNG. El venv por proyecto nace vacío, así que la skill
  no usa el `python3` de la sesión. No usa ImageMagick ni `vncdotool`; la
  alternativa interactiva es la consola web de Proxmox, que opera el humano.
- **Se oculta del catálogo:** lleva `metadata.opencode/autoinvoke: false`. Se
  carga por ID y `sysadmin.md` la nombra explícitamente.
- **Licencia:** MPL-2.0, igual que el resto del código propio del repo.

## Reglas para un upgrade de heinzel

1. Antes de tocar nada, leer este archivo y `upgrade-heinzel.md`.
2. Conservar intactas las skills `calisto-*` (hoy `calisto-landlock`,
   `calisto-debian-server-baseline` y `calisto-proxmox-console-fallback`). No
   copiar upstream encima.
3. Al borrar skills/reglas que desaparecieron upstream, excluir cualquier ruta
   bajo `calisto-*`.
4. Mantener la referencia a cada `calisto-*` en `sysadmin.md` (sección de skills;
   `calisto-landlock` también en la de read-only opcional y
   `calisto-proxmox-console-fallback` en su sección de último recurso).
5. Validar: cada `name:` coincide con su carpeta, `sysadmin.md` nombra cada ID,
   `agents_update.sh --check` las lista y `src/check-skill-wiring.sh` pasa.
6. Incluir `src/agents/sysadmin/skills/calisto-*/**` en el alcance de la
   auditoría de `cyberseguridad`.

## Validación rápida

```bash
# El registro de arriba es la fuente de verdad. Un add-on borrado no lo detecta
# check-skill-wiring.sh (sólo recorre lo que existe), así que este loop es el
# gate que sí lo ve.
addons=$(sed -n 's/^| `\(calisto-[a-z0-9-]*\)` |.*/\1/p' src/agents/sysadmin/ADDONS.md)
[ -n "$addons" ] || { echo "ERROR: el registro de ADDONS.md está vacío o cambió de formato"; exit 1; }
for addon in $addons; do
  skill="src/agents/sysadmin/skills/$addon/SKILL.md"
  test -f "$skill" || { echo "ERROR: falta $addon"; exit 1; }
  grep -q "^name: $addon$" "$skill" || { echo "ERROR: $addon: name: no coincide con la carpeta"; exit 1; }
  grep -qF -- "$addon" src/agents/sysadmin/sysadmin.md || { echo "ERROR: $addon no está cableado en sysadmin.md"; exit 1; }
done

# Y al revés: toda carpeta calisto-* debe figurar en el registro. Sin este control
# inverso, un add-on nuevo quedaría fuera del manifiesto y el loop de arriba lo
# ignoraría en silencio.
for dir in src/agents/sysadmin/skills/calisto-*/; do
  addon="$(basename "$dir")"
  grep -qF -- "| \`$addon\` |" src/agents/sysadmin/ADDONS.md || {
    echo "ERROR: $addon existe en skills/ pero no está registrado en ADDONS.md"; exit 1; }
done
src/check-skill-wiring.sh
```

Si alguna falla, el upgrade borró o desconectó el add-on: restaurarlo desde git
antes de desplegar.
