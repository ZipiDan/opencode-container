#!/bin/bash
# opencode.sh — launcher de opencode en contenedor Podman.
# VERSION y TAG_RELEASE: bumpear ambos al liberar una nueva versión.
# VERSION sigue semver (major.minor.patch). El tag de git es v$VERSION.

# ==========================
# CONFIGURACIÓN GENERAL (EDITABLE)
# ==========================
VERSION="1.5.0"
TAG_RELEASE="v1.5.0"
# Ruta fija para la configuración global (opencode.json con API keys, providers, etc.)
# No se ve afectada por -config, siempre en $HOME/.config/opencode/
GLOBAL_CONFIG_DIR="${HOME}/.config/opencode"
# Datos globales de opencode (auth.json, BD de cuentas, repos)
# Se ubican dentro de la config global para centralizar todo el estado del usuario.
# Se montan en XDG_DATA_HOME/opencode dentro del contenedor.
GLOBAL_DATA_DIR="${GLOBAL_CONFIG_DIR}/share"
# Subdirectorio por defecto para datos del proyecto (state, data, python)
DEFAULT_PROJECT_DATA_SUBDIR=".opencode"
CONTAINER_NAME="opencode"
# Rutas internas del contenedor (XDG Base Directory Specification)
XDG_CONFIG_HOME_IN_CONTAINER="/home/opencode/.config"
XDG_STATE_HOME_IN_CONTAINER="/home/opencode/.local/state"
XDG_DATA_HOME_IN_CONTAINER="/home/opencode/.local/share"
PYTHONUSERBASE_IN_CONTAINER="/home/opencode/.pythonuser"
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
${BLUE}Uso:${NC} $0 <ruta_del_proyecto> [-config <ruta>] [--port <puerto>] [--tui] [--rebuild] [--update] [--network-host]
       $0 --rebuild
       $0 --update
       $0 --renew
       $0 --ps | --ls
       $0 --kill <patrón> | --rm <patrón>
       $0 --version
       $0 -h | --help

${BLUE}Descripción:${NC}
     opencode.sh ${VERSION} (${TAG_RELEASE})
     Lanza opencode en un contenedor Podman (basado en Debian stable-backports),
     montando el proyecto y separando los datos en dos ámbitos:

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
         python/            → paquetes pip instalados con --user (aislado).

     Usa -config <ruta> para redirigir state/, data/ y python/
     a una ubicación personalizada.

${BLUE}Parámetros:${NC}
    <ruta_del_proyecto>          Ruta al directorio del proyecto.
                                 Obligatorio salvo con --rebuild, --update o --renew.
    -config <ruta>               Ruta para state/, data/, python/.
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

${BLUE}Combinaciones de parámetros:${NC}
    Los parámetros se separan en tres mundos mutuamente excluyentes:

      • Mundo IMAGEN:    --renew | --rebuild | --update   (gestionan la imagen)
      • Mundo GESTIÓN:  --ps/--ls (listar) | --kill/--rm <patrón> (detener)
      • Mundo EJECUCIÓN:  <proyecto> + [-config] [--port] [--tui] [--network-host]

    Árbol de combinaciones válidas (-h es compatible con cualquier rama):

    parámetros
    ├── --renew                reconstruye imagen atómicamente
    ├── --rebuild              reconstruye imagen usando caché
    ├── --update               actualiza imagen desde cero
    ├── --ps | --ls            muestra contenedores opencode en ejecución
    ├── --kill <patrón>        detiene un contenedor opencode (alias --rm)
    │       Patrones: nombre exacto (opencode-tui2, opencode-4096)
    │                 o forma corta: tui2 / 2 / 4096
    │       Si el patrón no matchea o matchea varios, no se actúa.
    └── <proyecto>             lanza opencode en el proyecto
        ├── --tui              arranca terminal interactiva (nombre: opencode-tuiN)
        │   ├── -config <ruta>
        │   └── --network-host
        └── web (sin --tui)   arranca servidor web (nombre: opencode-<puerto>)
            ├── --port <1-65535>   (default ${DEFAULT_PORT})
            ├── -config <ruta>
            └── --network-host

    Reglas clave:
      • No mezclar flags de mundos distintos (IMAGEN/GESTIÓN/EJECUCIÓN).
      • --renew y --rebuild son mutuamente excluyentes.
      • --ps/--ls y --kill/--rm son mutuamente excluyentes entre sí.
      • --tui ignora --port (no hay servidor web).

