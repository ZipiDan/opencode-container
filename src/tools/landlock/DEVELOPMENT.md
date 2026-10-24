<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Desarrollo de `landlock_rosh`

Guía para quien modifique el binario. La documentación **operativa** del agente
(vivir en un servidor, desplegar, verificar) está en la skill
`calisto-landlock`; este archivo es la fuente de verdad para **desarrollar** el
tool. Si cambia una funcionalidad, actualizá este archivo y el `README.md`
primero; la skill solo se toca si cambia el comportamiento que el agente usa en
runtime.

## Mapa de módulos

| Archivo | Responsabilidad |
|---|---|
| `src/main.rs` | Parseo de flags, selección de modo (Landlock/bwrap/log-only), orquestación, paths writables, `-c` |
| `src/landlock.rs` | Syscalls Landlock (444/445/446), structs `repr(C)`, reglas path-beneath |
| `src/seccomp.rs` | Filtro BPF para `chmod`/`chown`/`setxattr`/`truncate` (gap de Landlock) |
| `src/bwrap.rs` | Fallback para kernels < 5.13 |
| `src/audit.rs` | Detección de backend (journald/archivo), formato, sanitización, `--install-log` |
| `src/shell.rs` | `--install-shell`, `--install-ssh`, `--print-ssh-line`, línea de `authorized_keys` |
| `src/osinfo.rs` | Parseo de `/etc/os-release`, distros soportadas, hints de paquetes |

## Invariantes (no romper)

1. **Read-only por defecto.** El modo normal permite leer/ejecutar bajo `/` y
   escribir solo en `DEFAULT_WRITABLE_PATHS`/`NODES`. No agregar excepciones sin
   una razón de diagnóstico concreta y documentada.
2. **`no_new_privs` siempre** antes de `landlock_restrict_self`. Sin esto,
   setuid/setgid podrían escapar del dominio (confused deputy).
3. **Auditoría antes del sandbox.** El fd del log (o el socket journald) se abre
   antes de sellar; el proceso encerrado no debe necesitar permisos de escritura
   para loguear.
4. **Un fallo de auditoría nunca bloquea la ejecución.** Degrada con aviso a
   stderr.
5. **ABI best-effort.** Los bits no soportados por el kernel se quitan de
   `handled` (quedan sin restringir); nunca fallar por un bit nuevo.
6. **Sin Landlock:** fallback a bwrap si existe; si no, error claro con
   instrucciones. No degradar silenciosamente a "sin sandbox".
7. **`--log-only` no es sandbox.** Debe imprimir un aviso y no debe usarse para
   afirmar protección. Es solo auditoría.
8. **La línea de `authorized_keys` se genera, no se aplica sola.** El binario
   asiste (`--print-ssh-line`); la edición de claves es una operación explícita
   del operador/agente con backup y verificación.
9. **Nada de secretos en logs.** El comando se registra sanitizado; las claves
   privadas nunca se leen ni se imprimen.
10. **x86_64 en v1.** Si se agrega otro arco, el binario y el empaquetado deben
    ser explícitos; no asumir que el target coincide con el host.

## Contrato CLI

| Flag | Efecto |
|---|---|
| `-c "cmd"` | Ejecuta `cmd`; gana sobre `SSH_ORIGINAL_COMMAND` |
| `--log-only` | Sin sandbox; auditoría; incompatible con `--no-log` |
| `--no-log` | Deshabilita auditoría en esta invocación |
| `--print-ssh-line [--mode ro\|log] [--pubkey FILE]` | Imprime la línea y sale |
| `--install-log` / `--uninstall-log` | Backend de archivo (root, sin sandbox) |
| `--install-shell` / `--uninstall-shell` | Binario + wrapper + `/etc/shells` |
| `--install-ssh` / `--uninstall-ssh` | Shell + placeholder comentado en `/root/.ssh/authorized_keys` |
| `--version`, `-V`, `--help`, `-h` | Salida limpia |

Precedencia de comando: `-c` > `SSH_ORIGINAL_COMMAND` > shell interactiva.

## Cómo agregar una funcionalidad

