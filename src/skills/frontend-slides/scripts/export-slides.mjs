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
// La resolución de playwright/Chromium, el servidor estático y la apertura del deck viven en
// lib/browser.mjs. Acá queda solo la lógica de slides y el ensamblado del PDF.

import { mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { launchOptions, loadPlaywright, openDeck, startStaticServer } from './lib/browser.mjs';

const { chromium } = loadPlaywright();

const SERVE_DIR = process.argv[2];
const HTML_FILE = process.argv[3];
const OUTPUT_PDF = process.argv[4];
const SCREENSHOT_DIR = process.argv[5];
const VP_WIDTH = parseInt(process.argv[6], 10) || 1920;
const VP_HEIGHT = parseInt(process.argv[7], 10) || 1080;

// ─── Servidor estático y navegador ───────────────────────────────────────────────
const server = await startStaticServer({ serve_dir: SERVE_DIR, html_file: HTML_FILE });
console.log(`  Servidor local (loopback) en puerto ${server.port}`);

// ─── Screenshot por slide ─────────────────────────────────────────────────────────
const browser = await chromium.launch(launchOptions());
const page = await openDeck({ browser, url: server.url, width: VP_WIDTH, height: VP_HEIGHT });
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
        slide.classList.add('active', 'visible');
      } else {
        slide.style.display = 'none';
        slide.classList.remove('active', 'visible');
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

  // Las entradas de los decks usan transiciones con `transition-delay: var(--d)` (o keyframes):
  // si se fotografía antes de que terminen, la página sale con el contenido todavía invisible.
  // Terminarlas es instantáneo y deja cada elemento en su estado final, que es lo que un PDF
  // estático tiene que mostrar. Las animaciones infinitas (cursores, pulsos) no se pueden
  // "terminar" y se dejan como están.
  await page.evaluate(() => {
    for (const anim of document.getAnimations()) {
      if (anim.effect?.getTiming?.().iterations === Infinity) continue;
      try {
        anim.finish();
      } catch {
        /* la transición ya no existe: no hay nada que terminar */
      }
    }
  });

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

const browser2 = await chromium.launch(launchOptions());
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
