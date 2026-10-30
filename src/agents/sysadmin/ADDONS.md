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

## Reglas para un upgrade de heinzel

1. Antes de tocar nada, leer este archivo y `upgrade-heinzel.md`.
2. Conservar `skills/calisto-landlock/` y `skills/calisto-debian-server-baseline/`
   intactas. No copiar upstream encima.
3. Al borrar skills/reglas que desaparecieron upstream, excluir cualquier ruta
   bajo `calisto-*`.
4. Mantener la referencia a `calisto-landlock` y `calisto-debian-server-baseline`
   en `sysadmin.md` (sección de skills; `calisto-landlock` también en la de
   read-only opcional).
5. Validar: `name:` coincide con la carpeta en ambas skills, `sysadmin.md` las
   menciona, `agents_update.sh --check` las lista y `src/check-skill-wiring.sh`
   pasa.
6. Incluir `src/agents/sysadmin/skills/calisto-*/**` en el alcance de la
   auditoría de `cyberseguridad`.

## Validación rápida

```bash
for addon in calisto-landlock calisto-debian-server-baseline; do
  test -f "src/agents/sysadmin/skills/$addon/SKILL.md"
  grep -q "name: $addon" "src/agents/sysadmin/skills/$addon/SKILL.md"
  grep -q "$addon" src/agents/sysadmin/sysadmin.md
done
src/check-skill-wiring.sh
```

Si alguna falla, el upgrade borró o desconectó el add-on: restaurarlo desde git
antes de desplegar.