${BLUE}Ejemplos:${NC}
    $0 /home/usuario/mi-proyecto
    $0 ./proyecto -config /mnt/opencode-data
    $0 ./proyecto --port 4097
    $0 ./proyecto --tui
    $0 ./proyecto --network-host
    $0 --update
    $0 --renew
    $0 --ps
    $0 --kill tui2
    $0 --rm opencode-4096

${BLUE}Nota:${NC}
    Config global (API keys, share)    → ${GLOBAL_CONFIG_DIR}/  (no afectado por -config)
    Datos del proyecto (sesiones, etc) → controlado por -config
    --network-host rompe el aislamiento de red del contenedor (uso de red
    del host). Úsalo solo cuando necesites alcanzar servicios del host.
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
  local subdirs=("data" "state" "python")
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
      (( n > max )) && max=$n
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
      mode="tui"; port="-"
    elif [[ "$name" =~ opencode-([0-9]+)$ ]]; then
      mode="web"; port="${BASH_REMATCH[1]}"
    else
      mode="?"; port="?"
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
PS_MODE=false
KILL_MODE=false
KILL_PATTERN=""
PASSED_PORT_SET=false

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

# Mundo GESTIÓN: --ps/--ls y --kill/--rm son mutuamente excluyentes entre sí
# y con cualquier flag de los mundos IMAGEN o EJECUCIÓN.
if [[ "$PS_MODE" == "true" || "$KILL_MODE" == "true" ]]; then
  if [[ "$PS_MODE" == "true" && "$KILL_MODE" == "true" ]]; then
    error_exit "Las opciones --ps/--ls y --kill/--rm son mutuamente excluyentes."
  fi
  if [[ "$RENEW" == "true" || "$REBUILD" == "true" || "$UPDATE" == "true" \
      || -n "$PROJECT_PATH" || "$TUI_MODE" == "true" || "$NETWORK_HOST" == "true" \
      || -n "$PROJECT_DATA_DIR" || "$PASSED_PORT_SET" == "true" ]]; then
    error_exit "Las opciones --ps/--ls/--kill/--rm (mundo GESTIÓN) no pueden combinarse con flags de otros mundos (IMAGEN/EJECUCIÓN)."
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

if [[ "$RENEW" == "true" ]]; then
  renew_image
elif [[ "$REBUILD" == "true" ]]; then
  build_image
elif [[ "$UPDATE" == "true" ]]; then
  update_image
else
  check_image
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
  -v "${PROJECT_DATA_DIR}/python:${PYTHONUSERBASE_IN_CONTAINER}:Z"
)

ENV_VARS=(
  -e "XDG_CONFIG_HOME=${XDG_CONFIG_HOME_IN_CONTAINER}"
  -e "XDG_STATE_HOME=${XDG_STATE_HOME_IN_CONTAINER}"
  -e "XDG_DATA_HOME=${XDG_DATA_HOME_IN_CONTAINER}"
  -e "PYTHONUSERBASE=${PYTHONUSERBASE_IN_CONTAINER}"
  -e "AGENT_GIT_NAME=${AGENT_GIT_NAME}"
  -e "AGENT_GIT_EMAIL=${AGENT_GIT_EMAIL}"
)

NETWORK_ARGS=()
if [[ "$NETWORK_HOST" == "true" ]]; then
  NETWORK_ARGS=(--network host)
  echo -e "${YELLOW}[AVISO]${NC} --network-host: el contenedor comparte la red del host."
  echo -e "${YELLOW}[AVISO]${NC} Se pierde el aislamiento de red (acceso a todos los puertos/servicios del host)."
fi

if [[ "$TUI_MODE" == "true" ]]; then
  RUN_NAME=$(next_tui_name)
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
