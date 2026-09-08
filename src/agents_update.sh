#!/bin/bash
# agents_update.sh — Sincroniza los agentes personalizados, los estilos CSS y los
# comandos del repo hacia la configuración global de opencode, y puede instalar
# las tools (scripts) en el entorno del usuario.
#
# Se ejecuta SOLO desde el repo (debe encontrar src/agents/ junto a sí mismo).
#
# Stages:
#   agents    src/agents/**         → ~/.config/opencode/agents/**     (por defecto: SÍ)
#   skills    src/agents/*/skills/** → ~/.config/opencode/skills/**    (por defecto: SÍ)
#   styles    src/tools/css-styles/** → ~/.config/opencode/css-styles/** (por defecto: SÍ)
#   commands  src/commands/**       → ~/.config/opencode/commands/**   (por defecto: SÍ)
#   tools     src/tools/* (solo la raíz, p. ej. md2pdf.py)
#                                   → ~/.local/bin (u otro dir) — NO se instalan
#                                     por defecto, solo con --install-tools.
#
# Las tools (p. ej. md2pdf.py) suelen estar horneadas en la imagen del contenedor
# (ver Containerfile: COPY tools/md2pdf.py /usr/local/bin/md2pdf), por lo que NO se
# instalan en el host a menos que se pida explícitamente con --install-tools. Ese
# flag instala SOLO las tools de la raíz de src/tools/ (en el directorio indicado
# o, por defecto, en ~/.local/bin) y no hace ninguna otra acción. Se usa para
# compatibilidad con entornos opencode que corren directo en el host.
#
# La migración del layout (carpetas legacy de la raíz del proyecto a documents/)
# NO viaja con el deploy: tiene su modo exclusivo --update-directory <dir>,
# que solo mueve y no hace ninguna otra acción (igual que --install-tools con
# las tools). <dir> es obligatorio e indica el proyecto a migrar
# (cada proyecto corre en su propio contenedor).
#
# Los estilos CSS (src/tools/css-styles/) se despliegan a la config global
# (~/.config/opencode/css-styles/) porque esa carpeta se monta dentro del
# contenedor y es leída por opencode local: un solo sync alcanza para ambos
# entornos. El README.md de los estilos se despliega también para dar contexto
# a los agentes (alternativas y ayuda con estilos).
#
# Los agentes se organizan en subcarpetas; OpenCode escanea {agent,agents}/**/*.md
# de forma recursiva (sin registro previo) y nombra a cada agente según su ruta
# relativa (p. ej. agents/investigador/investigador-en.md → investigador/investigador-en).
# Cada archivo puede fijar su nombre con el campo 'name:' del frontmatter.
# Los .md que no tienen 'mode:' (p. ej. README.md o el meta-doc upgrade-heinzel.md)
# NO se despliegan como agentes. Las skills viven en subcarpetas
# src/agents/<agente>/skills/<nombre>/ y se despliegan a
# ~/.config/opencode/skills/<nombre>/ (opencode las detecta como skills/*/SKILL.md).
#
# Los commands y los estilos se despliegan a la config global (~/.config/opencode/).
# Esa carpeta es leída por opencode local Y se monta dentro del contenedor (ver
# opencode.sh), así un solo sync alcanza para ambos entornos con la misma ruta
# relativa.
#
# Comparación: los agentes usan el campo 'version:' del frontmatter + checksum
# sha256. Los estilos, tools y commands (sin frontmatter con version) se comparan
# solo por checksum.
#
# Solo gestiona los archivos que viven bajo src/agents/, src/tools/ y
# src/commands/: nunca toca los agentes por defecto de OpenCode (build, plan,
# etc.) ni ningún otro archivo de la config del usuario.

set -u

# Colores ANSI (mismo esquema que opencode.sh)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="${SCRIPT_DIR}/agents"
TOOLS_SRC="${SCRIPT_DIR}/tools"
STYLES_SRC="${TOOLS_SRC}/css-styles"
COMMANDS_SRC="${SCRIPT_DIR}/commands"
# Raíz de config de opencode: respetar XDG_CONFIG_HOME si está definido (si no, ~/.config).
CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
DEST_DIR="${CONFIG_ROOT}/agents"
SKILLS_DEST="$(dirname "${DEST_DIR}")/skills"
STYLES_DEST="$(dirname "${DEST_DIR}")/css-styles"
COMMANDS_DEST="$(dirname "${DEST_DIR}")/commands"

