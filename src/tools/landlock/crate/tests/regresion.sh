#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# =============================================================================
# Suite de regresión landlock_rosh v1.9.0
# =============================================================================
# Uso:  bash tests/regresion.sh
# Requiere: root, binario compilado (./build_static.sh), logrotate y bubblewrap instalados.
# Cubre: funcionalidad v1.6/v1.6.1 + shells v1.7.0 + SSH v1.8.0 +
#        -c/--log-only/--print-ssh-line de v1.9.0.
# Al final deja el entorno instalado (log + shells) y el log de pruebas limpio.
# =============================================================================

set -u

CRATE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$CRATE/../.." && pwd)"
BIN="$ROOT/landlock_rosh"
LOG="/var/log/landlock_rosh/landlock_rosh.log"
CONF="/etc/logrotate.d/landlock_rosh"
SIM_DIR="/tmp/opencode/journalsim"
LISTENER="$SIM_DIR/listener.py"
TMP_LOG="/tmp/rosh-test.log"
PASS=0
FAIL=0
FAILED_TESTS=()

# --- helpers ---------------------------------------------------------------

ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); echo "  [FAIL] $1"; }

# t <nombre> <cond> — evalúa cond como test (exit 0 = pass)
t() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}

log_lines() { wc -l < "$LOG" 2>/dev/null || echo 0; }
# log_lines se usa dentro de `bash -c` (subshell): hay que exportar la función
# y las variables que referencia (LOG).
export -f log_lines
export LOG

sim_start() {
  mkdir -p "$SIM_DIR"
  cat > "$LISTENER" <<'PYEOF'
import socket, os, sys
SOCK="/run/systemd/journal/socket"
os.makedirs(os.path.dirname(SOCK), exist_ok=True)
if os.path.exists(SOCK): os.unlink(SOCK)
s=socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(SOCK); os.chmod(SOCK, 0o666)
open(sys.argv[1], "w").close()
try:
    while True:
        data=s.recv(65535)
        with open(sys.argv[1], "a") as f: f.write(data.decode(errors="replace"))
except KeyboardInterrupt:
    pass
PYEOF
  rm -f /run/systemd/journal/socket
  python3 "$LISTENER" "$TMP_LOG" 2>/dev/null &
  SIM_PID=$!
  sleep 0.8
}

sim_stop() {
  [ -n "${SIM_PID:-}" ] && kill "$SIM_PID" 2>/dev/null
  sleep 0.3
  rm -f /run/systemd/journal/socket
  SIM_PID=""
}

require_root() { [ "$(id -u)" = "0" ] || { echo "ERROR: requiere root"; exit 1; }; }

# =============================================================================
# GATE ESTÁTICO
# =============================================================================
echo "== GATE estático =="
(
  cd "$CRATE"
  cargo test --quiet >/dev/null 2>&1
)
t "cargo test (20 unit)" [ $? -eq 0 ]
(
  cd "$CRATE"
  cargo clippy --all-targets -- -D warnings >/dev/null 2>&1
)
t "clippy -D warnings" [ $? -eq 0 ]
(
  cd "$CRATE"
  cargo fmt --check >/dev/null 2>&1
)
t "cargo fmt --check" [ $? -eq 0 ]

# =============================================================================
# INSTALACIÓN (backend archivo; el contenedor no tiene journald)
# =============================================================================
echo "== Instalación backend archivo =="
t "--version imprime 1.9.0" bash -c "'$BIN' --version | grep -q 1.9.0"
t "--help muestra uso y flags" bash -c "'$BIN' --help | grep -q 'FLAGS ADMINISTRATIVAS'"
t "-h también muestra ayuda" bash -c "'$BIN' -h | grep -q 'FLAGS DE USO'"
t "--install-log como root" "$BIN" --install-log
t "conf logrotate existe" test -f "$CONF"
t "dir log con perms 0750" bash -c "stat -c%a /var/log/landlock_rosh | grep -q 750"
t "log file con perms 0640" bash -c "stat -c%a '$LOG' | grep -q 640"
t "config logrotate válida (logrotate -d)" bash -c "logrotate -d '$CONF' >/dev/null 2>&1"
t "no-root rechazado" bash -c "setpriv --reuid=1000 --regid=1000 --clear-groups '$BIN' --install-log; test \$? -eq 1"

