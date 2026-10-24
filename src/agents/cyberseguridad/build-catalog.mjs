#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

/**
 * build-catalog.mjs — Genera el catálogo vendorizado de ciberseguridad.
 *
 * Lee el repo upstream briiirussell/cybersecurity-skills (clon local) y
 * regenera, de forma IDEMPOTENTE y reproducible:
 *
 *   skills/cyberseguridad-catalog/references/<skill>.md   (29 metodologías,
 *         renombradas a <skill>.md para que opencode NO las escanee como
 *         skills: solo se cargan a demanda con Read → 0 tokens hasta usarse)
 *   skills/cyberseguridad-catalog/SKILL.md                (índice/router:
 *         tablas por familia + crossovers + instrucciones de uso)
 *
 * Uso:
 *   node build-catalog.mjs <ruta-upstream> [--out <dir>]
 *     <ruta-upstream>  clon local de https://github.com/briiirussell/cybersecurity-skills
 *     --out <dir>      directorio del skill (default: skills/cyberseguridad-catalog)
 *
 * El script es el punto único de regeneración del vendorizado: cualquier
 * actualización del repo original se refleja re-corriendo este script
 * (ver upgrade-briiirussell.md). No modifica nada que no sea el catálogo.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "fs";
import { join, resolve } from "path";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const UPSTREAM = process.argv[2] || "upstream";
const OUT_ARG = process.argv.indexOf("--out");
const OUT_DIR = OUT_ARG !== -1
  ? resolve(process.argv[OUT_ARG + 1])
  : resolve("skills", "cyberseguridad-catalog");
const UPSTREAM_SKILLS = join(UPSTREAM, "skills");
const UPSTREAM_URL = "https://github.com/briiirussell/cybersecurity-skills";
const UPSTREAM_LICENSE = "MIT (Bri Russell)";
const TODAY = new Date().toISOString().slice(0, 10);

// Mapa oficial de familias del README upstream (29 skills, 7 familias).
const FAMILIES = {
  "AppSec & Supply Chain": [
    "owasp-audit", "api-audit", "dependency-audit", "secrets-audit",
    "crypto-audit", "mobile-audit",
  ],
  "Offensive & Recon": [
    "recon", "osint-recon", "web-pentest", "red-team-engagement",
  ],
  "Detect & Respond": [
    "incident-triage", "disk-forensics", "siem-detection", "soc-operations",
    "threat-hunting", "breach-patterns",
  ],
  "Cloud & Infra": [
    "cloud-audit", "container-audit", "iam-audit",
  ],
  "AI Security": [
    "prompt-injection", "ai-risk-management",
  ],
  "Design & Governance": [
    "threat-modeling", "vuln-research", "finding-triage", "csf-mapping",
    "security-comms",
  ],
  "Compliance & Privacy": [
    "privacy-engineering", "pci-audit", "hipaa-audit",
  ],
};

// Orquestadores transversales: cierran cualquier tarea, no solo su familia.
const ORCHESTRATORS = ["finding-triage", "security-comms", "csf-mapping"];

// Crossovers oficiales (README upstream).
const CROSSOVERS = [
  "owasp-audit ↔ api-audit ↔ dependency-audit ↔ vuln-research",
  "web-pentest ↔ recon ↔ osint-recon ↔ red-team-engagement",
  "siem-detection → threat-hunting → incident-triage → disk-forensics",
  "cloud-audit ↔ container-audit ↔ iam-audit ↔ secrets-audit",
  "threat-modeling → owasp-audit / api-audit (pre-implementación → código)",
  "prompt-injection ⇆ ai-risk-management (rebanada de seguridad ⇆ ciclo completo)",
  "privacy-engineering ⇆ hipaa-audit / pci-audit (ingeniería ⇆ regulatorio)",
  "breach-patterns → todas las de auditoría (qué revisar)",
  "finding-triage ← todas (cierra cualquier hallazgo)",
  "security-comms ← todas (traduce output a audiencias no técnicas)",
  "csf-mapping ← todas (convierte evidencia en marco de gobierno)",
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseFrontmatter(content) {
  const m = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) return { meta: {}, body: content.trim() };
  const meta = {};
  for (const line of m[1].split("\n")) {
    const kv = line.match(/^([\w-]+):\s*(.*)$/);
    if (kv) meta[kv[1]] = kv[2].replace(/^"|"$/g, "");
  }
  return { meta, body: m[2].trim() };
}

function familyOf(skill) {
  for (const [fam, skills] of Object.entries(FAMILIES)) {
    if (skills.includes(skill)) return fam;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  if (!existsSync(join(UPSTREAM_SKILLS))) {
    console.error(`[ERROR] No se encontró el upstream en: ${UPSTREAM_SKILLS}`);
    console.error("Cloná primero: git clone --depth 1 " + UPSTREAM_URL);
    process.exit(1);
  }

  const expected = Object.values(FAMILIES).flat();

  const found = readdirSync(UPSTREAM_SKILLS, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .filter((n) => existsSync(join(UPSTREAM_SKILLS, n, "SKILL.md")))
    .sort();

  const missing = expected.filter((s) => !found.includes(s));
  const unknown = found.filter((s) => !expected.includes(s));
  if (missing.length || unknown.length) {
    console.error("[ERROR] El catálogo upstream no coincide con el mapa de familias.");
    if (missing.length) console.error("  Faltan en upstream:", missing.join(", "));
    if (unknown.length) console.error("  No mapeados en FAMILIES:", unknown.join(", "));
    console.error("  Revisá el README upstream y actualizá el mapa FAMILIES.");
    process.exit(1);
  }

  mkdirSync(join(OUT_DIR, "references"), { recursive: true });

  // --- 1) References: <skill>.md = frontmatter original + body + metadato ---
  const catalog = {};
  for (const skill of expected) {
    const raw = readFileSync(join(UPSTREAM_SKILLS, skill, "SKILL.md"), "utf-8");
    const { meta, body } = parseFrontmatter(raw);
    const fam = familyOf(skill);
    const ref =
      raw.trimEnd() +
      `\n\n<!-- ${"cyberseguridad-catalog"}: family=${fam}; source=${UPSTREAM_URL}; ` +
      `license=${UPSTREAM_LICENSE}; vendored=${TODAY}; regen: node build-catalog.mjs -->\n`;
    writeFileSync(join(OUT_DIR, "references", `${skill}.md`), ref);
    catalog[skill] = { meta, fam, body };
  }

  // --- 2) Índice/router: SKILL.md ---
  const short = (s) => {
    const d = (catalog[s].meta.description || "").replace(/\s+/g, " ").trim();
    return d.length > 130 ? d.slice(0, 127).trimEnd() + "…" : d;
  };

  const famTables = Object.entries(FAMILIES)
    .map(([fam, skills]) => {
      const rows = skills
        .map((s) => `| \`${s}\` | ${short(s)} |`)
        .join("\n");
      return `### ${fam}\n\n| Skill | Cuándo usarla |\n|---|---|\n${rows}`;
    })
    .join("\n\n");

  const orchestratorRow = ORCHESTRATORS
    .map((s) => `| \`${s}\` | ${short(s)} |`)
    .join("\n");

  const crossLines = CROSSOVERS.map((c) => `- ${c}`).join("\n");

  const index = `---
name: cyberseguridad-catalog
description: "Catálogo y router de metodologías de ciberseguridad para agentes de IA (vendorizado de briiirussell/cybersecurity-skills, MIT): auditoría de código OWASP, APIs, dependencias, secretos, cripto, móvil; pentest/recon/OSINT autorizado; respuesta a incidentes, forense, SIEM, SOC, threat hunting; auditoría cloud/container/IAM; seguridad de IA (prompt injection, AI RMF); threat modeling, CVE research, triage, CSF, comunicación; cumplimiento PCI/HIPAA/privacidad. Use when the user asks for a security audit, vulnerability assessment, secure code review, pentest, recon, OSINT, incident response, threat hunting, cloud/container/IAM audit, AI/LLM security review, prompt injection, threat modeling, CVE triage, compliance review (PCI, HIPAA, GDPR), risk assessment, or any cybersecurity task on code, infrastructure, or AI systems."
---

# Catálogo de ciberseguridad (router)

Mapa de **${expected.length} metodologías en ${Object.keys(FAMILIES).length} familias**,
vendorizado de [briiirussell/cybersecurity-skills](${UPSTREAM_URL}) (${UPSTREAM_LICENSE}).
Vendored el ${TODAY} — regenerable con \`node build-catalog.mjs <clon-upstream>\`.

## Cómo usar este catálogo

1. **Clasificá la tarea** en una de las familias de abajo (la mayoría de los
   trabajos cruza familias; usá los crossovers al final).
2. **Leé la metodología** antes de ejecutar: \`Read\` el archivo
   \`references/<skill>.md\` de la familia correspondiente (¡son archivos
   planos, no skills activas!).
3. **Seguí la metodología** paso a paso — incluidos los checks de
   autorización que abren los skills ofensivos (\`recon\`, \`osint-recon\`,
   \`web-pentest\`, \`red-team-engagement\`, \`disk-forensics\`).
4. **Cerrá con los orquestadores** cuando aplique: \`finding-triage\`
   (disposición de hallazgos), \`security-comms\` (comunicación) y
   \`csf-mapping\` (gobierno/roadmap).
5. **Nunca corrijas el código auditado**: tu entregable es el reporte.

## Familias

${famTables}

## Orquestadores transversales (cierra cualquier tarea)

| Skill | Cuándo usarla |
|---|---|
${orchestratorRow}

## Crossovers entre familias

${crossLines}

## Autorización y ética

- Los skills ofensivos exigen **autorización explícita** del objetivo antes de
  cualquier acción y **rechazan** usos ambiguos o no autorizados.
- \`red-team-engagement\` exige carta "get-out-of-jail" firmada, revisión
  legal y deconfliction; nunca exfiltra datos reales (usa marcadores
  sintéticos).
- \`osint-recon\` rechaza doxing, acoso y vigilancia no autorizada.
- Ningún skill debe usarse contra sistemas sin autorización, ni para
  construir herramientas de ataque para uso no autorizado.
`;

  writeFileSync(join(OUT_DIR, "SKILL.md"), index);

  // --- 3) Resumen ---
  console.log(`Catálogo regenerado en ${OUT_DIR}`);
  console.log(`  ${expected.length} references (${Object.keys(FAMILIES).length} familias)`);
  console.log(`  Índice: ${index.split("\n").length} líneas`);
  console.log("  OK — idempotente; re-correr no cambia nada salvo el metadato vendored.");
}

main();