CHECK_MODE=false
FORCE_MODE=false
SKIP_COMMANDS=false
SKIP_STYLES=false
SKIP_SKILLS=false
INSTALL_TOOLS=false
TOOLS_DEST=""
UPDATE_DIRECTORY=false
UPDATE_DIR_TARGET=""

show_help() {
  cat <<EOF
Usage: $0 [options]

Sync the custom agents, CSS styles and commands from this repo to the global
opencode configuration, and optionally install the tools into your user
environment.

Stages:
  src/agents/...            → ${DEST_DIR}/...           (deployed by default)
  src/agents/*/skills/...   → ${SKILLS_DEST}/...        (deployed by default)
  src/tools/css-styles/...  → ${STYLES_DEST}/...        (deployed by default)
  src/commands/...          → ${COMMANDS_DEST}/...      (deployed by default)
  src/tools/* (root only)   → NOT installed by default.
                             Use --install-tools to install the tool scripts
                             (e.g. md2pdf.py) into ~/.local/bin. They are usually
                             baked into the container image (e.g. /usr/local/bin/md2pdf),
                             so this is only for host-only opencode installs.

OpenCode scans {agent,agents}/**/*.md recursively with no registry entry. The
global config directory is read by any local opencode AND is mounted inside the
launcher container, so one sync covers both environments. Skills are detected
at skills/<name>/SKILL.md; each agent can carry its own skills under
src/agents/<agent>/skills/<name>/ which deploy to the global skills directory
(skill names must be unique across all locations).

Comparison: agents use the frontmatter 'version:' field plus a sha256 checksum;
skills, styles, tools and commands (no version field) are compared by checksum only.
Only the files under src/agents/, src/tools/ and src/commands/ are managed here;
default OpenCode agents (build, plan, etc.) are never touched.

Options:
  --check                     Show what would change, without writing anything.
  --force                     Apply the changes without asking for confirmation.
  --no-commands               Skip the commands stage.
  --no-styles                 Skip the styles stage (deploy agents+skills+commands only).
  --no-skills                 Skip the skills stage (deploy agents+styles+commands only).
  --install-tools [<dir>]     Install ONLY the tool scripts from the root of
                              src/tools/ (e.g. md2pdf.py) into <dir> and do
                              nothing else. If <dir> is omitted, installs into
                              ~/.local/bin. Verifies that <dir> is in your PATH
                              so the tool is invocable (warns if it is not).
  --update-directory <dir>    Migrate ONLY the legacy root dirs of <dir> into
                               documents/ (docs/arquitectura, investigaciones,
                               memory, reports; never overwrites) and do
                               nothing else. <dir> must be an existing
                               directory; pass a project dir to migrate it.
  --dest <dir>                Use <dir> as the destination agents folder (default: ${DEST_DIR}).
                              styles/commands are derived from its parent directory.
  -h, --help                  Show this help and exit.

Examples:
  $0 --check                  # preview only
  $0                          # preview + confirmation, then apply (agents+skills+styles+commands)
  $0 --force                  # apply without confirmation
  $0 --no-skills              # deploy agents+styles+commands only
  $0 --no-styles              # deploy agents+skills+commands only
  $0 --install-tools          # install tools into ~/.local/bin (nothing else)
  $0 --install-tools ~/bin    # install tools into ~/bin (nothing else)
  $0 --update-directory /path/to/project  # migrate project dirs into documents/ (nothing else)
EOF
}

