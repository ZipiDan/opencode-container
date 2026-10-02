#!/bin/bash
# opencode.sh — launcher de opencode en contenedor Podman.
# VERSION y TAG_RELEASE: bumpear ambos al liberar una nueva versión.
# VERSION sigue semver (major.minor.patch). El tag de git es v$VERSION.

# ==========================
# CONFIGURACIÓN GENERAL (EDITABLE)
# ==========================
VERSION="3.7.0"
TAG_RELEASE="v3.7.0"
# Ruta fija para la configuración global (opencode.json con API keys, providers, etc.)
# No se ve afectada por -config, siempre en $HOME/.config/opencode/
GLOBAL_CONFIG_DIR="${HOME}/.config/opencode"
# Datos globales de opencode (auth.json, BD de cuentas, repos)
# Se ubican dentro de la config global para centralizar todo el estado del usuario.
# Se montan en XDG_DATA_HOME/opencode dentro del contenedor.
GLOBAL_DATA_DIR="${GLOBAL_CONFIG_DIR}/share"
# Subdirectorio por defecto para datos del proyecto (state, data, python)
DEFAULT_PROJECT_DATA_SUBDIR=".opencode"
# Contenido del anchor opencode.jsonc creado en proyectos sin .git ni config
# per-project. Fija el project root dentro del contenedor. Editable por el usuario.
PROJECT_ANCHOR_CONTENT='{
  "$schema": "https://opencode.ai/config.json",
  "lsp": true
}'
CONTAINER_NAME="opencode"
# Rutas internas del contenedor (XDG Base Directory Specification)
XDG_CONFIG_HOME_IN_CONTAINER="/home/opencode/.config"
XDG_STATE_HOME_IN_CONTAINER="/home/opencode/.local/state"
XDG_DATA_HOME_IN_CONTAINER="/home/opencode/.local/share"
# Identidad git del agente por defecto, luego puedes cambiar estos valores dentro del ~/.config/opencode/identity/
AGENT_GIT_NAME="OpenCode Agent"
AGENT_GIT_EMAIL="agent@opencode.local"

# Puerto por defecto del servidor web de opencode
DEFAULT_PORT=4096

# Imagen de Podman a utilizar
# OPENCODE_IMAGE="ghcr.io/anomalyco/opencode:latest"
# OPENCODE_IMAGE="ghcr.io/anomalyco/opencode:1.15.10"
# OPENCODE_IMAGE="opencode-python:latest"
OPENCODE_IMAGE="opencode-debian:latest"
# OPENCODE_IMAGE="ghcr.io/anomalyco/opencode:1.17.3"

# ==========================
# COLORES ANSI
# ==========================
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# ==========================
# FUNCIONES AUXILIARES
# ==========================

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
    ubuntu | debian | linuxmint | pop | kali | raspbian) echo "debian" ;;
    fedora | centos | rhel | rocky | almalinux | amzn) echo "redhat" ;;
    arch | manjaro | endeavouros) echo "arch" ;;
    opensuse* | sles) echo "suse" ;;
    alpine) echo "alpine" ;;
    *) echo "other" ;;
    esac
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos"
  else
    echo "unknown"
  fi
}

check_podman() {
  if command -v podman &>/dev/null; then
    return 0
  fi

  echo -e "${RED}[ERROR]${NC} Podman no está instalado en este sistema."
  echo -e "${YELLOW}[INFO]${NC} Para ejecutar este script, necesitas instalar Podman."
  echo -e "${YELLOW}[INFO]${NC} Según tu sistema operativo, ejecuta uno de los siguientes comandos:"
  echo ""

  local distro
  distro=$(detect_distro)

  case "$distro" in
  debian)
    echo "  🐧 Debian/Ubuntu y derivados:"
    echo "     sudo apt update && sudo apt install -y podman"
    ;;
  redhat)
    echo "  🐧 RHEL/Fedora/CentOS/Rocky/Alma y derivados:"
    echo "     sudo dnf install -y podman"
    ;;
  arch)
    echo "  🐧 Arch Linux y derivados:"
    echo "     sudo pacman -S podman"
    ;;
  suse)
    echo "  🐧 openSUSE/SLES:"
    echo "     sudo zypper install -y podman"
    ;;
  alpine)
    echo "  🐧 Alpine Linux:"
    echo "     sudo apk add podman"
    ;;
  macos)
    echo "  🍎 macOS:"
    echo "     brew install podman"
    ;;
  *)
    echo "  ❓ Sistema no reconocido. Visita la documentación oficial:"
    echo "     https://podman.io/getting-started/installation"
    ;;
  esac
  echo ""
  exit 1
}

