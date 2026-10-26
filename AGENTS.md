<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# AGENTS.md

## What this repo is

Container-based opencode launcher using Podman. Entrypoint is `opencode.sh`; it builds a Debian container image and runs opencode inside it against a user project. Each project runs in its own container instance with isolated sessions, snapshots and logs, while sharing credentials and config across all projects.

## Commands

| Action | Command |
|--------|---------|
| Launch web (default port 4096) | `./opencode.sh /path/to/project` |
| Launch TUI (no web server) | `./opencode.sh /path/to/project --tui` |
| Launch web (explicit) | `./opencode.sh /path/to/project --web` |
| Launch mode via host env var | `OPENCODE_GUI=tui ./opencode.sh /path/to/project` (or `OPENCODE_GUI=web`) |
| Publish extra ports (both modes) | `./opencode.sh /path/to/project --extra-ports 3000,8080` |
| Resolve project root from a subdirectory | `./opencode.sh /path/to/project/subdir` |
| Force working inside a subdirectory (no climb) | `./opencode.sh /path/to/project/subdir --no-climb` |
| Custom port | `./opencode.sh /path/to/project --port 4097` |
| Web basic auth (password) | `./opencode.sh /path/to/project --password "pwd"` (user: `opencode`; default password: `opencode`) |
| Generate pairing links for a web container | `./opencode.sh --pair 4096` (or `--pair opencode-4096`) |
| Stop a container | `./opencode.sh --kill <pattern>` (or `--rm <pattern>`) |
| Custom project data dir | `./opencode.sh /path/to/project -config /custom/path` |
| Rebuild image (cached) | `./opencode.sh --rebuild` |
| Rebuild image (no-cache + pull) | `./opencode.sh --update` |
| Update image from scratch, replacing the previous one if the build succeeds | `./opencode.sh --renew` |
| Share host network | `./opencode.sh /path/to/project --network-host` |
| Auto-approve permissions (default: on) | `./opencode.sh /path/to/project` — add `--no-auto` to disable |

`--renew` and `--rebuild` are mutually exclusive.

## Permissions

By default the container **auto-approves opencode permissions** (the container is an isolated sandbox): no approval prompts when accessing folders or running tools. The launcher injects `OPENCODE_PERMISSION='{"*": "allow"}'` into the container. To change this:

- `--no-auto` → opencode asks again (defaults of opencode: `external_directory` asks when touching paths outside `/workspace`).
- Host env `OPENCODE_PERMISSION` (JSON inline permissions config) → takes precedence over `--auto`/`--no-auto` for custom rules (e.g. `OPENCODE_PERMISSION='{"bash": "deny"}' ./opencode.sh ...`).

## Network

By default the container uses Podman's own network namespace (slirp4netns/pasta), so it **cannot** reach services running on the host that listen on `127.0.0.1` (e.g. a local dev DB, an LLM proxy). Pass `--network-host` (or `--network_host`) to add `--network host` to `podman run`: the container then shares the host's network namespace and `localhost` inside the container resolves to the host. This **breaks network isolation** (the container sees every host port/service), so use it only when host access is required. In web mode the port is published automatically via the host network, so the `-p` flag is omitted (Podman would ignore it and warn otherwise). TUI mode is unaffected and also gains host access.

