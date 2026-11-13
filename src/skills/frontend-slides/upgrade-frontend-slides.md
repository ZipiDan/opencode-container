<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade — frontend-slides (procedimiento)

Meta-documento de mantenimiento. **No es una skill ni un agente** (sin frontmatter `mode:`/`name:`
relevante para el loader). Describe cómo re-vendorizar desde upstream.

## Fuente

- Repo: https://github.com/zarazhangrui/frontend-slides
- Ruta a comparar: `SKILL.md`, `STYLE_PRESETS.md`, `viewport-base.css`, `html-template.md`,
  `animation-patterns.md`, `bold-template-pack/**` y `scripts/` (excepto `deploy.sh`, excluido).

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
   - `scripts/export-slides.mjs`: **preservar** `LAUNCH_OPTIONS` y la resolución de
     `PLAYWRIGHT_CHROMIUM_EXECUTABLE` (validación de ruta absoluta). Si upstream reescribe el
     `chromium.launch()`, re-aplicar el patch; sin él el export a PDF vuelve a fallar en el contenedor
     porque la imagen **no** descarga el navegador de playwright.
   - `scripts/deps.sh`: **preservar** `has_chromium` / `chromium_source` (Chromium del sistema) y el
     mensaje de `doctor`.
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
   ```
   Es el chequeo que detecta si el patch de `executablePath` se perdió.
8. Auditoría de seguridad (gate) si cambió código de los scripts.
9. Deploy: `./src/agents_update.sh`.
10. Correr la suite de no-regresión si el upgrade tocó scripts:
    ```bash
    bash documents/reports/test-rebuild.sh --skill-dir src/skills/frontend-slides
    ```
11. Registrar en `BITACORA.md`.

## Nota sobre Vercel

La Fase 6A y `deploy.sh` se excluyeron por decisión del proyecto. Si en el futuro se quisiera
reincorporar, debe hacerse como opción **opt-in explícita** con guardrail (publica contenido en un
tercero) y no romper el flujo local de generación + PDF.
