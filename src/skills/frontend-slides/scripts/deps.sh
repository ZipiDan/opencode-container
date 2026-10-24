#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# deps.sh — Diagnóstico e instalación aislada de las dependencias de Frontend Slides.
#
# Uso:
#   bash scripts/deps.sh doctor            # detecta deps y, si faltan, imprime instrucciones por OS
#   bash scripts/deps.sh install [--yes]   # instala de forma AISLADA dentro de la skill (.deps/)
#
# Estrategia (H2 con fallback a H1):
#   - H2: crea un venv propio y un node_modules propio dentro de <skill>/.deps/, baja el Chromium
#     headless shell ahí (PLAYWRIGHT_BROWSERS_PATH) y lo usa todo desde ahí. No requiere root ni
#     ensucia el sistema; compatible con PEP 668. Los cachés de npm/pip quedan scoped en .deps/.
#   - H1 (fallback): si la instalación aislada falla, imprime las instrucciones por OS.
#
# Seguridad: NO se sourcea ningún archivo del proyecto ni se ejecutan intérpretes desde variables
# de entorno; las rutas se derivan del propio directorio de la skill.
#
# En el contenedor de opencode.sh las dependencias ya vienen horneadas en la imagen: `doctor`
# reporta todo OK y nadie necesita `install`.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${HERE}/.." && pwd)"
DEPS_DIR="${SKILL_DIR}/.deps"

# Colores (mismo esquema que el resto del repo)
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}    $*"; }
miss() { echo -e "  ${RED}FALTA${NC} $*"; }
info() { echo -e "  ${CYAN}info${NC}  $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ── Resolución de intérprete Python con python-pptx ────────────────────────────
# Solo rutas derivadas de la skill (/usr/bin/python3, python3, python). Sin env.
resolve_python() {
  local cand
  for cand in "${DEPS_DIR}/venv/bin/python3" /usr/bin/python3 python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import pptx' >/dev/null 2>&1; then
      printf '%s' "$cand"; return 0
    fi
  done
  return 1
}

# ── Resolución del paquete npm de playwright (solo ubicaciones de node_modules) ──
resolve_pw_module() {
  local cand root
  for cand in "${DEPS_DIR}/node_modules/playwright" /usr/local/lib/node_modules/playwright; do
    [ -d "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  if has_cmd npm; then
    root="$(npm root -g 2>/dev/null || true)"
    [ -n "$root" ] && [ -d "${root}/playwright" ] && { printf '%s' "${root}/playwright"; return 0; }
  fi
  return 1
}

# ── Resolución de la caché de browsers de playwright ──────────────────────────
browsers_path() {
  if [ -d "${DEPS_DIR}/browsers" ]; then
    printf '%s' "${DEPS_DIR}/browsers"
  else
    printf '%s' "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
  fi
}

has_chromium() {
  local bp; bp="$(browsers_path)"
  [ -n "$(find "$bp" -maxdepth 1 -iname 'chromium*' 2>/dev/null | head -1)" ]
}

# ── Instrucciones por OS (H1) ─────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos"; return;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"; return; fi
      [ -f /etc/os-release ] || { echo "linux"; return; }
      . /etc/os-release
      case "${ID:-}${ID_LIKE:-}" in
        *debian*|*ubuntu*) echo "debian";;
        *fedora*|*rhel*|*centos*) echo "fedora";;
        *arch*) echo "arch";;
        *suse*) echo "suse";;
        *) echo "linux";;
      esac;;
    *) echo "unknown";;
  esac
}

os_instructions() {
  local os; os="$(detect_os)"
  echo ""
  echo -e "${BOLD}Instalación de dependencias (según tu sistema)${NC}"
  echo ""
  echo "  1) python-pptx (conversión PPT):"
  case "$os" in
    debian) echo "       sudo apt-get install -y python3-pip && pipx install --include-deps python-pptx";;
    fedora) echo "       sudo dnf install -y python3-pip && pipx install --include-deps python-pptx";;
    arch)   echo "       sudo pacman -S python-pip && pipx install --include-deps python-pptx";;
    suse)   echo "       sudo zypper install -y python3-pip && pipx install --include-deps python-pptx";;
    macos)  echo "       brew install pipx && pipx install --include-deps python-pptx";;
    wsl)    echo "       (dentro de WSL/Ubuntu) sudo apt-get install -y python3-pip && pipx install --include-deps python-pptx";;
    *)      echo "       pipx install --include-deps python-pptx   (o un venv dedicado)";;
  esac
  echo ""
  echo "  2) node + playwright + chromium (export PDF):"
  case "$os" in
    debian|wsl) echo "       sudo apt-get install -y nodejs npm";;
    fedora)     echo "       sudo dnf install -y nodejs npm";;
    arch)       echo "       sudo pacman -S nodejs npm";;
    suse)       echo "       sudo zypper install -y nodejs npm";;
    macos)      echo "       brew install node";;
    *)          echo "       instalá Node.js (https://nodejs.org)";;
  esac
  echo "       npm install -g playwright && npx playwright install --with-deps --only-shell chromium"
  echo ""
  echo -e "  ${YELLOW}Alternativa recomendada (aislada, sin root):${NC} bash scripts/deps.sh install --yes"
  echo ""
}

