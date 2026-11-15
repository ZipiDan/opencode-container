#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
#
# setup-subuid.sh — provisiona rangos subuid/subgid para Podman rootless.
#
# Resuelve este síntoma, que aparece al construir o correr contenedores sin sudo:
#   cannot find UID/GID for user <u>: No subuid ranges found for user "<u>" in /etc/subuid
#   potentially insufficient UIDs or GIDs available in user namespace (requested 0:42 for /etc/gshadow)
#
# Uso (necesita root para escribir /etc/subuid y /etc/subgid):
#   sudo ./src/bonus/setup-subuid.sh jasuaga
#   sudo ./src/bonus/setup-subuid.sh jasuaga 200000      # forzar bloque base
#   sudo ./src/bonus/setup-subuid.sh jasuaga --dry-run   # mostrar sin escribir
#
# Soporta usuarios de dominio (NSS/SSSD): valida con getent, no con /etc/passwd.
# No borra nada, no corre podman como root y no toca los datos de los proyectos.

set -euo pipefail

SUBUID_FILE="${SUBUID_FILE:-/etc/subuid}"
SUBGID_FILE="${SUBGID_FILE:-/etc/subgid}"
BLOCK_SIZE="${BLOCK_SIZE:-65536}"
FIRST_BASE="${FIRST_BASE:-100000}"
DRY_RUN=0

die()  { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
ok()   { echo "[OK] $*"; }
warn() { echo "[AVISO] $*" >&2; }

detectDistro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
    ubuntu | debian | linuxmint | pop | kali | raspbian) echo "debian" ;;
    fedora | centos | rhel | rocky | almalinux | amzn) echo "redhat" ;;
    arch | manjaro | endeavouros) echo "arch" ;;
    opensuse* | sles) echo "suse" ;;
    alpine) echo "alpine" ;;
    *) echo "other" ;;
    esac
  else
    echo "unknown"
  fi
}

ensureFile() { # ensureFile <archivo>
  if [[ ! -e "$1" ]]; then
    : >"$1"
    chmod 0644 "$1"
  fi
}

hasEntry() { # hasEntry <archivo> <usuario>
  [[ -f "$1" ]] || return 1
  awk -F: -v u="$2" '$1 == u { found = 1 } END { exit !found }' "$1"
}

hostIdClash() { # hostIdClash <base> <count>: imprime IDs reales del host dentro del bloque
  local base="$1" count="$2" end hits
  end=$((base + count - 1))
  hits=$({ getent passwd; getent group; } | awk -F: -v s="$base" -v e="$end" '$3 >= s && $3 <= e { print $1 ":" $3 }')
  [[ -n "$hits" ]] || return 1
  echo "$hits"
}

nextFreeBase() { # primer bloque completo libre, mirando los rangos ya asignados
  cat "$SUBUID_FILE" "$SUBGID_FILE" | awk -F: -v size="$BLOCK_SIZE" -v base="$FIRST_BASE" '
    NF == 3 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { s[NR] = $2; c[NR] = $3; n = NR }
    END {
      start = base
      do {
        moved = 0
        for (i = 1; i <= n; i++)
          if (start < s[i] + c[i] && s[i] < start + size) { start = s[i] + c[i]; moved = 1 }
      } while (moved)
      print start
    }'
}

appendRange() { # appendRange <archivo> <usuario> <base> <count>
  local file="$1" user="$2" base="$3" count="$4"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] ${file} += ${user}:${base}:${count}"
    return 0
  fi
  ensureFile "$file"
  # Sin salto final, la entrada nueva se pegaría a la última línea existente.
  if [[ -s "$file" ]] && [[ "$(tail -c1 "$file" | wc -l)" -eq 0 ]]; then
    echo >>"$file"
  fi
  printf '%s:%s:%s\n' "$user" "$base" "$count" >>"$file"
  chmod 0644 "$file"
}

installUidmap() {
  if command -v newuidmap &>/dev/null && command -v newgidmap &>/dev/null; then
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] instalar uidmap (newuidmap/newgidmap)"
    return 0
  fi
  warn "Falta uidmap (newuidmap/newgidmap): sin esos helpers, rootless no arranca."
  case "$(detectDistro)" in
  debian) apt-get update -qq && apt-get install -y -qq uidmap ;;
  redhat) dnf install -y shadow-utils ;;
  arch) pacman -S --noconfirm shadow ;;
  suse) zypper install -y shadow ;;
  alpine) apk add shadow ;;
  *) die "Instalá el paquete uidmap/shadow-utils a mano y volvé a correr el script." ;;
  esac
  ok "uidmap instalado."
}