Checklist mínimo:

1. **Definir el comportamiento y el threat model.** ¿Abre una escritura? ¿Puede
   usarse para evadir el sandbox? ¿Qué pasa en kernel viejo, ABI baja, bwrap,
   arco distinto, no-root?
2. **Implementar en el módulo correcto** (ver mapa). Si es un flag, parsearlo en
   `main.rs` y documentarlo en `print_help`.
3. **Actualizar `README.md`** (uso/operación) y este `DEVELOPMENT.md` si cambia
   la arquitectura o los invariantes.
4. **Agregar tests** en `src/*.rs` (`#[cfg(test)]`) y/o `tests/regresion.sh`.
   Todo flag nuevo necesita al menos: caso feliz, caso de error y no-regresión
   del sandbox.
5. **Compilar** con `crate/build_static.sh`; verificar `file` (static-pie) y
   `--version`.
6. **Checksum/provenance:** regenerar `SHA256SUMS` y anotar la versión en
   `PROVENANCE.md`.
7. **Empaquetado:** el binario va a `src/tools/landlock_rosh` (imagen +
   `--install-tools`); la fuente queda en `src/tools/landlock/crate/`.
8. **Skill:** solo si cambia el comportamiento operativo (nuevo modo, flag que
   el agente use, verificación, límite que deba comunicar), actualizar
   `src/agents/sysadmin/skills/calisto-landlock/references/`.
9. **Revisión de seguridad.** Cambios que toquen sandbox, seccomp, auditoría o
   `authorized_keys` deben pasar por revisión (idealmente el agente
   `cyberseguridad`).

### Dónde va cada cosa

- Nueva syscall a bloquear → `seccomp.rs` (tabla de números x86_64; si se agrega
  otro arco, tabla por arco).
- Nuevo bit de ABI → `landlock.rs` + `adjust_handled_for_abi` en `main.rs`.
- Nuevo backend de auditoría → `audit.rs` (`detect_backend`, `emit`).
- Nueva integración de instalación → `shell.rs` o `audit.rs` según corresponda.
- Nuevo path writable → constantes en `main.rs` + README; justificar por qué es
  seguro.
- Nuevo modo de ejecución → `main.rs`, `finish`, auditoría y tests.

## Matriz de tests

| Nivel | Qué cubre |
|---|---|
| `cargo test` | Parseo, líneas SSH, helpers, distro |
| `cargo clippy -D warnings` | Calidad |
| `cargo fmt --check` | Estilo |
| `tests/regresion.sh` | Comando, `-c`, `--log-only`, `--print-ssh-line`, sandbox, log, bwrap (requiere `bubblewrap`), interactivo, install/uninstall |
| Host real | Kernel 6.x (ABI 6), kernel 5.10 (bwrap), Debian/Ubuntu/RHEL, root/no-root, `/tmp` noexec |
| Remoto | `command=` en `authorized_keys`, `scp` denegado, log en journald/archivo |

## Deuda conocida / futuro

- **write-guarded**: modo que permita escribir en el sistema pero mantenga
  read-only `/root/.ssh`, `/etc/ssh`, `/etc/sudoers` (bwrap con binds RO).
- **IPC estricto**: `LANDLOCK_SCOPE_SIGNAL`, `LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET`
  y `LANDLOCK_ACCESS_FS_RESOLVE_UNIX` (ABI 9) para bloquear daemons; rompe
  diagnósticos por socket, debe ser opt-in.
- **`utime`/`chattr`**: bloquear por seccomp si se justifica (hoy solo se
  documenta).
- **aarch64**: build cruzado/CI y binario separado.
- **Log-only tamperable**: con root el agente puede editar el log o
  `authorized_keys`; no es un control.

## Separación docs tool vs skill

- `README.md` + `DEVELOPMENT.md` + `PROVENANCE.md` → repo, para desarrollar y
  auditar el binario.
- `calisto-landlock/SKILL.md` + `references/` → runtime del agente sysadmin:
  cómo ofrecer, desplegar, verificar y respetar la herramienta. No duplicar el
  modelo técnico completo; enlazar al README.
