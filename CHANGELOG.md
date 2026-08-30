# Changelog

Todas las versiones notables de **opencode-container** (launcher de opencode en
contenedor Podman).

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
proyecto respeta [SemVer](https://semver.org/lang/es/).

> **Nota sobre versionado:** el campo `VERSION` se incorporó al launcher en
> v1.5.0. Las iteraciones anteriores (v1.0–v1.4) no llevan número en el script;
> su historial se reconstruye desde los mensajes de commit.

## [2.6.2-pre1] — 2026-08-30

### Changed
- `opencode.sh` bumpeado a 2.6.2-pre1.
- **Agente `developer`**: baseline de configuración ruff — `line-length = 120` (estándar del driver) e `ignore = ["I001", "RUF023"]` (isort reordena imports/normaliza líneas en blanco y `RUF023` ordena `__slots__` alfabéticamente; ambos puramente cosméticos y en conflicto con el `__slots__` semántico del driver). Aplica a `ruff.toml` y `pyproject.toml`.

## [2.6.0-pre1] — 2026-08-30

### Added
- **Agente `agent-builder` v1** — meta-orquestador creador de agentes: workflow `investigador → plan → developer → cyberseguridad` con **Regla de oro de los labs (Anthropic/OpenAI/Google): lo determinístico va a hooks (PreToolUse), lo reutilizable a skills, lo universal y corto queda en el .md** (hook emulado como bloque `## Guardrails` en opencode), efímero en `/tmp` (investigador escribe solo en `/tmp`, cleanup obligatorio con `trap`), nunca auto-vendoriza (opción `A*` pre-vendorizada solo si `>500★ + MIT` para evaluación humana), múltiples ciclos `plan↔developer` y **gate final obligatorio** con `cyberseguridad` (STOP en medio/alto con decisión humana).
- **Skill `agent-architecture`** — router de la Regla de Oro, checklist de frontmatter/permisos mínimos, plantilla de prompt y mapa de reescrituras Claude Code→opencode.
- **Auditoría `agent-builder`** — `reports/cyberseguridad-2026-08-30-agent-builder.md` (H-01 MEDIO bloqueante mitigado → `## Guardrails` verbatim) y `reports/cyberseguridad-2026-08-30-agent-builder-reaudit.md` (APROBADO).

### Changed
- `opencode.sh` bumpeado a 2.6.0-pre1.
- `src/agents/README.md` — registro de `agent-builder` v1.
- `TODO.md #7` — marcado Resuelto (2026-08-30 20:45).

## [2.5.0] — 2026-08-30

### Added
- **ruff global en la imagen**: binario estático de `astral-sh/ruff` instalado en `/usr/local/bin/ruff` vía `Containerfile` (fuera de venvs, no enmascarado por mounts).
- **Agente `developer` v7**: reglas de calidad reforzadas — ruff como linter estándar (`ruff check` antes de entregar), fallback `uvx`/`pipx`, propiedades y atributos privados en `snake_case` (`self._internal_state`), y URL del binario precompilado documentada.

### Changed
- `opencode.sh` bumpeado a 2.5.0.
- `test/test/sorted_collection.py` modernizado: `collections.abc` + sintaxis `X | None` (PEP 604), limpieza de variable no usada.

## [2.4.0] — 2026-08-24

### Added
- **`--kill-all` / `--killall`** en `opencode.sh` (mundo GESTIÓN): detiene **todos** los contenedores opencode en ejecución (web y TUI) con un solo `podman stop` (paralelo interno de Podman). Pide confirmación interactiva (procede avisando si no hay TTY) y filtra por prefijo `^opencode` para no tocar contenedores ajenos. Verificación post-stop y reporte de errores por remanente.
- **Agente `cyberseguridad`**: auditor de ciberseguridad con arquitectura **router + catálogo a demanda** — 29 metodologías vendorizadas de [`briiirussell/cybersecurity-skills`](https://github.com/briiirussell/cybersecurity-skills) (MIT) organizadas en 7 familias, cargadas solo cuando se necesitan (`references/<skill>.md`, renombradas para no escanearse como skills). Generador `build-catalog.mjs` (regeneración idempotente del vendorizado) y procedimiento `upgrade-briiirussell.md`.
- **Permisos de solo auditoría** para `cyberseguridad`: `edit` limitado a `reports/**` y `tmp/**` (matcher relativo al workspace, por eso también `../tmp/**`); `bash`/`read`/`task` habilitados; `edit` denegado en el resto.
- **Agente `sysadmin` (vendorizado heinzel)**: agente de administración de sistemas con 5 skills (`heinzel-rules`, `heinzel-housekeeping`, `heinzel-security`, `heinzel-email`, `heinzel-fleet-audit`), memoria por proyecto y procedimiento `upgrade-heinzel.md` — primera vez versionado en git.
- **Tablas en `md2pdf`**: parches en los 5 estilos CSS (`table-layout: fixed`, `overflow-wrap`, `thead` repetido, `page-break-inside`, primera columna angosta) para que las tablas anchas entren en A4 sin desbordes; verificado en los 6 estilos.
- **`BITACORA.md`**: bitácora del proyecto (hitos por timestamp).
- **`reports/`**: directorio de salida de informes del agente `cyberseguridad`.

### Changed
- `opencode.sh` bumpeado a 2.4.0.

## [2.1.0] — 2026-08-21

### Added
- **Estilos CSS para `md2pdf`** (`--style <nombre>`): `github`, `pandoc`, `newsprint`, `notion`, `paper` — CSS autocontenidos con `text-align: justify` y `@page` A4 con numeración.
- Flag `--html` en `md2pdf`: genera un HTML autocontenido en lugar de PDF.
- Flag `--custom-css <archivo.css>`: CSS personalizado con prioridad sobre `--style`.
- Flag `--list-styles` en `md2pdf`: lista los estilos detectados con su origen (no requiere dependencias).
- Stage **styles** en `agents_update.sh`: despliega `src/tools/css-styles/` → `~/.config/opencode/css-styles/` (por defecto, incluido el README; flag `--no-styles` para omitir).
- Búsqueda de estilos por precedencia: config global del usuario (`~/.config/opencode/css-styles/`, montada en el contenedor) > imagen (`/usr/local/share/md2pdf/css-styles/`) > junto al script > relativo al `.md`. Fallback al CSS embebido.

### Changed
- `md2pdf` pasa de v1.0 a v1.2; CSS default embebido con `body` a 10px y justificado.
- `agents_update.sh`: `--install-tools` ahora copia solo la raíz de `src/tools/` (únicamente `md2pdf.py`, no los estilos).
- `src/css-styles/` se reubica a `src/tools/css-styles/` (los estilos son recursos de la tool).

## [2.0.0] — 2026-08-20

### Added
- **Permisos auto-aprobados**: flags `--auto`/`--no-auto` en `opencode.sh` (default: `--auto`). El contenedor ya no pide confirmación para carpetas/herramientas (sandbox aislado).
- **Comando `/md2pdf`**: conversor de informes Markdown → PDF estilizado (comando global + tool `md2pdf.py`).
- `md2pdf` con modos `--doctor` (instrucciones de instalación por OS) e `--install` (accesible en PATH); sin fallback silencioso si faltan dependencias.
- **`agents_update.sh` rediseñado**: gestiona stages (agentes, tools, commands); las tools ya no se instalan por defecto, solo con `--install-tools [dir]` (verifica PATH).
- Agente **investigador v8**: genera la versión PDF del informe con `/md2pdf` a pedido.

### Changed
- `opencode.sh` bumpeado a 2.0.0 (major por el cambio de comportamiento en permisos).
- La env `OPENCODE_PERMISSION` del host tiene prioridad sobre `--auto`/`--no-auto` para reglas personalizadas (JSON inline).
- `Containerfile`: instala `python3-markdown` y `weasyprint`; hornea `md2pdf` en `/usr/local/bin/md2pdf`.

### Documentation
- `AGENTS.md` y `PARAMETERS.md` actualizados (permisos, stages, matriz y BNF con `--auto`).

## [1.9.5] — 2026-08-19

### Fixed
- Se agrega `.opencode/` al `.gitignore` que se completa automáticamente en los proyectos (datos internos de opencode ya no se versionan).

### Changed
- Bump de versión a 1.9.5.

## [1.9.0] — 2026-08-18

### Changed
- **Python venv-first**: se elimina `pip --user` y `PYTHONUSERBASE`. El entorno canónico es el venv del proyecto (`<proyecto>/python/`).
- `entrypoint.sh` crea el venv automáticamente en el primer arranque (si falta) y lo activa en cada arranque.
- `-config` ahora redirige solo `state/` y `data/` (ya no `python/`).
- El `.gitignore` del proyecto se completa automáticamente con `python/` (venv) + `rust/` + temporales.

## [1.8.0] — 2026-08-17

### Added
- **Agente `investigador`**: investigación web multilingüe por subagentes (`investigador-es/en/fr/de/zh/ru`), con modo simplificado (EN/ES) y extendido.
- **`agents_update.sh`**: sincroniza los agentes del repo a la config global (copia canónica en `src/agents/`, deploy preserva subcarpetas).
- **Entorno Rust** por proyecto: `CARGO_HOME`/`CARGO_TARGET_DIR` en `<proyecto>/rust/` (aislado).
- `TODO.md` con registro de pendientes.

## [1.6.0] — 2026-07-12

### Added
- **Resolución del project root**: `opencode.sh` escala hacia arriba buscando `.git` (soporta worktrees), con límite en `$HOME`.
- Anchor idempotente `opencode.jsonc` para proyectos sin `.git` ni config (fija el root dentro del contenedor).
- **Ansible** en la imagen.
- Limpieza de imagen y documentación.

## [1.5.0] — 2026-06-30

### Added
- **Mundo GESTIÓN**: `--ps`/`--ls` (lista contenedores opencode) y `--kill`/`--rm` (detiene un contenedor por patrón).
- **Versionado**: campo `VERSION`/`TAG_RELEASE` en `opencode.sh` y `--version`.

## [1.0–1.4] — 2026-06-27 a 2026-06-28

### Added
- **Launcher inicial**: `opencode.sh` ejecuta opencode en un contenedor Podman por proyecto, con aislamiento de sesiones/datos y compartición de credenciales.
- Sección de capacidades del contenedor en el README (dev Python/Rust, diagnóstico de red, DevOps, IA, Node.js, seguridad).
- `PARAMETERS.md`: referencia formal de combinaciones de parámetros (matriz, árbol, BNF).
- Se incrementa la documentación del README.

---

[2.6.2-pre1]: #262--2026-08-30
[2.6.0-pre1]: #260--2026-08-30
[2.5.0]: #250--2026-08-30
[2.4.0]: #240--2026-08-24
[2.1.0]: #210--2026-08-21
[2.0.0]: #200--2026-08-20
[1.9.5]: #195--2026-08-19
[1.9.0]: #190--2026-08-18
[1.8.0]: #180--2026-08-17
[1.6.0]: #160--2026-07-12
[1.5.0]: #150--2026-06-30
