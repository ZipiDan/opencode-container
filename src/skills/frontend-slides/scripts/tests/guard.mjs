// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

// guard.mjs — Guard mecánico contra la re-duplicación del resolvedor de playwright.
//
// Uso:
//   node guard.mjs [dir]        # dir por defecto: scripts/
//
// Por qué existe: la resolución de playwright y del Chromium del sistema ya vive en
// lib/browser.mjs. Copiarla de nuevo (o hardcodear el binario) produce deriva silenciosa: el
// contenedor y el host dejan de resolver lo mismo y el fallo aparece lejos de la causa. Este
// guard convierte esa deriva en un test rojo.
//
// Reglas:
//   R1  el literal /usr/bin/chromium: el navegador se lee SOLO de PLAYWRIGHT_CHROMIUM_EXECUTABLE.
//   R2  `require('playwright')`, `from 'playwright'` o `import('playwright')` fuera de lib/browser.mjs.
//   R3  una ruta de candidato de playwright (`…/node_modules/playwright`) fuera de lib/browser.mjs.
//
// Vive en tests/ porque no se despliega (el stage de skills excluye tests/) y porque así el
// propio guard queda fuera de su barrido.

import { readdirSync, readFileSync } from 'node:fs';
import { extname, join, relative, resolve } from 'node:path';

const SCANNED_EXTENSIONS = new Set(['.mjs', '.js', '.sh']);
const SKIPPED_DIRS = new Set(['tests']);

// Único archivo autorizado a nombrar el paquete y sus candidatos.
const RESOLVER_FILE = join('lib', 'browser.mjs');
const RESOLVER_RULES = new Set(['R2', 'R3']);

const PLAYWRIGHT_IMPORT =
  /(?:require|import)\s*\(\s*['"]playwright['"]\s*\)|\bfrom\s+['"]playwright['"]/;
const CANDIDATE_PATHS = ['/usr/local/lib/node_modules/playwright', '.deps/node_modules/playwright'];

const RULES = [
  {
    id: 'R1',
    why: 'Chromium hardcodeado; se lee de PLAYWRIGHT_CHROMIUM_EXECUTABLE',
    matches: (line) => line.includes('/usr/bin/chromium'),
  },
  {
    id: 'R2',
    why: 'playwright importado fuera de lib/browser.mjs',
    matches: (line) => PLAYWRIGHT_IMPORT.test(line),
  },
  // R3: plan export-video-frontend-slides dec. 2 (un solo resolvedor) + criterio 0.4 (sin candidatos duplicados).
  {
    id: 'R3',
    why: 'ruta de candidato de playwright duplicada fuera de lib/browser.mjs',
    matches: (line) => CANDIDATE_PATHS.some((candidate) => line.includes(candidate)),
  },
];

function collectFiles(dir, files = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRS.has(entry.name)) collectFiles(join(dir, entry.name), files);
    } else if (SCANNED_EXTENSIONS.has(extname(entry.name))) {
      files.push(join(dir, entry.name));
    }
  }
  return files;
}

// lib/browser.mjs es el dueño del resolvedor: ahí R2 y R3 no aplican.
function ownsResolver(rel_path, rule_id) {
  return RESOLVER_RULES.has(rule_id) && rel_path === RESOLVER_FILE;
}

function scanFile(root, file) {
  const rel_path = relative(root, file);
  const rules = RULES.filter((rule) => !ownsResolver(rel_path, rule.id));
  if (rules.length === 0) return [];

  const violations = [];
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, index) => {
    for (const rule of rules) {
      if (rule.matches(line)) {
        violations.push(`${rel_path}:${index + 1}: ${rule.id} ${rule.why}`);
      }
    }
  });
  return violations;
}

function main() {
  const root = resolve(process.argv[2] ?? join(import.meta.dirname, '..'));
  const files = collectFiles(root);
  const violations = files.flatMap((file) => scanFile(root, file));

  if (violations.length === 0) {
    console.log(`guard: OK (${files.length} archivos)`);
    return 0;
  }

  violations.forEach((violation) => console.error(`  ${violation}`));
  console.error(`guard: ${violations.length} violación(es) en ${root}`);
  return 1;
}

process.exitCode = main();
