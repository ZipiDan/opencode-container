<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Deploy

Run this only after the user approved the mode and the plan. Order matters:
**copy → install log → verify → pin last**. After pinning, the key is read-only
and cannot stage files or edit `authorized_keys`.

> Each code block runs in a new shell: re-resolve `BIN`/`SKILL` in each call or
> use absolute paths.

## 0. Locate the binary on the controller

```bash
# Container: baked into the image
# Legacy host: installed by agents_update.sh --install-tools
BIN=$(command -v landlock_rosh || true)
[ -n "$BIN" ] || { echo "landlock_rosh no está en PATH"; exit 1; }
"$BIN" --version
```

If it is missing in a legacy host, ask the user to run:

```bash
./src/agents_update.sh --install-tools
```

## 1. Probe the target

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 USER@HOST '
  uname -s -m -r
  cat /etc/os-release | head -3
  python3 -c "import ctypes; print(\"landlock_abi\", ctypes.CDLL(None).syscall(444,0,0,1))" 2>/dev/null || echo "landlock_abi n/a"
  command -v bwrap || true
  test -S /run/systemd/journal/socket && echo journald || true
  command -v logrotate || true
  findmnt -no OPTIONS /tmp 2>/dev/null || mount | grep " /tmp "
  command -v landlock_rosh && landlock_rosh --version || true
'
```

Refuse if `uname -s` is not Linux or `uname -m` is not `x86_64`. On kernel
< 5.13, `bwrap` must be installed; otherwise stop and explain.

## 2. Copy the binary

Prefer `/usr/local/bin` (root). If the user cannot write there, use `/var/tmp`
and verify it is not `noexec`.

```bash
# Uses the current (provisioning) key; scp works before pinning
BIN=$(command -v landlock_rosh)
scp -q "$BIN" USER@HOST:/var/tmp/landlock_rosh
ssh USER@HOST 'chmod 755 /var/tmp/landlock_rosh && /var/tmp/landlock_rosh --version'
```

If `scp` is unavailable, stream it:

```bash
BIN=$(command -v landlock_rosh)
ssh USER@HOST 'cat > /var/tmp/landlock_rosh' < "$BIN"
ssh USER@HOST 'chmod 755 /var/tmp/landlock_rosh && /var/tmp/landlock_rosh --version'
```

Install persistently (root):

```bash
ssh USER@HOST 'cp /var/tmp/landlock_rosh /usr/local/bin/landlock_rosh && chmod 755 /usr/local/bin/landlock_rosh'
ssh USER@HOST '/usr/local/bin/landlock_rosh --version'
```

`--install-shell` is only needed for M2 (login shell); it also creates the
`-nolog` wrapper and registers `/etc/shells`. For M3/M4/M5 only the binary is
needed.

## 3. Install the audit backend (before pinning)

```bash
# journald hosts: nothing to install; the socket is detected
# non-journald hosts: file backend + logrotate
ssh USER@HOST '/usr/local/bin/landlock_rosh --install-log'
```

If the command reports "sin journald ni logrotate", install `logrotate` first or
choose a journald host.

## 4. Generate the line

```bash
BIN=$(command -v landlock_rosh)
# ro
"$BIN" --print-ssh-line --pubkey ~/.ssh/id_ed25519.pub

# log (audit only)
"$BIN" --print-ssh-line --mode log --pubkey ~/.ssh/id_ed25519.pub
```

Show the line to the user. It looks like:

```
restrict,no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="/usr/local/bin/landlock_rosh" ssh-ed25519 AAAA... user@host
```

## 5. Pin the key (last)

Copy the script and run it **on the target** so it edits the target's
`authorized_keys`:

```bash
SKILL="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/calisto-landlock"
scp -q "$SKILL/scripts/pin-key.sh" USER@HOST:/var/tmp/pin-key.sh
scp -q ~/.ssh/id_ed25519.pub USER@HOST:/tmp/agent.pub

# Dry run first: prints the diff, changes nothing
ssh USER@HOST "sh /var/tmp/pin-key.sh --pubkey /tmp/agent.pub \
  --authorized-keys /root/.ssh/authorized_keys --mode ro --dry-run"

# Apply after approval (backup + atomic replace + verification)
ssh USER@HOST "sh /var/tmp/pin-key.sh --pubkey /tmp/agent.pub \
  --authorized-keys /root/.ssh/authorized_keys --mode ro --yes"
```

The public key file must already be on the target (`/tmp/agent.pub` above) or
passed as a literal line with `--key-line`. The script:

- backs up `authorized_keys` (`authorized_keys.bak.YYYYMMDDHHMMSS`);
- replaces **every** line that matches that key (type + blob) with the forced
  line, so an old unrestricted line cannot win;
- writes atomically and preserves `0600`;
- refuses without `--yes`;
- prints the rollback command.

Use `/root/.ssh/authorized_keys` for root, `/home/USER/.ssh/authorized_keys` for
a normal user, or the path configured in `AuthorizedKeysFile`.

## 6. Verify

See `verify.md`. Do it before closing the provisioning session.

## 7. Rollback

After pinning, the pinned key cannot edit `authorized_keys` (read-only jail).
Use another admin key or the console:

```bash
cp -p /root/.ssh/authorized_keys.bak.YYYYMMDDHHMMSS /root/.ssh/authorized_keys
```

`pin-key.sh` prints the exact command. `--uninstall-shell` / `--uninstall-log`
also require an unrestricted session (and `--uninstall-shell` refuses if a user
still uses the shell).

## Non-root login / sudo

`no_new_privs` blocks `sudo` inside the jail. Two options:

1. Dedicated UID 0 user (preferred):

   ```bash
   landlock_rosh --install-shell
   useradd -m -s /usr/local/bin/landlock_rosh rosh
   usermod -o -u 0 -g 0 rosh
   ```

   Put the agent key in `/home/rosh/.ssh/authorized_keys` **without**
   `command=`; the login shell enforces the jail.

   > If sshd has `PermitRootLogin no`, a duplicate UID 0 account may be rejected
   > (OpenSSH treats UID 0 as root). Use the `sudo` variant below or ask the
   > admin to allow that account. Never edit `sshd_config` yourself.

2. `sudo` before the jail:

   ```
   command="sudo /usr/local/bin/landlock_rosh" ssh-ed25519 AAAA... user@host
   ```

   ```
   Defaults:USER env_keep += "SSH_ORIGINAL_COMMAND SSH_CONNECTION SSH_CLIENT"
   USER ALL=(root) NOPASSWD: /usr/local/bin/landlock_rosh
   ```

   Add `!requiretty` if the distro requires a TTY.

## Notes

- `scp`, `sftp` and `rsync` stop working with a pinned key (the subsystem is
  replaced by the launcher). Download with `ssh host 'cat /path'`; do uploads
  before pinning.
- `/tmp` may be `noexec`. Use `/usr/local/bin` or `/var/tmp` and test
  `--version`.
- Do not leave the `-nolog` wrapper on a strict RO host unless the user wants
  that escape hatch; it is a convenience, not a control.