show_help() {
  cat <<EOF
${BLUE}Uso:${NC} $0 <ruta_del_proyecto> [-config <ruta>] [--port <puerto>] [--tui] [--no-climb] [--rebuild] [--update] [--network-host] [--password <pwd>] [--user <usuario>] [--auto|--no-auto]
       $0 --rebuild
       $0 --update
       $0 --renew
       $0 --ps | --ls
       $0 --kill <patrón> | --rm <patrón>
       $0 --kill-all | --killall
       $0 --version
       $0 -h | --help

${BLUE}Descripción:${NC}
     opencode.sh ${VERSION} (${TAG_RELEASE})
     Lanza opencode en un contenedor Podman (basado en Debian stable-backports),
     montando el proyecto y separando los datos en dos ámbitos.

     Resolución de project root: si <ruta_del_proyecto> es un subdirectorio
     de un repo git, el launcher trepa buscando .git (tope en $HOME) y monta
     la raíz real. Usá --no-climb (alias --no-search-git) para desactivarlo.
     Si el proyecto no tiene .git ni opencode.json(c), se crea un anchor
     opencode.jsonc idempotente para fijar el root dentro del contenedor.

       Global (siempre en ~/.config/opencode/):
         opencode.json      → API keys, proveedores, modelos, permisos.
         agents/, commands/ → agentes y comandos personalizados.
         identity/          → identidad git/ssh del agente.
         share/             → datos de opencode compartidos:
           auth.json        → credenciales (/connect).
           db/              → cuentas OAuth (GitHub, GitLab, etc.).
           repos/           → clones internos.
         No se ve afectado por -config.

       Del proyecto (por defecto <proyecto>/${DEFAULT_PROJECT_DATA_SUBDIR}/):
         state/             → file locks de ejecución (efímero).
         data/storage/      → sesiones, mensajes, metadatos (aislado).
         data/snapshot/     → snapshots de git para undo/revert (aislado).
         data/log/          → logs de ejecución (aislado).
         rust/              → CARGO_HOME/CARGO_TARGET_DIR per-proyecto:
                              registry/, target/ y bin/ de cargo (aislado).
                            Se crea en la raíz del proyecto y se agrega al
                            .gitignore automáticamente (junto con python/ y
                            los temporales).

       Python (venv-first): el venv canónico del proyecto vive en la carpeta
       python/ de la raíz (<proyecto>/python/). El entrypoint lo crea
       automáticamente en el primer arranque (si falta) y lo activa en cada
       arranque. Ya está ignorado por el .gitignore (entrada python/).
       No se usa pip --user ni PYTHONUSERBASE.

     Usa -config <ruta> para redirigir state/ y data/
     a una ubicación personalizada.

${BLUE}Parámetros:${NC}
    <ruta_del_proyecto>          Ruta al directorio del proyecto.
                                 Obligatorio salvo con --rebuild, --update o --renew.
    -config <ruta>               Ruta para state/ y data/.
                                 Por defecto: <proyecto>/${DEFAULT_PROJECT_DATA_SUBDIR}/
    --port <puerto>              Puerto donde se servirá opencode web.
                                 Por defecto: ${DEFAULT_PORT}
    --tui, --no-web              Inicia la TUI de opencode en lugar del
                                 servidor web (ignora --port).
    --network-host               Comparte la red del host con el contenedor
                                 (equivale a --network host de Podman).
                                 Permite que el contenedor acceda a puertos
                                 y servicios que corren en el host (p.ej.
                                 en 127.0.0.1). Se pierde el aislamiento de
                                 red. En modo web el puerto se publica
                                 automáticamente (se omite -p).

    --no-climb, --no-search-git  Desactiva la resolución del project root.
                                 Si pasás una subcarpeta de un proyecto,
                                 opencode trabaja exactamente en esa ruta.
    --auto                       Auto-aprueba los permisos de opencode
                                 (sin prompts; es el valor por defecto en el
                                 contenedor). Se inyecta OPENCODE_PERMISSION.
    --no-auto                    Desactiva la auto-aprobación: opencode vuelve
                                 a pedir confirmación (p. ej. para acceder a
                                 carpetas fuera del workspace).
                                 El env OPENCODE_PERMISSION del host tiene
                                 prioridad sobre ambos flags.
    --password <pwd>             Activa auth básica en el servidor web con el
                                 password indicado (solo web, se ignora en TUI).
                                 Si no se pasa, se usa la variable de entorno
                                 OPENCODE_SERVER_PASSWORD del host (si existe).
    --user <usuario>             Usuario para la auth básica web. Por defecto
                                 opencode usa 'opencode'. Prioridad: flag --user
                                 > OPENCODE_SERVER_USERNAME del host.
    --rebuild                    Reconstruye la imagen desde el Containerfile
                                 (usando caché de capas).
    --update                     Reconstruye la imagen desde cero:
                                 1. podman pull docker.io/debian:stable-backports
                                 2. podman build --no-cache --pull
                                 Actualiza imagen base, apt, pip y opencode.
    --renew                      Reconstruye la imagen desde cero y reemplaza
                                 la anterior solo si el build es exitoso.
                                 Si falla, la imagen anterior no se modifica.
                                 ⚠ DETIENE cualquier contenedor activo
                                 que esté usando la imagen anterior.
    --ps, --ls                   Lista los contenedores opencode en ejecución
                                 (ID, nombre, status, modo, puerto, proyecto).
    --kill <patrón>              Detiene un contenedor opencode en ejecución.
    --rm <patrón>                Alias de --kill. El patrón puede ser:
                                 nombre exacto (opencode-tui2, opencode-4096),
                                 forma corta (tui2, 2, 4096). Si el patrón no
                                 encuentra exactamente 1 contenedor no actúa.
    --kill-all                   Detiene TODOS los contenedores opencode en
                                 ejecución (web y TUI). Pide confirmación
                                 antes de actuar si el terminal lo permite.
                                 Alias: --killall.

${BLUE}Combinaciones de parámetros:${NC}
    Los parámetros se separan en tres mundos mutuamente excluyentes:

      • Mundo IMAGEN:    --renew | --rebuild | --update   (gestionan la imagen)
      • Mundo GESTIÓN:  --ps/--ls (listar) | --kill/--rm <patrón> | --kill-all (detener)
      • Mundo EJECUCIÓN:  <proyecto> + [-config] [--port] [--tui] [--network-host]
                          [--password <pwd>] [--user <usuario>] [--auto|--no-auto]

    Árbol de combinaciones válidas (-h es compatible con cualquier rama):

    parámetros
    ├── --renew                actualiza la imagen reconstruyendo desde cero;
    │                          elimina la anterior si el build es exitoso
    ├── --rebuild              reconstruye imagen usando caché
    ├── --update               actualiza imagen desde cero
    ├── --ps | --ls            muestra contenedores opencode en ejecución
    ├── --kill <patrón>        detiene un contenedor opencode (alias --rm)
    │       Patrones: nombre exacto (opencode-tui2, opencode-4096)
    │                 o forma corta: tui2 / 2 / 4096
    │       Si el patrón no matchea o matchea varios, no se actúa.
    ├── --kill-all             detiene TODOS los contenedores opencode
    │                          (web y TUI; pide confirmación; alias --killall)
    └── <proyecto>             lanza opencode en el proyecto
        ├── --no-climb         desactiva la búsqueda de .git hacia atrás
        │                      (también: --no-search-git)
        ├── --auto | --no-auto auto-aprueba permisos (default: --auto)
        ├── --tui              arranca terminal interactiva (nombre: opencode-tuiN)
        │   ├── -config <ruta>
        │   └── --network-host
        └── web (sin --tui)   arranca servidor web (nombre: opencode-<puerto>)
            ├── --port <1-65535>   (default ${DEFAULT_PORT})
            ├── --password <pwd>   activa auth básica web
            ├── --user <usuario>   usuario de la auth (default: opencode)
            ├── -config <ruta>
            └── --network-host

    Reglas clave:
      • No mezclar flags de mundos distintos (IMAGEN/GESTIÓN/EJECUCIÓN).
      • --renew y --rebuild son mutuamente excluyentes.
      • --ps/--ls, --kill/--rm y --kill-all son mutuamente excluyentes entre sí.
      • --tui ignora --port (no hay servidor web).
      • --password/--user aplican solo a web; en TUI se avisan y se ignoran.
      • Prioridad auth: flag --password/--user > env OPENCODE_SERVER_PASSWORD/
        OPENCODE_SERVER_USERNAME del host.

${BLUE}Ejemplos:${NC}
    $0 /home/usuario/mi-proyecto
    $0 ./proyecto/subdir      # busca .git hacia arriba para encontrar la raíz del proyecto
    $0 ./proyecto/subdir --no-climb  # no busca la raíz; trabaja en la subcarpeta
    $0 ./proyecto -config /mnt/opencode-data
    $0 ./proyecto --port 4097
    $0 ./proyecto --tui
    $0 ./proyecto --network-host
    $0 ./proyecto --password "secreto"
    $0 ./proyecto --password "secreto" --user "admin"
    $0 --update
    $0 --renew
    $0 --ps
    $0 --kill tui2
    $0 --rm opencode-4096
    $0 --kill-all

${BLUE}Nota:${NC}
    Config global (API keys, share)    → ${GLOBAL_CONFIG_DIR}/  (no afectado por -config)
    Datos del proyecto (sesiones, etc) → controlado por -config
    --network-host rompe el aislamiento de red del contenedor (uso de red
    del host). Úsalo solo cuando necesites alcanzar servicios del host.
    --no-climb impide la resolución automática de .git hacia arriba.
    Proyectos sin .git ni config reciben un anchor opencode.jsonc en el
    project root para fijar el root dentro del contenedor (idempotente).
    El .gitignore del proyecto se completa automáticamente con .opencode/,
    rust/, python/ (directorio del venv en la raíz) y los temporales
    (*.tmp, *.swp, *~) si faltan.
    --password/--user activan auth básica HTTP en el servidor web (env vars
    OPENCODE_SERVER_PASSWORD/OPENCODE_SERVER_USERNAME al contenedor). La TUI
    no usa auth; los flags se ignoran en modo TUI.
    --auto/--no-auto controlan la auto-aprobación de permisos de opencode.
    Por defecto el contenedor auto-aprueba (sandbox aislado): no pide permiso
    para acceder a carpetas ni ejecutar herramientas. Usá --no-auto si querés
    que opencode vuelva a pedir confirmación, u OPENCODE_PERMISSION del host
    para reglas de permisos personalizadas (JSON inline).
EOF
}

