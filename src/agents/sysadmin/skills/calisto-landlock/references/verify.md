<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Verify

Run these checks on the target after deployment and before reporting success.
Use a throwaway path; do not test with a real config file.

## Version and binary

```bash
ssh USER@HOST 'command -v landlock_rosh && landlock_rosh --version'
```

Expected: `/usr/local/bin/landlock_rosh` and `landlock_rosh 1.9.0` (or the
version the controller shipped). If the target has an older binary, replace it
before pinning.

## Read-only (M2/M3/M5)

```bash
# Direct write outside the allowed paths: must fail
ssh USER@HOST 'touch /root/.landlock_probe 2>&1; echo rc=$?'
# EACCES / Permission denied, rc != 0

# Write in /tmp: must succeed
ssh USER@HOST 'echo ok > /tmp/.landlock_probe && echo tmp_ok'
# tmp_ok

# chmod/truncate: must fail (seccomp/Landlock)
ssh USER@HOST 'chmod 777 /etc/hostname 2>&1; echo rc=$?'
ssh USER@HOST 'truncate -s 0 /etc/hostname 2>&1; echo rc=$?'

# Read: must succeed (root read-only)
ssh USER@HOST 'head -1 /etc/hostname'
```

Clean up `/tmp/.landlock_probe`.

Expected on a read-only host:

| Check | Result |
|---|---|
| `touch /root/...` | denied |
| `echo > /tmp/...` | allowed |
| `chmod` | denied |
| `truncate` | denied |
| `cat /etc/shadow` | allowed (if the login is root/UID 0) |

## Unrestricted key must not work

If the agent had another key authorized on that host, test that it no longer
authenticates:

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 \
    -o ConnectTimeout=5 USER@HOST 'true'
# Must fail (Permission denied) on a strict RO host.
```

If it succeeds, the host still has an unrestricted key. Stop and tell the user;
the read-only guarantee does not exist.

## Audit log

```bash
# journald
ssh USER@HOST 'journalctl -t landlock_rosh -n 4 --no-pager'

# file backend
ssh USER@HOST 'tail -4 /var/log/landlock_rosh/landlock_rosh.log'
```

Expected: a `start` and an `end` entry with the command, user, `src=` and
`exit=0`. Run a marker command first if needed:

```bash
ssh USER@HOST 'landlock_rosh -c "true"'   # or the forced key
```

If there is no entry, the backend is disabled. Check `--install-log` (file) or
the journald socket; do not claim auditing works.

## Log-only (M4)

```bash
ssh USER@HOST 'echo x > /root/.landlock_probe && echo write_ok'
# write_ok: no sandbox

ssh USER@HOST 'journalctl -t landlock_rosh -n 2 --no-pager'
# or tail the file: mode=log-only start/end
```

Expected: write allowed and a `mode=log-only` entry. Do not call this
"protected".

## Controller-side sanity

```bash
# From the controller (container or legacy host)
landlock_rosh --version
landlock_rosh --print-ssh-line --pubkey ~/.ssh/id_ed25519.pub
```

The line must contain `command="/usr/local/bin/landlock_rosh"`; the `log` variant
must contain `--log-only`.

## Report

Record in `documents/memory/servers/<host>/memory.md`:

```
- Landlock: ro | log | none
- Landlock version: 1.9.0
- Log backend: journald | file | disabled
- Verified: YYYY-MM-DD (write denied, /tmp allowed, log present)
```

If any check fails, report the exact command and output; do not retry with
another key or by disabling the jail.
