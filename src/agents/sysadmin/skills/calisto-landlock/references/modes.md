<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Modes

`landlock_rosh` can be integrated in five ways. Only **M3** and **M5** give a
hard filesystem guarantee; **M1** and **M4** are convenience/audit.

| Mode | Server-side setup | Protection | Use |
|---|---|---|---|
| **M1** ephemeral | copy binary to `/var/tmp` or `/usr/local/bin`, run `-c` | None (best-effort; the client can skip it) | one-off diagnostics while provisioning, never as a control |
| **M2** login shell | user's shell in `/etc/passwd` is `/usr/local/bin/landlock_rosh` | Filesystem read-only | dedicated UID 0 user for privileged reads, or manual login |
| **M3** forced command | `command="/usr/local/bin/landlock_rosh"` for the agent key | Filesystem read-only (kernel) | hosts in `readonly.md`; the client cannot bypass |
| **M4** forced log | `command="/usr/local/bin/landlock_rosh --log-only"` | None; audit only | hosts where writes are allowed but a trace is wanted |
| **M5** forced RO as root | `command="sudo /usr/local/bin/landlock_rosh"` + `env_keep`, or UID 0 login shell | Filesystem read-only | non-root login that needs to read `/var/log` 0600 |

## Decision tree

1. The user wants **no writes** on the host → M3 (if the agent logs in as root)
   or M5 (if the login is non-root).
2. The user wants **writes with a trace** → M4. Explain it is not a control.
3. The user only wants to try it on a host where the agent already has normal
   access → M1. Do not present M1 as a security boundary.
4. A dedicated read-only user is acceptable and the host has no sudo → M2 with a
   UID 0 user, or M3 on the root key.

## What to tell the user

- M3/M5: "This host will be read-only at the filesystem level, including for
  root. I will not be able to edit configs, install packages, restart services
  or write files. Diagnostics that only read still work. Daemons, signals and
  network changes are not covered."
- M4: "This only records commands. It does not prevent changes, and with root
  the agent could edit the log or the key. Use it as a trace, not as a control."
- M1: "This is a one-off wrapper. It does not stop a client that chooses not to
  use it."

## Why M3 is the only non-bypassable mode

`authorized_keys` with `command=` is enforced by sshd; the client cannot choose
the command or the flags. When the same key is authorized without `command=`,
sshd may use that line first, so the key must be **replaced**, not duplicated.
M4 is also enforced by sshd, but it runs without a sandbox, so it protects
nothing; it only logs.

## Sudo / UID 0

`landlock_rosh` sets `no_new_privs`, so `sudo` inside the jail cannot elevate.
Elevate **before** the jail:

- Preferred: a dedicated UID 0 user with login shell `landlock_rosh`.
- Alternative: `command="sudo /usr/local/bin/landlock_rosh"` plus
  `Defaults:USER env_keep += "SSH_ORIGINAL_COMMAND SSH_CONNECTION SSH_CLIENT"`
  (sudo's `env_reset` would otherwise drop the command). Ensure
  `!requiretty` if the distro defaults to it.
