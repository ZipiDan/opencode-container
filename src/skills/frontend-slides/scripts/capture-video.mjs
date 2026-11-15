#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

// capture-video.mjs — Exporta un deck Frontend Slides (HTML) a un MP4 determinista.
//
// Uso (scripts/export-video.sh lo envuelve; --help imprime la tabla completa):
//   node capture-video.mjs <input.html> <output.mp4> [opciones]
//
// Cómo funciona:
//   1. Sirve el HTML por loopback (fuentes y assets relativos cargan como en el navegador) y abre
//      el deck en Chromium headless con el viewport del stage (1920x1080).
//   2. Inyecta un reloj virtual: cada transición CSS nueva se pausa y se conduce con T = n / fps.
//      Un screenshot tarda ~500 ms, así que grabar en tiempo real desfasaría todo.
//   3. Avanza de slide con un adapter (controlador del deck si lo expone, si no DOM) y después
//      verifica el índice real: si no cambió aborta en vez de grabar N copias del slide 0.
//   4. Cada frame es un PNG (JPEG con --quality fast) en memoria que va a ffmpeg por stdin: cero
//      frames en disco. --keep-frames y --smoke son excepciones de debug y lo avisan.
//
// El timeline se deriva del número de slides, sin constantes de duración cableadas:
//   d_i   = dwell del slide i (0..N-2): --dwell por defecto, --hold para pisar uno
//   t_1   = d_0                     t_k = t_(k-1) + fade + d_(k-1)
//   total = Σ d_i + (N-1) * fade + closing        frames = round(total * fps)
//   --duration no se imprime: deriva los dwells (y con --hold los reescala en proporción).
//
// Límites conocidos:
//   - El reloj virtual sólo cubre CSS y WAAPI: requestAnimationFrame, canvas y setTimeout corren
//     a velocidad de la pared y no son deterministas.
//   - El fallback DOM cambia el slide activo, pero no actualiza pager/progreso del deck.
//   - --hide-chrome no alcanza los overlays de <deck-stage>: viven en su shadow DOM.

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { launchOptions, loadPlaywright, startStaticServer } from './lib/browser.mjs';

const DEFAULT_FPS = 30;
const DWELL_SEC = 1.2; // slide quieto antes del próximo crossfade
const FADE_SEC = 0.35; // crossfade de opacidad entre slides (fijo: no hay --fade en v1)
const CLOSING_SEC = 2.1; // cola sobre el último slide
const MIN_DWELL_SEC = 0.4; // piso de dwell: por debajo de esto el slide no llega a leerse
const MAX_FPS = 120;
const QUALITIES = ['fast', 'max'];
const VIEWPORT = { width: 1920, height: 1080 };
const PROGRESS_EVERY = 150; // frames entre líneas de progreso
const STDERR_KEEP = 4000; // último tramo del stderr de ffmpeg

// Preset y CRF de cada calidad; --quality fast cambia además el formato del frame (JPEG q100).
const ENCODE_PRESETS = {
  max: { preset: 'slow', crf: '18' },
  fast: { preset: 'veryfast', crf: '20' },
};

// Args propios del video, que se suman a los de lib/browser.mjs. No se repiten `--no-sandbox` ni
// el binario de Chromium: ambos salen de launchOptions().
const VIDEO_ARGS = ['--hide-scrollbars', '--force-color-profile=srgb', '--disable-lcd-text'];

const CHROME_SELECTORS = ['.deck-nav', '.deck-progress', '.deck-controls'];

const USAGE = 'uso: node capture-video.mjs <input.html> <output.mp4> [opciones] · --help para la tabla';

const HELP = `uso: bash scripts/export-video.sh <deck.html> [salida.mp4] [opciones]
     node capture-video.mjs <deck.html> <salida.mp4> [opciones]

Exporta un deck de Frontend Slides a MP4 determinista (reloj virtual, no tiempo real).

Tiempo (el total se deriva del número de slides; el crossfade es fijo en ${FADE_SEC}s):
  --fps <n>            frames por segundo, entero 1..${MAX_FPS} (default ${DEFAULT_FPS})
  --dwell <s>          segundos por slide antes del crossfade (default ${DWELL_SEC})
  --closing <s>        cola sobre el último slide (default ${CLOSING_SEC})
  --duration <s>       duración total objetivo; deriva el dwell (incompatible con --dwell)
  --hold <i>=<s>       fija el dwell del slide i (0-based, 0..N-2: el último slide lo gobierna
                       --closing); repetible, y con --duration se reescala en proporción

Encode:
  --quality fast|max   max = PNG + x264 preset slow crf 18 (default)
                       fast = JPEG q100 + x264 preset veryfast crf 20
                       ambas rutas: -pix_fmt yuv420p -color_range tv -colorspace bt709

Deck:
  --hide-chrome            oculta .deck-nav / .deck-progress / .deck-controls
  --allow-fallback-fonts   acepta fuentes web faltantes, con aviso (por defecto aborta)

Debug (no producen video):
  --dry-run                imprime el timeline y sale; no captura ni encodea
  --smoke                  escribe a disco sólo frames de control (0, último y ±1 por transición)
  --keep-frames <dir>      escribe todos los frames a disco; sin encode

  --help                   esta tabla

Con el wrapper, la salida por defecto es <dir del deck>/<nombre>.mp4.
Exit: 0 ok · 2 argumentos inválidos · 1 deck o encode fallido.`;