# Parseo de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_MODE=true; shift ;;
    --force) FORCE_MODE=true; shift ;;
    --no-commands) SKIP_COMMANDS=true; shift ;;
    --no-styles) SKIP_STYLES=true; shift ;;
    --no-skills) SKIP_SKILLS=true; shift ;;
    --update-directory)
      UPDATE_DIRECTORY=true
      if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
        echo "[ERROR] --update-directory requires a directory path." >&2
        exit 1
      fi
      UPDATE_DIR_TARGET="$2"
      shift 2
      ;;
    --install-tools)
      INSTALL_TOOLS=true
      # Parámetro opcional de directorio: el siguiente argumento si no es una opción.
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        TOOLS_DEST="$2"
        shift
      fi
      shift
      ;;
    --dest)
      if [[ -z "${2:-}" ]]; then
        echo "[ERROR] --dest requires a directory path." >&2
        exit 1
      fi
      DEST_DIR="$2"
      SKILLS_DEST="$(dirname "${DEST_DIR}")/skills"
      STYLES_DEST="$(dirname "${DEST_DIR}")/css-styles"
      COMMANDS_DEST="$(dirname "${DEST_DIR}")/commands"
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

if [[ ! -d "$AGENTS_SRC" ]]; then
  echo "[ERROR] Agents directory not found: $AGENTS_SRC" >&2
  echo "Make sure you run this script from the opencode-container repo." >&2
  exit 1
fi

# ============================================================================
# Modo exclusivo: --install-tools [<dir>]
# Instala SOLO las tools y no hace ninguna otra acción.
# ============================================================================
install_tools() {
  local dest="$1"

  if [[ ! -d "$TOOLS_SRC" ]]; then
    echo "[ERROR] Tools directory not found: $TOOLS_SRC" >&2
    exit 1
  fi

  if [[ ! -d "$dest" ]]; then
    mkdir -p "$dest" || {
      echo "[ERROR] Could not create directory: $dest" >&2
      exit 1
    }
  fi

  echo "Installing tools from $TOOLS_SRC -> $dest"
  echo ""

  local installed=0
  local src dst
  while IFS= read -r src; do
    [[ "$(basename "$src")" == "README.md" ]] && continue
    dst="${dest}/$(basename "$src")"
    if ! cp -f "$src" "$dst"; then
      echo "  [ERROR] Failed to copy $(basename "$src")" >&2
      exit 1
    fi
    chmod +x "$dst" 2>/dev/null || true
    echo "  [INSTALLED] $(basename "$src") -> $dst"
    installed=$((installed + 1))
  done < <(find "$TOOLS_SRC" -maxdepth 1 -type f | sort)

  echo ""
  echo "Done. $installed tool(s) installed."

  # Verificar que el directorio de destino esté en el PATH para que el comando
  # sea invocable. Es responsabilidad del usuario cerciorarse; solo se advierte.
  local found=""
  local p
  IFS=: read -r -a path_arr <<<"$PATH"
  for p in "${path_arr[@]}"; do
    [[ "${p%/}" == "$(realpath "$dest" 2>/dev/null || echo "$dest")" ]] && found="yes"
  done
  if [[ "$found" != "yes" ]]; then
    echo ""
    echo "${YELLOW}[WARN] El directorio '$dest' NO está en tu PATH.${NC}"
    echo "${YELLOW}El/los comando(s) instalados no serán invocables por nombre hasta que${NC}"
    echo "${YELLOW}agregues esa carpeta al PATH (p. ej. export PATH=\"$dest:\$PATH\").${NC}"
  else
    echo ""
    echo "[OK] '$dest' está en tu PATH; los comando(s) ya son invocables."
  fi
  exit 0
}

if [[ "$INSTALL_TOOLS" == "true" ]]; then
  install_tools "${TOOLS_DEST:-$HOME/.local/bin}"
fi

