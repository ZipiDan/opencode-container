---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: calisto-debian-server-baseline
description: Use ONLY when the user asks to set up, configure, or prepare a Debian/Ubuntu server with the standard baseline. Applies America/Montevideo timezone, installs core packages (net-tools, htop, iotop, neovim, tmux, lvm2, bash-completion), and configures a custom PS1 prompt. Covers SSH connection patterns, idempotent checks, and remote execution caveats (heredoc escaping, tput without PTY). **Never run automatically** — only on an explicit user request naming the host.
metadata:
  opencode/autoinvoke: false
---

# Calisto Debian Server Baseline

Apply the driver's standard baseline to a Debian/Ubuntu server. Every step is
idempotent — verify state before applying, never duplicate.

The whole of the heinzel `first-connection` onboarding pipeline applies before
any SSH: blacklist → read-only → DNS/server memory → SSH user → OS detection.
See `heinzel-rules` (`references/first-connection.md`).

## 0. Gate (mandatory, before touching the host)

This skill mutates remote state as root, directly or through `sudo`. Nothing
here runs on its own.

Every command connects as `<user>@<host>`: the SSH user resolved by the
pipeline and the host named in the request — never an assumed `root`. Whether a
mutating command needs `sudo`, or runs directly because the session is already
`root`, is **detected**, never assumed.

**Detect the privilege mode once, before mutating, and keep it in the session
context.** Every block of this skill uses it as `$SUDO`:

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'echo "uid=$(id -u)"; command -v sudo >/dev/null && sudo -n true && echo "sudo: passwordless" || echo "sudo: unusable"'
```

- **`uid=0`** — connected as `root`. No escalation: `SUDO=""`, commands run
  directly.
- **`sudo: passwordless`** — `SUDO="sudo -n"`.
- **Neither** — resolve the escalation per `references/privilege-escalation.md`
  before going on. That includes the **Root SSH Fallback** of that ruleset,
  probed once with `ssh -o BatchMode=yes root@<host> id` and only when a
  privileged action is really needed: if it works, run the blocks as
  `ssh -o BatchMode=yes root@<host> 'bash -s'` with `SUDO=""`. It is the
  reference's last resort before giving up, not a shortcut to dodge sudo. If
  root SSH also fails, the host is in unprivileged mode and **this skill does
  not apply** (it is pure mutation): abort and report to the operator.

Reuse the sudo flag already recorded in server memory instead of probing again.

`$SUDO` is resolved inside each block, after `set -e`, with
`SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"`. The backup and rollback
blocks (§0.3 (backup) and §0.5 (rollback)) ship it inline together with the
`bash -s` wrapper: the script travels through stdin, so the heredoc is not
mangled by quoting. Writes into `/root/` go through `$SUDO tee` — a shell
redirection is performed by the connecting user's shell, not by `sudo`, and
would fail with "permission denied" before the command even runs.

1. **Explicit request naming the host.** Run only on a direct request from the
   operator that names the target host. Never as part of another task, never on
   several hosts at once, never by inference.

   Before any `ssh`, load the `heinzel-rules` skill and run
   `references/first-connection.md` in full:
   - host listed in `blacklist.md` → refuse, do not connect;
   - host listed in `readonly.md` → this skill does not apply (it is pure
     mutation): abort and tell the operator;
   - SSH user: the one resolved by `references/ssh-user.md` / the host's server
     memory. **Never assume `root`**: the mutating steps (timezone, `apt`,
     `.bashrc`) run with `$SUDO` — empty when the session is already root,
     `sudo -n` when the probe succeeded — per
     `references/privilege-escalation.md`.
2. **Show the plan first, then wait.** Present what will change: the timezone
   (`America/Montevideo`), the 7 packages, and the PS1 block. Ask for explicit
   confirmation. No confirmation → stop, change nothing.
