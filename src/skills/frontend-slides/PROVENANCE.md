<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# PROVENANCE — frontend-slides

## Origen

- **Upstream**: https://github.com/zarazhangrui/frontend-slides
- **Licencia**: MIT (Copyright © 2025 Zara Zhang). Las copias literales
  conservan MIT y no llevan header propio (anotadas en `REUSE.toml`); las
  reescrituras de Calisto se licencian MPL-2.0 conservando el aviso MIT. Ver
  `THIRD-PARTY.md` en la raíz.
- **Snapshot vendorizado**: commit `9906a34` (main, 2026-06-23).
- **Tipo**: skill (no agente). Vive en `src/skills/frontend-slides/` (stage global de skills).

## Archivos vendorizados (verbatim, sin cambios)

- `STYLE_PRESETS.md`
- `viewport-base.css`
- `html-template.md`
- `animation-patterns.md`
- `bold-template-pack/**` (34 templates, `selection-index.json`, `deck-stage.js`)

## Reescrituras Claude Code → opencode

| Upstream | Adaptación |
|---|---|
| Instalación como plugin de Claude Code (`.claude-plugin/`, `/frontend-slides:frontend-slides`) | Se elimina; la skill se descubre por su `description` vía el tool `skill` de opencode |
| Fase 6A "Deploy to URL (Vercel)" + `scripts/deploy.sh` | **Excluida** por decisión de proyecto (publicación en tercero + login). Ver `upgrade-frontend-slides.md` |
| `scripts/export-pdf.sh` instala playwright en `mktemp` en cada corrida | Reescrito: usa playwright ya provisto (imagen del contenedor o `.deps/` en host); sin reinstalar. Se separó el Node embebido a `scripts/export-slides.mjs` |
| `chromium.launch()` | `chromium.launch(LAUNCH_OPTIONS)`: `--no-sandbox` / `--disable-dev-shm-usage` (contenedores/root) y `executablePath` tomado de `PLAYWRIGHT_CHROMIUM_EXECUTABLE` (la imagen usa `/usr/bin/chromium`; en host, sin la variable, queda el navegador de playwright) |
| `pip install python-pptx` ad-hoc; `python scripts/extract-pptx.py` | Wrapper `scripts/pptx-extract.sh` que resuelve el intérprete con `python-pptx`; error accionable si falta |
| `open`/`xdg-open` automático del PDF | Se quita la apertura automática (contenedor sin display) |
| Sin `## Guardrails` | Se agregan guardrails determinísticos (data-is-data, no publicar en terceros, no borrar archivos del usuario) |
| Sin gestión de dependencias | Se agrega `scripts/deps.sh` (`doctor` / `install` aislado en `.deps/`, con fallback de instrucciones por OS). `doctor` acepta el Chromium del sistema cuando `PLAYWRIGHT_CHROMIUM_EXECUTABLE` está definida (`has_chromium` / `chromium_source`) |

## Cambios locales que el próximo upgrade NO debe pisar

Lista de verificación al re-vendorizar (el detalle está en la tabla de arriba):

1. `scripts/export-slides.mjs`: `LAUNCH_OPTIONS` con `executablePath` + la validación de que
   `PLAYWRIGHT_CHROMIUM_EXECUTABLE` sea una ruta **absoluta**. Si upstream reescribe el
   `chromium.launch()`, re-aplicar el patch: sin él, el export a PDF vuelve a fallar en el contenedor.
2. `scripts/deps.sh`: `has_chromium` y `chromium_source` aceptan el navegador del sistema; el mensaje
   de `doctor` reporta `sistema:` o `playwright:`.
3. `scripts/export-pdf.sh`: nunca instalar playwright ni descargar browsers en tiempo de corrida.
4. Un solo *navegador*: `playwright install` se invoca **solo** con `ffmpeg` (lo exige `recordVideo`);
   nunca con `chromium`, que viene del paquete apt. Si alguien lo cambia a `npx playwright install` a
   secas, vuelven los ~126 MB de navegador duplicado y el riesgo del `rm -rf /root/.cache`.

## Dependencias externas

| Dep | Uso | Contenedor | Host |
|---|---|---|---|
| `python-pptx` | conversión PPT | horneada (pip) | `deps.sh install` (venv en `.deps/`) |
| `node` + `playwright` + Chromium | export PDF | horneada: **un solo** `/usr/bin/chromium` vía `PLAYWRIGHT_CHROMIUM_EXECUTABLE` (sin navegador de playwright) | `deps.sh install` (node_modules + browsers en `.deps/`) |

## Riesgo residual

- **Skew de versiones Chromium/playwright**: el navegador de la imagen es el de Debian (`156.x` al
  momento de escribir esto) y playwright 1.65 espera su propio build (`158.x`). Funciona —verificado con
  export real a PDF— porque playwright lanza cualquier Chromium por CDP vía `executablePath`, pero un
  salto mayor de playwright podría requerir features que el Chromium de Debian no tenga. Lo detecta la
  suite de no-regresión (chequeos [2] y [4] de `documents/reports/test-rebuild.sh`), que se corre en
  cada upgrade y en cada rebuild.
- **Motivo del enfoque**: un solo *navegador* evita ~128 MB duplicados y el export roto que dejó el
  borrado de `/root/.cache` en una capa posterior. Solo el ffmpeg de Playwright vive ahí (2,2 MB) y el
  build ya no toca ese directorio.

## Actualización

Ver `upgrade-frontend-slides.md` (meta-documento; **no** es un agente, no lleva `mode:`).
