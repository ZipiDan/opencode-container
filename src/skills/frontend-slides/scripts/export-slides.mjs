// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

// export-slides.mjs — Exporta una presentación Frontend Slides (HTML) a PDF.
//
// Uso (lo invoca scripts/export-pdf.sh):
//   node export-slides.mjs <serveDir> <htmlFilename> <outputPdf> <screenshotDir> <vpW> <vpH>
//
// Cómo funciona:
//   1. Levanta un servidor HTTP local EN LOOPBACK (necesario para fuentes/assets relativos).
//   2. Abre la presentación en Chromium headless (playwright) al viewport indicado.
//   3. Cuenta las slides, navega una por una y saca un screenshot.
//   4. Combina los screenshots en un único PDF (una página por slide).
//
// Seguridad:
//   - El paquete playwright se resuelve SOLO desde ubicaciones conocidas de node_modules
//     (.deps/node_modules/playwright o /usr/local/lib/node_modules/playwright). No se carga
//     código desde variables de entorno arbitrarias.
//   - El servidor estático confina las rutas a SERVE_DIR (rechaza path traversal) y escucha
//     únicamente en 127.0.0.1.

import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { join, extname, resolve, sep } from 'node:path';

// Resolución acotada de playwright (sin rutas de entorno arbitrarias).
function loadPlaywright() {
  const candidates = [
    '/usr/local/lib/node_modules/playwright',
    join(process.cwd(), 'node_modules', 'playwright'),
    join(import.meta.dirname, '..', '.deps', 'node_modules', 'playwright'),
  ];
  for (const dir of candidates) {
    try {
      const req = createRequire(join(dir, 'index.js'));
      return req(dir);
    } catch { /* siguiente candidato */ }
  }
  // Último recurso: resolución normal de Node (paquete instalado en el proyecto).
  return createRequire(import.meta.url)('playwright');
}
const { chromium } = loadPlaywright();

const SERVE_DIR = resolve(process.argv[2]);
const HTML_FILE = process.argv[3];
const OUTPUT_PDF = process.argv[4];
const SCREENSHOT_DIR = process.argv[5];
const VP_WIDTH = parseInt(process.argv[6], 10) || 1920;
const VP_HEIGHT = parseInt(process.argv[7], 10) || 1080;

// ─── Servidor estático (confinado a SERVE_DIR, solo loopback) ─────────────────────
const MIME_TYPES = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.mjs': 'application/javascript', '.json': 'application/json', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml',
  '.webp': 'image/webp', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
};

const server = createServer((req, res) => {
  let decodedUrl;
  try {
    decodedUrl = decodeURIComponent(req.url);
  } catch {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }
  const filePath = resolve(SERVE_DIR, decodedUrl === '/' ? HTML_FILE : '.' + decodedUrl);
  // Confinamiento: la ruta resuelta debe quedar dentro de SERVE_DIR.
  if (filePath !== SERVE_DIR && !filePath.startsWith(SERVE_DIR + sep)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  try {
    const content = readFileSync(filePath);
    const ext = extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
});

const port = await new Promise((resolvePort) => {
  server.listen(0, '127.0.0.1', () => resolvePort(server.address().port));
});
console.log(`  Servidor local (loopback) en puerto ${port}`);

// ─── Screenshot por slide ─────────────────────────────────────────────────────────
const browser = await chromium.launch({
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
});
const page = await browser.newPage({ viewport: { width: VP_WIDTH, height: VP_HEIGHT } });

await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(1500);

const slideCount = await page.evaluate(() => document.querySelectorAll('.slide').length);
console.log(`  Slides encontradas: ${slideCount}`);

if (slideCount === 0) {
  console.error('  ERROR: no se encontraron elementos .slide.');
  console.error('  Asegurate de que el HTML use <div class="slide"> o <section class="slide">.');
  await browser.close();
  server.close();
  process.exit(1);
}

mkdirSync(SCREENSHOT_DIR, { recursive: true });
const screenshotPaths = [];

for (let i = 0; i < slideCount; i++) {
  await page.evaluate((index) => {
    const slides = document.querySelectorAll('.slide');
    slides.forEach((slide, idx) => {
      if (idx === index) {
        slide.style.display = '';
        slide.style.opacity = '1';
        slide.style.visibility = 'visible';
        slide.style.position = 'relative';
        slide.style.transform = 'none';
        slide.classList.add('active');
      } else {
        slide.style.display = 'none';
        slide.classList.remove('active');
      }
    });
    if (window.presentation && typeof window.presentation.goToSlide === 'function') {
      window.presentation.goToSlide(index);
    }
    slides[index]?.scrollIntoView({ behavior: 'instant' });
  }, i);

  await page.waitForTimeout(300);
  await page.waitForTimeout(200);

  await page.evaluate((index) => {
    const currentSlide = document.querySelectorAll('.slide')[index];
    if (currentSlide) {
      currentSlide.querySelectorAll('.reveal').forEach((el) => {
        el.style.opacity = '1';
        el.style.transform = 'none';
        el.style.visibility = 'visible';
      });
    }
  }, i);

  await page.waitForTimeout(100);

  const screenshotPath = join(SCREENSHOT_DIR, `slide-${String(i + 1).padStart(3, '0')}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: false });
  screenshotPaths.push(screenshotPath);
  console.log(`  Capturada slide ${i + 1}/${slideCount}`);
}

await browser.close();
server.close();

// ─── Ensamblar PDF ────────────────────────────────────────────────────────────────
console.log('  Ensamblando PDF...');

const browser2 = await chromium.launch({
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
});
const pdfPage = await browser2.newPage();

const imagesHtml = screenshotPaths.map((p) => {
  const imgData = readFileSync(p).toString('base64');
  return `<div class="page"><img src="data:image/png;base64,${imgData}" /></div>`;
}).join('\n');

const pdfHtml = `<!DOCTYPE html>
<html><head><style>
  * { margin: 0; padding: 0; }
  @page { size: ${VP_WIDTH}px ${VP_HEIGHT}px; margin: 0; }
  .page { width: ${VP_WIDTH}px; height: ${VP_HEIGHT}px; page-break-after: always; overflow: hidden; }
  .page:last-child { page-break-after: auto; }
  img { width: ${VP_WIDTH}px; height: ${VP_HEIGHT}px; display: block; object-fit: contain; }
</style></head>
<body>${imagesHtml}</body></html>`;

await pdfPage.setContent(pdfHtml, { waitUntil: 'load' });
await pdfPage.pdf({
  path: OUTPUT_PDF,
  width: `${VP_WIDTH}px`,
  height: `${VP_HEIGHT}px`,
  printBackground: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
});

await browser2.close();
screenshotPaths.forEach((p) => unlinkSync(p));

console.log(`  OK -> ${OUTPUT_PDF}`);
