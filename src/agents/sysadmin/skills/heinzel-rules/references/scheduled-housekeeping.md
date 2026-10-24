<!-- SPDX-FileCopyrightText: 2026 Stefan Wintermeyer -->
<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Scheduled Housekeeping

How to run heinzel housekeeping on a schedule —
nightly or weekly health reports delivered by email
without a human at the keyboard. Read this when the
user asks to "schedule housekeeping", "run a nightly
check", or "email me a weekly report automatically".

## Where the Scheduler Lives

On the workstation or ops box that has the opencode
CLI, the sysadmin agent, and the SSH keys — **never
on the managed server itself**. The managed server
needs no heinzel installation.

## The Command

```
cd /path/to/heinzel && opencode run --agent sysadmin \
  --auto "Run housekeeping on server1.example.com \
and email me the report"
```

- Verify the flags with `opencode run --help` on the
  installed CLI before writing the crontab — flag
  names have changed across releases.
- `--agent sysadmin` selects the sysadmin agent (the
  equivalent of a dedicated heinzel session). In the
  Podman launcher, attach to the running headless
  server instead: `opencode run --attach
  http://localhost:4096 --agent sysadmin "..."`.
- The `-p`-style prompt counts as the explicit user
  request that the `heinzel-email` skill requires;
  "never run automatically" means never
  self-initiated, not never scheduled by the user.

## Prerequisite: One Interactive Dry Run

Run the exact prompt **interactively once** before
scheduling it. The first run answers questions an
unattended run cannot:

- the email skill's pickers (recipient, local vs
  remote source, MTA choice) — persisted as
  `Alert email:` / `Email source:` lines in
  `documents/memory/servers/<host>/memory.md`;
- the backup-presence question from housekeeping;
- any first-connection onboarding for a new host.

Once memory holds the answers, unattended runs have
nothing left to ask.

## Safety

- **Auto-approve with guardrails, never blindly.**
  `--auto` keeps heinzel's prose rules active: the
  agent still backs up configs, tests before
  applying, asks before destructive actions, and
  follows least privilege. The launcher's default
  container already runs with
  `OPENCODE_PERMISSION='{"*": "allow"}'`.
- **Never schedule an unguarded run.** Unattended
  plus unguarded plus production SSH keys is the
  worst possible combination. If you need a
  mechanical backstop, install the heinzel-guard
  plugin (see `upgrade-heinzel.md`); otherwise rely
  on the agent's instructions and review the report.
- Stricter alternative: an explicit allowlist in the
  opencode permission config
  (`permission.bash` in `opencode.json`) — only
  pre-approved commands run.
- Wrap the run in `timeout` (see template). A run
  that hits a question it cannot answer idles; the
  timeout ends it instead of letting it hang until
  the next run.

## Cron Environment

- cron's default `PATH` is minimal — `opencode` is
  often a mise or npm shim that won't resolve. Use
  the absolute path from `command -v opencode`, or
  set `PATH=` at the top of the crontab.
- Schedule in the crontab of the user who owns
  `~/.config/opencode` (CLI credentials) and the SSH
  keys — not root's.
- The SSH key must work without an interactive
  agent or passphrase prompt (heinzel's standard
  BatchMode requirement).

## Crontab Template

```
17 6 * * * cd /path/to/heinzel && flock -n \
  /tmp/heinzel-cron-server1.lock timeout 30m \
  /abs/path/to/opencode run --agent sysadmin --auto \
  "Run housekeeping on server1.example.com and \
email me the report" >> ~/heinzel-cron.log 2>&1
```

- `flock -n` skips the run if the previous one is
  still going — never two heinzel sessions on the
  same host at once. (`flock` is Linux; on macOS,
  prefer the launchd alternative below, which
  serializes runs by itself.)
- `timeout 30m` caps a stuck run.
- Pick an off-peak minute that is not :00.

## systemd Timer Alternative (Linux)

A `heinzel-housekeeping.service` (Type=oneshot,
`ExecStart` = the command above) plus a timer:

```
[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true
```

Timers never start the service while a previous run
is active, so no flock is needed. On macOS, launchd
is the native equivalent; cron also works.

## Where Output Goes

- **Delivery:** the report arrives by email via the
  `heinzel-email` skill (that is what the prompt
  asks for).
- **Debug trail:** `opencode run` stdout lands in
  the log file from the template (or cron's
  `MAILTO`).
- **Audit trail:** as in any session —
  `journalctl -t heinzel` on the server and
  `documents/memory/servers/<host>/changelog.log` locally.