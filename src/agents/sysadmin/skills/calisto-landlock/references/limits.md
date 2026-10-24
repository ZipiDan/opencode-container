<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Limits

`landlock_rosh` is a **filesystem** jail. It is strong against accidental or
direct file changes, not against every way of changing a system.

## Blocked (filesystem)

- `open` for write, `creat`, `mkdir`, `mknod`, `symlink`, `rename`, `unlink`,
  `truncate` by path, outside `/tmp`, `/var/tmp` and the device nodes.
- `chmod`, `chown`, `setxattr`, `truncate(2)`/`ftruncate(2)` via seccomp.
- Writes to `procfs`/`sysfs`.
- `ioctl` on block/char devices on ABI >= 5: `smartctl`, `storcli`, `nvme` may
  fail even for read-only queries.

## Not blocked

| Vector | Why | What to do |
|---|---|---|
| `systemctl start/stop/restart`, `reboot` | systemd/dbus socket; the daemon writes outside the jail | Do not run on a read-only host. If the task needs it, tell the user. |
| `docker`, `podman`, `virsh`, `gluster` | Daemon sockets | Same. |
| `kill`, `pkill` | Signals are not in Landlock | Do not use on a read-only host. |
| `ip`, `iptables`, `nft` | Netlink is not filesystem | Do not use on a read-only host. |
| `touch -m` | `utime` is not covered | Mention if timestamps matter. |
| `/tmp`, `/var/tmp` | Writable by design | Never store secrets or persistent state. |
| `--log-only` | No sandbox | Treat as audit only; never as protection. |

## Agent guardrails

1. On a read-only host, **do not attempt to bypass** the restriction: no
   alternate key, user, port, `sudo`, nested `landlock_rosh --no-log`, config
   edit or `authorized_keys` edit. The only paths are the user's explicit
   decision or another host.
2. If a task fails with `EACCES`/`EPERM`, stop and report: the exact command,
   what it needs, and the options. Do not rephrase the command to evade the
   jail.
3. Do not run `landlock_rosh` locally in the container. It is a remote payload.
4. Do not use `--no-log` unless the user explicitly asks to disable auditing.
5. Do not claim "the system cannot be altered". Say "filesystem writes are
   blocked; daemons, signals and network are not".
6. Do not leave a second unrestricted key for the agent on a read-only host.
7. Do not unpin or uninstall from the pinned session; it cannot do it anyway.
   Use another admin key or the console, with the user's approval.

## User-facing wording

- Read-only: "The host is read-only at the filesystem level; config edits,
  package installs, service restarts and file writes are blocked. Reading and
  diagnostics still work. Daemons, signals and network changes are not covered."
- Log-only: "Commands are recorded but not blocked; with root the agent could
  edit the log or the key. This is a trace, not a control."
- Blocked task: "This task needs a write that the kernel is denying. I will not
  bypass it. Options: run it on a non-read-only host, do it yourself, or lift the
  restriction on this host. Which do you prefer?"

For the full technical model, see `src/tools/landlock/README.md` in the launcher
repo (section "Límites y modelo de amenaza").