// Mismo texto de ayuda que el export a PDF, más la mención al <deck-stage> de bold-template-pack.
const NO_SLIDES_MESSAGE = [
  'no se encontraron elementos .slide.',
  '  Asegurate de que el HTML use <div class="slide"> o <section class="slide">.',
  '  También se aceptan los hijos directos de <deck-stage>.',
].join('\n');

// Error previsto (deck inválido, ffmpeg caído, fuente rota): se reporta sin stack, que sólo
// agregaría ruido. Los bugs inesperados sí muestran stack (ver printError).
class CaptureError extends Error {}

// Argumento inválido: exit 2, para distinguirlo de un deck que no se puede capturar (exit 1).
class UsageError extends CaptureError {}

// ─── CLI ─────────────────────────────────────────────────────────────────────────
// El parseo es la única fuente de validación: el wrapper .sh sólo resuelve paths y dependencias.
function parseArgs(argv) {
  const positional = [];
  const holds = new Map();
  const options = {
    fps: DEFAULT_FPS,
    dwell: DWELL_SEC,
    closing: CLOSING_SEC,
    duration: null,
    holds,
    quality: 'max', // sin prompt nunca: el wrapper corre también bajo nohup o un pipe
    hide_chrome: false,
    allow_fallback_fonts: false,
    dry_run: false,
    smoke: false,
    keep_frames: null,
  };
  let is_dwell_explicit = false;

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const nextValue = () => argv[++index];

    switch (arg) {
      case '--fps': {
        const value = parseNumberArg(arg, nextValue());
        if (!Number.isInteger(value) || value < 1 || value > MAX_FPS) {
          throw new UsageError(`--fps fuera de rango: ${value} (válido 1..${MAX_FPS}, entero)`);
        }
        options.fps = value;
        break;
      }
      case '--dwell':
        options.dwell = parsePositiveArg(arg, nextValue());
        is_dwell_explicit = true;
        break;
      case '--closing':
        options.closing = parseNonNegativeArg(arg, nextValue());
        break;
      case '--duration':
        options.duration = parsePositiveArg(arg, nextValue());
        break;
      case '--hold': {
        const { index: hold_index, seconds } = parseHoldArg(nextValue());
        holds.set(hold_index, seconds);
        break;
      }
      case '--quality': {
        const value = nextValue();
        if (!QUALITIES.includes(value)) {
          throw new UsageError(`--quality debe ser ${QUALITIES.join('|')} (recibí: ${value ?? 'nada'})`);
        }
        options.quality = value;
        break;
      }
      case '--keep-frames':
        options.keep_frames = nextValue() ?? null;
        if (options.keep_frames === null) throw new UsageError('--keep-frames necesita un directorio');
        break;
      case '--dry-run':
        options.dry_run = true;
        break;
      case '--smoke':
        options.smoke = true;
        break;
      case '--hide-chrome':
        options.hide_chrome = true;
        break;
      case '--allow-fallback-fonts':
        options.allow_fallback_fonts = true;
        break;
      default:
        // Un `--flag` desconocido es error; el resto son los dos positional (entrada y salida).
        if (arg.startsWith('--')) throw new UsageError(`opción desconocida: ${arg}\n${USAGE}`);
        positional.push(arg);
    }
  }

  if (options.duration !== null && is_dwell_explicit) {
    throw new UsageError('--duration y --dwell son incompatibles: --duration deriva el dwell');
  }
  if (positional.length !== 2) throw new UsageError(USAGE);

  const input_path = resolve(positional[0]);
  const output_path = resolve(positional[1]);
  if (!existsSync(input_path)) throw new UsageError(`no existe el deck de entrada: ${input_path}`);
  if (!existsSync(dirname(output_path))) {
    throw new UsageError(`no existe el directorio de salida: ${dirname(output_path)}`);
  }

  return { input_path, output_path, ...options };
}

function parseNumberArg(flag, raw) {
  const value = Number(raw);
  if (raw === undefined || !Number.isFinite(value)) {
    throw new UsageError(`${flag} necesita un número (recibí: ${raw ?? 'nada'})`);
  }
  return value;
}

function parsePositiveArg(flag, raw) {
  const value = parseNumberArg(flag, raw);
  if (value <= 0) throw new UsageError(`${flag} debe ser > 0 (recibí: ${value})`);
  return value;
}

function parseNonNegativeArg(flag, raw) {
  const value = parseNumberArg(flag, raw);
  if (value < 0) throw new UsageError(`${flag} no puede ser negativo (recibí: ${value})`);
  return value;
}

// --hold usa índice 0-based; el rango contra N se valida después de descubrir los slides.
const HOLD_FORMAT = /^(-?\d+)=(-?\d+(?:\.\d+)?)$/;