# ── doctor ────────────────────────────────────────────────────────────────────
doctor() {
  echo -e "${BOLD}Frontend Slides — diagnóstico de dependencias${NC}"
  echo ""
  local missing=0 py pw

  if has_cmd node; then ok "node ($(node --version 2>/dev/null))"; else miss "node (export PDF)"; missing=1; fi
  if has_cmd npx;  then ok "npx"; else miss "npx"; missing=1; fi

  if py="$(resolve_python)"; then
    ok "python con python-pptx ($py)"
  else
    miss "python-pptx (conversión PPT)"; missing=1
  fi

  if pw="$(resolve_pw_module)"; then
    ok "playwright ($pw)"
  else
    miss "playwright (export PDF)"; missing=1
  fi

  if has_chromium; then
    ok "chromium headless ($(browsers_path))"
  else
    miss "chromium headless"; missing=1
  fi

  echo ""
  if [ "$missing" -eq 0 ]; then
    echo -e "${GREEN}Todas las dependencias están presentes.${NC}"
    return 0
  fi
  echo -e "${YELLOW}Faltan dependencias.${NC}"
  os_instructions
  return 1
}

# ── install (H2 aislado, con fallback H1) ─────────────────────────────────────
confirm() {
  [ "${1:-}" = "--yes" ] && return 0
  [ -t 0 ] || { echo "Sin TTY; usá --yes para instalar sin confirmación." >&2; return 1; }
  read -r -p "¿Instalar dependencias aisladas en ${DEPS_DIR}? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]]
}

install_deps() {
  local assume_yes="${1:-}"
  command -v node >/dev/null 2>&1 || { echo -e "${RED}Node.js no está instalado.${NC}"; os_instructions; return 1; }
  command -v python3 >/dev/null 2>&1 || { echo -e "${RED}python3 no está instalado.${NC}"; os_instructions; return 1; }
  confirm "$assume_yes" || { echo "Cancelado."; return 1; }

  mkdir -p "$DEPS_DIR" || { os_instructions; return 1; }

  # 1) python-pptx en un venv propio (caché de pip scoped en .deps/)
  info "Creando venv y instalando python-pptx..."
  if [ ! -x "${DEPS_DIR}/venv/bin/python3" ]; then
    python3 -m venv "${DEPS_DIR}/venv" || { echo -e "${RED}No se pudo crear el venv.${NC}"; os_instructions; return 1; }
  fi
  PIP_CACHE_DIR="${DEPS_DIR}/.pip-cache" "${DEPS_DIR}/venv/bin/python3" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
  if ! PIP_CACHE_DIR="${DEPS_DIR}/.pip-cache" "${DEPS_DIR}/venv/bin/python3" -m pip install --quiet python-pptx; then
    echo -e "${RED}Falló la instalación de python-pptx.${NC}"; os_instructions; return 1
  fi
  rm -rf "${DEPS_DIR}/.pip-cache"

  # 2) playwright + chromium headless shell en la skill (caché npm scoped en .deps/)
  info "Instalando playwright (npm local)..."
  if ! npm --prefix "$DEPS_DIR" --cache "${DEPS_DIR}/.npm-cache" install --silent playwright; then
    echo -e "${RED}Falló la instalación de playwright.${NC}"; os_instructions; return 1
  fi
  info "Descargando Chromium headless shell..."
  if ! PLAYWRIGHT_BROWSERS_PATH="${DEPS_DIR}/browsers" \
       "${DEPS_DIR}/node_modules/.bin/playwright" install --only-shell chromium; then
    echo -e "${RED}Falló la descarga de Chromium.${NC}"; os_instructions; return 1
  fi
  rm -rf "${DEPS_DIR}/.npm-cache"

  echo ""
  echo -e "${GREEN}Dependencias instaladas en ${DEPS_DIR}.${NC}"
  echo "Verificá con: bash scripts/deps.sh doctor"
}

cmd="${1:-doctor}"; shift || true
case "$cmd" in
  doctor|-d) doctor;;
  install|-i) install_deps "${1:-}";;
  help|-h|--help)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//';;
  *) echo "Uso: bash scripts/deps.sh {doctor|install [--yes]}" >&2; exit 2;;
esac
