<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Troubleshooting

## `landlock_rosh: cannot execute binary file` / `Exec format error`

The target is not x86_64 or not Linux. v1 ships only
`x86_64-unknown-linux-musl`. Stop; do not copy the binary.

## `Operation not permitted` or `Landlock no disponible`

- Kernel < 5.13: Landlock is absent. The binary falls back to `bwrap`; if it is
  not installed, install it (Debian/Ubuntu `apt-get install -y bubblewrap`,
  RHEL `dnf install -y epel-release && dnf install -y bubblewrap`, etc.).
- `cat /sys/kernel/security/lsm` does not list `landlock`: the kernel was built
  or booted without it. Use `bwrap` or upgrade the kernel.
- ABI < 5: `IOCTL_DEV` is not available; `smartctl`/`storcli` may work
  differently. Check `landlock_rosh --version` and the kernel.

## `/tmp` is `noexec`

The binary cannot run from `/tmp`. Use `/usr/local/bin` (root) or `/var/tmp`;
verify with `landlock_rosh --version`. The staging script should test execution,
not just copy the file.

## `sudo: effective uid is not 0` inside the jail

`no_new_privs` blocks setuid elevation. Elevate before the jail:
`command="sudo /usr/local/bin/landlock_rosh"` with `env_keep` for
`SSH_ORIGINAL_COMMAND`, or use a dedicated UID 0 user with login shell
`landlock_rosh`.

## `sudo` runs but the command is empty / opens an interactive shell

`sudo`'s `env_reset` dropped `SSH_ORIGINAL_COMMAND`. Add:

```
Defaults:USER env_keep += "SSH_ORIGINAL_COMMAND SSH_CONNECTION SSH_CLIENT"
```

or use `landlock_rosh -c "..."` with the command passed as an argument.

## `scp`/`sftp`/`rsync` stopped working

Expected with a pinned key: `command=` replaces the subsystem. Do transfers
**before** pinning. To download, use `ssh host 'cat /path'`; to upload, use a
separate provisioning channel. Do not remove the forced command just to copy a
file.

## The old key still works after pinning

There is another line for the same key without `command=`, or another authorized
key. sshd uses the first matching line. `pin-key.sh` replaces every line for
that key; verify with `ssh -o IdentitiesOnly=yes -i <old-key> host true` and make
it fail. If it succeeds, the host is not read-only; tell the user.

## `systemctl`/`gluster`/`docker` still work

Expected: the daemon performs the write outside the jail. Landlock is
filesystem-only. Do not use this to claim the host is immutable. A command
allowlist or a future write-guarded mode is required for that.

## No audit entries

- journald hosts: check `/run/systemd/journal/socket` and
  `journalctl -t landlock_rosh`.
- file hosts: `landlock_rosh --install-log` needs root and `logrotate`; check
  `/etc/logrotate.d/landlock_rosh` and `/var/log/landlock_rosh/`.
- `--no-log` or `LANDLOCK_NO_LOG=1` was used.
- `--log-only` logs, but the file is writable by the agent; do not treat it as
  tamper-proof.

## `authorized_keys` line rejected / login denied

- The binary path must exist and be executable on the target.
- Options are comma-separated; `command="..."` must be quoted.
- `restrict` already implies `no-pty`, `no-port-forwarding`,
  `no-agent-forwarding`, `no-X11-forwarding`; duplicating them is harmless.
- Keep a backup and a second admin key/console before editing.
- `sshd -t` validates the daemon config, not `authorized_keys`; test a new
  connection.

## Version mismatch

The controller and the target must run the same `landlock_rosh` version. Compare
`landlock_rosh --version` and `sha256sum /usr/local/bin/landlock_rosh` with
`src/tools/landlock/SHA256SUMS`. Replace the target binary before pinning.
