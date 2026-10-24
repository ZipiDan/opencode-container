<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Provenance — `landlock_rosh`

## Origen

Desarrollo propio del proyecto **opencode-container** (operador: Calisto). No es
un vendor de un repositorio externo. Nació como prototipo en Python
(`landlock_rosh.py`, v1.0–v1.5) y fue portado a Rust para eliminar la dependencia
de Python y distribuir un binario estático.

- Fuente: `src/tools/landlock/crate/`
- Binario empaquetado: `src/tools/landlock_rosh`
- Tests: `src/tools/landlock/crate/tests/regresion.sh`
- Licencia: MPL-2.0 (Daniel Zipitría / Calisto). El binario se distribuye en el
  repo junto a su fuente (`src/tools/landlock/crate/`), como exige MPL §3.2.

## Historial de versiones

| Versión | Cambio |
|---|---|
| 1.0 | Port inicial a Rust; Landlock ABI 1, paths writables, seccomp básico |
| 1.1 | Ajustes de ABI, seccomp y pruebas |
| 1.5 | Fallback bubblewrap para kernels < 5.13; documentación de escenarios |
| 1.6 | Auditoría de comandos (journald/archivo), `--install-log`, formato y sanitización |
| 1.6.1 | `truncate`/`ftruncate` bloqueados por seccomp (integridad del log) |
| 1.7.0 | `--install-shell` / `--uninstall-shell`, wrapper `-nolog`, `/etc/shells` |
| 1.8.0 | `--install-ssh` / `--uninstall-ssh`, placeholder en `authorized_keys` |
| 1.9.0 | `-c`, `--log-only`, `--print-ssh-line`; docs consolidadas; prototipo Python eliminado |

## Build

```bash
cd src/tools/landlock/crate
./build_static.sh
# OK -> src/tools/landlock_rosh
```

- Target: `x86_64-unknown-linux-musl`
- Perfil: `release` (`lto = true`, `opt-level = "z"`, `strip = true`)
- Resultado: ELF x86-64 static-pie, ~590 KB
- Dependencia: `libc` (crates.io; se resuelve en build, no se vendoriza)

Prerequisitos: Rust estable, `rustup target add x86_64-unknown-linux-musl`,
`musl-tools`.

## Distribución

- **Imagen del contenedor:** `Containerfile` copia el binario a
  `/usr/local/bin/landlock_rosh` como payload para targets remotos. No se
  ejecuta localmente como sandbox; solo el smoke test de build y los helpers
  `--version`/`--print-ssh-line`.
- **OpenCode legacy:** `agents_update.sh --install-tools` copia los archivos de
  la raíz de `src/tools/` a `~/.local/bin`.
- **Skill:** `calisto-landlock` (en `src/agents/sysadmin/skills/`) contiene el
  procedimiento operativo y `scripts/pin-key.sh`; no reemplaza al binario.

## Checksum

Ver `SHA256SUMS` en este directorio:

```bash
cd src/tools/landlock && sha256sum -c SHA256SUMS
```