# =============================================================================
# MODO COMANDO SSH (no interactivo) — funcionalidad original
# =============================================================================
echo "== Modo comando SSH =="
: > "$LOG"
SSH_ORIGINAL_COMMAND='echo OK' "$BIN" >/dev/null 2>&1
t "exit 0 propagado" [ $? -eq 0 ]
SSH_ORIGINAL_COMMAND='exit 3' "$BIN" >/dev/null 2>&1
t "exit 3 propagado" [ $? -eq 3 ]
SSH_ORIGINAL_COMMAND='exit 5' "$BIN" >/dev/null 2>&1
t "exit 5 propagado" [ $? -eq 5 ]
SSH_ORIGINAL_COMMAND='noexiste-xyz' "$BIN" >/dev/null 2>&1
t "exit 127 (comando inexistente)" [ $? -eq 127 ]
t "4 comandos -> 8 lineas (start+end c/u)" bash -c "test \$(log_lines) -eq 8"
t "entradas tienen exit code" bash -c "grep -q 'exit=3' '$LOG' && grep -q 'exit=127' '$LOG'"

# --- v1.9.0: -c, --log-only, --print-ssh-line ------------------------------
OUT=$("$BIN" -c 'echo CMDC' 2>/dev/null)
t "-c ejecuta el comando y devuelve stdout" [ "$OUT" = "CMDC" ]
SSH_ORIGINAL_COMMAND='exit 9' "$BIN" -c 'exit 4' >/dev/null 2>&1
t "-c gana sobre SSH_ORIGINAL_COMMAND" [ $? -eq 4 ]
rm -f /etc/ROSH-LOGONLY-TEST
SSH_ORIGINAL_COMMAND='echo x > /etc/ROSH-LOGONLY-TEST' "$BIN" --log-only >/dev/null 2>&1
t "--log-only permite escribir fuera de /tmp" [ $? -eq 0 ]
t "--log-only deja traza mode=log-only" bash -c "grep -q 'mode=log-only | end' '$LOG'"
rm -f /etc/ROSH-LOGONLY-TEST
t "--log-only + --no-log rechazado" bash -c "'$BIN' --log-only --no-log >/dev/null 2>&1; test \$? -eq 1"
LINE_RO=$("$BIN" --print-ssh-line)
t "--print-ssh-line ro fuerza el sandbox" bash -c "printf '%s' '$LINE_RO' | grep -qF 'command=\"/usr/local/bin/landlock_rosh\"'"
LINE_LOG=$("$BIN" --print-ssh-line --mode log)
t "--print-ssh-line log fuerza --log-only" bash -c "printf '%s' '$LINE_LOG' | grep -qF 'command=\"/usr/local/bin/landlock_rosh --log-only\"'"
PUB_TEST=/tmp/rosh-test.pub
printf 'ssh-ed25519 AAAATESTKEY agente@test\n' > "$PUB_TEST"
LINE_PUB=$("$BIN" --print-ssh-line --pubkey "$PUB_TEST")
t "--print-ssh-line usa la clave real" bash -c "printf '%s' '$LINE_PUB' | grep -qF 'ssh-ed25519 AAAATESTKEY agente@test'"
rm -f "$PUB_TEST"

SSH_CONNECTION='10.1.0.5 52234 10.1.0.13 22' SSH_ORIGINAL_COMMAND='true' "$BIN" >/dev/null 2>&1
t "src=IP:puerto desde SSH_CONNECTION" bash -c "grep -q 'src=10.1.0.5:52234' '$LOG'"
SSH_ORIGINAL_COMMAND='true' "$BIN" >/dev/null 2>&1
t "src=local en TTY" bash -c "grep -q 'src=local' '$LOG'"

# --- exclusiones -----------------------------------------------------------
N=$(log_lines)
SSH_ORIGINAL_COMMAND='whoami' "$BIN" --no-log >/dev/null 2>&1
SSH_ORIGINAL_COMMAND='whoami' LANDLOCK_NO_LOG=1 "$BIN" >/dev/null 2>&1
t "--no-log y LANDLOCK_NO_LOG=1 silencian" bash -c "test \$(log_lines) -eq $N"

