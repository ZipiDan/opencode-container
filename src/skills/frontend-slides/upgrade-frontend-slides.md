<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade — frontend-slides (procedimiento)

Meta-documento de mantenimiento. **No es una skill ni un agente** (sin frontmatter `mode:`/`name:`
relevante para el loader). Describe cómo re-vendorizar desde upstream.

## Fuente

- Repo: https://github.com/zarazhangrui/frontend-slides
- Ruta a comparar: `SKILL.md`, `STYLE_PRESETS.md`, `viewport-base.css`, `html-template.md`,
  `animation-patterns.md`, `bold-template-pack/**` y `scripts/` (excepto `deploy.sh`, excluido).
- **Archivos que upstream no tiene y son locales** (`scripts/lib/browser.mjs`,
  `scripts/capture-video.mjs`, `scripts/export-video.sh`, `scripts/tests/guard.mjs`, `PROVENANCE.md` y
  este documento): el `diff -r` los va a mostrar como `Only in` del lado local. **No son drift y no se
  borran ni se "alinean"**: son las features propias de este repo (resolvedor único, export a video y
  guard anti-hardcode). Si un paso de re-vendorizado los elimina, se rompe PDF y video a la vez.

## Procedimiento

1. Clonar upstream en `$TMP`:
   ```bash
   TMP=$(mktemp -d); git clone --depth 1 https://github.com/zarazhangrui/frontend-slides.git "$TMP/fs"
   ```
2. Diff estructurado contra la copia local:
   ```bash
   diff -r --brief "$TMP/fs" src/skills/frontend-slides
   ```
3. Aplicar el **mapa de reescrituras** de `PROVENANCE.md` a lo que haya cambiado:
   - Datos de diseño (`STYLE_PRESETS.md`, `bold-template-pack/**`, etc.): copiar verbatim.
   - `SKILL.md`: plegar cambios de las fases al SKILL.md adaptado, **preservando** los `## Guardrails`
     y la sección de Dependencias/`deps.sh`. Mantener Vercel excluido.
   - `scripts/export-pdf.sh`: no reimportar el instalador de playwright; portar solo mejoras de
     lógica al `export-slides.mjs`/wrapper local.
   - `scripts/export-slides.mjs`: **preservar** dos parches locales que upstream no tiene:
     (a) cada slide se navega marcándolo con `.active` **y** `.visible`, y (b) antes del screenshot se
     terminan las animaciones finitas (`anim.finish()`). Sin (a) el contenido queda en `opacity: 0`
     (el CSS revela con `.slide.visible .reveal`) y sin (b) el screenshot agarra las entradas a medio
     `transition-delay`: el PDF sale con las páginas 2..N casi vacías. Era un bug **previo** al
     refactor de la Fase 0; si el patch se pierde, vuelve.
   - `scripts/lib/browser.mjs`: **local** (upstream no lo tiene) y único resolvedor de
     playwright/Chromium: `launchOptions()` con `executablePath` tomado de
     `PLAYWRIGHT_CHROMIUM_EXECUTABLE` (validada como ruta absoluta) más `--no-sandbox`, servidor
     estático de loopback y modo `--doctor`. Si upstream reescribe el `chromium.launch()` de un export,
     el patch se re-aplica **acá**, no en los consumidores.
   - `scripts/deps.sh`: **preservar** la delegación de `doctor` en `node scripts/lib/browser.mjs
     --doctor` (imprime `módulo:` y `navegador:`). No reintroducir una detección propia en bash: sería
     una segunda fuente de verdad.
   - `scripts/capture-video.mjs` y `scripts/export-video.sh`: **locales**, sin equivalente upstream.
     El motor depende de `lib/browser.mjs` y de `ffmpeg`; el crossfade fijo de 0.35 s y el default
     `--quality max` (el script nunca abre un prompt) son decisiones del proyecto — ver `PROVENANCE.md`,
     ítem 5.
   - `scripts/tests/guard.mjs`: **local**; falla si vuelve el Chromium hardcodeado, un `playwright`
     importado pelado o una segunda lista de candidatos de playwright. El stage de skills no despliega
     `tests/`, así que no viaja a `~/.config/opencode/skills/`.
   - `scripts/extract-pptx.py`: portar cambios, preservando el `try/except ImportError` accionable.
4. Verificar que no se cuele `deploy.sh` ni referencias a Vercel/`.claude`:
   ```bash
   rg -n 'vercel|deploy\.sh|\.claude|Claude Code' src/skills/frontend-slides || true
   ```
5. Subir `version:` en el frontmatter de `SKILL.md`.
6. Validar en seco el deploy: `./src/agents_update.sh --check`.
7. Validar el export a PDF (en el contenedor, o en host con `.deps/`):
   ```bash
   bash src/skills/frontend-slides/scripts/export-pdf.sh <deck.html> /tmp/check.pdf
   grep -ac '/Type */Page\b' /tmp/check.pdf
   ```
   Es el chequeo que detecta si los parches de `export-slides.mjs` se perdieron. **Mirá el contenido**,
   no solo que el archivo exista: la cantidad de páginas tiene que ser la de slides y ninguna página
   puede salir casi vacía (un PDF con el bug de revelado pesa bastante menos).
8. Validar el export a video y el guard:
   ```bash
   bash src/skills/frontend-slides/scripts/export-video.sh <deck.html> /tmp/check.mp4 --fps 2
   ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt,color_range -of default=nw=1 /tmp/check.mp4
   node src/skills/frontend-slides/scripts/tests/guard.mjs
   ```
   Esperado: `pix_fmt=yuv420p`, `color_range=tv` y `guard: OK`. Si `--fps` bajo tarda poco, el motor
   está sano; el tiempo real se mide con los defaults.
9. Auditoría de seguridad (gate) si cambió código de los scripts.
10. Deploy: `./src/agents_update.sh`.
11. Correr la suite de no-regresión si el upgrade tocó scripts:
    ```bash
    bash documents/reports/test-rebuild.sh --skill-dir src/skills/frontend-slides
    ```
    Ojo: ese harness todavía duplica el resolvedor y hardcodea Chromium (deuda conocida, fuera del
    barrido del guard); sirve como prueba de que el contenedor sigue exportando, no como fuente de
    verdad.
12. Registrar en `BITACORA.md`.

## Nota sobre Vercel

La Fase 6A y `deploy.sh` se excluyeron por decisión del proyecto. Si en el futuro se quisiera
reincorporar, debe hacerse como opción **opt-in explícita** con guardrail (publica contenido en un
tercero) y no romper el flujo local de generación + PDF + video.