# ============================================================================
# Modo exclusivo: --update-directory <dir>
# Migra SOLO las carpetas legacy de la raíz del target a documents/ y no hace
# ninguna otra acción. <dir> es obligatorio (proyectos arbitrarios, cada uno
# en su contenedor).
# ============================================================================
update_directories() {
  local target_root="$1"
  local documents_dir="${target_root}/documents"
  if [[ -f "$documents_dir" ]]; then
    echo "[ERROR] Documents path exists as a regular file: $documents_dir" >&2
    exit 1
  fi

  declare -a move_src=() move_dst=() move_rel=()
  declare -a dir_skip=()
  local pair src_rel dst_rel src dst
  for pair in "docs/arquitectura:documents/arquitectura" "investigaciones:documents/investigaciones" \
      "memory:documents/memory" "reports:documents/reports"; do
    src_rel="${pair%%:*}"
    dst_rel="${pair#*:}"
    src="${target_root}/${src_rel}"
    dst="${target_root}/${dst_rel}"
    if [[ -L "$src" ]]; then
      dir_skip+=("$src_rel (source is a symlink, skipped)")
      continue
    fi
    if [[ -e "$src" ]]; then
      if [[ -e "$dst" ]]; then
        dir_skip+=("$src_rel (destination $dst_rel already exists, skipped)")
        continue
      fi
      move_src+=("$src")
      move_dst+=("$dst")
      move_rel+=("$src_rel -> $dst_rel")
    fi
  done

  echo "Checking directory layout for migration into documents/..."
  echo "  Root: $target_root -> $documents_dir"
  echo ""

  if [[ ${#move_rel[@]} -eq 0 ]]; then
    echo "Documents layout already normalized. Nothing to do."
    if [[ ${#dir_skip[@]} -gt 0 ]]; then
      echo ""
      echo "Skipped (not touched):"
      local note
      for note in "${dir_skip[@]}"; do
        printf '  - %s\n' "$note"
      done
    fi
    exit 0
  fi

  echo "The following directories will be moved into documents/:"
  echo ""
  local i
  for i in "${!move_rel[@]}"; do
    printf '  - %s\n' "${move_rel[$i]}"
  done

  if [[ ${#dir_skip[@]} -gt 0 ]]; then
    echo ""
    echo "Skipped (not touched):"
    local note
    for note in "${dir_skip[@]}"; do
      printf '  - %s\n' "$note"
    done
  fi

  if [[ "$CHECK_MODE" == "true" ]]; then
    echo ""
    echo "${#move_rel[@]} change(s) would be applied."
    exit 0
  fi

  if [[ "$FORCE_MODE" == "true" ]]; then
    echo ""
    echo "[--force mode: applying changes without confirmation.]"
  elif [[ ! -t 0 ]]; then
    # stdin no es un terminal: no hay forma de pedir confirmación. Nunca aplicar
    # (ni cancelar) en silencio — exigir que se corra interactivo o con un modo explícito.
    echo ""
    echo "${RED}[ERROR] Standard input is not a terminal — cannot ask for confirmation.${NC}" >&2
    echo "${YELLOW}Re-run interactively, or use --force to apply, or --check to preview.${NC}" >&2
    exit 1
  else
    echo ""
    read -r -p "Move these directories into documents/? (Y/s) " answer
    case "${answer,,}" in
      y | s) ;;
      *)
        echo ""
        echo "Update cancelled. No changes were made."
        exit 0
        ;;
    esac
  fi

  echo ""
  echo "Updating..."
  local applied=0 rel_src rel_dst
  for i in "${!move_rel[@]}"; do
    src="${move_src[$i]}"
    dst="${move_dst[$i]}"
    mkdir -p "$(dirname "$dst")" || {
      echo "  [ERROR] Failed to create directory for ${move_rel[$i]}" >&2
      exit 1
    }
    # Corte limpio sin symlinks: 'git mv' si el origen está trackeado, si no 'mv' plano.
    rel_src="${src#$target_root/}"
    rel_dst="${dst#$target_root/}"
    if git -C "$target_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
        git -C "$target_root" ls-files --error-unmatch -- "$rel_src" >/dev/null 2>&1; then
      git -C "$target_root" mv -- "$rel_src" "$rel_dst" || {
        echo "  [ERROR] Failed to move ${move_rel[$i]}" >&2
        exit 1
      }
    elif ! mv "$src" "$dst"; then
      echo "  [ERROR] Failed to move ${move_rel[$i]}" >&2
      exit 1
    fi
    printf '  [MOVED] %s\n' "${move_rel[$i]}"
    applied=$((applied + 1))
  done

  echo ""
  echo "Done. $applied change(s) applied."
  exit 0
}

# Resolución del target de --update-directory (<dir> obligatorio). Acepta ruta
# relativa (contra $PWD) o absoluta; debe ser un directorio existente (no se crea).
UPDATE_TARGET=""
if [[ "$UPDATE_DIRECTORY" == "true" ]]; then
  _raw_target="$UPDATE_DIR_TARGET"
  [[ "$_raw_target" != /* ]] && _raw_target="$PWD/$_raw_target"
  if [[ ! -d "$_raw_target" ]]; then
    echo "[ERROR] --update-directory requires an existing directory: $UPDATE_DIR_TARGET" >&2
    exit 1
  fi
  UPDATE_TARGET="$(cd "$_raw_target" && pwd)"
fi

if [[ "$UPDATE_DIRECTORY" == "true" ]]; then update_directories "$UPDATE_TARGET"; fi

# ============================================================================
# Modo normal (default): despliega agents, styles y commands.
# Las tools NO se instalan por defecto.
# ============================================================================

mkdir -p "$DEST_DIR" "$SKILLS_DEST" "$STYLES_DEST" "$COMMANDS_DEST"

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

# Cola de cambios pendientes (compartida por los stages).
declare -a pending_stage=() pending_rel=() pending_src=() pending_dst=() pending_kind=() pending_ver=()
declare -a skipped_note=()
changed=0

queue_change() {
  local stage="$1" rel="$2" src="$3" dst="$4" kind="$5" verstr="$6"
  pending_stage+=("$stage"); pending_rel+=("$rel")
  pending_src+=("$src"); pending_dst+=("$dst")
  pending_kind+=("$kind"); pending_ver+=("$verstr")
  changed=$((changed + 1))
}

echo "Checking custom files in the repo against your installed copies..."
echo "  Agents:   $AGENTS_SRC -> $DEST_DIR"
if [[ "$SKIP_SKILLS" == "true" ]]; then
  echo "  Skills:   (skipped --no-skills)"
else
  echo "  Skills:   $AGENTS_SRC/*/skills/ -> $SKILLS_DEST"
fi
if [[ "$SKIP_STYLES" == "true" ]]; then
  echo "  Styles:   (skipped --no-styles)"
else
  echo "  Styles:   $STYLES_SRC -> $STYLES_DEST"
fi
if [[ "$SKIP_COMMANDS" == "true" ]]; then
  echo "  Commands: (skipped --no-commands)"
else
  echo "  Commands: $COMMANDS_SRC -> $COMMANDS_DEST"
fi
echo "  Tools:    ${YELLOW}(no instaladas por defecto; usa --install-tools para instalarlas)${NC}"
echo ""

# --- Stage 1: agents (version + checksum) ---
declare -a managed_rel=() managed_src=()
while IFS= read -r src; do
  is_agent_file "$src" || continue
  rel="$(realpath --relative-to="$AGENTS_SRC" "$src")"
  # Las skills viven bajo <agente>/skills/ y NO son agentes (deploy a skills/).
  [[ "$rel" == *"/skills/"* ]] && continue
  managed_rel+=("$rel")
  managed_src+=("$src")
done < <(find "$AGENTS_SRC" -type f -iname '*.md' ! -iname 'readme.md' | sort)

if [[ ${#managed_rel[@]} -eq 0 ]]; then
  echo "[ERROR] No custom agents found under $AGENTS_SRC." >&2
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

for i in "${!managed_rel[@]}"; do
  rel="${managed_rel[$i]}"
  src="${managed_src[$i]}"
  dst="${DEST_DIR}/${rel}"
  src_ver="$(agent_version "$src")"

  if [[ ! -f "$dst" ]]; then
    queue_change "agents" "$rel" "$src" "$dst" "INSTALL" "version $src_ver"
    continue
  fi

  dst_ver="$(agent_version "$dst")"
  src_hash="$(sha256sum "$src" | awk '{print $1}')"
  dst_hash="$(sha256sum "$dst" | awk '{print $1}')"

  if [[ "$src_ver" -gt "$dst_ver" ]]; then
    queue_change "agents" "$rel" "$src" "$dst" "UPDATE" "version $dst_ver -> $src_ver"
  elif [[ "$src_ver" -eq "$dst_ver" ]]; then
    if [[ "$src_hash" != "$dst_hash" ]]; then
      # Misma versión pero contenido distinto: la copia instalada fue editada localmente.
      queue_change "agents" "$rel" "$src" "$dst" "REPLACE" "version $src_ver"
    fi
  else
    skipped_note+=("$rel (installed version $dst_ver is newer than repo version $src_ver)")
  fi
done

# --- Stage 2 y 3: styles y commands (checksum sha256, sin version) ---
# keep_readme: 1 = incluir README.md (usado por styles, cuyo README aporta
# contexto a los agentes); 0 = excluirlo (commands/tools).
sync_plain() {
  local stage="$1" src_dir="$2" dst_dir="$3" keep_readme="${4:-0}"
  [[ -d "$src_dir" ]] || return 0
  while IFS= read -r src; do
    if [[ "$keep_readme" != "1" && "$(basename "$src")" == "README.md" ]]; then
      continue
    fi
    rel="$(realpath --relative-to="$src_dir" "$src")"
    dst="${dst_dir}/${rel}"
    src_hash="$(sha256sum "$src" | awk '{print $1}')"
    if [[ ! -f "$dst" ]]; then
      queue_change "$stage" "$rel" "$src" "$dst" "INSTALL" "(checksum)"
    else
      dst_hash="$(sha256sum "$dst" | awk '{print $1}')"
      if [[ "$src_hash" != "$dst_hash" ]]; then
        queue_change "$stage" "$rel" "$src" "$dst" "UPDATE" "(checksum)"
      fi
    fi
  done < <(find "$src_dir" -type f | sort)
}

# --- Stage 2: skills (checksum sha256) ---
# Las skills viven en src/agents/<agente>/skills/<nombre>/ y se despliegan a
# ~/.config/opencode/skills/<nombre>/. OpenCode las detecta como skills/*/SKILL.md
# (un nivel: cada carpeta <nombre> debe contener SKILL.md) y exige nombres de
# skill únicos en todos los ámbitos, así que se detectan duplicados.
skills_stage() {
  local src_dir="$1" dst_dir="$2"
  [[ -d "$src_dir" ]] || return 0
  declare -a skill_files=()
  while IFS= read -r f; do skill_files+=("$f"); done \
    < <(find "$src_dir" -type f -path '*/skills/*/SKILL.md' | sort)
  [[ ${#skill_files[@]} -eq 0 ]] && return 0

  declare -A seen_skill=()
  local rel skill lower
  for f in "${skill_files[@]}"; do
    rel="${f##*/skills/}"
    skill="${rel%%/*}"
    lower="$(printf '%s' "$skill" | tr '[:upper:]' '[:lower:]')"
    if [[ -n "${seen_skill[$lower]+x}" ]]; then
      echo "[ERROR] Duplicate skill name '$skill' found in the repo." >&2
      echo "OpenCode requires unique skill names across all locations." >&2
      exit 1
    fi
    seen_skill[$lower]=1
  done

  while IFS= read -r src; do
    rel="${src##*/skills/}"
    dst="${dst_dir}/${rel}"
    src_hash="$(sha256sum "$src" | awk '{print $1}')"
    if [[ ! -f "$dst" ]]; then
      queue_change "skills" "$rel" "$src" "$dst" "INSTALL" "(checksum)"
    else
      dst_hash="$(sha256sum "$dst" | awk '{print $1}')"
      if [[ "$src_hash" != "$dst_hash" ]]; then
        queue_change "skills" "$rel" "$src" "$dst" "UPDATE" "(checksum)"
      fi
    fi
  done < <(find "$src_dir" -type f -path '*/skills/*' | sort)
}

[[ "$SKIP_SKILLS" == "true" ]] || skills_stage "$AGENTS_SRC" "$SKILLS_DEST"
[[ "$SKIP_STYLES" == "true" ]] || sync_plain "styles" "$STYLES_SRC" "$STYLES_DEST" 1
[[ "$SKIP_COMMANDS" == "true" ]] || sync_plain "commands" "$COMMANDS_SRC" "$COMMANDS_DEST" 0

if [[ "$CHECK_MODE" == "true" ]]; then
  echo "[--check mode: showing what would change. No changes will be made.]"
  echo ""
fi

if [[ "$changed" -eq 0 ]]; then
  echo "All custom agents, skills, styles and commands are up to date. Nothing to do."
  echo "(Tools are not installed by default; use --install-tools to install them.)"
  exit 0
fi

echo "The following ${RED}custom files changed${NC} in the repo compared to your installed copies:"
echo ""
for i in "${!pending_rel[@]}"; do
  case "${pending_kind[$i]}" in
    INSTALL) note="will be installed (${pending_ver[$i]})" ;;
    UPDATE) note="will be updated (${pending_ver[$i]})" ;;
    REPLACE) note="was modified locally and will be replaced (${pending_ver[$i]})" ;;
  esac
  printf '%s  %s\n' "${RED}- [${pending_stage[$i]}] ${pending_rel[$i]}${NC}" "$note"
done

if [[ ${#skipped_note[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped (not touched):"
  for note in "${skipped_note[@]}"; do
    printf '  - %s\n' "$note"
  done
fi

echo ""
echo "${YELLOW}These files will be REPLACED in your opencode configuration.${NC}"
echo "${YELLOW}WARNING: If you made local changes to any of these files, those changes${NC}"
echo "${YELLOW}will be lost. It is your responsibility to back them up first if you want${NC}"
echo "${YELLOW}to keep them.${NC}"
echo ""
echo "Only the files under src/agents/, src/tools/ (incl. css-styles/) and"
echo "src/commands/ are managed by this script (skills via src/agents/*/skills/)."
echo "The default OpenCode agents (build, plan) and any other user files are never touched."

if [[ "$CHECK_MODE" == "true" ]]; then
  echo ""
  echo "$changed change(s) would be applied."
  exit 0
fi

if [[ "$FORCE_MODE" == "true" ]]; then
  echo ""
  echo "[--force mode: applying changes without confirmation.]"
elif [[ ! -t 0 ]]; then
  # stdin no es un terminal: no hay forma de pedir confirmación. Nunca aplicar
  # (ni cancelar) en silencio — exigir que se corra interactivo o con un modo explícito.
  echo ""
  echo "${RED}[ERROR] Standard input is not a terminal — cannot ask for confirmation.${NC}" >&2
  echo "${YELLOW}Re-run interactively, or use --force to apply, or --check to preview.${NC}" >&2
  exit 1
else
  echo ""
  read -r -p "Do you want to continue and apply these changes? (Y/s) " answer
  case "${answer,,}" in
    y | s) ;;
    *)
      echo ""
      echo "Update cancelled. No changes were made."
      for i in "${!pending_rel[@]}"; do
        printf '  [NOT UPDATED] [%s] %s\n' "${pending_stage[$i]}" "${pending_rel[$i]}"
      done
      exit 0
      ;;
  esac
fi

echo ""
echo "Updating..."
updated=0
for i in "${!pending_rel[@]}"; do
  kind="${pending_kind[$i]}"
  rel="${pending_rel[$i]}"
  dst="${pending_dst[$i]}"
  mkdir -p "$(dirname "$dst")" || {
    echo "  [ERROR] Failed to create directory for $rel" >&2
    exit 1
  }
  if ! cp -f "${pending_src[$i]}" "$dst"; then
    echo "  [ERROR] Failed to copy $rel" >&2
    exit 1
  fi
  case "$kind" in
    INSTALL) msg="[INSTALLED] ${pending_stage[$i]}/$rel (${pending_ver[$i]})" ;;
    UPDATE) msg="[UPDATED] ${pending_stage[$i]}/$rel (${pending_ver[$i]})" ;;
    REPLACE) msg="[REPLACED] ${pending_stage[$i]}/$rel (${pending_ver[$i]})" ;;
  esac
  printf '  %s\n' "$msg"
  updated=$((updated + 1))
done

echo ""
echo "Done. $updated change(s) applied."