# --- modo bwrap no interactivo ---------------------------------------------
SSH_ORIGINAL_COMMAND='uname -s' LANDLOCK_FORCE_BWRAP=1 "$BIN" >/dev/null 2>&1
t "bwrap no-interactivo exit 0" [ $? -eq 0 ]
SSH_ORIGINAL_COMMAND='exit 7' LANDLOCK_FORCE_BWRAP=1 "$BIN" >/dev/null 2>&1
t "bwrap exit 7 propagado" [ $? -eq 7 ]
t "bwrap loguea mode=bwrap start/end" bash -c "grep -q 'mode=bwrap | end' '$LOG'"

# =============================================================================
# SANDBOX / JAULA (funcionalidad original)
# =============================================================================
echo "== Jaula Landlock (escritura denegada, lectura OK) =="
SSH_ORIGINAL_COMMAND='touch /etc/ESCAPE-TEST' "$BIN" >/dev/null 2>&1
t "touch /etc denegado" [ $? -ne 0 ]
SSH_ORIGINAL_COMMAND='chmod 777 /etc' "$BIN" >/dev/null 2>&1
t "chmod /etc denegado (seccomp)" [ $? -ne 0 ]
SSH_ORIGINAL_COMMAND='truncate -s 0 /etc/hostname' "$BIN" >/dev/null 2>&1
t "truncate por path /etc denegado (Landlock)" [ $? -ne 0 ]
SSH_ORIGINAL_COMMAND='cat /etc/shadow >/dev/null' "$BIN" >/dev/null 2>&1
t "lectura /etc/shadow permitida (root read-only)" [ $? -eq 0 ]
SSH_ORIGINAL_COMMAND='echo x >/tmp/rosh-write && echo y >/var/tmp/rosh-write2' "$BIN" >/dev/null 2>&1
t "escritura en /tmp y /var/tmp permitida" [ $? -eq 0 ]

# =============================================================================
# INYECCIÓN DE LOG (funcionalidad original)
# =============================================================================
echo "== Inyección de log =="
: > "$LOG"
SSH_ORIGINAL_COMMAND='echo "salto\nreal"' "$BIN" >/dev/null 2>&1
t "cmd normal -> 2 lineas (start+end)" bash -c "test \$(log_lines) -eq 2"
SSH_ORIGINAL_COMMAND='echo "X"; echo "FAKE | landlock-abi6 | start | cmd=\"FALSIFICADO\""' "$BIN" >/dev/null 2>&1
t "intento de forjar NO agrega lineas extra" bash -c "test \$(log_lines) -eq 4"
t "cadena FAKE queda contenida (no como inicio de linea)" bash -c "grep -q 'FAKE | landlock-abi6 | start | cmd' '$LOG'"
REAL_NL=$'echo a\nSYSLOG_IDENTIFIER=evil\nLANDLOCK_EXIT=0'
SSH_ORIGINAL_COMMAND="$REAL_NL" "$BIN" >/dev/null 2>&1
t "newline real escapado -> 2 lineas, no mas" bash -c "test \$(log_lines) -eq 6"
t "newline real queda como literal \\n en el log" grep -qF '\nSYSLOG_IDENTIFIER=evil' "$LOG"

# --- journal backend (simulado) --------------------------------------------
echo "== Journal backend (simulado) =="
sim_start
SSH_CONNECTION='10.9.9.9 1234 10.1.0.13 22' SSH_ORIGINAL_COMMAND='uptime' "$BIN" >/dev/null 2>&1
t "journal rc 0" [ $? -eq 0 ]
sim_stop
t "journal: datagramas start/end" bash -c "grep -q 'LANDLOCK_EVENT=start' '$TMP_LOG' && grep -q 'LANDLOCK_EVENT=end' '$TMP_LOG'"
t "journal: campos estructurados" bash -c "grep -q 'SYSLOG_IDENTIFIER=landlock_rosh' '$TMP_LOG' && grep -q 'LANDLOCK_SRC=10.9.9.9:1234' '$TMP_LOG' && grep -q 'LANDLOCK_EXIT=0' '$TMP_LOG'"
# inyección de campos en journal
sim_start
CMD=$'echo x\nSYSLOG_IDENTIFIER=evil_actor\nLANDLOCK_EXIT=0\nFAKE=1'
SSH_ORIGINAL_COMMAND="$CMD" "$BIN" >/dev/null 2>&1
sim_stop
t "journal: sin inyección de campos" bash -c "! grep -q '^SYSLOG_IDENTIFIER=evil_actor$' '$TMP_LOG'"

