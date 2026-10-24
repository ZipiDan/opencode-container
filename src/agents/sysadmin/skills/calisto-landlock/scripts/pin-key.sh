#!/bin/sh
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# pin-key.sh — reemplaza la línea de una clave en authorized_keys por la línea
# forzada de landlock_rosh. Pensado para ejecutarse EN EL TARGET (o contra un
# archivo local en tests). No genera claves y no toca otras claves.
#
# Uso:
#   pin-key.sh --authorized-keys FILE --pubkey FILE.pub [--mode ro|log] [--dry-run] [--yes]
#   pin-key.sh --authorized-keys FILE --key-line "ssh-ed25519 AAAA... user@host" ...
#
# Opciones:
#   --bin PATH             binario en el target (default /usr/local/bin/landlock_rosh)
#   --allow-missing-bin    no abortar si el binario no existe (solo tests)
#   --dry-run              muestra el diff y sale sin escribir
#   --yes                  aplica el cambio (sin esto solo muestra el plan)
#
# Códigos: 0 OK/dry-run, 3 falta --yes, 1 error.

set -eu
umask 077

MODE=ro
BIN=/usr/local/bin/landlock_rosh
AK=
PUBKEY_FILE=
KEY_LINE=
DRY_RUN=0
YES=0
ALLOW_MISSING_BIN=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --authorized-keys) AK=${2:-}; shift 2 ;;
    --pubkey)          PUBKEY_FILE=${2:-}; shift 2 ;;
    --key-line)        KEY_LINE=${2:-}; shift 2 ;;
    --mode)            MODE=${2:-}; shift 2 ;;
    --bin)             BIN=${2:-}; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --yes)             YES=1; shift ;;
    --allow-missing-bin) ALLOW_MISSING_BIN=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "opción desconocida: $1 (usá --help)" ;;
  esac
done

[ -n "$AK" ] || die "falta --authorized-keys"
case "$MODE" in ro|log) ;; *) die "--mode inválido: $MODE (ro|log)" ;; esac

if [ -n "$PUBKEY_FILE" ] && [ -n "$KEY_LINE" ]; then
  die "usá --pubkey o --key-line, no ambos"
fi
if [ -n "$PUBKEY_FILE" ]; then
  [ -r "$PUBKEY_FILE" ] || die "no puedo leer $PUBKEY_FILE"
  KEY_LINE=$(tr -d '\r' < "$PUBKEY_FILE" | awk 'NF { print; exit }')
fi
[ -n "$KEY_LINE" ] || die "falta --pubkey o --key-line"

# Tipo + blob de la clave (ignora comentario y cualquier opción previa).
KEY_PAIR=$(printf '%s\n' "$KEY_LINE" | awk '{
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^(ssh-|ecdsa-|sk-)/) { print $i, $(i + 1); exit }
  }
}')
[ -n "$KEY_PAIR" ] || die "no reconozco la clave pública (se esperaba ssh-*/ecdsa-*/sk-*)"
KEY_TYPE=${KEY_PAIR%% *}
KEY_BLOB=${KEY_PAIR#* }
[ -n "$KEY_BLOB" ] && [ "$KEY_BLOB" != "$KEY_TYPE" ] || die "clave pública incompleta"

if [ "$DRY_RUN" -eq 0 ] && [ "$ALLOW_MISSING_BIN" -eq 0 ] && [ ! -x "$BIN" ]; then
  die "$BIN no existe o no es ejecutable; copiá el binario antes de fijar la clave"
fi

if [ "$MODE" = log ]; then
  CMD="$BIN --log-only"
else
  CMD="$BIN"
fi
OPTS='restrict,no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding'
NEW_LINE="$OPTS,command=\"$CMD\" $KEY_LINE"

AK_DIR=$(dirname "$AK")
CREATED_DIR=0
if [ ! -d "$AK_DIR" ]; then
  mkdir -p "$AK_DIR" || die "no pude crear $AK_DIR"
  chmod 700 "$AK_DIR"
  CREATED_DIR=1
fi
[ -w "$AK_DIR" ] || die "$AK_DIR no es escribible"

TMP=$(mktemp "$AK_DIR/.authorized_keys.XXXXXX") || die "no pude crear temporal en $AK_DIR"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

INPUT=$AK
[ -f "$AK" ] || INPUT=/dev/null

# Reemplaza TODAS las líneas de esa clave; si no hay, agrega una.
awk -v t="$KEY_TYPE" -v b="$KEY_BLOB" -v new="$NEW_LINE" '
  {
    hit = 0
    for (i = 1; i <= NF; i++) if ($i == t && $(i + 1) == b) { hit = 1; break }
    if (hit) { if (!done) { print new; done = 1 } ; next }
    print
  }
  END { if (!done) print new }
' "$INPUT" > "$TMP"

MATCHES=$(awk -v t="$KEY_TYPE" -v b="$KEY_BLOB" '
  { for (i = 1; i <= NF; i++) if ($i == t && $(i + 1) == b) { c++; break } }
  END { print c + 0 }
' "$INPUT")

echo "Linea planificada:" >&2
echo "  $NEW_LINE" >&2
echo "Coincidencias de la clave en $AK: $MATCHES" >&2
if [ -f "$AK" ]; then
  diff -u "$AK" "$TMP" >&2 || true
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run: no se modificó nada." >&2
  exit 0
fi
if [ "$YES" -ne 1 ]; then
  echo "sin --yes: no se modificó nada. Revisá el diff y volvé a ejecutar con --yes." >&2
  exit 3
fi

if [ -f "$AK" ]; then
  BACKUP=$(mktemp "$AK.bak.$(date +%Y%m%d%H%M%S).XXXXXX") || die "no pude crear backup"
  cp -p "$AK" "$BACKUP" || die "no pude hacer backup en $BACKUP"
  chown "$(stat -c '%u:%g' "$AK")" "$TMP" 2>/dev/null || true
else
  BACKUP=""
fi

chmod 600 "$TMP"
mv "$TMP" "$AK" || die "no pude reemplazar $AK"
chmod 600 "$AK"
if command -v restorecon >/dev/null 2>&1; then
  restorecon -F "$AK" 2>/dev/null || true
fi
[ "$CREATED_DIR" -eq 1 ] && chmod 700 "$AK_DIR"

grep -Fq "$NEW_LINE" "$AK" || die "la línea no quedó en $AK; restaurá el backup"
REMAIN=$(awk -v t="$KEY_TYPE" -v b="$KEY_BLOB" '
  { for (i = 1; i <= NF; i++) if ($i == t && $(i + 1) == b) { c++; break } }
  END { print c + 0 }
' "$AK")
if [ "$REMAIN" -gt 1 ]; then
  echo "AVISO: quedan $REMAIN líneas para esa clave; revisá $AK a mano." >&2
fi

echo "OK: $AK actualizado (modo $MODE)." >&2
if [ -n "$BACKUP" ]; then
  echo "Rollback: cp -p '$BACKUP' '$AK'" >&2
else
  echo "Rollback: rm -f '$AK' (no existía antes)" >&2
fi
echo "Verificá con una conexión nueva antes de cerrar la sesión de provisioning." >&2