function parseHoldArg(raw) {
  const text = String(raw ?? '').trim();
  const match = HOLD_FORMAT.exec(text);
  if (!match) throw new UsageError(`--hold necesita <i>=<s>, con i 0-based (recibí: ${raw ?? 'nada'})`);

  const hold_index = Number(match[1]);
  const seconds = Number(match[2]);
  if (hold_index < 0) throw new UsageError(`--hold ${text}: el índice no puede ser negativo`);
  if (seconds < 0) throw new UsageError(`--hold ${text}: los segundos no pueden ser negativos`);
  return { index: hold_index, seconds };
}

// ─── Timeline ────────────────────────────────────────────────────────────────────
// d_i es el dwell del slide i (0..N-2). La transición k ocurre cuando corrieron los dwells
// anteriores con un crossfade entre medio; el total suma dwells, crossfades y cierre:
//   t_1 = d_0        t_k = t_(k-1) + fade + d_(k-1)
//   total = Σ d_i + (N-1) * fade + closing        frames = round(total * fps)
function buildTimeline({ slide_count, fps, dwell, closing, holds, duration }) {
  const dwells = [];
  for (let index = 0; index < slide_count - 1; index++) dwells.push(holds.get(index) ?? dwell);

  if (duration !== null) {
    // --duration no fija un número: reparte el tiempo pedido. Lo que queda tras crossfades y
    // cierre se reparte entre los dwells en la proporción que ya tenían (ritmo relativo intacto).
    const dwells_sum_sec = sumSeconds(dwells);
    if (dwells_sum_sec <= 0) {
      throw new UsageError('--duration necesita dwells > 0 para reescalar: revisá los --hold');
    }
    const dwells_span_sec = duration - (slide_count - 1) * FADE_SEC - closing;
    const ratio = dwells_span_sec / dwells_sum_sec;
    for (let index = 0; index < dwells.length; index++) dwells[index] *= ratio;
  }

  const transitions = [];
  let cursor_sec = 0;
  for (let slide = 1; slide < slide_count; slide++) {
    cursor_sec += dwells[slide - 1];
    transitions.push({ k: slide, t: cursor_sec });
    cursor_sec += FADE_SEC;
  }

  const total_sec = sumSeconds(dwells) + (slide_count - 1) * FADE_SEC + closing;
  return { transitions, dwells, total_sec, frames: Math.round(total_sec * fps) };
}

function sumSeconds(values) {
  return values.reduce((sum, value) => sum + value, 0);
}

// Chequeos que necesitan N y por eso corren después de abrir el deck; los rangos de cada flag
// corren en parseArgs.
function validateDeckArgs({ slide_count, options }) {
  const last_hold_index = slide_count - 2;
  for (const [index, seconds] of options.holds) {
    if (index > last_hold_index) {
      throw new UsageError(
        `--hold ${index}=${seconds}: índice fuera de rango (0..${last_hold_index} para ${slide_count} slides, ` +
          '0-based; el último slide lo gobierna --closing)'
      );
    }
  }

  if (options.duration === null) return;
  if (slide_count < 2) {
    throw new UsageError(`--duration necesita al menos 2 slides y este deck tiene ${slide_count}`);
  }

  // Mínimo viable: todos los dwells en el piso, más crossfades y cierre.
  const min_sec = (slide_count - 1) * (MIN_DWELL_SEC + FADE_SEC) + options.closing;
  // Epsilon: 0.4 + 0.35 no es exacto en coma flotante y 15.6 quedaría "por debajo" de 15.6.
  if (options.duration < min_sec - 1e-9) {
    throw new UsageError(
      `--duration ${formatSeconds(options.duration)} es menor al mínimo viable: ${formatSeconds(min_sec)} s ` +
        `para ${slide_count} slides (${slide_count - 1} × (${MIN_DWELL_SEC} + ${FADE_SEC}) + ${options.closing})`
    );
  }
}

// Con --duration los dwells se reescalan: alguno puede quedar por debajo del piso y ese slide no
// se lee. Es aviso y no error porque la duración pedida es del usuario.
function warnShortDwells(dwells) {
  dwells.forEach((seconds, index) => {
    if (seconds >= MIN_DWELL_SEC) return;
    console.warn(`aviso: slide ${index} con ${seconds.toFixed(3)}s < ${MIN_DWELL_SEC}s: no se llega a leer`);
  });
}

// ─── Salida del timeline ─────────────────────────────────────────────────────────
// Segundos con hasta 3 decimales y sin ceros de cola, pero siempre con decimal:
// 1.2 → "1.2", 30 → "30.0", 2.03333 → "2.033".
function formatSeconds(value) {
  return value.toFixed(3).replace(/0+$/, '').replace(/\.$/, '.0');
}

// Con --duration cambian todos los dwells; sin --duration sólo los que fijó --hold.
function describeHolds({ dwells, holds, duration }) {
  const indices = duration === null ? [...holds.keys()].sort((a, b) => a - b) : dwells.map((_, index) => index);
  if (indices.length === 0) return null;
  return indices.map((index) => `${index}=${dwells[index].toFixed(3)}`).join(', ');
}

