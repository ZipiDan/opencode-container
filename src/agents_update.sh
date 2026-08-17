#!/bin/bash
# agents_update.sh — Sincroniza los agentes personalizados del repo hacia la
# configuración global de opencode.
#
# Se ejecuta SOLO desde el repo (debe encontrar src/agents/ junto a sí mismo).
# Los agentes se organizan en subcarpetas (src/agents/<agente>/). El deploy
# PRESERVA el árbol de subcarpetas hacia ~/.config/opencode/agents/<rel>:
# OpenCode escanea {agent,agents}/**/*.md de forma recursiva (sin registro
# previo) y nombra a cada agente según su ruta relativa (p. ej. el archivo
# agents/investigador/investigador-en.md crea el agente
# investigador/investigador-en). No se requiere declaración en opencode.json.
#
# Compara los archivos del repo contra las copias instaladas usando el campo
# 'version:' del frontmatter y un checksum sha256. Solo gestiona los agentes
# que viven bajo src/agents/: nunca toca los agentes por defecto de OpenCode
# (build, plan, etc.).

set -u

# Colores ANSI (mismo esquema que opencode.sh)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/agents"
DEST_DIR="${HOME}/.config/opencode/agents"

CHECK_MODE=false
FORCE_MODE=false

show_help() {
  cat <<EOF
Usage: $0 [options]

Sync the custom agents from this repo to the global opencode configuration.

The agents live in subfolders in this repo (src/agents/<agent>/*.md). On
deploy the folder tree is PRESERVED into ${DEST_DIR}/<rel>: OpenCode scans
{agent,agents}/**/*.md recursively with no registry entry, and each agent is
named after its relative path (e.g. agents/investigador/investigador-en.md
becomes the agent investigador/investigador-en). No opencode.json declaration
is needed.

It compares the repo files against the installed copies using the 'version:'
field and a sha256 checksum. It only manages the custom agents that live in
this repo; the default OpenCode agents (build, plan, etc.) are never touched.

Options:
  --check          Show what would change, without writing anything.
  --force          Apply the changes without asking for confirmation.
  --dest <dir>     Use <dir> as the destination agents folder (default: ${DEST_DIR}).
  -h, --help       Show this help and exit.

Examples:
  $0 --check        # preview only
  $0                # preview + confirmation, then apply
  $0 --force        # apply without confirmation
EOF
}

# Parseo de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_MODE=true; shift ;;
    --force) FORCE_MODE=true; shift ;;
    --dest)
      if [[ -z "${2:-}" ]]; then
        echo "[ERROR] --dest requires a directory path." >&2
        exit 1
      fi
      DEST_DIR="$2"
      shift 2
      ;;
    -h | --help) show_help; exit 0 ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SRC_DIR" ]]; then
  echo "[ERROR] Agents directory not found: $SRC_DIR" >&2
  echo "Make sure you run this script from the opencode-container repo." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

# Devuelve la 'version:' entera del frontmatter de un archivo (0 si no existe).
agent_version() {
  local file="$1"
  sed -n '2,/^---$/p' "$file" | awk '/^[[:space:]]*version:[[:space:]]*[0-9]+[[:space:]]*$/ { v=$2 } END { print v+0 }'
}

# ¿Es un agente gestionable? (tiene frontmatter con campo mode:; README no es agente)
is_agent_file() {
  local file="$1"
  [[ "$(basename "$file")" == "README.md" ]] && return 1
  sed -n '2,/^---$/p' "$file" | grep -qE '^[[:space:]]*mode:[[:space:]]*'
}

# Descubrir los agentes gestionados del repo: cualquier .md bajo src/agents/
# (una subcarpeta por agente) que sea un agente válido (frontmatter con mode:).
declare -a managed_rel=() managed_src=()
while IFS= read -r src; do
  is_agent_file "$src" || continue
  rel="$(realpath --relative-to="$SRC_DIR" "$src")"
  managed_rel+=("$rel")
  managed_src+=("$src")
done < <(find "$SRC_DIR" -type f -iname '*.md' ! -iname 'readme.md' | sort)