error_exit() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
  exit 1
}

setup_global_config() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Creando configuración global en: ${dir}"
    mkdir -p "$dir" || error_exit "No se pudo crear ${dir}"
    echo -e "${GREEN}[OK]${NC} Estructura global creada."
  else
    echo -e "${GREEN}[OK]${NC} Configuración global encontrada en: ${dir}"
  fi

  # Datos globales de opencode: auth.json, BD de cuentas OAuth, repos internos.
  # Se montan en el contenedor bajo XDG_DATA_HOME/opencode-global/ y se
  # exponen al proyecto mediante symlinks, de modo que opencode.db y los
  # demás datos del proyecto permanezcan aislados por proyecto.
  mkdir -p "${dir}/share" || error_exit "No se pudo crear ${dir}/share"
  mkdir -p "${dir}/share/db" || error_exit "No se pudo crear ${dir}/share/db"
  mkdir -p "${dir}/share/repos" || error_exit "No se pudo crear ${dir}/share/repos"
  if [[ ! -f "${dir}/share/auth.json" ]]; then
    echo '{}' >"${dir}/share/auth.json" || error_exit "No se pudo crear ${dir}/share/auth.json"
    chmod 600 "${dir}/share/auth.json"
  fi

  # Asegurar subcarpetas de identidad del agente (idempotente)
  mkdir -p "${dir}/identity/ssh" || error_exit "No se pudo crear ${dir}/identity/ssh"
  touch "${dir}/identity/gitconfig" 2>/dev/null || true
  chmod 700 "${dir}/identity/ssh"
}

setup_project_dirs() {
  local base="$1"
  # data/ se monta directamente como XDG_DATA_HOME/opencode/ dentro del
  # contenedor, por lo que storage/, snapshot/, log/ y opencode.db viven
  # ahí de forma aislada por proyecto.
  local subdirs=("data" "state")
  local all_exist=true

  for sub in "${subdirs[@]}"; do
    if [[ ! -d "${base}/${sub}" ]]; then
      all_exist=false
      break
    fi
  done

  if $all_exist; then
    echo -e "${GREEN}[OK]${NC} Datos del proyecto encontrados en: ${base}"
  else
    echo -e "${YELLOW}[INFO]${NC} Creando estructura de datos del proyecto en: ${base}"
    for sub in "${subdirs[@]}"; do
      mkdir -p "${base}/${sub}" || error_exit "No se pudo crear ${base}/${sub}"
    done
    echo -e "${GREEN}[OK]${NC} Estructura del proyecto creada correctamente."
  fi
}

# Agrega una entrada al .gitignore si no existe. Devuelve 0 si la agregó.
ensure_gitignore_entry() {
  local file="$1" entry="$2"
  if ! grep -qxF "$entry" "$file"; then
    printf '%s\n' "$entry" >>"$file"
    return 0
  fi
  return 1
}