// Tabla estable del timeline: es lo que verifica --dry-run y lo que registra la corrida real.
// Las transiciones y los dwells no uniformes sólo se imprimen en el modo verboso (--dry-run),
// porque en una captura de 900 frames serían ruido.
function printTimeline({ slide_count, timeline, options, dwell, verbose }) {
  const rows = [
    ['slides', String(slide_count)],
    ['fade', formatSeconds(FADE_SEC)],
    ['closing', formatSeconds(options.closing)],
    ['fps', String(options.fps)],
    ['dwell', formatSeconds(dwell)],
    ['total', formatSeconds(timeline.total_sec)],
    ['frames', String(timeline.frames)],
  ];
  for (const [label, value] of rows) console.log(`${label}:`.padEnd(11) + value);

  const holds_line = describeHolds({ dwells: timeline.dwells, holds: options.holds, duration: options.duration });
  if (holds_line) console.log(`holds: ${holds_line}`);

  if (!verbose) return;
  for (const { k, t } of timeline.transitions) {
    console.log(`t=${t.toFixed(3)}s frame=${Math.round(t * options.fps)} -> slide ${k}`);
  }
}

// ─── Helpers que corren dentro de la página ──────────────────────────────────────
/* Factory de la parte que vive en Chromium. Se serializa con toString() y se evalúa allí, así
   que su cuerpo NO puede referenciar nada del scope de Node: todo entra por `config`.

   Responsabilidades: descubrir slides, inyectar el crossfade, resolver el adapter de avance y
   conducir el reloj virtual (pausar cada animación nueva y fijarle currentTime en cada tick). */