3. **Back up before mutating.** On the host:

   ```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
ts=$(date +%Y%m%d-%H%M%S)
$SUDO cp -p /root/.bashrc "/root/.bashrc.bak.${ts}"
if ! $SUDO cp -p /etc/localtime "/root/.localtime.bak.${ts}"; then
  # readlink -f prints the path even when the file is absent: only record a
  # target that really exists, so an empty/false artifact can't mask a failure.
  localtime_target=$(readlink -f /etc/localtime 2>/dev/null || true)
  if [ -n "$localtime_target" ] && $SUDO test -e "$localtime_target"; then
    printf '%s\n' "$localtime_target" | $SUDO tee "/root/.localtime.link.${ts}" > /dev/null
  fi
fi
if ! $SUDO test -s "/root/.localtime.bak.${ts}" &&
   ! $SUDO test -s "/root/.localtime.link.${ts}"; then
  echo "BACKUP_FAIL: localtime" >&2
  exit 1
fi
{
  echo "backed-up-at: $(date -Is)"
  printf "timezone: %s\n" "$(cat /etc/timezone 2>/dev/null || true)"
  printf "localtime: %s\n" "$(readlink -f /etc/localtime 2>/dev/null || true)"
} | $SUDO tee "/root/.baseline-rollback.${ts}" > /dev/null
$SUDO ls -l "/root/.bashrc.bak.${ts}" "/root/.baseline-rollback.${ts}"
$SUDO test -s "/root/.bashrc.bak.${ts}"
echo "ts=${ts}"
EOS
   ```

   The `EOS` terminator sits flush left on purpose: with `<<'EOS'` (no `-`)
   bash only closes the heredoc on a column-0 delimiter, indenting it breaks
   the block. The quoted delimiter keeps `$(…)` and `${ts}` for the remote
   shell.

   `set -e` makes the block fail for real: the exit code is no longer the one
   from the last read-only command. The output must show the two artifacts plus
   the `ts=...` line; **write that `<ts>` down**, step 5 needs it. If the block
   returns an error, abort without applying anything.

   The `.baseline-rollback.<ts>` file is the persistent record of the previous
   state: `backed-up-at:` (timestamp), `timezone:` (previous `/etc/timezone`
   content) and `localtime:` (resolved localtime path). `cp -p` dereferences
   `/etc/localtime`: it backs up the bytes even when it is a symlink, and only
   falls back to recording the target path if that copy fails — but only when
   the resolved target really exists, since `readlink -f` also prints the path
   of a missing file. After both branches the block **verifies** that at least
   one non-empty artifact exists (`.localtime.bak.<ts>` or
   `.localtime.link.<ts>`); if neither does, it prints `BACKUP_FAIL: localtime`
   and exits 1. With `set -e` the script aborts there: nothing is mutated and
   the timezone rollback is never left without a source.
4. **One step at a time.** Apply each step, verify its result, then move to the
   next one. Never chain the whole baseline into a single command.
5. **Rollback on request.** `<ts>` is the one printed by step 3. Read the
   record first, then restore both artifacts:

   ```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
ts="<YYYYmmdd-HHMMSS>"   # reemplazar por el <ts> del paso 3
$SUDO cat "/root/.baseline-rollback.${ts}"
$SUDO cp -p "/root/.bashrc.bak.${ts}" /root/.bashrc
if $SUDO test -s "/root/.localtime.bak.${ts}"; then
  $SUDO cp -p "/root/.localtime.bak.${ts}" /etc/localtime
elif $SUDO test -s "/root/.localtime.link.${ts}"; then
  $SUDO ln -sf "$($SUDO cat "/root/.localtime.link.${ts}")" /etc/localtime
fi
EOS
   ```

   `/root/.bashrc` comes back from `/root/.bashrc.bak.<ts>`. The timezone comes
   back from `/root/.localtime.bak.<ts>` (byte copy, restored as a regular
   file); if that copy is missing, `/root/.localtime.link.<ts>` holds the
   original symlink target for `ln -sf`. Check the `timezone:` line of the
   record: if it is non-empty and differs from the current `/etc/timezone`,
   write it back. Never roll back without a verified `<ts>`.

## 1. Detect OS

Do not detect it here: the pipeline already did it (`heinzel-rules` →
`references/os-detection.md`). Use what it reported and confirm the target is
Debian-based. Only if the pipeline did not run (e.g. a known host, where the OS
step is skipped), fall back to:

```bash
ssh -o ConnectTimeout=5 <user>@<host> "cat /etc/os-release | head -3"
```

Abort or warn if the output — from the pipeline or from that fallback — does
not show Debian or Ubuntu.

## 2. Verify current state (idempotency check)