# =============================================================================
# MODO INTERACTIVO (funcionalidad original + fix 2)
# =============================================================================
echo "== Interactivo (PTY real) =="
: > "$LOG"
printf 'echo LL-INTER\nexit\n' | script -qec "$BIN" /dev/null >/dev/null 2>&1
t "landlock interactivo: session-start" bash -c "grep -q 'session-start' '$LOG'"
t "landlock interactivo: inter-cmd" bash -c "grep -q 'inter-cmd | cmd=\"echo LL-INTER\"' '$LOG'"
printf 'echo BW-INTER\nexit\n' | script -qec "env LANDLOCK_FORCE_BWRAP=1 $BIN" /dev/null >/dev/null 2>&1
t "bwrap interactivo: session-start" bash -c "grep -q 'mode=bwrap | session-start' '$LOG'"
t "bwrap interactivo: inter-cmd" bash -c "grep -q 'mode=bwrap | inter-cmd | cmd=\"echo BW-INTER\"' '$LOG'"

# fix 2: comillas escapadas en hook
printf 'echo "comillas" dobles\nexit\n' | script -qec "$BIN" /dev/null >/dev/null 2>&1
t "fix2: comillas escapadas en hook" bash -c "grep -q 'cmd=\"echo \\\\\"comillas\\\\\" dobles\"' '$LOG'"

# =============================================================================
# TESTS DE FIXES v1.6.1
# =============================================================================
echo "== Fixes v1.6.1 =="
: > "$LOG"

# fix 1: ftruncate bloqueado (EPERM vía fd 9 heredado en interactivo)
SIM_IN=/tmp/rosh-sim1.in
printf 'python3 -c "import os; os.ftruncate(9,0)" 2>&1; echo rc=$?\nexit\n' > "$SIM_IN"
script -qec "$BIN" /dev/null < "$SIM_IN" >/tmp/rosh-sim1.out 2>&1
t "fix1: ftruncate da EPERM (PermissionError/rc!=0)" bash -c "grep -qE 'PermissionError|rc=[1-9]' /tmp/rosh-sim1.out"
printf ': > /tmp/rosh-trunc-probe\nexit\n' | script -qec "$BIN" /dev/null >/dev/null 2>&1
t "fix1: redireccion '>' en /tmp intacta (open O_TRUNC)" test -f /tmp/rosh-trunc-probe

# fix 3: no-UTF8 (comando con bytes 0xff/0xfe)
CMD_RAW=$(printf 'printf "byte \xff\xfe"')
OUT_NL=/tmp/rosh-utf8.out
SSH_ORIGINAL_COMMAND="$CMD_RAW" "$BIN" >"$OUT_NL" 2>&1
RC_NL=$?
t "fix3: no-UTF8 rc 0" [ "$RC_NL" -eq 0 ]
t "fix3: no-UTF8 avisa en stderr" grep -q "UTF-8" "$OUT_NL"
t "fix3: no-UTF8 loguea start (no cae a interactivo)" bash -c "grep -q 'start' '$LOG' && tail -1 '$LOG' | grep -qv 'session-start'"

# =============================================================================
# SHELLS DEL SISTEMA (--install-shell / --uninstall-shell, v1.7.0)
# =============================================================================
echo "== Instalación de shells =="
BIN_INST=/usr/local/bin/landlock_rosh
WRAPPER=/usr/local/bin/landlock_rosh-nolog
SHELLS=/etc/shells

t "no-root rechazado (install-shell)" bash -c "setpriv --reuid=1000 --regid=1000 --clear-groups '$BIN' --install-shell; test \$? -eq 1"
t "no-root rechazado (uninstall-shell)" bash -c "setpriv --reuid=1000 --regid=1000 --clear-groups '$BIN' --uninstall-shell; test \$? -eq 1"

