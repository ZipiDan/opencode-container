// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

// lib/browser.mjs — Único lugar donde se resuelven playwright y Chromium, más el servidor
// estático y la apertura del deck.
//
// Lo consumen export-slides.mjs (export a PDF) y deps.sh (doctor). Tenerlo en un solo archivo
// evita que cada consumidor reinvente la lista de candidatos, el `--no-sandbox` y la tabla MIME.
//
// Uso CLI (lo invoca `deps.sh doctor`):
//   node lib/browser.mjs --doctor
//   Imprime `módulo: <ruta>` y `navegador: <ruta>`; exit 0 si ambos existen, 1 si falta alguno.
//
// Seguridad:
//   - playwright se resuelve SOLO desde ubicaciones conocidas de node_modules, nunca desde
//     variables de entorno: NODE_PATH está prohibido (ESM lo ignora y contamina todo el proceso).
//   - Chromium se lee SOLO de PLAYWRIGHT_CHROMIUM_EXECUTABLE y debe ser una ruta absoluta.
//   - El servidor estático confina las rutas a `serve_dir` (rechaza path traversal) y escucha
//     únicamente en 127.0.0.1.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { dirname, extname, join, resolve, sep } from 'node:path';

// <skill>/scripts/lib -> <skill>, donde `deps.sh install` deja .deps/node_modules
const SKILL_DIR = join(import.meta.dirname, '..', '..');

const MIME_TYPES = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.mjs': 'application/javascript', '.json': 'application/json', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml',
  '.webp': 'image/webp', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
};

// ─── Resolución de playwright ────────────────────────────────────────────────────
// Orden: instalación aislada de la skill (.deps, host) -> imagen del contenedor -> proyecto -> npm global.
function npmGlobalRoot() {
  try {
    const out = execFileSync('npm', ['root', '-g'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 5000,
    }).trim();
    return out || undefined;
  } catch {
    return undefined; // npm ausente o colgado: quedan otros candidatos.
  }
}

// Cada candidato se carga por ruta absoluta, así no depende del cwd ni de NODE_PATH.
function loadFromDir(dir) {
  try {
    return createRequire(join(dir, 'index.js'))(dir);
  } catch {
    return undefined; // siguiente candidato
  }
}

// Privada a propósito: la API pública son las cinco funciones exportadas. El doctor necesita
// además la ruta de origen; `loadPlaywright()` solo el módulo.
function resolvePlaywrightModule() {
  const candidates = [
    join(SKILL_DIR, '.deps', 'node_modules', 'playwright'),
    '/usr/local/lib/node_modules/playwright',
    join(process.cwd(), 'node_modules', 'playwright'),
  ];
  const npm_root = npmGlobalRoot();
  if (npm_root) candidates.push(join(npm_root, 'playwright'));

  for (const dir of candidates) {
    const playwright = loadFromDir(dir);
    if (playwright) return { playwright, path: dir };
  }

  // Último recurso: resolución normal de Node (paquete hermano del script o en un padre).
  const req = createRequire(import.meta.url);
  const entry = req.resolve('playwright');
  return { playwright: req('playwright'), path: dirname(entry) };
}

/**
 * Devuelve el módulo `playwright` resuelto desde la primera ubicación que funcione.
 *
 * @returns {object} El módulo playwright (con `chromium`, `firefox`, …).
 */
export function loadPlaywright() {
  return resolvePlaywrightModule().playwright;
}

// ─── Resolución de Chromium ──────────────────────────────────────────────────────
/**
 * Ruta al Chromium a usar, o `undefined` para que Playwright use el navegador de su caché.
 *
 * En el contenedor de opencode.sh la imagen ya trae Chromium del sistema y se evita duplicar
 * ~128 MB: la variable apunta a ese binario. Es una ruta, no código.
 *
 * @returns {string|undefined} Ruta absoluta, o `undefined` si la variable no está definida.
 * @throws {Error} Si la variable no es una ruta absoluta.
 */