# Gestiona el .gitignore del proyecto: crea uno por defecto si no existe (con
# rust/, python/ y la sección de archivos temporales); si existe, agrega las
# entradas faltantes. Idempotente.
# Desde v2.7.0-pre1 permite versionar agentes/skills/commands locales en
# .opencode/{agents,skills,commands}/ mediante excepciones !.
setup_project_gitignore() {
  local project="$1"
  local gitignore="${project}/.gitignore"
  local changed=false

  if [[ ! -f "$gitignore" ]]; then
    cat >"$gitignore" <<'EOF'
.opencode/*
!.opencode/agents/
!.opencode/agents/**
!.opencode/skills/
!.opencode/skills/**
!.opencode/commands/
!.opencode/commands/**
rust/
python/

# Archivos temporales
*.tmp
*.swp
*~
EOF
    echo -e "${GREEN}[OK]${NC} .gitignore creado en: ${project}"
    changed=true
  else
    # Migrar .opencode/ legacy (no permite re-include) → .opencode/* (sí permite)
    if grep -qxF ".opencode/" "$gitignore"; then
      sed -i '\|^\.opencode/$|d' "$gitignore"
      changed=true
    fi
    ensure_gitignore_entry "$gitignore" ".opencode/*" && changed=true
    # Excepciones para agentes/skills/commands locales versionables (v2.7.0-pre1)
    ensure_gitignore_entry "$gitignore" "!.opencode/agents/" && changed=true
    ensure_gitignore_entry "$gitignore" "!.opencode/agents/**" && changed=true
    ensure_gitignore_entry "$gitignore" "!.opencode/skills/" && changed=true
    ensure_gitignore_entry "$gitignore" "!.opencode/skills/**" && changed=true
    ensure_gitignore_entry "$gitignore" "!.opencode/commands/" && changed=true
    ensure_gitignore_entry "$gitignore" "!.opencode/commands/**" && changed=true
    ensure_gitignore_entry "$gitignore" "rust/" && changed=true
    ensure_gitignore_entry "$gitignore" "python/" && changed=true

    if ! grep -qxF "# Archivos temporales" "$gitignore"; then
      printf '\n# Archivos temporales\n' >>"$gitignore"
      changed=true
    fi
    ensure_gitignore_entry "$gitignore" "*.tmp" && changed=true
    ensure_gitignore_entry "$gitignore" "*.swp" && changed=true
    ensure_gitignore_entry "$gitignore" "*~" && changed=true

    if [[ "$changed" == "true" ]]; then
      echo -e "${GREEN}[OK]${NC} .gitignore actualizado en: ${project}"
    fi
  fi

  # Estructura local versionable para agentes/skills/commands (idempotente)
  for d in "${project}/.opencode/agents" "${project}/.opencode/skills" "${project}/.opencode/commands"; do
    if [[ ! -d "$d" ]]; then
      mkdir -p "$d" 2>/dev/null || continue
    fi
    if [[ -z "$(ls -A "$d" 2>/dev/null)" ]]; then
      touch "$d/.gitkeep" 2>/dev/null || true
    fi
  done
}

# Resuelve el project root trepando hacia atrás buscando .git (dir o archivo,
# soporta worktrees). Nunca elige $HOME como root, para evitar que un repo de
# dotfiles en $HOME capture subdirectorios sueltos.
# Si no encuentra .git antes de / o $HOME, devuelve el path original.
resolve_project_root() {
  local path="$1" home_norm cur
  home_norm="$(realpath -m "$HOME")"
  cur="$(realpath -m "$path")"
  while [[ "$cur" != "/" && "$cur" != "$home_norm" ]]; do
    if [[ -e "${cur}/.git" ]]; then
      printf '%s\n' "$cur"
      return 0
    fi
    cur="$(dirname "$cur")"
  done
  printf '%s\n' "$(realpath -m "$path")"
}

# ==========================
# FUNCIONES DE GESTIÓN DE CONTENEDORES
# ==========================

# Calcula el siguiente nombre TUI disponible: opencode-tuiN con N = (max existente) + 1.
# No rellena huecos: si tui1 y tui3 están corriendo, devuelve tui4.
next_tui_name() {
  local max=0 n name
  while read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" =~ opencode-tui([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
      ((n > max)) && max=$n
    fi
  done < <(podman ps --filter "name=opencode-tui" --format "{{.Names}}" 2>/dev/null)
  echo "opencode-tui$((max + 1))"
}

# Lista contenedores opencode en ejecución con formato extendido.
# Columnas: ID, Nombre, Status, Modo, Puerto, Proyecto.
list_opencode_containers() {
  local id name status mode port project
  local has_containers=false

  printf "%-12s %-22s %-14s %-6s %-7s %s\n" \
    "ID" "NOMBRE" "STATUS" "MODO" "PUERTO" "PROYECTO"
  printf "%-12s %-22s %-14s %-6s %-7s %s\n" \
    "------------" "----------------------" "--------------" "------" "-------" "-------"

  while read -r name; do
    [[ -z "$name" ]] && continue
    has_containers=true

    id=$(podman ps --filter "name=^${name}\$" --format "{{.ID}}" 2>/dev/null | head -n1)
    status=$(podman ps --filter "name=^${name}\$" --format "{{.Status}}" 2>/dev/null | head -n1)

    if [[ "$name" =~ opencode-tui([0-9]+)$ ]]; then
      mode="tui"
      port="-"
    elif [[ "$name" =~ opencode-([0-9]+)$ ]]; then
      mode="web"
      port="${BASH_REMATCH[1]}"
    else
      mode="?"
      port="?"
    fi

    # Proyecto: buscar el mount cuyo destino sea /workspace
    project=$(podman inspect "$name" \
      --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' \
      2>/dev/null)

    printf "%-12s %-22s %-14s %-6s %-7s %s\n" \
      "${id:0:12}" "$name" "$status" "$mode" "$port" "$project"
  done < <(podman ps --filter "name=opencode-" --format "{{.Names}}" 2>/dev/null | sort)

  if [[ "$has_containers" == "false" ]]; then
    echo -e "${YELLOW}[INFO]${NC} No hay contenedores opencode en ejecución."
  fi
}

# Detiene un contenedor opencode por nombre exacto o patrón corto.
# Patrones aceptados:
#   opencode-tui2  (exacto)
#   opencode-4096  (exacto, web)
#   tui2           (expandido a opencode-tui2)
#   2              (expandido a opencode-2 [web] y opencode-tui2)
#   4096           (expandido a opencode-4096 [web] y opencode-tui4096 [TUI])
# Reglas:
#   - 0 matches  → no actúa, avisa
#   - >1 match   → no actúa, lista los candidatos y pide más especificidad
#   - 1 match    → podman stop y confirma
kill_opencode_container() {
  local pattern="$1"
  local -A seen=()
  local -a matches=()
  local -a candidates=()
  local c match

  # Construir lista de candidatos a probar
  candidates+=("$pattern")

  # tuiN → opencode-tuiN
  if [[ "$pattern" =~ ^tui([0-9]+)$ ]]; then
    candidates+=("opencode-tui${BASH_REMATCH[1]}")
  fi

  # N puro o puerto puro → opencode-N (web) y opencode-tuiN (TUI)
  if [[ "$pattern" =~ ^([0-9]+)$ ]]; then
    candidates+=("opencode-${BASH_REMATCH[1]}")
    candidates+=("opencode-tui${BASH_REMATCH[1]}")
  fi

  # Resolver candidatos contra podman (solo running)
  for c in "${candidates[@]}"; do
    while read -r match; do
      [[ -n "$match" && -z "${seen[$match]:-}" ]] && {
        seen[$match]=1
        matches+=("$match")
      }
    done < <(podman ps --filter "name=^${c}\$" --format "{{.Names}}" 2>/dev/null)
  done

  # Decidir según la cantidad de matches
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[INFO]${NC} No se encontró contenedor opencode en ejecución que coincida con '${pattern}'."
    echo -e "${YELLOW}[INFO]${NC} Usá --ps para ver los contenedores disponibles."
    return 1
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo -e "${YELLOW}[AVISO]${NC} ${#matches[@]} contenedores coinciden con '${pattern}':"
    printf "  • %s\n" "${matches[@]}"
    echo -e "${YELLOW}[AVISO]${NC} Sé más específico (usá el nombre completo). No se tomó ninguna acción."
    return 1
  fi

  # Exactamente un match → stop graceful
  echo -e "${BLUE}[INFO]${NC} Deteniendo contenedor: ${matches[0]}"
  if podman stop "${matches[0]}" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Contenedor '${matches[0]}' detenido correctamente."
    return 0
  else
    error_exit "No se pudo detener el contenedor '${matches[0]}'."
  fi
}

# Detiene TODOS los contenedores opencode en ejecución (web + TUI).
# Usa un prefijo regex (^opencode) para tocar únicamente los contenedores del
# launcher, no contenedores ajenos cuyo nombre solo contenga "opencode".
# Pide confirmación interactiva; si stdin no es un terminal, procede avisando.
kill_all_opencode_containers() {
  local -a names=()
  local name answer failed=0

  while read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(podman ps --filter "name=^opencode" --format "{{.Names}}" 2>/dev/null)

  if [[ ${#names[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[INFO]${NC} No hay contenedores opencode en ejecución."
    return 0
  fi

  echo -e "${YELLOW}[AVISO]${NC} Se detendrán ${#names[@]} contenedor(es) opencode:"
  printf "  • %s\n" "${names[@]}"

  if [[ -t 0 ]]; then
    read -r -p "¿Detener todos? (Y/n) " answer
    case "${answer,,}" in
      y | s | "") ;;
      *)
        echo "Cancelado. No se detuvo ningún contenedor."
        return 0
        ;;
    esac
  fi

  # Un solo `podman stop` con todos los nombres: podman los detiene en
  # paralelo internamente (mismo patrón que --renew con `xargs podman stop`).
  echo -e "${BLUE}[INFO]${NC} Deteniendo ${#names[@]} contenedores en paralelo..."
  if ! podman stop "${names[@]}" >/dev/null 2>&1; then
    failed=1
  fi

  # Verificar cuáles (si alguno) siguen en ejecución tras el stop
  local remaining
  remaining=$(podman ps --filter "name=^opencode" --format "{{.Names}}" 2>/dev/null | tr '\n' ' ')
  if [[ -n "$remaining" ]]; then
    echo -e "${RED}[ERROR]${NC} No se pudieron detener: $remaining" >&2
    failed=1
  fi

  if [[ "$failed" -eq 0 ]]; then
    echo -e "${GREEN}[OK]${NC} ${#names[@]} contenedores opencode detenidos."
  fi
  return "$failed"
}

# ==========================
# FUNCIONES DE CONSTRUCCIÓN DE IMAGEN
# ==========================

build_image() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local containerfile="${script_dir}/Containerfile"
  if [[ ! -f "$containerfile" ]]; then
    error_exit "No se encuentra Containerfile en ${containerfile}"
  fi
  echo -e "${YELLOW}[INFO]${NC} Construyendo imagen ${OPENCODE_IMAGE}..."
  podman build -t "${OPENCODE_IMAGE}" -f "$containerfile" "$script_dir" || error_exit "Falló la construcción de la imagen"
  echo -e "${GREEN}[OK]${NC} Imagen construida."
}

update_image() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local containerfile="${script_dir}/Containerfile"
  if [[ ! -f "$containerfile" ]]; then
    error_exit "No se encuentra Containerfile en ${containerfile}"
  fi
  echo -e "${YELLOW}[INFO]${NC} Actualizando imagen base docker.io/debian:stable-backports..."
  podman pull docker.io/debian:stable-backports || error_exit "Falló la actualización de la imagen base"
  echo -e "${YELLOW}[INFO]${NC} Reconstruyendo imagen ${OPENCODE_IMAGE} sin caché..."
  podman build --no-cache --pull -t "${OPENCODE_IMAGE}" -f "$containerfile" "$script_dir" || error_exit "Falló la reconstrucción de la imagen"
  echo -e "${GREEN}[OK]${NC} Imagen actualizada correctamente."
}

# Renueva la imagen atómicamente: build con tag temporal, y solo si el build
# es exitoso se reemplaza la imagen anterior. Si falla, la original queda intacta.
renew_image() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local containerfile="${script_dir}/Containerfile"
  if [[ ! -f "$containerfile" ]]; then
    error_exit "No se encuentra Containerfile en ${containerfile}"
  fi

  local staging_tag="${OPENCODE_IMAGE}-staging-$(date +%s)"

  # Verificar contenedores activos usando la imagen actual
  local running
  running=$(podman ps -q --filter "ancestor=${OPENCODE_IMAGE}" 2>/dev/null)
  local running_count
  running_count=$(echo "$running" | wc -l)
  if [[ -n "$running" ]]; then
    echo -e "${YELLOW}[AVISO]${NC} ${running_count} contenedor(es) activo(s) usando '${OPENCODE_IMAGE}'."
    echo -e "${YELLOW}[AVISO]${NC} Se detendrán para poder reemplazar la imagen."
    echo "$running" | xargs podman stop
    echo -e "${GREEN}[OK]${NC} Contenedores detenidos."
  fi

  echo -e "${YELLOW}[INFO]${NC} Actualizando imagen base docker.io/debian:stable-backports..."
  podman pull docker.io/debian:stable-backports || error_exit "Falló la actualización de la imagen base"

  echo -e "${YELLOW}[INFO]${NC} Construyendo nueva imagen con tag temporal '${staging_tag}'..."
  if podman build --no-cache --pull -t "${staging_tag}" -f "$containerfile" "$script_dir"; then
    # Build exitoso: reemplazar imagen anterior
    echo -e "${YELLOW}[INFO]${NC} Build exitoso. Reemplazando imagen anterior..."
    podman rmi "${OPENCODE_IMAGE}" 2>/dev/null || true
    podman tag "${staging_tag}" "${OPENCODE_IMAGE}"
    podman rmi "${staging_tag}" 2>/dev/null || true
    podman image prune -f 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Imagen renovada correctamente: '${OPENCODE_IMAGE}'"
  else
    # Build falló: eliminar solo la imagen temporal, la original no se modifica
    podman rmi "${staging_tag}" 2>/dev/null || true
    error_exit "Falló la renovación. La imagen anterior '${OPENCODE_IMAGE}' no fue modificada."
  fi
}

check_image() {
  if ! podman image exists "${OPENCODE_IMAGE}"; then
    echo -e "${YELLOW}[INFO]${NC} Imagen ${OPENCODE_IMAGE} no encontrada. Construyendo..."
    build_image
  fi
}

# ==========================
# FLUJO PRINCIPAL
# ==========================
# Referencia formal de combinaciones válidas: ver PARAMETERS.md
# (tabla única, árbol y BNF). El parser actual es permisivo por
# compatibilidad histórica con iteraciones 9-11; endurecerlo es
# un cambio de behavior de tratarse como breaking change.

PORT="$DEFAULT_PORT"
TUI_MODE=false
PROJECT_PATH=""
REBUILD=false
UPDATE=false
RENEW=false
PROJECT_DATA_DIR=""
NETWORK_HOST=false
NO_CLIMB=false
PS_MODE=false
KILL_MODE=false
KILL_PATTERN=""
KILL_ALL_MODE=false
PASSED_PORT_SET=false
SERVER_PASSWORD=""
SERVER_USERNAME=""
PASSWORD_SET=false
USER_SET=false
# Auto-aprobación de permisos en el contenedor (por defecto ON: el contenedor
# es un sandbox aislado y no debería pedir permiso para acceder a carpetas).
# --auto la fuerza; --no-auto la desactiva; el env OPENCODE_PERMISSION del host
# tiene prioridad si está seteado.
AUTO_APPROVE=true
AUTO_SET=false

# Parseo de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
  -config)
    if [[ -z "$2" ]]; then
      error_exit "La opción -config requiere una ruta como argumento."
    fi
    PROJECT_DATA_DIR="$2"
    shift 2
    ;;
  --port)
    if [[ -z "$2" ]]; then
      error_exit "La opción --port requiere un número de puerto como argumento."
    fi
    if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 65535 ]]; then
      error_exit "Puerto inválido: $2. Debe ser un número entre 1 y 65535."
    fi
    PORT="$2"
    PASSED_PORT_SET=true
    shift 2
    ;;
  --tui | --no-web)
    TUI_MODE=true
    shift
    ;;
  --rebuild)
    REBUILD=true
    shift
    ;;
  --update)
    UPDATE=true
    shift
    ;;
  --renew)
    RENEW=true
    shift
    ;;
  --network-host | --network_host)
    NETWORK_HOST=true
    shift
    ;;
  --no-climb | --no-search-git)
    NO_CLIMB=true
    shift
    ;;
  --auto)
    AUTO_APPROVE=true
    AUTO_SET=true
    shift
    ;;
  --no-auto)
    AUTO_APPROVE=false
    AUTO_SET=true
    shift
    ;;
  --password)
    if [[ -z "$2" ]]; then
      error_exit "La opción --password requiere un valor como argumento."
    fi
    SERVER_PASSWORD="$2"
    PASSWORD_SET=true
    shift 2
    ;;
  --user)
    if [[ -z "$2" ]]; then
      error_exit "La opción --user requiere un valor como argumento."
    fi
    SERVER_USERNAME="$2"
    USER_SET=true
    shift 2
    ;;
  --ps | --ls)
    PS_MODE=true
    shift
    ;;
  --kill | --rm)
    if [[ -z "$2" ]]; then
      error_exit "La opción $1 requiere un nombre o patrón como argumento."
    fi
    KILL_MODE=true
    KILL_PATTERN="$2"
    shift 2
    ;;
  --kill-all | --killall)
    KILL_ALL_MODE=true
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  --version)
    echo "opencode.sh ${VERSION} (${TAG_RELEASE})"
    exit 0
    ;;
  *)
    if [[ -z "$PROJECT_PATH" ]]; then
      PROJECT_PATH="$1"
      shift
    else
      error_exit "Argumento desconocido: $1"
    fi
    ;;
  esac
done

check_podman

# Validar exclusión mutua: --renew y --rebuild no pueden usarse juntos
if [[ "$RENEW" == "true" && "$REBUILD" == "true" ]]; then
  error_exit "Las opciones --renew y --rebuild no pueden usarse juntas."
fi

# Mundo GESTIÓN: --ps/--ls, --kill/--rm y --kill-all son mutuamente excluyentes
# entre sí y con cualquier flag de los mundos IMAGEN o EJECUCIÓN.
if [[ "$PS_MODE" == "true" || "$KILL_MODE" == "true" || "$KILL_ALL_MODE" == "true" ]]; then
  if [[ "$KILL_ALL_MODE" == "true" && ( "$PS_MODE" == "true" || "$KILL_MODE" == "true" ) ]]; then
    error_exit "Las opciones --kill-all y --ps/--ls/--kill/--rm son mutuamente excluyentes."
  fi
  if [[ "$PS_MODE" == "true" && "$KILL_MODE" == "true" ]]; then
    error_exit "Las opciones --ps/--ls y --kill/--rm son mutuamente excluyentes."
  fi
  if [[ "$RENEW" == "true" || "$REBUILD" == "true" || "$UPDATE" == "true" ||
    -n "$PROJECT_PATH" || "$TUI_MODE" == "true" || "$NETWORK_HOST" == "true" ||
    "$NO_CLIMB" == "true" || -n "$PROJECT_DATA_DIR" || "$PASSED_PORT_SET" == "true" ||
    "$PASSWORD_SET" == "true" || "$USER_SET" == "true" || "$AUTO_SET" == "true" ]]; then
    error_exit "Las opciones --ps/--ls/--kill/--rm/--kill-all (mundo GESTIÓN) no pueden combinarse con flags de otros mundos (IMAGEN/EJECUCIÓN)."
  fi
  # Ejecutar y salir (no requieren <proyecto> ni imagen)
  if [[ "$PS_MODE" == "true" ]]; then
    list_opencode_containers
    exit 0
  fi
  if [[ "$KILL_MODE" == "true" ]]; then
    kill_opencode_container "$KILL_PATTERN"
    exit $?
  fi
  if [[ "$KILL_ALL_MODE" == "true" ]]; then
    kill_all_opencode_containers
    exit $?
  fi
fi

if [[ "$RENEW" == "true" && -z "$PROJECT_PATH" ]]; then
  renew_image
  exit 0
fi

if [[ "$REBUILD" == "true" && -z "$PROJECT_PATH" ]]; then
  build_image
  exit 0
fi

if [[ "$UPDATE" == "true" && -z "$PROJECT_PATH" ]]; then
  update_image
  exit 0
fi

if [[ -z "$PROJECT_PATH" ]]; then
  show_help
  exit 1
fi

PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
PROJECT_PATH=$(realpath -m "$PROJECT_PATH") || error_exit "Ruta de proyecto inválida: $PROJECT_PATH"

if [[ ! -d "$PROJECT_PATH" ]]; then
  error_exit "El directorio del proyecto no existe: $PROJECT_PATH"
fi

# Resolución automática del project root: si se pasa un subdirectorio de un
# repo git, trepar hacia atrás (tope en $HOME) para montar la raíz real.
if [[ "$NO_CLIMB" == "false" ]]; then
  resolved_root="$(resolve_project_root "$PROJECT_PATH")"
  if [[ "$resolved_root" != "$PROJECT_PATH" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Project root resuelto a: ${resolved_root} (se encontró .git en un ancestro)."
    echo -e "${YELLOW}[INFO]${NC} Para usar exactamente ${PROJECT_PATH} pasá --no-climb (alias --no-search-git)."
    PROJECT_PATH="$resolved_root"
  fi
fi

if [[ -z "$PROJECT_DATA_DIR" ]]; then
  PROJECT_DATA_DIR="${PROJECT_PATH}/${DEFAULT_PROJECT_DATA_SUBDIR}"
fi

PROJECT_DATA_DIR="${PROJECT_DATA_DIR/#\~/$HOME}"
PROJECT_DATA_DIR=$(realpath -m "$PROJECT_DATA_DIR") || error_exit "Ruta de datos inválida: $PROJECT_DATA_DIR"

# Configuración global: siempre en ~/.config/opencode/ (inamovible)
GLOBAL_CONFIG_DIR="${GLOBAL_CONFIG_DIR/#\~/$HOME}"
setup_global_config "$GLOBAL_CONFIG_DIR"

# Datos del proyecto: state, data, python
setup_project_dirs "$PROJECT_DATA_DIR"

# Directorio rust/ en la raíz del proyecto: CARGO_HOME per-proyecto donde cargo
# guarda registry/, target/ y bin/. Creado idempotentemente en el host.
if [[ ! -d "${PROJECT_PATH}/rust" ]]; then
  mkdir -p "${PROJECT_PATH}/rust" || error_exit "No se pudo crear ${PROJECT_PATH}/rust"
  echo -e "${GREEN}[OK]${NC} Directorio rust/ creado en: ${PROJECT_PATH}"
fi

# .gitignore del proyecto: crea uno por defecto si no existe e incorpora rust/
# y python/ (directorio del venv en la raíz) más los temporales.
setup_project_gitignore "$PROJECT_PATH"

if [[ "$RENEW" == "true" ]]; then
  renew_image
elif [[ "$REBUILD" == "true" ]]; then
  build_image
elif [[ "$UPDATE" == "true" ]]; then
  update_image
else
  check_image
fi

# Anchor de project root para proyectos sin .git ni config per-project.
# Idempotente: sólo crea si falta .git y ambos opencode.json/.jsonc.
if [[ ! -e "${PROJECT_PATH}/.git" ]] &&
  [[ ! -f "${PROJECT_PATH}/opencode.json" ]] &&
  [[ ! -f "${PROJECT_PATH}/opencode.jsonc" ]]; then
  printf '%s\n' "$PROJECT_ANCHOR_CONTENT" >"${PROJECT_PATH}/opencode.jsonc" ||
    error_exit "No se pudo crear el anchor ${PROJECT_PATH}/opencode.jsonc"
  echo -e "${GREEN}[OK]${NC} Anchor opencode.jsonc creado en: ${PROJECT_PATH}"
fi

MOUNTS=(
  -v "${PROJECT_PATH}:/workspace:Z"
  -v "${GLOBAL_CONFIG_DIR}:${XDG_CONFIG_HOME_IN_CONTAINER}/opencode:Z"
  -v "${GLOBAL_CONFIG_DIR}/identity:/root/.identity:Z"
  # Todo XDG_DATA_HOME/opencode/ es por proyecto. opencode escribe aquí
  # opencode.db, storage/, snapshot/, log/ y tool-output/ aislados.
  -v "${PROJECT_DATA_DIR}/data:${XDG_DATA_HOME_IN_CONTAINER}/opencode:Z"
  # Datos compartidos entre proyectos (auth.json, db/, repos/). Se exponen
  # al proyecto mediante symlinks creados en entrypoint.sh.
  -v "${GLOBAL_DATA_DIR}:${XDG_DATA_HOME_IN_CONTAINER}/opencode-global:Z"
  -v "${PROJECT_DATA_DIR}/state:${XDG_STATE_HOME_IN_CONTAINER}:Z"
)

ENV_VARS=(
  -e "XDG_CONFIG_HOME=${XDG_CONFIG_HOME_IN_CONTAINER}"
  -e "XDG_STATE_HOME=${XDG_STATE_HOME_IN_CONTAINER}"
  -e "XDG_DATA_HOME=${XDG_DATA_HOME_IN_CONTAINER}"
  -e "CARGO_HOME=/workspace/rust"
  -e "CARGO_TARGET_DIR=/workspace/rust/target"
  -e "AGENT_GIT_NAME=${AGENT_GIT_NAME}"
  -e "AGENT_GIT_EMAIL=${AGENT_GIT_EMAIL}"
)

# Permisos del contenedor: auto-aprobación por defecto (sandbox aislado).
# Prioridad: env OPENCODE_PERMISSION del host > flag --auto/--no-auto.
# OPENCODE_PERMISSION es config de permisos inline JSON (ver docs de opencode);
# con '{"*": "allow"}' no se pide aprobación salvo reglas deny explícitas.
PERMISSION_JSON=""
if [[ -n "${OPENCODE_PERMISSION:-}" ]]; then
  PERMISSION_JSON="${OPENCODE_PERMISSION}"
elif [[ "$AUTO_APPROVE" == "true" ]]; then
  PERMISSION_JSON='{"*": "allow"}'
fi
if [[ -n "$PERMISSION_JSON" ]]; then
  ENV_VARS+=(-e "OPENCODE_PERMISSION=${PERMISSION_JSON}")
  if [[ "$AUTO_SET" == "true" ]]; then
    echo -e "${BLUE}[INFO]${NC} Auto-aprobación de permisos: $([ "$AUTO_APPROVE" == "true" ] && echo 'activada' || echo 'desactivada') (OPENCODE_PERMISSION)."
  fi
fi

NETWORK_ARGS=()
if [[ "$NETWORK_HOST" == "true" ]]; then
  NETWORK_ARGS=(--network host)
  echo -e "${YELLOW}[AVISO]${NC} --network-host: el contenedor comparte la red del host."
  echo -e "${YELLOW}[AVISO]${NC} Se pierde el aislamiento de red (acceso a todos los puertos/servicios del host)."
fi

# Auth básica web: el flag --password/--user del launcher tiene prioridad
# sobre las variables de entorno OPENCODE_SERVER_PASSWORD/OPENCODE_SERVER_USERNAME
# del host. Solo aplica al entorno web (serve/web de opencode), nunca a la TUI.
AUTH_PASSWORD="${SERVER_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"
AUTH_USERNAME="${SERVER_USERNAME:-${OPENCODE_SERVER_USERNAME:-}}"

if [[ "$TUI_MODE" == "true" ]]; then
  RUN_NAME=$(next_tui_name)
  if [[ "$PASSWORD_SET" == "true" || "$USER_SET" == "true" ]]; then
    echo -e "${YELLOW}[AVISO]${NC} --password/--user se ignoran en modo TUI (la auth básica es solo web)."
  fi
  echo -e "${BLUE}[INFO]${NC} Modo TUI activado (contenedor: ${RUN_NAME}, --port se ignora)"
  PORT_ARGS=()
  ENV_VARS+=(-e "OPENCODE_MODE=tui")
  EXTRA_ARGS=()
else
  RUN_NAME="${CONTAINER_NAME}-${PORT}"
  if [[ "$NETWORK_HOST" == "true" ]]; then
    echo -e "${BLUE}[INFO]${NC} Servidor web activo en puerto ${PORT} (contenedor: ${RUN_NAME}, red del host)"
    echo -e "${BLUE}[INFO]${NC} Con --network-host el puerto se publica automáticamente (se omite -p)."
    # --network host hace que -p lo ignore podman (emite warning): se omite.
    PORT_ARGS=()
  else
    echo -e "${BLUE}[INFO]${NC} Servidor web activo en puerto ${PORT} (contenedor: ${RUN_NAME}, hostname 0.0.0.0)"
    PORT_ARGS=(-p "${PORT}:${PORT}")
  fi
  if [[ -n "$AUTH_PASSWORD" ]]; then
    ENV_VARS+=(-e "OPENCODE_SERVER_PASSWORD=${AUTH_PASSWORD}")
    if [[ -n "$AUTH_USERNAME" ]]; then
      ENV_VARS+=(-e "OPENCODE_SERVER_USERNAME=${AUTH_USERNAME}")
      echo -e "${BLUE}[INFO]${NC} Auth básica web activada (usuario: ${AUTH_USERNAME})."
    else
      echo -e "${BLUE}[INFO]${NC} Auth básica web activada (usuario por defecto: opencode)."
    fi
  fi
  EXTRA_ARGS=(web --port "${PORT}" --hostname 0.0.0.0)
fi

echo -e "${BLUE}[INFO]${NC} Lanzando opencode en el proyecto: ${PROJECT_PATH}"
echo -e "${BLUE}[INFO]${NC} Config global: ${GLOBAL_CONFIG_DIR}"
echo -e "${BLUE}[INFO]${NC} Datos globales: ${GLOBAL_DATA_DIR}"
echo -e "${BLUE}[INFO]${NC} Datos del proyecto: ${PROJECT_DATA_DIR}"
echo -e "${BLUE}[INFO]${NC} Imagen: ${OPENCODE_IMAGE}"

podman run -it --rm --name "${RUN_NAME}" \
  "${NETWORK_ARGS[@]}" \
  "${PORT_ARGS[@]}" \
  --workdir /workspace \
  "${MOUNTS[@]}" \
  "${ENV_VARS[@]}" \
  "${OPENCODE_IMAGE}" \
  "${EXTRA_ARGS[@]}"
