#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# pptx-extract.sh — wrapper que elige el intérprete con python-pptx y corre extract-pptx.py.
# Uso: bash scripts/pptx-extract.sh <input.pptx> [output_dir]
# Seguridad: no sourcea archivos del proyecto ni usa intérpretes de variables de entorno.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$(cd "${HERE}/.." && pwd)/.deps"

PY=""
for cand in "${DEPS_DIR}/venv/bin/python3" /usr/bin/python3 python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import pptx' >/dev/null 2>&1; then
    PY="$cand"; break
  fi
done

if [ -z "$PY" ]; then
  echo "FALTA python-pptx (conversión de PPT). Diagnóstico e instalación:" >&2
  echo "  bash \"${HERE}/deps.sh\" doctor" >&2
  echo "  bash \"${HERE}/deps.sh\" install     # aislado en la skill" >&2
  exit 3
fi

exec "$PY" "${HERE}/extract-pptx.py" "$@"
