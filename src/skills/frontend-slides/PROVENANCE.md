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
| `chromium.launch()` | `chromium.launch({ args: ['--no-sandbox', ...] })` (contenedores/root) |
| `pip install python-pptx` ad-hoc; `python scripts/extract-pptx.py` | Wrapper `scripts/pptx-extract.sh` que resuelve el intérprete con `python-pptx`; error accionable si falta |
| `open`/`xdg-open` automático del PDF | Se quita la apertura automática (contenedor sin display) |
| Sin `## Guardrails` | Se agregan guardrails determinísticos (data-is-data, no publicar en terceros, no borrar archivos del usuario) |
| Sin gestión de dependencias | Se agrega `scripts/deps.sh` (`doctor` / `install` aislado en `.deps/`, con fallback de instrucciones por OS) |

## Dependencias externas

| Dep | Uso | Contenedor | Host |
|---|---|---|---|
| `python-pptx` | conversión PPT | horneada (pip) | `deps.sh install` (venv en `.deps/`) |
| `node` + `playwright` + Chromium | export PDF | horneada (imagen) | `deps.sh install` (node_modules + browsers en `.deps/`) |

## Actualización

Ver `upgrade-frontend-slides.md` (meta-documento; **no** es un agente, no lleva `mode:`).
