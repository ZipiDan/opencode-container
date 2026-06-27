# AGENTS.md

## What this repo is

Container-based opencode launcher using Podman. Entrypoint is `opencode.sh`; it builds a Debian container image and runs opencode inside it against a user project. Each project runs in its own container instance with isolated sessions, snapshots and logs, while sharing credentials and config across all projects.

## Commands

| Action | Command |
|--------|---------|
| Launch web (default port 4096) | `./opencode.sh /path/to/project` |
| Launch TUI (no web server) | `./opencode.sh /path/to/project --tui` |
| Custom port | `./opencode.sh /path/to/project --port 4097` |
| Custom project data dir | `./opencode.sh /path/to/project -config /custom/path` |
| Rebuild image (cached) | `./opencode.sh --rebuild` |
| Rebuild image (no-cache + pull) | `./opencode.sh --update` |
| Atomic replace (build + swap on success) | `./opencode.sh --renew` |
| Share host network | `./opencode.sh /path/to/project --network-host` |

`--renew` and `--rebuild` are mutually exclusive.

## Network

By default the container uses Podman's own network namespace (slirp4netns/pasta), so it **cannot** reach services running on the host that listen on `127.0.0.1` (e.g. a local dev DB, an LLM proxy). Pass `--network-host` (or `--network_host`) to add `--network host` to `podman run`: the container then shares the host's network namespace and `localhost` inside the container resolves to the host. This **breaks network isolation** (the container sees every host port/service), so use it only when host access is required. In web mode the port is published automatically via the host network, so the `-p` flag is omitted (Podman would ignore it and warn otherwise). TUI mode is unaffected and also gains host access.

## Architecture

- `Containerfile` — Debian stable-backports base, installs dev/network tools, opencode (via official install script), and pyright.
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
| `<project>/.opencode/python/` | pip `--user` packages (`PYTHONUSERBASE`) |

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
| `<project>/.opencode/python/` | `/home/opencode/.pythonuser` | project |

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
| `PYTHONUSERBASE` | `/home/opencode/.pythonuser` | pip `--user` install target |
| `AGENT_GIT_NAME` | `OpenCode Agent` | Git author name for agent commits |
| `AGENT_GIT_EMAIL` | `agent@opencode.local` | Git author email for agent commits |
| `OPENCODE_MODE` | `web` / `tui` | Selected by `--tui`/`--no-web` |

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

## Notes

- Container runs as root. `xdg-open` is stubbed with a no-op script.
- Network diagnostic tools are available inside the container (nmap, tcpdump, tshark, iperf, etc.).
- `PYTHONUSERBASE=/home/opencode/.pythonuser` — pip `--user` installs go to the mounted python volume.
- The agent's git/ssh identity lives in `~/.config/opencode/identity/` and is symlinked into `/root/` at container startup by `entrypoint.sh`. This keeps the agent's commits/pushes separate from the user's own git identity.
- opencode organizes sessions and snapshots internally by `projectID` (derived from the git root commit hash). The nested bind mounts provide an additional physical guarantee of isolation between projects.