function pageHelpers() {
  return (config) => {
    const { fade_sec } = config;

    const SLIDE_MARK = 'data-deck-video-slide';
    const NON_VISUAL_TAGS = ['SCRIPT', 'STYLE', 'TEMPLATE', 'LINK', 'META'];
    // Nombres con los que un deck suele publicar su controlador cuando no lo deja en
    // `window.presentation`.
    const NEXT_GLOBAL_NAMES = ['presentation', 'deck', 'slides', 'slidedeck'];
    // Orden en que los controladores del repo publican cuál slide está activo. La primera
    // entrada no repite la última: acota el atributo a los hijos del stage, así un
    // [data-deck-active] anidado dentro de un slide no gana por aparecer antes en el documento.
    const INDEX_SELECTORS = [
      'deck-stage > [data-deck-active]',
      '.slide.active',
      '.slide.visible',
      '[data-deck-active]',
    ];

    let slides = [];
    let pending = [];
    let advance = () => {};

    // ── Descubrimiento ──
    // `.slide` es el contrato de viewport-base.css; si no hay, se aceptan los hijos directos de
    // <deck-stage> descartando lo que no se ve (script/style/template y cajas vacías).
    function discoverSlides() {
      const by_class = Array.from(document.querySelectorAll('.slide'));
      if (by_class.length) return { source: '.slide', elements: by_class };

      const stage = document.querySelector('deck-stage');
      if (!stage) return { source: '.slide', elements: [] };

      const elements = Array.from(stage.children).filter((child) => {
        if (NON_VISUAL_TAGS.includes(child.tagName)) return false;
        return child.textContent.trim() !== '' || Boolean(child.querySelector('img, video, svg, canvas, picture'));
      });
      return { source: 'deck-stage > *', elements };
    }

    // ── Crossfade ──
    // La slide que sale se desvanece y la que entra sube de golpe; el delay de `visibility` evita
    // que la saliente desaparezca antes de tiempo. Se aplica al marcador propio y no a `.slide`
    // para no depender de que el deck use esa clase. `!important` gana sobre las transiciones
    // que ya trae el deck.
    function injectCrossfade() {
      const style = document.createElement('style');
      style.id = '__deck_video_css';
      style.textContent = `
        [${SLIDE_MARK}] { transition: opacity ${fade_sec}s ease, visibility 0s linear ${fade_sec}s !important; }
        [${SLIDE_MARK}].active, [${SLIDE_MARK}].visible,
        [${SLIDE_MARK}][data-deck-active] { transition: opacity ${fade_sec}s ease, visibility 0s linear 0s !important; }
        [${SLIDE_MARK}]:not(.active):not([data-deck-active]) { z-index: 2; }
      `;
      document.head.appendChild(style);
    }

    // ── Adapter de avance ──
    // El fallback DOM hace lo que los controladores no exportados (devday): mueve las clases y el
    // atributo del slide activo. Se tocan ambos estados para no depender de cuál use el deck.
    function advanceDom(target) {
      slides.forEach((slide, index) => {
        const is_target = index === target;
        slide.classList.toggle('active', is_target);
        slide.classList.toggle('visible', is_target);
        if (is_target) slide.setAttribute('data-deck-active', '');
        else slide.removeAttribute('data-deck-active');
      });
    }

    function findNextController() {
      for (const name of NEXT_GLOBAL_NAMES) {
        const candidate = window[name];
        if (candidate && typeof candidate.next === 'function') return candidate;
      }
      return typeof window.next === 'function' ? window : null;
    }

    // Se resuelve una sola vez: re-descubrir el controlador en cada frame costaría queries por
    // frame sin cambiar el resultado.
    function resolveAdapter() {
      const stage = document.querySelector('deck-stage');
      if (stage && typeof stage.goTo === 'function') {
        return { mode: 'deck-stage', advance: (k) => stage.goTo(k) };
      }

      const presentation = window.presentation;
      if (presentation && typeof presentation.goToSlide === 'function') {
        return { mode: 'presentation', advance: (k) => presentation.goToSlide(k) };
      }
      if (presentation && typeof presentation.showSlide === 'function') {
        return { mode: 'presentation', advance: (k) => presentation.showSlide(k) };
      }

      // Avanzar de a uno alcanza: el schedule avanza 1, 2, 3… en orden.
      const controller = findNextController();
      if (controller) return { mode: 'next', advance: () => controller.next() };

      return { mode: 'dom', advance: advanceDom };
    }

    function readIndex() {
      for (const selector of INDEX_SELECTORS) {
        const active = document.querySelector(selector);
        const index = active ? slides.indexOf(active) : -1;
        if (index >= 0) return index;
      }
      return null;
    }

    // ── Reloj virtual ──
    const tracked = new Map(); // Animation -> segundo virtual en que nació

    // `offsetHeight` fuerza el cálculo de estilo: sin eso la transición todavía no existe como
    // objeto y no se puede pausar ni conducir.
    function forceReflow() {
      void document.body.offsetHeight;
    }

    function snapshotClock(virtual_sec) {
      for (const animation of document.getAnimations()) {
        if (tracked.has(animation)) continue;
        try {
          animation.pause();
        } catch {
          // Animación ya finalizada o no pausable: se ignora, igual que en el motor anterior.
        }
        tracked.set(animation, virtual_sec);
      }
    }

    function driveAnimations(virtual_sec) {
      for (const [animation, started_at] of tracked) {
        const elapsed_ms = (virtual_sec - started_at) * 1000;
        if (elapsed_ms < 0) continue;
        try {
          animation.currentTime = elapsed_ms;
        } catch {
          // La animación salió de la lista: nada que conducir.
        }
      }
    }

    // Re-dispara los `.reveal` del slide 0 para que la animación de portada ocurra dentro del
    // video y no antes de empezar a grabar. El `off` congela el estado 0 sin transición.
    function resetSlide0() {
      const off = document.createElement('style');
      off.textContent = '* { transition: none !important; animation: none !important; }';
      document.head.appendChild(off);

      const first = slides[0];
      first.classList.remove('visible');
      forceReflow(); // aplica el estado 0 sin transición
      off.remove();
      forceReflow(); // vuelve a existir transición
      first.classList.add('visible'); // re-dispara los .reveal
      forceReflow(); // crea los objetos de transición
      snapshotClock(0);
    }

    return {
      init() {
        const { source, elements } = discoverSlides();
        slides = elements;
        if (!slides.length) return { slide_count: 0, mode: null, source };

        slides.forEach((slide) => slide.setAttribute(SLIDE_MARK, ''));
        injectCrossfade();
        const resolved = resolveAdapter();
        advance = resolved.advance;
        return { slide_count: slides.length, mode: resolved.mode, source };
      },

      start(schedule) {
        pending = schedule.slice();
        resetSlide0();
      },

      // Devuelve los slides a los que se avanzó en este tick (normalmente 0 o 1) para que el
      // llamador verifique el índice real de cada uno.
      tick(virtual_sec) {
        const advanced_steps = [];
        while (pending.length && pending[0].t <= virtual_sec + 1e-9) {
          const step = pending.shift();
          advance(step.k);
          forceReflow(); // materializa las transiciones nuevas antes de fotografiarlas
          snapshotClock(virtual_sec);
          advanced_steps.push(step.k);
        }
        driveAnimations(virtual_sec);
        return advanced_steps;
      },

      readIndex,
    };
  };
}

// La factory se evalúa en Chromium y el instalador recibe la config ya dentro de la página:
// page.evaluate(string) no admite argumentos.
async function installDeckHelpers(page) {
  await page.evaluate(`window.__createDeckVideo = (${pageHelpers.toString()})();`);
  return page.evaluate((config) => {
    window.__deckVideo = window.__createDeckVideo(config);
    return window.__deckVideo.init();
  }, { fade_sec: FADE_SEC });
}

// ─── Chequeos de la página ───────────────────────────────────────────────────────
// Las fuentes web se bajan por red: si una cara queda en `error` el video sale con el fallback
// del sistema, que en un deck de diseño se nota. Por defecto se aborta.
async function checkFonts(page, { allow_fallback_fonts: allow_fallback }) {
  const broken = await page.evaluate(() => {
    return Array.from(document.fonts)
      .filter((face) => face.status === 'error')
      .map((face) => `${face.family} ${face.weight}`.trim());
  });

  if (broken.length === 0) {
    console.log('fonts: ok');
    return;
  }

  const detail = `${broken.length} cara(s) con error: ${broken.join(', ')}`;
  if (!allow_fallback) {
    throw new CaptureError(
      `fonts: fallback no permitido (${detail}). El deck necesita red para las fuentes web; ` +
        'si querés el fallback del sistema agregá --allow-fallback-fonts.'
    );
  }
  console.log(`fonts: fallback (${detail})`);
}

