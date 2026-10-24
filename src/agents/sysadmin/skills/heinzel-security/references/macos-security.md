<!-- SPDX-FileCopyrightText: 2026 Stefan Wintermeyer -->
<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# macOS Security

## SIP (System Integrity Protection)

```bash
csrutil status
```

- Disabled → **CRITICAL**
- Enabled → OK

## FileVault (Full Disk Encryption)

```bash
fdesetup status
```

- Off → **WARN**
- On → OK

## Gatekeeper

```bash
spctl --status 2>&1
```

- `assessments disabled` → **WARN**
- `assessments enabled` → OK
