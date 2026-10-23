# Add-ons de Calisto (no upstream)

Este archivo **no se despliega** (no tiene `mode:` ni vive en `skills/`). Es el
manifiesto de los componentes que no vienen de [`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel)
y que **deben sobrevivir** a cualquier re-vendorización o regeneración del
agente `sysadmin`.

## Registro

| Add-on | Origen | Archivos | Se despliega | Preservar en upgrade |
|---|---|---|---|---|
| `calisto-landlock` | Calisto | `src/agents/sysadmin/skills/calisto-landlock/**` + referencia en `sysadmin.md` | Sí, como skill global | Sí: no borrar ni sobrescribir |

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

## Reglas para un upgrade de heinzel

1. Antes de tocar nada, leer este archivo y `upgrade-heinzel.md`.
2. Conservar `skills/calisto-landlock/` intacta. No copiar upstream encima.
3. Al borrar skills/reglas que desaparecieron upstream, excluir cualquier ruta
   bajo `calisto-*`.
4. Mantener la referencia a `calisto-landlock` en `sysadmin.md` (sección de
   skills y sección de read-only opcional).
5. Validar: `name: calisto-landlock` coincide con la carpeta, la skill existe,
   `sysadmin.md` la menciona y `agents_update.sh --check` la lista.
6. Incluir `src/agents/sysadmin/skills/calisto-landlock/**` en el alcance de la
   auditoría de `cyberseguridad`.

## Validación rápida

```bash
test -f src/agents/sysadmin/skills/calisto-landlock/SKILL.md
grep -q 'name: calisto-landlock' src/agents/sysadmin/skills/calisto-landlock/SKILL.md
grep -q 'calisto-landlock' src/agents/sysadmin/sysadmin.md
```

Si alguna falla, el upgrade borró o desconectó el add-on: restaurarlo desde git
antes de desplegar.