if [[ ${#managed_rel[@]} -eq 0 ]]; then
  echo "[ERROR] No custom agents found under $SRC_DIR." >&2
  exit 1
fi

# Colisiones de nombre de agente (path relativo sin extensión). Un sistema de
# archivos case-insensitive (macOS/Windows) podría chocar con rutas que solo
# difieren en mayúsculas; se rechazan por seguridad.
declare -A seen_name=()
for rel in "${managed_rel[@]}"; do
  name="${rel%.md}"
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${seen_name[$lower]+x}" ]]; then
    echo "[ERROR] Duplicate agent name '$name' found in the repo (two paths differ only by case)." >&2
    echo "Agent names must be unique in the destination folder." >&2
    exit 1
  fi
  seen_name[$lower]=1
done

echo "Checking custom agents in the repo against your installed copies..."
echo "  Source:      $SRC_DIR"
echo "  Destination: $DEST_DIR"
echo ""

declare -a pending_name=() pending_kind=() pending_old=() pending_new=() pending_src=() pending_dst=() pending_rel=()
declare -a skipped_note=()
changed=0

for i in "${!managed_rel[@]}"; do
  rel="${managed_rel[$i]}"
  src="${managed_src[$i]}"
  name="${rel%.md}"
  dst="${DEST_DIR}/${rel}"
  src_ver="$(agent_version "$src")"

  if [[ ! -f "$dst" ]]; then
    pending_name+=("$name"); pending_kind+=("INSTALL"); pending_old+=("-"); pending_new+=("$src_ver")
    pending_src+=("$src"); pending_dst+=("$dst"); pending_rel+=("$rel")
    changed=$((changed + 1))
    continue
  fi

  dst_ver="$(agent_version "$dst")"
  src_hash="$(sha256sum "$src" | awk '{print $1}')"
  dst_hash="$(sha256sum "$dst" | awk '{print $1}')"

  if [[ "$src_ver" -gt "$dst_ver" ]]; then
    pending_name+=("$name"); pending_kind+=("UPDATE"); pending_old+=("$dst_ver"); pending_new+=("$src_ver")
    pending_src+=("$src"); pending_dst+=("$dst"); pending_rel+=("$rel")
    changed=$((changed + 1))
  elif [[ "$src_ver" -eq "$dst_ver" ]]; then
    if [[ "$src_hash" != "$dst_hash" ]]; then
      # Misma versión pero contenido distinto: la copia instalada fue editada localmente.
      pending_name+=("$name"); pending_kind+=("REPLACE"); pending_old+=("$dst_ver"); pending_new+=("$src_ver")
      pending_src+=("$src"); pending_dst+=("$dst"); pending_rel+=("$rel")
      changed=$((changed + 1))
    fi
  else
    skipped_note+=("$rel (installed version $dst_ver is newer than repo version $src_ver)")
  fi
done

if [[ "$CHECK_MODE" == "true" ]]; then
  echo "[--check mode: showing what would change. No changes will be made.]"
  echo ""
fi

if [[ "$changed" -eq 0 ]]; then
  echo "All custom agents are up to date. Nothing to do."
  exit 0
fi

echo "The following ${RED}custom agents changed${NC} in the repo compared to your installed copies:"
echo ""
for i in "${!pending_name[@]}"; do
  case "${pending_kind[$i]}" in
    INSTALL) note="${RED}will be installed${NC} (version ${pending_new[$i]})" ;;
    UPDATE) note="${RED}will be updated${NC} (version ${pending_old[$i]} -> ${pending_new[$i]})" ;;
    REPLACE) note="${RED}was modified locally and will be replaced${NC} (version ${pending_new[$i]})" ;;
  esac
  printf '%s  %s\n' "${RED}- ${pending_rel[$i]}${NC}" "$note"
done

if [[ ${#skipped_note[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped (not touched):"
  for note in "${skipped_note[@]}"; do
    printf '  - %s\n' "$note"
  done
fi

echo ""
echo "${YELLOW}These agents will be REPLACED in your opencode configuration.${NC}"
echo "${YELLOW}WARNING: If you made local changes to any of these agents, those changes${NC}"
echo "${YELLOW}will be lost. It is your responsibility to back them up first if you want${NC}"
echo "${YELLOW}to keep them.${NC}"
echo ""
echo "Only the files under src/agents/ are managed by this script. The default"
echo "OpenCode agents (build, plan) and any other agent you may have installed are"
echo "never touched."

if [[ "$CHECK_MODE" == "true" ]]; then
  echo ""
  echo "$changed change(s) would be applied."
  exit 0
fi

if [[ "$FORCE_MODE" == "true" ]]; then
  echo ""
  echo "[--force mode: applying changes without confirmation.]"
else
  echo ""
  read -r -p "Do you want to continue and apply these changes? (Y/s) " answer
  case "${answer,,}" in
    y | s) ;;
    *)
      echo ""
      echo "Update cancelled. No changes were made."
      for i in "${!pending_name[@]}"; do
        printf '  [NOT UPDATED] %s\n' "${pending_rel[$i]}"
      done
      exit 0
      ;;
  esac
fi

echo ""
echo "Updating agents..."
updated=0
for i in "${!pending_name[@]}"; do
  kind="${pending_kind[$i]}"
  rel="${pending_rel[$i]}"
  mkdir -p "$(dirname "${pending_dst[$i]}")" || {
    echo "  [ERROR] Failed to create directory for $rel" >&2
    exit 1
  }
  if ! cp -f "${pending_src[$i]}" "${pending_dst[$i]}"; then
    echo "  [ERROR] Failed to copy $rel" >&2
    exit 1
  fi
  case "$kind" in
    INSTALL) msg="[INSTALLED] $rel (version ${pending_new[$i]})" ;;
    UPDATE) msg="[UPDATED] $rel (version ${pending_old[$i]} -> ${pending_new[$i]})" ;;
    REPLACE) msg="[REPLACED] $rel (version ${pending_new[$i]})" ;;
  esac
  printf '  %s\n' "$msg"
  updated=$((updated + 1))
done

echo ""
echo "Done. $updated change(s) applied."