// El chrome del deck (nav, progreso, controles) se ve por defecto: el video de referencia lo
// tiene visible. --hide-chrome lo oculta.
async function hideChrome(page) {
  const result = await page.evaluate((selectors) => {
    const missing = selectors.filter((selector) => !document.querySelector(selector));
    const style = document.createElement('style');
    style.textContent = `${selectors.join(', ')} { display: none !important; }`;
    document.head.appendChild(style);
    return { hidden: selectors.length - missing.length, missing };
  }, CHROME_SELECTORS);

  const absent = result.missing.length ? ` · sin elementos: ${result.missing.join(', ')}` : '';
  console.log(`chrome: oculto (${result.hidden}/${CHROME_SELECTORS.length})${absent}`);
}

// ─── Encode ──────────────────────────────────────────────────────────────────────
// PNG/JPEG por stdin y encode en una sola pasada. `-pix_fmt yuv420p -color_range tv` explícito:
// con entrada MJPEG, x264 hereda yuvj420p (rango completo) y el video queda lavado. Por eso
// --quality fast (JPEG) usa los mismos flags que max.
// `-colorspace bt709` es lo que hace que x264 escriba la VUI: sin él `-color_range tv` se acepta
// pero queda sin declarar y ffprobe informa `color_range=unknown` (yuv420p + tv es además el
// matriz/rango correcto para 1080p, y es lo que declara el MP4 de referencia).
function buildFfmpegArgs({ output_path, fps, quality }) {
  const { preset, crf } = ENCODE_PRESETS[quality];
  return [
    '-hide_banner',
    '-loglevel', 'error',
    '-f', 'image2pipe',
    '-framerate', String(fps),
    '-i', '-',
    '-c:v', 'libx264',
    '-preset', preset,
    '-crf', crf,
    '-pix_fmt', 'yuv420p',
    '-colorspace', 'bt709',
    '-color_range', 'tv',
    '-movflags', '+faststart',
    '-y',
    output_path,
  ];
}

// Espera el `drain` de un stream con backpressure. No falla nunca: si el pipe se cortó, el
// próximo write lo detecta.
function waitForDrain(stream) {
  return new Promise((done) => stream.once('drain', done));
}

// Proceso de ffmpeg con su estado: stdin para los frames y el último tramo del stderr para
// poder explicar un fallo. Matar el proceso es responsabilidad de quien lo creó.
class FrameEncoder {
  constructor({ output_path, fps, quality }) {
    this._stderr = '';
    this._failure = null;
    this._process = spawn('ffmpeg', buildFfmpegArgs({ output_path, fps, quality }), {
      stdio: ['pipe', 'inherit', 'pipe'],
    });

    this._closed = new Promise((done) => {
      this._process.once('close', (code, signal) => {
        this._exit = { code, signal };
        done(this._exit);
      });
    });

    this._process.on('error', (error) => {
      this._failure =
        error.code === 'ENOENT'
          ? new CaptureError('falta ffmpeg: no se encontró el binario en el PATH')
          : error;
      this._process.stdin.destroy(); // despierta cualquier write esperando `drain`
    });

    // EPIPE / write-after-end cuando ffmpeg muere a mitad del encode.
    this._process.stdin.on('error', (error) => {
      this._failure ??= error;
    });

    this._process.stderr.on('data', (chunk) => {
      this._stderr = (this._stderr + chunk).slice(-STDERR_KEEP);
    });
  }

  // ffmpeg se fue antes de terminar: el stderr es la única pista de por qué.
  _earlyExit() {
    const { code, signal } = this._exit;
    const detail = this._stderr.trim() || 'sin mensaje';
    return new CaptureError(`ffmpeg terminó antes de tiempo (exit ${code}, señal ${signal ?? 'ninguna'})\n${detail}`);
  }

  async write(frame) {
    if (this._failure) throw this._failure;
    if (this._exit) throw this._earlyExit(); // murió y el pipe ya no tiene a quién escribirle

    if (this._process.stdin.write(frame)) return;

    // Backpressure: el pipe está lleno. Se reanuda con `drain` o se corta si ffmpeg murió.
    await Promise.race([waitForDrain(this._process.stdin), this._closed]);
    if (this._failure) throw this._failure;
  }

  // Cierra stdin y espera el exit code: un encode roto se detecta acá, no mirando el archivo.
  async finish() {
    this._process.stdin.end();
    const { code, signal } = await this._closed;
    if (this._failure) throw this._failure;
    if (code !== 0) {
      throw new CaptureError(`ffmpeg falló (exit ${code}, señal ${signal ?? 'ninguna'})\n${this._stderr.trim()}`);
    }
  }

