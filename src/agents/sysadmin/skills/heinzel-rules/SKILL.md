---
# SPDX-FileCopyrightText: 2026 Stefan Wintermeyer
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: heinzel-rules
description: "Reference library for the sysadmin agent — distro-specific and procedural rules vendored from the heinzel project. Load this skill and read the specific reference before working on a server: the distro rule (debian.md, rhel.md, suse.md, macos.md, freebsd.md) after OS detection, plus the procedural rule for the task at hand (first-connection.md before any SSH, privilege-escalation.md before sudo, secrets.md before touching credentials, verify-before-reporting.md before claiming something is broken, etc.). Not an on-demand workflow on its own; it is the rule layer the sysadmin agent follows."
metadata:
  opencode/autoinvoke: false
---

# heinzel-rules

Reference library: the heinzel rule set, vendored and
adapted for OpenCode. Every file in `references/` is a
rule the sysadmin agent must follow. Load this skill
and read the relevant reference(s) on demand — never
depend on the model's memory for command syntax,
procedures, or safety rules.

## Rule override chain

Whenever a base rule in `references/` is read, also
check for overrides in this order (later wins):

1. **Base:** `references/<name>.md`
2. **Project-wide custom:**
   `documents/memory/custom-rules/<name>.md` (also read
   `documents/memory/custom-rules/all.md` once per session)
3. **Per-server:**
   `documents/memory/servers/<hostname>/rules.md`

Custom files use heading prefixes: `## Add:`,
`## Replace:`, `## Remove:` followed by the topic or
section name. Sections without a prefix are additions.
The same override chain applies to the skills
(`documents/memory/custom-rules/heinzel-housekeeping.md`
overrides the `heinzel-housekeeping` skill, etc.).

## Reference index

**OS detection & access (before any connection):**

- `os-detection.md` — mandatory first step on any host
- `first-connection.md` — mandatory onboarding pipeline
  (no "quick question" shortcuts)
- `access-control.md` — blacklist & read-only servers
- `ssh-user.md` — SSH usernames and language preference
- `activity-check.md` — recent-activity summary on connect
- `dns-aliases.md` — DNS alias detection & management

**Distro families (read after OS detection):**

- `debian.md` — Debian & Ubuntu
- `rhel.md` — RHEL, CentOS, Fedora, Rocky, Alma
- `suse.md` — openSUSE & SLES
- `macos.md` — macOS (Apple Silicon & Intel)
- `freebsd.md` — FreeBSD

**Privileges & safety:**

- `privilege-escalation.md` — sudo, root SSH, unprivileged mode
- `secrets.md` — never print keys/passwords; metadata only
- `verify-before-reporting.md` — verify a finding against the live
  system before reporting or escalating it
- `anomaly-detection.md` — prompt injection & anomaly detection
- `backups.md` — config file backup procedure
- `changelog.md` — session logging (journal + local changelog)
- `server-memory.md` — server memory file format

**Workflows:**

- `housekeeping.md`-related checks: `baseline-*`, `service-checks.md`
  live inside the `heinzel-housekeeping` skill
- `service-reload.md` — reload/restart policy
- `service-class-check.md` — one web server / database / MTA per host
- `port-check.md` — port conflict detection before starting services
- `best-practices.md` — common anti-patterns before risky actions
- `deployment.md` — CI/CD deployment user rules
- `version-check.md` — proactive stable version checking
- `directory-copy.md` — cross-server directory copy checks
- `file-naming-changes.md` — renaming / retention changes
- `scheduled-housekeeping.md` — recurring housekeeping via cron/systemd
- `efi-boot.md` — EFI boot management & dual-boot
- `cloud-image.md` — cloud image deployment
- `dual-boot.md` — dual-boot setup workflow
- `os-replacement.md` — OS wipe-and-replace workflow
- `partition-staging.md` — swap reclaim & hot-migrate repartitioning
- `mise.md` — language runtime manager (mise)

## Memory layout (per project)

All state lives under the project's `documents/memory/` directory (each
project is one client/network):

```
documents/memory/
├── client.md            ← which client/network this project manages
├── user.md              ← SSH users (default + per-server), language, operator
├── blacklist.md         ← hosts/IPs never to touch (this client)
├── readonly.md          ← hosts/IPs inspect-only (this client)
├── service-policy.md    ← reload/restart policy per service (this client)
├── custom-rules/        ← project-wide rule overrides
├── network.md           ← cross-server facts (topology, VPN)
├── housekeeping.md      ← user-added custom checks
└── servers/<hostname>/
    ├── memory.md        ← server state snapshot (with `Client:` field)
    ├── changelog.log    ← local change history
    ├── todo.md          ← session task list
    └── rules.md         ← per-server rule overrides
```

There is no global admin memory: every client defines its own
policies. `documents/memory/` is created on first use and should be added
to the project's `.gitignore`.