Run this before applying changes — it tells you what's already in place:

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
echo "=== Timezone ===" && (cat /etc/timezone 2>/dev/null || readlink /etc/localtime)
echo "=== Packages ===" && dpkg -l net-tools htop iotop neovim tmux lvm2 bash-completion 2>/dev/null | grep "^ii" | awk "{print \$2, \$3}" || echo "(missing)"
echo "=== PS1 ==="
if ! $SUDO test -r /root/.bashrc; then
  echo "(unreadable: needs privileges)"
else
  rc=0; $SUDO grep -q "Custom prompt" /root/.bashrc || rc=$?
  case $rc in
    0) echo "block present" ;;
    1) echo "(stock)" ;;
    *) echo "(error reading /root/.bashrc: rc=$rc)" ;;
  esac
fi
EOS
```

`(stock)` only when the `grep` actually ran and found nothing (rc=1): it is the
only answer that licenses appending the block. An unreadable `/root/.bashrc`
reports `(unreadable: needs privileges)`, and any other return code — a real
`sudo`/read failure, rc≥2 — reports `(error reading /root/.bashrc: rc=<rc>)` and
**must not** be taken as a clean slate. The rc is captured explicitly so `set -e`
does not cut the block on the expected rc=1. `/etc/timezone` and `dpkg` stay
unprivileged.

Skip any step that is already satisfied.

## 3. Apply timezone

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
$SUDO ln -sf /usr/share/zoneinfo/America/Montevideo /etc/localtime
echo "America/Montevideo" | $SUDO tee /etc/timezone > /dev/null
EOS
```

## 4. Install core packages

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
$SUDO apt update -qq
$SUDO apt install -y net-tools htop iotop neovim tmux lvm2 bash-completion
EOS
```

## 5. Configure PS1 prompt

**Important:** The PS1 string contains `$(…)`, `\[`, `\]`, and ANSI sequences.
Do NOT feed it through a heredoc — the escaping collapses and bash will
complain about `EOF` not found. The heredoc of the block below only carries the
script (`<<'EOS'`, quoted); the PS1 string still goes through `printf`.

Use `printf` with proper double-escaping instead. Every `\` and `$` destined
for the remote /root/.bashrc must be escaped once for the remote shell, and the
write goes through `$SUDO tee -a`: the `>>` redirection would be performed by
the connecting user's shell, not by `sudo`:

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
if $SUDO grep -q "Custom prompt" /root/.bashrc; then
  echo "PS1 already present"
else
  printf "\n%s\n" "# Custom prompt" "PS1=\"[\\A]\\[\$(tput bold)\\]\\[\$(tput sgr0)\\]\\[\\033[38;5;6m\\]\\u\\[\$(tput sgr0)\\]\\[\$(tput sgr0)\\]\\[\\033[38;5;15m\\]@\\[\$(tput bold)\\]\\[\$(tput sgr0)\\]\\[\\033[38;5;9m\\]\\h\\[\$(tput sgr0)\\]\\[\$(tput sgr0)\\]\\[\\033[38;5;15m\\]:\\w > \\[\$(tput sgr0)\\]\"" | $SUDO tee -a /root/.bashrc > /dev/null
  echo "PS1 added"
fi
EOS
```

### Caveats

- **`tput: No value for $TERM`** appears when SSH runs without a PTY (non-interactive session). This is normal and harmless — it only means `tput` can't query terminal capabilities. In an interactive login the prompt renders correctly.
- **The `grep -q "Custom prompt"` guard** prevents appending a duplicate PS1 if the block already exists in bashrc.
- **Verificar el resultado final** ejecutando `$SUDO tail -3 /root/.bashrc` (o el bloque de §6) y confirmando que las secuencias escapadas llegaron limpias (sin backslashes sobrantes ni `$()` expandidos prematuramente).

## 6. Final verification

```bash
ssh -o ConnectTimeout=5 <user>@<host> 'bash -s' <<'EOS'
set -e
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
echo "=== Timezone ===" && cat /etc/timezone
echo "=== Packages ===" && dpkg -l net-tools htop iotop neovim tmux lvm2 bash-completion 2>/dev/null | grep "^ii" | awk "{print \$2, \$3}"
echo "=== PS1 ===" && $SUDO tail -3 /root/.bashrc
EOS
```

All three sections should show the expected values: `America/Montevideo`, all 7
packages with version numbers, and the custom PS1 block.