  // Corte en seco para cuando la captura aborta a mitad de camino.
  abort() {
    this._process.stdin.destroy();
    if (this._process.exitCode === null && this._process.signalCode === null) {
      this._process.kill('SIGKILL');
    }
  }
}

// ─── Destinos de frames ─────────────────────────────────────────────────────────
// --quality decide el formato del frame: PNG (~519 ms/frame) o JPEG q100 (~92 ms/frame), medido
// en la Fase 1. El pipe no cuesta nada: el cuello es el encoder PNG de Chromium.
function screenshotOptions(quality) {
  return quality === 'fast' ? { type: 'jpeg', quality: 100 } : { type: 'png' };
}

// Frames de control de --smoke: el 0, el último y el entorno (±1) de cada transición.
function smokeIndices(timeline, fps) {
  const last_index = timeline.frames - 1;
  const control = new Set([0, last_index]);
  for (const { t } of timeline.transitions) {
    const center = Math.round(t * fps);
    for (const index of [center - 1, center, center + 1]) {
      if (index >= 0 && index <= last_index) control.add(index);
    }
  }
  return control;
}

// Camino normal: todos los frames al stdin de ffmpeg, cero bytes en disco.
class StreamSink {
  constructor(encoder) {
    this._encoder = encoder;
  }

  wants() {
    return true;
  }

  async write(_index, frame) {
    await this._encoder.write(frame);
  }

  async finish() {
    await this._encoder.finish();
  }
}

// --keep-frames y --smoke: escriben a disco y rompen el streaming a propósito (debug del timeline).
class DiskSink {
  constructor({ dir_path, quality, control }) {
    this._dir = dir_path;
    this._control = control; // Set de índices, o null para escribir todos
    this._extension = quality === 'fast' ? 'jpg' : 'png';
    this.written = 0;
    mkdirSync(dir_path, { recursive: true });
  }

  wants(index) {
    return this._control === null || this._control.has(index);
  }

  async write(index, frame) {
    const name = `frame-${String(index).padStart(5, '0')}.${this._extension}`;
    await writeFile(join(this._dir, name), frame);
    this.written++;
  }

  // Los frames ya están en disco: no hay nada que cerrar.
  finish() {}
}

// Devuelve { sink, dir_path }; dir_path queda en null en el camino de streaming.
function createFrameSink({ args, session, timeline }) {
  if (!args.smoke && args.keep_frames === null) {
    session.encoder = new FrameEncoder({ output_path: args.output_path, fps: args.fps, quality: args.quality });
    return { sink: new StreamSink(session.encoder), dir_path: null };
  }

  const control = args.smoke ? smokeIndices(timeline, args.fps) : null;
  const dir_path = args.keep_frames ?? join(tmpdir(), `deck-video-smoke-${process.pid}`);
  const count = control ? control.size : timeline.frames;
  const what = control ? 'frames de control' : 'frames';
  console.warn(`aviso: ${args.smoke ? '--smoke' : '--keep-frames'} rompe el streaming: ${count} ${what} en disco`);
  return { sink: new DiskSink({ dir_path, quality: args.quality, control }), dir_path };
}

// ─── Captura ─────────────────────────────────────────────────────────────────────
// Verificación de avance: si el índice no cambió, el deck no está navegando y el video saldría
// con N copias del slide 0. Se chequea en cada transición, no una vez al principio.
async function assertAdvance(page, expected, mode) {
  const actual = await page.evaluate(() => window.__deckVideo.readIndex());

  if (actual === null) {
    throw new CaptureError(
      `el deck no expone estado de navegación (adapter: ${mode}): no pude leer qué slide quedó ` +
        `activo después de avanzar a ${expected}. Necesita .slide.active/.visible, ` +
        '[data-deck-active] o un controlador goTo/showSlide/next que funcione.'
    );
  }

  if (actual !== expected) {
    throw new CaptureError(`el índice no cambió: esperaba ${expected}, leí ${actual} (adapter: ${mode})`);
  }
}

function reportProgress(index, timeline, fps, started_at) {
  const elapsed_sec = (Date.now() - started_at) / 1000;
  const rate = (index / Math.max(elapsed_sec, 0.001)).toFixed(1);
  console.log(`  frame ${index}/${timeline.frames} (t=${(index / fps).toFixed(2)}s) · ${rate} f/s`);
}

// El reloj virtual avanza en todos los modos: --smoke escribe sólo frames de control, pero el
// tick corre igual, así cada frame de control es el mismo que saldría en el video.
async function captureFrames({ page, sink, timeline, fps, mode, quality }) {
  const started_at = Date.now();
  const shot_options = screenshotOptions(quality);

  for (let index = 0; index < timeline.frames; index++) {
    const virtual_sec = index / fps;
    const advanced_steps = await page.evaluate((t) => window.__deckVideo.tick(t), virtual_sec);
    for (const step of advanced_steps) await assertAdvance(page, step, mode);

    // Buffer en memoria: al streaming va por stdin; a disco sólo en los modos de debug.
    if (sink.wants(index)) await sink.write(index, await page.screenshot(shot_options));

    if (index > 0 && index % PROGRESS_EVERY === 0) reportProgress(index, timeline, fps, started_at);
  }

  return Date.now() - started_at;
}

