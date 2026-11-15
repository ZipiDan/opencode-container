#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# export-video.sh — Exporta una presentación HTML de Frontend Slides a MP4.
#
# Uso:
#   bash scripts/export-video.sh <path-to-html> [output.mp4] [opciones]
#
# Notas:
#   - No reimplementa nada: valida dependencias, resuelve la salida por defecto y delega en
#     capture-video.mjs. Toda la validación de parámetros vive ahí (una sola fuente).
#   - Nunca abre un prompt interactivo: corre igual bajo nohup o dentro de un pipe. Sin
#     --quality se usa max.
#   - --help delega en el .mjs para no duplicar la tabla de parámetros.
#   - Usa el playwright ya instalado (imagen del contenedor o .deps/ en host). No instala nada ni
#     descarga browsers en cada corrida.
#   - Chromium se resuelve en lib/browser.mjs (--no-sandbox incluido: el contenedor corre como root).
#   - Seguridad: no sourcea archivos del proyecto; el servidor del deck escucha sólo en loopback.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$(cd "${HERE}/.." && pwd)/.deps"

RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
info() { echo -e "${CYAN}i${NC} $*"; }
err()  { echo -e "${RED}x${NC} $*" >&2; }

USO='Uso: bash scripts/export-video.sh <path-to-html> [output.mp4] [opciones]  ·  --help para la tabla'

if [ "$#" -lt 1 ]; then
  err "$USO"
  exit 1
fi

# --help no necesita deck: sólo delegar (o avisar si no hay node).
for arg in "$@"; do
  if [ "$arg" = "--help" ]; then
    command -v node >/dev/null 2>&1 \
      || { err "Falta node, no puedo mostrar la ayuda. Corré: bash scripts/deps.sh doctor"; exit 3; }
    node "${HERE}/capture-video.mjs" --help
    exit 0
  fi
done

INPUT_HTML="$1"; shift
[ -f "$INPUT_HTML" ] || { err "No existe el archivo: $INPUT_HTML"; exit 1; }
INPUT_HTML="$(cd "$(dirname "$INPUT_HTML")" && pwd)/$(basename "$INPUT_HTML")"

# Salida opcional: las opciones pueden venir sin salida, así que $1 sólo cuenta si no es una flag.
OUTPUT_MP4=""
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  OUTPUT_MP4="$1"; shift
fi
if [ -z "$OUTPUT_MP4" ]; then
  OUTPUT_MP4="$(dirname "$INPUT_HTML")/$(basename "$INPUT_HTML" .html).mp4"
fi
OUTPUT_DIR="$(dirname "$OUTPUT_MP4")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_MP4="${OUTPUT_DIR}/$(basename "$OUTPUT_MP4")"

# ── Dependencias ──────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || { err "Falta node. Corré: bash scripts/deps.sh doctor"; exit 3; }
command -v ffmpeg >/dev/null 2>&1 || { err "Falta ffmpeg (encode H.264). Instalalo y volvé a intentar."; exit 3; }

# Browsers aislados en host (.deps); en contenedor se usa la caché por defecto.
if [ -d "${DEPS_DIR}/browsers" ]; then
  export PLAYWRIGHT_BROWSERS_PATH="${DEPS_DIR}/browsers"
fi

# Después de PLAYWRIGHT_BROWSERS_PATH: el doctor resuelve el navegador con chromium.executablePath().
DOCTOR_OUT=""
if ! DOCTOR_OUT="$(node "${HERE}/lib/browser.mjs" --doctor 2>&1)"; then
  printf '%s\n' "$DOCTOR_OUT" >&2
  err "Falta playwright o Chromium. Corré: bash scripts/deps.sh doctor"
  exit 3
fi

# ── Export ────────────────────────────────────────────────────────────────────
# exec: el .mjs imprime el plan, el progreso y el resultado; acá no hay nada más que hacer.
info "Exportando $(basename "$INPUT_HTML") -> $(basename "$OUTPUT_MP4")"
exec node "${HERE}/capture-video.mjs" "$INPUT_HTML" "$OUTPUT_MP4" "$@"
