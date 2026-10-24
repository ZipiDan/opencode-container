---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: cyberseguridad-catalog
description: "Catálogo y router de metodologías de ciberseguridad para agentes de IA (vendorizado de briiirussell/cybersecurity-skills, MIT): auditoría de código OWASP, APIs, dependencias, secretos, cripto, móvil; pentest/recon/OSINT autorizado; respuesta a incidentes, forense, SIEM, SOC, threat hunting; auditoría cloud/container/IAM; seguridad de IA (prompt injection, AI RMF); threat modeling, CVE research, triage, CSF, comunicación; cumplimiento PCI/HIPAA/privacidad. Use when the user asks for a security audit, vulnerability assessment, secure code review, pentest, recon, OSINT, incident response, threat hunting, cloud/container/IAM audit, AI/LLM security review, prompt injection, threat modeling, CVE triage, compliance review (PCI, HIPAA, GDPR), risk assessment, or any cybersecurity task on code, infrastructure, or AI systems."
---

# Catálogo de ciberseguridad (router)

Mapa de **29 metodologías en 7 familias**,
vendorizado de [briiirussell/cybersecurity-skills](https://github.com/briiirussell/cybersecurity-skills) (MIT (Bri Russell)).
Vendored el 2026-08-23 — regenerable con `node build-catalog.mjs <clon-upstream>`.

## Cómo usar este catálogo

1. **Clasificá la tarea** en una de las familias de abajo (la mayoría de los
   trabajos cruza familias; usá los crossovers al final).
2. **Leé la metodología** antes de ejecutar: `Read` el archivo
   `references/<skill>.md` de la familia correspondiente (¡son archivos
   planos, no skills activas!).
3. **Seguí la metodología** paso a paso — incluidos los checks de
   autorización que abren los skills ofensivos (`recon`, `osint-recon`,
   `web-pentest`, `red-team-engagement`, `disk-forensics`).
4. **Cerrá con los orquestadores** cuando aplique: `finding-triage`
   (disposición de hallazgos), `security-comms` (comunicación) y
   `csf-mapping` (gobierno/roadmap).
5. **Nunca corrijas el código auditado**: tu entregable es el reporte.

## Familias

### AppSec & Supply Chain

| Skill | Cuándo usarla |
|---|---|
| `owasp-audit` | Audit application source code against the OWASP Top 10 (2021) vulnerability categories — broken access control, cryptographic f… |
| `api-audit` | Audit REST, GraphQL, and RPC APIs against the OWASP API Security Top 10 (2023). Use when the user mentions 'API security,' 'API… |
| `dependency-audit` | Audit project dependencies, frameworks, languages, and dev tools for known vulnerabilities, CVEs, and security anti-patterns. U… |
| `secrets-audit` | Find leaked secrets in source code, Git history, build artifacts, and infrastructure — and audit the secrets-management posture… |
| `crypto-audit` | Audit cryptography implementation — algorithm choice, key sizes, KDF parameters, IV/nonce handling, signature verification, ran… |
| `mobile-audit` | Audit iOS and Android mobile applications against OWASP MASVS / MASTG — insecure storage, weak crypto, certificate pinning, dee… |

### Offensive & Recon

| Skill | Cuándo usarla |
|---|---|
| `recon` | Perform structured reconnaissance and attack surface enumeration for authorized penetration tests, CTF challenges, and bug boun… |
| `osint-recon` | Gather and correlate open source intelligence from public sources for authorized investigations, threat intelligence, and attac… |
| `web-pentest` | Perform black-box / grey-box web application penetration testing on an authorized target — auth bypass, IDOR, session handling,… |
| `red-team-engagement` | Plan, scope, and execute an authorized red-team engagement — distinct from a penetration test. Covers engagement methodology, a… |

### Detect & Respond

| Skill | Cuándo usarla |
|---|---|
| `incident-triage` | Guide rapid triage and initial response to security incidents following NIST SP 800-61 methodology. Use when the user mentions… |
| `disk-forensics` | Analyze disk images, file systems, and memory captures for digital evidence recovery in forensic investigations and CTF challen… |
| `siem-detection` | Engineer and audit SIEM detection rules — log source coverage, Sigma / KQL / SPL / Elastic query authoring, MITRE ATT&CK mappin… |
| `soc-operations` | Build, run, and improve a Security Operations Center — alert prioritization, runbook authoring, escalation criteria, on-call st… |
| `threat-hunting` | Conduct proactive, hypothesis-driven threat hunts — search SIEM / EDR / logs for adversaries who haven't tripped an alert yet.… |
| `breach-patterns` | Learn from public breach disclosures — extract the audit question each one implies and check your own stack. Capital One IMDS a… |

### Cloud & Infra

| Skill | Cuándo usarla |
|---|---|
| `cloud-audit` | Audit cloud infrastructure (AWS, GCP, Azure) for misconfigurations, excessive permissions, and security gaps. Use when the user… |
| `container-audit` | Audit container images, Dockerfiles, and Kubernetes manifests for misconfigurations, excessive privileges, exposed secrets, and… |
| `iam-audit` | Audit, design, and migrate Identity and Access Management — cloud provider IAM (AWS, GCP, Azure), identity providers (Okta, Ent… |

### AI Security

| Skill | Cuándo usarla |
|---|---|
| `prompt-injection` | Audit applications for AI prompt injection, agent security, and LLM permission boundary vulnerabilities. Use when the user ment… |
| `ai-risk-management` | Apply the NIST AI Risk Management Framework (AI RMF 1.0) and adjacent guidance to AI / ML systems — model lifecycle governance,… |

### Design & Governance

| Skill | Cuándo usarla |
|---|---|
| `threat-modeling` | Run a structured threat-modeling session for a new feature, system, or architecture — STRIDE, attack trees, data flow diagrams,… |
| `vuln-research` | Research a specific CVE or vulnerability disclosure end-to-end — what version is affected, is your code reachable, is there a p… |
| `finding-triage` | Triage a single security finding — from a scanner, audit, advisory, or report — to a defensible disposition with a mitigation p… |
| `csf-mapping` | Map your security posture against the NIST Cybersecurity Framework 2.0 (Govern, Identify, Protect, Detect, Respond, Recover). P… |
| `security-comms` | Translate technical security work into the language of non-security audiences — board, executives, engineering, customer succes… |

### Compliance & Privacy

| Skill | Cuándo usarla |
|---|---|
| `privacy-engineering` | Implement and audit privacy controls in product and infrastructure — GDPR, CCPA / CPRA, LGPD, PIPEDA. Covers data minimization,… |
| `pci-audit` | Audit applications and infrastructure handling payment card data against PCI DSS v4.0. Heavy emphasis on scope determination (t… |
| `hipaa-audit` | Audit applications and infrastructure handling Protected Health Information against HIPAA — Security Rule (administrative, phys… |

## Orquestadores transversales (cierra cualquier tarea)

| Skill | Cuándo usarla |
|---|---|
| `finding-triage` | Triage a single security finding — from a scanner, audit, advisory, or report — to a defensible disposition with a mitigation p… |
| `security-comms` | Translate technical security work into the language of non-security audiences — board, executives, engineering, customer succes… |
| `csf-mapping` | Map your security posture against the NIST Cybersecurity Framework 2.0 (Govern, Identify, Protect, Detect, Respond, Recover). P… |

## Crossovers entre familias

- owasp-audit ↔ api-audit ↔ dependency-audit ↔ vuln-research
- web-pentest ↔ recon ↔ osint-recon ↔ red-team-engagement
- siem-detection → threat-hunting → incident-triage → disk-forensics
- cloud-audit ↔ container-audit ↔ iam-audit ↔ secrets-audit
- threat-modeling → owasp-audit / api-audit (pre-implementación → código)
- prompt-injection ⇆ ai-risk-management (rebanada de seguridad ⇆ ciclo completo)
- privacy-engineering ⇆ hipaa-audit / pci-audit (ingeniería ⇆ regulatorio)
- breach-patterns → todas las de auditoría (qué revisar)
- finding-triage ← todas (cierra cualquier hallazgo)
- security-comms ← todas (traduce output a audiencias no técnicas)
- csf-mapping ← todas (convierte evidencia en marco de gobierno)

## Autorización y ética

- Los skills ofensivos exigen **autorización explícita** del objetivo antes de
  cualquier acción y **rechazan** usos ambiguos o no autorizados.
- `red-team-engagement` exige carta "get-out-of-jail" firmada, revisión
  legal y deconfliction; nunca exfiltra datos reales (usa marcadores
  sintéticos).
- `osint-recon` rechaza doxing, acoso y vigilancia no autorizada.
- Ningún skill debe usarse contra sistemas sin autorización, ni para
  construir herramientas de ataque para uso no autorizado.