t "--install-shell como root" "$BIN" --install-shell
t "binario instalado en /usr/local/bin" test -x "$BIN_INST"
t "wrapper instalado y ejecutable" test -x "$WRAPPER"
t "wrapper contiene exec + --no-log" bash -c "grep -q 'exec $BIN_INST --no-log \"\\\$@\"' '$WRAPPER'"
t "/etc/shells registra AMBAS rutas" bash -c "grep -qx '$BIN_INST' '$SHELLS' && grep -qx '$WRAPPER' '$SHELLS'"
t "salida reporta distro y arch" bash -c "'$BIN' --install-shell | grep -Eq 'distro .+ arch [a-z0-9_]+'"
t "wrapper pasa --version al launcher" bash -c "'$WRAPPER' --version | grep -q 1.9.0"

# idempotencia: re-instalar no duplica entradas en /etc/shells
"$BIN" --install-shell >/dev/null 2>&1
t "re-install idempotente (1 sola ocurrencia c/u)" bash -c "[ \$(grep -cx '$BIN_INST' '$SHELLS') -eq 1 ] && [ \$(grep -cx '$WRAPPER' '$SHELLS') -eq 1 ]"
t "re-install rc 0" "$BIN" --install-shell

# gate passwd: usuario con landlock_rosh como shell → uninstall aborta sin cambios
if useradd -m -s "$BIN_INST" roshgate-test 2>/dev/null; then
  t "gate passwd: uninstall aborta (rc 1)" bash -c "'$BIN' --uninstall-shell >/dev/null 2>&1; test \$? -eq 1"
  t "gate passwd: NO quitó el binario" test -x "$BIN_INST"
  t "gate passwd: lista al usuario afectado" bash -c "'$BIN' --uninstall-shell 2>&1 | grep -q roshgate-test"
  userdel -r roshgate-test 2>/dev/null
else
  echo "  [SKIP] gate passwd (useradd no disponible en este entorno)"
fi

# =============================================================================
# Uninstall (log)
# =============================================================================
echo "== Uninstall =="
t "--uninstall-log como root" "$BIN" --uninstall-log
t "conf logrotate quitada" bash -c "! test -f '$CONF'"
N=$(log_lines)
SSH_ORIGINAL_COMMAND='whoami' "$BIN" >/dev/null 2>&1
t "tras uninstall: detección apagada (silencioso)" bash -c "test \$(log_lines) -eq $N"
t "logs históricos preservados" test -d /var/log/landlock_rosh
t "reinstala para dejar entorno listo" "$BIN" --install-log

# =============================================================================
# DESINSTALACIÓN DE SHELLS (--uninstall-shell)
# =============================================================================
echo "== Desinstalación de shells =="
t "--uninstall-shell como root" "$BIN" --uninstall-shell
t "binario quitado" bash -c "! test -e '$BIN_INST'"
t "wrapper quitado" bash -c "! test -e '$WRAPPER'"
t "/etc/shells sin las rutas de rosh" bash -c "! grep -q 'landlock_rosh' '$SHELLS'"
"$BIN" --uninstall-shell >/dev/null 2>&1
t "uninstall repetido idempotente (rc 0)" [ $? -eq 0 ]

# auto-desinstalación: correr --uninstall-shell DESDE el binario instalado
"$BIN" --install-shell >/dev/null 2>&1
t "re-instalado para prueba desde el path instalado" test -x "$BIN_INST"
t "uninstall ejecutándose desde el path instalado (rc 0)" bash -c "'$BIN_INST' --uninstall-shell >/dev/null 2>&1; test \$? -eq 0"
t "binario quitado tras auto-uninstall" bash -c "! test -e '$BIN_INST'"

# estado final: dejar las shells instaladas (entorno listo)
t "estado final: shells re-instaladas" "$BIN" --install-shell
t "estado final: ambas rutas en /etc/shells" bash -c "grep -qx '$BIN_INST' '$SHELLS' && grep -qx '$WRAPPER' '$SHELLS'"

# =============================================================================
# LIMPIEZA
# =============================================================================
: > "$LOG"
rm -f /tmp/rosh-write /tmp/rosh-write2 /tmp/rosh-trunc-probe "$SIM_IN" /tmp/rosh-sim1.out /tmp/rosh-test.log
rm -f /run/systemd/journal/socket

echo ""
echo "=================================================="
echo "RESULTADO: $PASS PASS, $FAIL FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "FALLIDOS:"
  for f in "${FAILED_TESTS[@]}"; do echo "  - $f"; done
  exit 1
else
  echo "TODOS LOS TESTS PASARON"
  exit 0
fi