runAsUser() { # runAsUser <usuario> <comando...>: el storage es del usuario, no de root
  local user="$1"
  shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] (como ${user}) $*"
    return 0
  fi
  if command -v runuser &>/dev/null; then
    runuser -l "$user" -c "$*"
  else
    su - "$user" -c "$*"
  fi
}

verifyMapping() { # verifyMapping <usuario>
  local user="$1" map
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] verificación del mapeo omitida"
    return 0
  fi
  if ! map=$(runAsUser "$user" "podman unshare cat /proc/self/uid_map" 2>/dev/null); then
    warn "No pude verificar el mapeo (¿podman disponible para ${user}?)."
    return 0
  fi
  echo "$map" | sed 's/^/     /'
  if [[ "$(echo "$map" | wc -l)" -ge 2 ]]; then
    ok "Mapeo rootless correcto: hay rango subordinado."
  else
    warn "Sigue siendo single-uid. Cerrá la sesión y volvé a entrar como ${user}."
  fi
}

main() {
  local user="" base="" uid=""

  # Parseo mínimo: [<usuario>] [<base>] [--dry-run]
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Uso: $(basename "$0") <usuario> [base_id] [--dry-run]"
      exit 0
      ;;
    -*)
      die "Opción desconocida: $1"
      ;;
    *)
      if [[ -z "$user" ]]; then
        user="$1"
      elif [[ -z "$base" ]]; then
        base="$1"
      else
        die "Argumento de más: $1"
      fi
      ;;
    esac
    shift
  done

  [[ -n "$user" ]] || die "Uso: $(basename "$0") <usuario> [base_id] [--dry-run]"
  [[ "$base" =~ ^[0-9]+$ || -z "$base" ]] || die "El bloque base debe ser numérico."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    die "En macOS los IDs los administra 'podman machine'; este script no aplica."
  fi
  if [[ "$(id -u)" -ne 0 && "$DRY_RUN" -eq 0 ]]; then
    die "Escribe ${SUBUID_FILE} y ${SUBGID_FILE}: correlo con sudo (o usá --dry-run)."
  fi

  uid=$(getent passwd "$user" | cut -d: -f3 || true)
  [[ -n "$uid" ]] || die "No encuentro al usuario '${user}' en el NSS (getent passwd)."
  info "Usuario: ${user} (uid ${uid})"

  if hasEntry "$SUBUID_FILE" "$user" && hasEntry "$SUBGID_FILE" "$user"; then
    ok "Ya tiene rangos en ${SUBUID_FILE} y ${SUBGID_FILE}: no agrego nada."
  else
    installUidmap
    [[ -n "$base" ]] || base=$(nextFreeBase)
    local clash
    if clash=$(hostIdClash "$base" "$BLOCK_SIZE"); then
      local sample
      sample=$(echo "$clash" | head -3 | paste -sd' ')
      die "El bloque ${base}-$((base + BLOCK_SIZE - 1)) choca con $(echo "$clash" | wc -l) IDs reales del host (p. ej.: ${sample}). Probá otro base."
    fi
    if hasEntry "$SUBUID_FILE" "$user"; then
      info "Ya estaba en ${SUBUID_FILE}, lo dejo igual."
    else
      appendRange "$SUBUID_FILE" "$user" "$base" "$BLOCK_SIZE"
    fi
    if hasEntry "$SUBGID_FILE" "$user"; then
      info "Ya estaba en ${SUBGID_FILE}, lo dejo igual."
    else
      appendRange "$SUBGID_FILE" "$user" "$base" "$BLOCK_SIZE"
    fi
    ok "Rangos ${base}-$((base + BLOCK_SIZE - 1)) asignados a ${user}."
  fi

  info "Migrando el storage de ${user} al mapeo nuevo..."
  runAsUser "$user" "podman system migrate" || warn "podman system migrate falló (¿sin storage previo?)."
  verifyMapping "$user"

  echo
  info "Si antes corrió como root, devolvé la propiedad de los datos del proyecto:"
  echo "     sudo chown -R ${user}: <proyecto>/.opencode <proyecto>/python <proyecto>/rust"
  echo "     sudo podman system reset    # solo si no va a seguir usando el storage de root"
}

main "$@"