export function resolveChromiumPath() {
  const configured = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (!configured) return undefined;
  if (!configured.startsWith('/')) {
    throw new Error('PLAYWRIGHT_CHROMIUM_EXECUTABLE debe ser una ruta absoluta');
  }
  return configured;
}

/**
 * Opciones de lanzamiento de Chromium listas para `chromium.launch()`.
 *
 * @returns {{executablePath: (string|undefined), args: string[]}}
 */
export function launchOptions() {
  return {
    executablePath: resolveChromiumPath(),
    // El contenedor corre como root: sin --no-sandbox Chromium no arranca.
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  };
}

// ─── Servidor estático (confinado a serve_dir, solo loopback) ────────────────────
/**
 * Levanta un servidor HTTP en 127.0.0.1 sobre un puerto efímero.
 *
 * Sirve `serve_dir` como raíz (necesario para que el deck cargue fuentes y assets relativos) y
 * resuelve `/` al `html_file` indicado.
 *
 * @param {{serve_dir: string, html_file: string}} options
 * @returns {Promise<{url: string, port: number, close: () => void}>}
 */
export function startStaticServer({ serve_dir, html_file }) {
  const root = resolve(serve_dir);

  const server = createServer((req, res) => {
    let decoded_url;
    try {
      decoded_url = decodeURIComponent(req.url);
    } catch {
      res.writeHead(400);
      res.end('Bad request');
      return;
    }

    const file_path = resolve(root, decoded_url === '/' ? html_file : '.' + decoded_url);
    // Confinamiento: la ruta resuelta debe quedar dentro de `root`.
    if (file_path !== root && !file_path.startsWith(root + sep)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    try {
      const content = readFileSync(file_path);
      const ext = extname(file_path).toLowerCase();
      res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
      res.end(content);
    } catch {
      res.writeHead(404);
      res.end('Not found');
    }
  });

  return new Promise((ready, fail) => {
    server.once('error', fail);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      ready({ url: `http://127.0.0.1:${port}/`, port, close: () => server.close() });
    });
  });
}

// ─── Apertura del deck ───────────────────────────────────────────────────────────
/**
 * Abre el deck ya servido y espera a que el layout y las fuentes estén listos.
 *
 * @param {{browser: object, url: string, width?: number, height?: number}} options
 * @returns {Promise<object>} La page de Playwright, lista para navegar slides.
 */
export async function openDeck({ browser, url, width = 1920, height = 1080 }) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(url, { waitUntil: 'networkidle' });
  // Sin las fuentes cargadas el screenshot cae al fallback y el PDF no reproduce el deck.
  await page.evaluate(() => document.fonts.ready);
  return page;
}

// ─── Modo --doctor ───────────────────────────────────────────────────────────────
function reportDoctor() {
  let playwright;
  let module_path;

  try {
    ({ playwright, path: module_path } = resolvePlaywrightModule());
  } catch {
    // Sin módulo no hay nada que preguntarle sobre el navegador.
  }

  let browser_path;
  if (playwright) {
    try {
      browser_path = resolveChromiumPath() ?? playwright.chromium.executablePath();
    } catch (error) {
      console.error(error.message); // variable mal configurada: se reporta como faltante
    }
    // El bundle de playwright puede no estar descargado: la ruta se calcula igual, pero el
    // archivo no existe. Se reporta como faltante en vez de dejar que el launch falle después.
    if (browser_path && !existsSync(browser_path)) browser_path = undefined;
  }

  console.log(`módulo: ${module_path ?? 'no encontrado'}`);
  console.log(`navegador: ${browser_path ?? 'no encontrado'}`);
  return module_path && browser_path ? 0 : 1;
}

if (process.argv[1]?.endsWith('browser.mjs') && process.argv.includes('--doctor')) {
  process.exit(reportDoctor());
}