Extra ports: `--extra-ports <n>,<n>,...` publishes each container port on the same host port (`-p n:n`), in addition to the web port. It applies in **both modes** (web and TUI) — useful to reach services running inside the container (e.g. a dev server). Format: comma-separated numbers without spaces, at least 1, each 1-65535, no duplicates, and no clash with `--port` in web mode. With `--network-host` it is omitted with a warning (the container's ports already are host ports).

## Architecture

- `Containerfile` — Debian stable-backports base, installs dev/network tools, Ansible, opencode (via official v2 install script), and pyright.
- `entrypoint.sh` — Container CMD, dispatches to `opencode` (web mode with args) or `opencode` (TUI mode) based on `OPENCODE_MODE`. Also sets up the agent's git/ssh identity via symlinks to `/root/.identity`.
- `opencode.sh` — Host-side launcher: resolves paths, creates dirs, sets up mounts, runs Podman.

## Data separation

Opencode stores data in three XDG scopes. The launcher splits them into **global** (shared across all projects) and **per-project** (isolated). The per-project `<project>/.opencode/data/` directory is mounted directly as `XDG_DATA_HOME/opencode/`, while the global `share/` directory is mounted at `XDG_DATA_HOME/opencode-global/`. Inside the container, `entrypoint.sh` symlinks the global items (`auth.json`, `db/`, `repos/`) into the per-project data directory so opencode can find them. This guarantees physical isolation of project data (including `opencode.db`) even if opencode's internal `projectID` collides (e.g. forked repos).

### Global (`~/.config/opencode/`) — shared, not affected by `-config`

| Path (host) | Purpose |
|-------------|---------|
| `~/.config/opencode/opencode.json` | API keys, providers, models, permissions |
| `~/.config/opencode/agents/` | Custom agents |
| `~/.config/opencode/commands/` | Custom commands |
| `~/.config/opencode/identity/` | Agent git/ssh identity (gitconfig, ssh keys) |
| `~/.config/opencode/share/auth.json` | Credentials from `/connect` |
| `~/.config/opencode/share/db/` | OAuth accounts (GitHub, GitLab, Copilot, etc.) |
| `~/.config/opencode/share/repos/` | Internal clones |

### Per-project (`<project>/.opencode/` by default, override with `-config`)

| Path (host) | Purpose |
|-------------|---------|
| `<project>/.opencode/data/` | Per-project `XDG_DATA_HOME/opencode/` mount: `opencode.db`, sessions, messages, project metadata, snapshots, logs, tool-output (isolated) |
| `<project>/.opencode/state/` | File locks (ephemeral, `XDG_STATE_HOME`) |
| `<project>/python/` | Canonical venv (venv-first): created automatically by `entrypoint.sh` on first start, auto-activated on every start, added to `.gitignore` |
| `<project>/rust/` | Cargo per-project dir (`CARGO_HOME`/`CARGO_TARGET_DIR`): `registry/`, `target/`, `bin/` (isolated). Created automatically and added to `.gitignore` |

## Mounts (container side)

`<project>/.opencode/data/` is mounted as `XDG_DATA_HOME/opencode/` so that `opencode.db` and all other per-project data are physically isolated. The global `share/` directory is mounted at `XDG_DATA_HOME/opencode-global/` and exposed inside the per-project data directory through symlinks created by `entrypoint.sh`.

| Host | Container | Scope |
|------|-----------|-------|
| `<project>` | `/workspace` | project |
| `~/.config/opencode/` | `/home/opencode/.config/opencode/` | global |
| `~/.config/opencode/identity/` | `/root/.identity` | global |
| `~/.config/opencode/share/` | `/home/opencode/.local/share/opencode-global/` | global |
| `<project>/.opencode/data/` | `/home/opencode/.local/share/opencode/` | project |
| `<project>/.opencode/state/` | `/home/opencode/.local/state` | project |

Inside the container, `entrypoint.sh` creates the following symlinks inside `/home/opencode/.local/share/opencode/`:

| Symlink | Target |
|---------|--------|
| `auth.json` | `/home/opencode/.local/share/opencode-global/auth.json` |
| `db/` | `/home/opencode/.local/share/opencode-global/db/` |
| `repos/` | `/home/opencode/.local/share/opencode-global/repos/` |

The global share mount must exist before the symlinks are created.

## Environment variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `XDG_CONFIG_HOME` | `/home/opencode/.config` | Config root |
| `XDG_STATE_HOME` | `/home/opencode/.local/state` | State root (file locks) |
| `XDG_DATA_HOME` | `/home/opencode/.local/share` | Data root (auth, storage, snapshots) |
| `VIRTUAL_ENV` | `/workspace/python` | Project venv (set by `entrypoint.sh` when `python/` is a venv) |
| `CARGO_HOME` | `/workspace/rust` | Cargo registry/bin per project |
| `CARGO_TARGET_DIR` | `/workspace/rust/target` | Cargo build artifacts per project |
| `RUSTUP_HOME` | `/root/.rustup` | Rust toolchain (in image, global) |
| `AGENT_GIT_NAME` | `OpenCode Agent` | Git author name for agent commits |
| `AGENT_GIT_EMAIL` | `agent@opencode.local` | Git author email for agent commits |
| `OPENCODE_MODE` | `web` / `tui` | Interface: flags `--tui`/`--no-web` or `--web` > host env `OPENCODE_GUI` (`tui`/`web`) > default web |
| `OPENCODE_SERVER_PASSWORD` | `opencode` (default) | Web basic auth password: `--password` > host env > default. Always passed in web mode and printed at startup |

Web basic auth: the `--password` flag on `opencode.sh` wins over the host env var `OPENCODE_SERVER_PASSWORD`; if neither is set, the launcher uses `opencode` as the default and prints it. The username is always `opencode`: opencode v2 hardcodes it in `ServerAuthConfig` and ignores `OPENCODE_SERVER_USERNAME`, so the `--user` flag was removed from the launcher. Only applies to web mode; ignored (with a warning) in TUI mode.

Web mode runs detached (`podman run -d`): the container survives terminal close and is stopped with `--kill <port>`. After startup the launcher polls `/api/info`, mints a one-time pairing link (`POST /api/pair`) and prints it; the link sets a 30-day cookie on the browser. `--pair <pattern>` reuses the `--kill` resolver to read the container's port and password and prints links for `127.0.0.1` + LAN IPs (one code per URL). `--pair` does not accept `--port` or `--password`.

Interface selection precedence: `--tui`/`--no-web` or `--web` flags win; otherwise the host env `OPENCODE_GUI` decides (`tui` or `web`; invalid value → warning + default web); otherwise web (default). `OPENCODE_GUI` is read host-side by the launcher and never reaches the container (it is resolved to `OPENCODE_MODE`).

## Migrating from the old layout

Projects created with a previous version of `opencode.sh` used `<project>/.opencode/data/opencode/` as the full `XDG_DATA_HOME` root. The current layout mounts `<project>/.opencode/data/` directly as `XDG_DATA_HOME/opencode/`, so `opencode.db`, `storage/`, `snapshot/`, `log/` and `tool-output/` live there. To migrate a project:

```bash
PROJECT=/path/to/proyecto

# 1. Ensure the global share dir exists
mkdir -p ~/.config/opencode/share

# 2. Copy auth.json to the global location (only the first time)
#    If you already have a global auth.json, do NOT overwrite it.
cp "${PROJECT}/.opencode/data/opencode/auth.json" ~/.config/opencode/share/auth.json 2>/dev/null || true

# 3. Move per-project data to the new layout
mv "${PROJECT}/.opencode/data/opencode/storage" "${PROJECT}/.opencode/data/storage" 2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/snapshot" "${PROJECT}/.opencode/data/snapshot" 2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/log"      "${PROJECT}/.opencode/data/log"      2>/dev/null || true

# 4. Move global data out of the project
mv "${PROJECT}/.opencode/data/opencode/db"    ~/.config/opencode/share/db    2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/repos" ~/.config/opencode/share/repos 2>/dev/null || true

# 5. Clean up the old opencode subdir
rm -rf "${PROJECT}/.opencode/data/opencode"
```

Migration is manual by design to avoid overwriting data. Run it once per existing project. After migrating, `opencode.db` will be created inside `<project>/.opencode/data/` on the next run.

## Plugin dependency

`@opencode-ai/plugin` is installed in `.opencode/node_modules/` inside the project. The `.opencode/.gitignore` excludes `node_modules`, `package.json`, `package-lock.json` — these are internal/expected, not user project files.

## Custom agents (sync with `agents_update.sh`)

The canonical copies of the custom agents live in `src/agents/<agent>/` — one subfolder per agent (even multi-file agents such as `investigador`, which also ships subagents) — each `.md` carrying an integer `version:` in its frontmatter. `agents_update.sh` applies a **hybrid layout** to the host's global config: the owner file (`<agent>/<agent>.md` or a root file) deploys flat (`~/.config/opencode/agents/<agent>.md`) and any other file in an agent folder (subagent) keeps its path (`~/.config/opencode/agents/<agent>/<subagent>.md`). This is decided by **file role, not by `mode:`** (an owner can be `primary` or `all`). OpenCode V2 derives each ID from the relative path and **ignores the `name:` frontmatter field**, so owners get clean IDs (`investigador`) and subagents keep the ownership prefix (`investigador/investigador-en`). Old nested owner files are backed up and removed during migration. OpenCode scans `{agent,agents}/**/*.md` recursively — no registry entry needed in `opencode.json`. Since v2.7.0-pre1 `agent-builder` also supports **local scope**: agents/skills/commands developed in `/tmp` and, after approval, copied to `<proyecto>/.opencode/` (`/workspace/.opencode/...` inside container) — primary at `.opencode/agents/<agent>.md`, subagents under `.opencode/agents/<agent>/` — versioned in the project's git. Global remains default; local is per-project and does not go through `agents_update.sh`.

`agents_update.sh` runs **only from the repo** and is independent of `opencode.sh` (the launcher is typically installed to `/usr/bin` and cannot locate the repo at runtime, so it is never modified by this mechanism). It manages **five stages** (agents → skills → styles → commands, plus tools on demand), showing a per-stage summary and asking one confirmation per stage. Use `--no-skills` to skip the skills stage, `--no-styles` to skip the styles stage, `--no-commands` to skip the commands stage, and `--install-tools [dir]` to install the tool scripts and binaries (e.g. `md2pdf.py`, `landlock_rosh`) into the user's local bin (only needed for host-only opencode installs); exclusive `--update-directory <dir>` migrates legacy root dirs of `<dir>` into `documents/` (mandatory dir; pass a project dir to migrate it, e.g. from its container), nothing else:

| Stage | Source (repo) | Destino (global) | Detección de cambios |
|-------|---------------|------------------|----------------------|
| agents | `src/agents/**/*.md` | `~/.config/opencode/agents/<agent>.md` (primary) / `<agent>/<subagent>.md` | `version:` (frontmatter) + `sha256sum` |
| skills | `src/agents/*/skills/<nombre>/**` + `src/skills/<nombre>/**` | `~/.config/opencode/skills/<nombre>/` | `sha256sum` |
| styles | `src/tools/css-styles/**` | `~/.config/opencode/css-styles/` | `sha256sum` |
| tools | `src/tools/*` (raíz, p. ej. `md2pdf.py`, `landlock_rosh`) | `~/.local/bin` (solo con `--install-tools`) | `sha256sum` |
| commands | `src/commands/*.md` | `~/.config/opencode/commands/` | `sha256sum` |

Since v2.7.0-pre1 local scope (`<proyecto>/.opencode/{agents,skills,commands}/`, `/workspace/.opencode/...` in container) is handled directly by `agent-builder` (copy from `/tmp` after approval, no `agents_update.sh`). Global is default; `setup_project_gitignore()` now creates the exception `!/.opencode/{agents,skills,commands}/` so local agents are git-tracked while `.opencode/data|state|python|node_modules` stay ignored.

The skills stage deploys skills from **two sources** to the **global** opencode skills directory (`skills/<nombre>/SKILL.md`, one level): an agent's own `skills/<nombre>/` folder and the standalone `src/skills/<nombre>/` tree (skills with no owning agent, e.g. `frontend-slides`, `mermaid2png`). The whole standalone tree is copied (scripts/templates included). Because opencode requires unique skill names across all locations, duplicate names **between both sources** are rejected. The `.md` files under `*/skills/` are never treated as agents, and meta-docs without `mode:` (e.g. `upgrade-heinzel.md`) are not deployed.

### Skill global `frontend-slides`

`src/skills/frontend-slides/` (v1, vendorizada de `zarazhangrui/frontend-slides`, MIT) genera presentaciones HTML autocontenidas desde cero o convirtiendo un PPT, con descubrimiento visual de estilo anti-"AI slop", 34 bold templates y export a PDF local. **Vercel excluido** (no publica en terceros). Dependencias **horneadas y offline** en la imagen: `python-pptx` (conversión PPT), `playwright` + Chromium headless shell (export PDF) y `@mermaid-js/mermaid-cli` + Chromium del sistema (para `mermaid2png`). En host, `bash scripts/deps.sh doctor` verifica y `bash scripts/deps.sh install` las aísla en `.deps/`. Se invoca con el comando `/frontend-slides` o cargando la skill por su `description`.

For agents it scans recursively, skips README files, and rejects duplicate agent names (case-insensitive, in case the destination filesystem is case-insensitive). It compares the repo files against the installed copies (plain files on disk, no git or network), shows the changed files, warns that local modifications will be overwritten on confirmation, and asks for confirmation (`Y`/`s`). It **only manages** the files under `src/agents/`, `src/skills/`, `src/tools/` and `src/commands/` — the default OpenCode agents (`build`, `plan`), user commands and any other user files are never touched or deleted. `--check` shows what would change without applying. See `src/agents/README.md` for the agent registry and update procedure.

### Agente `sysadmin` (heinzel) y su actualización

`src/agents/sysadmin/` vendoriza el ruleset de [`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel): el agente `sysadmin.md` (cerebro adaptado a opencode, memoria 100% por proyecto en `<proyecto>/documents/memory/`), sus 5 skills heinzel en `skills/` y la biblioteca de reglas `skills/heinzel-rules/references/`. Además lleva el add-on **`calisto-landlock`** (de Calisto, no de heinzel) para el acceso read-only por kernel con `landlock_rosh`. **No hay flag `--download`**: la actualización desde upstream sigue el procedimiento guiado `src/agents/sysadmin/upgrade-heinzel.md` (fetch → diff → re-vendorizar con mapa de reescrituras Claude-Code→opencode → plegar cambios a `sysadmin.md` y bumpear `version:` → validación → deploy con `agents_update.sh`). El add-on se declara en `src/agents/sysadmin/ADDONS.md` y **no se borra ni se sobrescribe** en el re-vendorizado (Paso 3b del procedimiento).

### Add-on `calisto-landlock`

`src/agents/sysadmin/skills/calisto-landlock/` es el procedimiento operativo para ofrecer, desplegar, verificar y respetar `landlock_rosh`: un binario estático Linux x86_64 que encierra una shell/comando en un filesystem read-only por Landlock + seccomp (también restringe root). Es **opcional**: el agente lo ofrece cuando el usuario pide read-only o en un host crítico; no cambia el flujo normal ni se auto-despliega. Si el host ya está restringido, el agente debe respetarlo y no intentar bypass (otra clave, `sudo`, `--no-log`, etc.). `--log-only` es auditoría, no control. El binario vive en `src/tools/landlock_rosh` (payload en la imagen; `--install-tools` en host) y su documentación de desarrollo en `src/tools/landlock/` (`README.md`, `DEVELOPMENT.md`, `PROVENANCE.md`). La skill es solo runtime; si cambia el binario, no se duplica el modelo técnico en la skill.

Custom commands are deployed to `~/.config/opencode/commands/` (e.g. the `/md2pdf` PDF converter) and custom tools to `~/.config/opencode/scripts/` (e.g. `md2pdf.py`). Because `~/.config/opencode/` is bind-mounted into every container (`opencode.sh` mounts it at `/home/opencode/.config/opencode/`), both commands and tools are available inside the container **and** on any host opencode install, keeping behavior consistent across environments.

The `md2pdf` tool ships with alternate CSS styles in `src/tools/css-styles/` (`github.css`, `pandoc.css`, `newsprint.css`, `notion.css`, `paper.css`), selectable with `md2pdf <entrada.md> --style <nombre>`; `--html` generates an HTML file instead of PDF, `--custom-css <archivo.css>` overrides the style with a custom CSS, and `--list-styles` lists the detected styles. The styles are resolved by precedence: config global of the user (`~/.config/opencode/css-styles/`, deployed by `agents_update.sh` and mounted into the container) wins over the ones baked into the image (`/usr/local/share/md2pdf/css-styles/`); if none is found, the embedded default CSS is used. `--install-tools` copies only the root files of `src/tools/` (e.g. `md2pdf.py`, `landlock_rosh`) and never the `css-styles/` folder, which travels via the styles stage and the image.

### Agente `arquitecto` (software architect)

Agente primario global para las fases previas al desarrollo: organiza ideas y produce arquitectura
documentada y plan de desarrollo. Flujo por fases con gate de aprobación humana por artefacto:
Detección → Ellicitación (socrática, una pregunta por vez, estimaciones solo en rangos) →
Arquitectura → Planificación → Tareas.

- **Home y artefactos**: su home es `<proyecto>/documents/arquitectura/`, con `INDEX.md` (registro de
  proyectos gestionados: `| Proyecto | Descripción | Estado | Fecha de creación | Fecha de última
  actualización |`) y una subcarpeta `<proyecto>/` por proyecto con `design.md`, `modulos/` (canvas por
  módulo), `adr/` MADR-numerados, `diagramas/` Mermaid (skill `mermaid2png`) y `plan/PLAN.md` +
  `plan/tareas/hito-NN/`. Nunca escribe código de aplicación: el handoff va a `plan` (built-in,
  planes de ejecución en `.opencode/plans/`, que carga la skill `delivery-planning`) y a `developer`.
- **Skills del agente**: `module-decomposition` (requisitos→módulos→capas→contratos),
  `architecture-decisions` (gate de 5 preguntas + ciclo de vida ADR), `delivery-planning` (WBS,
  hitos con AC, MoSCoW, DoD). Reusa `mermaid2png`, `api-and-interface-design` y delega research a
  `investigador*`/`explore`.
- **Permisos**: `edit: allow` y `write: allow` (v5): opencode no resuelve bien los patrones por
  directorio cuando el workspace root difiere del root del proyecto (root `/` + proyecto en
  `/workspace` → la ruta se relativiza como `workspace/documents/...`), así que el alcance
  (`documents/arquitectura/**` + scratch `/tmp/opencode/arquitecto/**`) se restringe **por prompt**
  (guardrail 2), no por el motor; `bash: allow`; `task` allowlist `investigador*`/`explore`; sin
  `webfetch`/`websearch` (el research se delega); `external_directory` acotado al scratch.
- **Comando**: `/arquitecto <idea>` (`src/commands/arquitecto.md`, frontmatter `agent: arquitecto`
  para correr bajo su envelope de permisos).
- **Procedencia**: las plantillas y patrones provienen de guías verificadas en 6 idiomas con licencia
  y justificación en `src/agents/arquitecto/PROVENANCE.md`; las re-verificaciones upstream siguen
  `src/agents/arquitecto/upgrade-arquitecto.md` (fetch → diff → plegar → bump `version:` → gate
  `cyberseguridad` → deploy). v1 audited 2026-09-08 (gate final APPROVED-WITH-NOTES; riesgo residual
  documentado R1: la delegación hereda el env auto-allow del launcher).

## Notes

- Container runs as root. `xdg-open` is stubbed with a no-op script.
- Network diagnostic tools are available inside the container (nmap, tcpdump, tshark, iperf, etc.).
- Python is **venv-first**: the canonical venv lives in `<project>/python/` (project root, git-ignored). `entrypoint.sh` creates it automatically on first start (if missing) and activates it on every container start. No `pip --user` / `PYTHONUSERBASE` is used.
- The agent's git/ssh identity lives in `~/.config/opencode/identity/` and is symlinked into `/root/` at container startup by `entrypoint.sh`. This keeps the agent's commits/pushes separate from the user's own git identity.
- `opencode.sh` resolves the project root by climbing upward from the given path looking for `.git` (directory or file, supports worktrees), stopping at `$HOME` to avoid capturing a dotfiles repository. If the project has no `.git` and no `opencode.json(c)`, it creates an idempotent `opencode.jsonc` anchor in the project root to fix opencode's root detection inside the container. Use `--no-climb` (alias `--no-search-git`) to disable root resolution and work exactly in the given directory.
- opencode organizes sessions and snapshots internally by `projectID` (derived from the git root commit hash). The nested bind mounts provide an additional physical guarantee of isolation between projects.

## Git policy (STRICT)

- **NEVER** run `git commit`, `git push`, `git add` (staging for a commit) or any remote operation unless the user **explicitly** instructs you to do so.
- This rule overrides any default proactiveness guidance. Even if a task is fully complete, do not commit or push it on your own initiative.
- The user will tell you when to commit (`"haz commit"`, `"commiteá"`, `"push"`, etc.). Only then stage, commit and/or push as requested.
- You may run read-only git commands freely (`git status`, `git log`, `git diff`, `git show`, etc.) without asking.

## Licencias (STRICT)

- **Todo archivo nuevo nace con header SPDX.** Es lo que marca qué cubre la MPL-2.0, que es copyleft **por archivo**:
  - Código (`.sh`, `.py`, `.rs`, `.mjs`, `.js`, `.css`, `Containerfile`): `#`/`//`/`/* */` después del shebang.
  - Markdown funcional (agentes, skills, comandos con frontmatter): comentario YAML **dentro** del frontmatter. Nunca un `<!-- -->` antes del `---`: rompe el parser de opencode.
  - Markdown de documentación: `<!-- SPDX-... -->` en la primera línea.
- Titular: `SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)`. En archivos derivados se agrega la línea del upstream (`2026 Stefan Wintermeyer`, `2025 Zara Zhang`, `ddd-crew`).
- Tabla de licencias: código y artefactos funcionales propios → **MPL-2.0**; documentación propia → **CC BY-SA 4.0**; terceros → **su licencia original**.
- **Las copias literales de terceros no se tocan.** No se les agrega header ni se re-licencian: se anotan en `REUSE.toml` y se declaran en `THIRD-PARTY.md`.
- Al vendorizar algo nuevo: actualizar `THIRD-PARTY.md` (titular, licencia, origen, qué se modificó), sumar el texto a `LICENSES/` si es una licencia nueva, y anotar la ruta en `REUSE.toml`.
- Excepción de share-alike: los derivados de ddd-crew quedan en **CC BY-SA 4.0** (no se pueden pasar a MPL).
- Verificación opcional: `reuse lint`, sobre un checkout limpio (el venv y los artefactos locales no están versionados y ensucian el conteo).