// ─── Orquestación ────────────────────────────────────────────────────────────────
function describeEncode({ output_path, quality }) {
  const { preset, crf } = ENCODE_PRESETS[quality];
  return `${output_path} · h264 yuv420p · crf ${crf} · preset ${preset}`;
}

async function openSession(args, session) {
  const { chromium } = loadPlaywright();

  // Servir el deck (y no abrirlo por file://) es lo que hace que fuentes y assets relativos
  // carguen igual que en el navegador.
  session.server = await startStaticServer({
    serve_dir: dirname(args.input_path),
    html_file: basename(args.input_path),
  });

  const launch_options = launchOptions();
  session.browser = await chromium.launch({
    ...launch_options,
    args: [...launch_options.args, ...VIDEO_ARGS],
    headless: true,
  });

  // Contexto propio en vez de lib/browser.mjs:openDeck: el video necesita deviceScaleFactor 1,
  // `reducedMotion: no-preference` (el deck apaga animaciones si el SO pide reduce) y locale fijo.
  const context = await session.browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: 1,
    reducedMotion: 'no-preference',
    locale: 'es-ES',
  });
  const page = await context.newPage();
  await page.goto(session.server.url, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);

  const deck = await installDeckHelpers(page);
  if (deck.slide_count === 0) throw new CaptureError(NO_SLIDES_MESSAGE);

  return { page, deck };
}

async function runExport(args) {
  // La sesión se crea acá y no dentro de openSession: si falla a mitad de camino (deck sin
  // slides, launch roto), el finally igual cierra el navegador y el servidor.
  const session = { server: null, browser: null, encoder: null };

  try {
    const { page, deck } = await openSession(args, session);
    validateDeckArgs({ slide_count: deck.slide_count, options: args });

    const timeline = buildTimeline({
      slide_count: deck.slide_count,
      fps: args.fps,
      dwell: args.dwell,
      closing: args.closing,
      holds: args.holds,
      duration: args.duration,
    });
    // Dwell uniforme del timeline: con --duration sale de la fórmula y es lo que se informa.
    const dwell =
      args.duration === null ? args.dwell : (args.duration - args.closing) / (deck.slide_count - 1) - FADE_SEC;

    // El aviso de dwell corto se emite en los dos caminos: --dry-run es donde se ve el riesgo.
    if (args.duration !== null) warnShortDwells(timeline.dwells);

    // --dry-run no escribe archivos ni lanza ffmpeg: sólo abre el deck para contar slides.
    if (args.dry_run) {
      printTimeline({ slide_count: deck.slide_count, timeline, options: args, dwell, verbose: true });
      return;
    }

    console.log(`adapter: ${deck.mode}`);
    console.log(`selector: ${deck.source}`);

    await checkFonts(page, args);
    if (args.hide_chrome) await hideChrome(page);

    printTimeline({ slide_count: deck.slide_count, timeline, options: args, dwell, verbose: false });
    console.log(`quality: ${args.quality}`);
    console.log(`encode: ${describeEncode(args)}`);

    await page.evaluate((schedule) => window.__deckVideo.start(schedule), timeline.transitions);

    const { sink, dir_path } = createFrameSink({ args, session, timeline });
    const capture_ms = await captureFrames({
      page,
      sink,
      timeline,
      fps: args.fps,
      mode: deck.mode,
      quality: args.quality,
    });

    await sink.finish();
    session.encoder = null; // cerrado bien: el cleanup no debe matarlo ni borrar el MP4

    console.log(`captura: ${timeline.frames} frames en ${(capture_ms / 1000).toFixed(1)}s`);
    if (args.smoke) console.log(`smoke: ${sink.written} frames en ${dir_path}`);
    else if (dir_path !== null) console.log(`frames: ${sink.written} en ${dir_path}`);
    else console.log(`OK -> ${args.output_path}`);
  } finally {
    await releaseSession(session, args.output_path);
  }
}

// Suelta lo que quedó abierto. Si la captura no terminó, mata ffmpeg y descarta el MP4 a medias:
// un archivo truncado que parece válido es peor que no tener archivo.
async function releaseSession(session, output_path) {
  if (session.encoder) {
    session.encoder.abort();
    rmSync(output_path, { force: true });
    console.error(`encode abortado: se descartó ${output_path}`);
  }
  if (session.browser) await session.browser.close();
  if (session.server) session.server.close();
}

function printError(error) {
  if (error instanceof CaptureError || process.env.CAPTURE_VIDEO_DEBUG !== '1') {
    console.error(`ERROR: ${error.message}`);
    return;
  }
  console.error(error); // bug inesperado: el stack es la única pista útil
}

async function main() {
  if (process.argv.includes('--help')) {
    console.log(HELP);
    return;
  }

  const args = parseArgs(process.argv.slice(2));
  await runExport(args);
}

main().catch((error) => {
  printError(error);
  process.exitCode = error instanceof UsageError ? 2 : 1;
});
