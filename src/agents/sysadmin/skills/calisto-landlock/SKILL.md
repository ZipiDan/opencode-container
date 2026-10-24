---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: calisto-landlock
description: Operational add-on (Calisto, not heinzel) for kernel-enforced read-only SSH access with landlock_rosh. Use when the user asks to make a server read-only, when a critical host should be protected from accidental writes, or when an existing read-only host must be verified or respected. Covers modes, deployment, verification and hard limits. Not for modifying the landlock_rosh binary itself.
---

# calisto-landlock

Optional add-on to the `sysadmin` agent. It is **not** part of the heinzel
ruleset: it is maintained by Calisto and preserved across heinzel upgrades (see
`ADDONS.md` in the launcher repo).

`landlock_rosh` is a static Linux binary that runs a shell or command inside a
kernel-enforced **filesystem read-only** jail (Landlock + seccomp). It also
restricts root. It is deployed **on the remote server**, not in the container.

## When to use

- The user explicitly asks for read-only access to a server.
- A first connection to a critical host where the user wants a hard boundary
  against accidental writes.
- An existing landlock deployment must be verified, maintained or respected.

Do **not** offer it on every host, do not auto-deploy it, and do not change the
normal sysadmin workflow. It is one more option, not an obligation.

## Non-negotiable rules

1. **An enforced host is absolute.** If `documents/memory/readonly.md` or the
   server memory says the host is landlocked, or a write returns `EACCES`/
   `EPERM`, the agent must not bypass it: no other key, user, port, `sudo`,
   `--no-log`, nested launcher or config edit. If a task needs writes, stop and
   tell the user the options (another host, another path, or the user lifts the
   restriction). Never alter the system to finish the task.
2. **`--log-only` is audit, not protection.** It disables the sandbox. With root
   the agent can edit the log or `authorized_keys`. Use it only when the user
   accepts writes and wants a trace.
3. **Never run `landlock_rosh` as a sandbox locally in the container.** The
   binary in the image is a payload to copy to the remote. The log and the
   sandbox live on the remote. Only controller-side `--version` and
   `--print-ssh-line` (no sandbox) are allowed.
4. **Never deploy without explicit approval.** Show the plan, the exact
   `authorized_keys` line and the rollback first.
5. **Never leave a second unrestricted key for the same agent on a read-only
   host.** If the same key was already authorized without `command=`, replace
   that line; do not append a second one.
6. **Never print private keys.** Public key lines only.
7. **Do not claim "the system cannot be altered".** Landlock protects the
   filesystem; daemons, signals, netlink and `utime` stay possible. Read
   `references/limits.md`.

## Workflow

1. **Check memory and enforcement.** Read `documents/memory/readonly.md` and
   `documents/memory/servers/<host>/memory.md`. If the host is already
   landlocked, treat it as read-only; do not reinstall or pin.
2. **Probe the target.** OS, architecture (`x86_64` only), kernel, Landlock ABI,
   `bwrap` fallback, journald/logrotate, `/tmp` `noexec`, installed binary
   version. On kernels < 5.13, `bwrap` is required.
3. **Choose the mode** with the user:
   - `ro`: hard filesystem read-only (recommended for `readonly.md` hosts).
   - `log`: writes allowed, audit only.
4. **Present the plan** and ask for approval: copy path, log backend, exact
   line, rollback. `references/deploy.md` has the runbook.
5. **Stage the binary** from `/usr/local/bin/landlock_rosh` (container) or
   `~/.local/bin/landlock_rosh` (legacy host) to an executable path on the
   remote. Prefer `/usr/local/bin`; if the user cannot write there, use
   `/var/tmp` and verify it is not `noexec`. Never assume `/tmp` is executable.
6. **Install the log backend** (`--install-log`) *before* pinning. After pinning
   the key is read-only and cannot write `/etc` or `/var/log`.
7. **Generate the line** with
   `landlock_rosh --print-ssh-line --mode ro|log --pubkey <file.pub>`.
8. **Pin last**, with `scripts/pin-key.sh`: it backs up `authorized_keys`,
   replaces every line for that key with the forced line, writes atomically and
   verifies. Requires `--yes`; without it, it only prints the plan.
9. **Verify** with `references/verify.md`: writes denied (or allowed in log
   mode), log entry present, version/checksum match, and (for ro) the previous
   unrestricted key no longer authenticates.
10. **Record** the result in `documents/memory/servers/<host>/memory.md`
    (`Landlock: ro|log`, version, log backend, date) and in the changelog.

## Mode summary

| Mode | `command=` value | Protection | `scp`/`sftp` |
|---|---|---|---|
| `ro` | `/usr/local/bin/landlock_rosh` | Filesystem read-only (kernel) | No |
| `log` | `/usr/local/bin/landlock_rosh --log-only` | None; audit only | No (SFTP subsystem replaced) |

For non-root logins that need privileged reads, use a dedicated UID 0 user whose
login shell is `landlock_rosh`, or `sudo` with `env_keep` for
`SSH_ORIGINAL_COMMAND` (see `references/deploy.md`). Do not rely on `sudo`
inside the jail: `no_new_privs` blocks setuid elevation.

## Rollback

With the key pinned, the agent **cannot unpin itself** (the jail is read-only).
Rollback requires another admin key or console. `scripts/pin-key.sh` prints the
exact `cp -p <backup> <authorized_keys>` command. `--uninstall-shell` and
`--uninstall-log` also require an unrestricted session.

## Boundaries

This skill is runtime-only. To modify the binary, read
`src/tools/landlock/DEVELOPMENT.md` in the launcher repo; update
`references/` only if the operational behavior changes.

## References

- `references/modes.md` — mode selection and user-facing trade-offs.
- `references/deploy.md` — step-by-step deployment, key lines, sudo/UID 0, rollback.
- `references/verify.md` — acceptance tests and expected outputs.
- `references/limits.md` — what is and is not blocked; what to tell the user.
- `references/troubleshooting.md` — kernel, bwrap, arch, `noexec`, sudo, scp,
  systemd/gluster, log backend.
