#!/usr/bin/env bash
# export-pdf.sh — Exporta una presentación HTML de Frontend Slides a PDF.
#
# Uso:
#   bash scripts/export-pdf.sh <path-to-html> [output.pdf] [--compact]
#
# Notas:
#   - Usa el paquete playwright ya instalado (imagen del contenedor o .deps/ en host).
#     NO instala nada ni descarga browsers en cada corrida (a diferencia del upstream).
#   - Chromium se lanza con --no-sandbox (necesario en contenedores/root).
#   - No abre el PDF automáticamente (en contenedor xdg-open es no-op); el usuario lo abre.
#   - Seguridad: no sourcea archivos del proyecto; resuelve playwright solo desde ubicaciones
#     de node_modules conocidas; el servidor local del export escucha solo en loopback.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$(cd "${HERE}/.." && pwd)/.deps"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
info() { echo -e "${CYAN}i${NC} $*"; }
ok()   { echo -e "${GREEN}v${NC} $*"; }
err()  { echo -e "${RED}x${NC} $*" >&2; }

# ── Flags ─────────────────────────────────────────────────────────────────────
VIEWPORT_W=1920; VIEWPORT_H=1080; COMPACT=false
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --compact) COMPACT=true; VIEWPORT_W=1280; VIEWPORT_H=720;;
    *) POSITIONAL+=("$arg");;
  esac
done
set -- "${POSITIONAL[@]:-}"

if [ "$#" -lt 1 ]; then
  err "Uso: bash scripts/export-pdf.sh <path-to-html> [output.pdf] [--compact]"
  exit 1
fi

INPUT_HTML="$1"
[ -f "$INPUT_HTML" ] || { err "No existe el archivo: $INPUT_HTML"; exit 1; }
INPUT_HTML="$(cd "$(dirname "$INPUT_HTML")" && pwd)/$(basename "$INPUT_HTML")"

if [ "$#" -ge 2 ]; then
  OUTPUT_PDF="$2"
else
  OUTPUT_PDF="$(dirname "$INPUT_HTML")/$(basename "$INPUT_HTML" .html).pdf"
fi
OUTPUT_DIR="$(dirname "$OUTPUT_PDF")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_PDF="${OUTPUT_DIR}/$(basename "$OUTPUT_PDF")"

# ── Dependencias ──────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || { err "Falta node. Corré: bash scripts/deps.sh doctor"; exit 3; }

PW_MODULE=""
for cand in "${DEPS_DIR}/node_modules/playwright" /usr/local/lib/node_modules/playwright; do
  [ -d "$cand" ] && { PW_MODULE="$cand"; break; }
done
if [ -z "$PW_MODULE" ] && command -v npm >/dev/null 2>&1; then
  root="$(npm root -g 2>/dev/null || true)"
  [ -n "$root" ] && [ -d "${root}/playwright" ] && PW_MODULE="${root}/playwright"
fi
if [ -z "$PW_MODULE" ] || [ ! -d "$PW_MODULE" ]; then
  err "Falta playwright. Corré: bash scripts/deps.sh doctor"
  exit 3
fi

# Browsers aislados en host (.deps); en contenedor se usa la caché por defecto.
if [ -d "${DEPS_DIR}/browsers" ]; then
  export PLAYWRIGHT_BROWSERS_PATH="${DEPS_DIR}/browsers"
fi

# ── Export ────────────────────────────────────────────────────────────────────
SERVE_DIR="$(dirname "$INPUT_HTML")"
HTML_FILENAME="$(basename "$INPUT_HTML")"
SCREENSHOT_DIR="$(mktemp -d)"
trap 'rm -rf "$SCREENSHOT_DIR"' EXIT

echo ""
info "Exportando $(basename "$INPUT_HTML") -> $(basename "$OUTPUT_PDF")"
[ "$COMPACT" = true ] && info "Modo compacto (1280x720)"

node "${HERE}/export-slides.mjs" \
  "$SERVE_DIR" "$HTML_FILENAME" "$OUTPUT_PDF" "$SCREENSHOT_DIR" "$VIEWPORT_W" "$VIEWPORT_H" \
  || { err "Falló el export a PDF."; exit 1; }

echo ""
ok "PDF generado: $OUTPUT_PDF"
SIZE="$(du -h "$OUTPUT_PDF" | cut -f1)"
echo "  Tamaño: ${BOLD}${SIZE}${NC}"
echo "  Nota: las animaciones quedan en su estado final (export estático)."
echo ""
