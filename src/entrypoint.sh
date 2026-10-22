#!/bin/bash
set -e

# opencode container entrypoint.
# El modo se selecciona mediante la variable de entorno OPENCODE_MODE:
#   - web (por defecto): ejecuta `opencode` con los argumentos recibidos
#                         (típicamente los del CMD: serve --port N --hostname ...)
#   - tui:                ejecuta `opencode` sin argumentos (arranca la TUI)

# Symlinks para que git/ssh encuentren la identidad del agente.
# /root/.ssh debe SER un symlink al directorio de identidad montado: si la imagen
# ya trae /root/.ssh como directorio, `ln -sf` crearía un symlink anidado
# (/root/.ssh/ssh) y ssh no vería las claves ni el known_hosts. Se elimina primero;
# rm sobre un symlink borra solo el enlace (no sigue al target montado /root/.identity).
ln -sf /root/.identity/gitconfig /root/.gitconfig
rm -rf /root/.ssh
ln -sfn /root/.identity/ssh /root/.ssh
chmod 700 /root/.identity/ssh

# Generar clave ed25519 si no existe
if [ ! -f /root/.identity/ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -C "agent@opencode.local" \
        -f /root/.identity/ssh/id_ed25519
fi
chmod 600 /root/.identity/ssh/id_ed25519
chmod 644 /root/.identity/ssh/id_ed25519.pub

# Configurar git user si no está seteado
if ! git config --global user.name >/dev/null 2>&1; then
    git config --global user.name "${AGENT_GIT_NAME:-OpenCode Agent}"
    git config --global user.email "${AGENT_GIT_EMAIL:-agent@opencode.local}"
fi

# Los datos globales (auth.json, db/, repos/) viven en
# XDG_DATA_HOME/opencode-global/ y se exponen dentro del directorio de datos
# del proyecto mediante symlinks. Así opencode.db y el resto de datos del
# proyecto permanecen aislados por proyecto.
ln -sf /home/opencode/.local/share/opencode-global/auth.json /home/opencode/.local/share/opencode/auth.json
ln -sf /home/opencode/.local/share/opencode-global/db   /home/opencode/.local/share/opencode/db
ln -sf /home/opencode/.local/share/opencode-global/repos /home/opencode/.local/share/opencode/repos

# Rust: el toolchain (rustup) vive en /root/.cargo/bin (imagen). El CARGO_HOME
# del proyecto (/workspace/rust) es un volumen montado vacío, así que se
# re-exponen los binarios de cargo/rustc/rustup dentro de él y se agrega su
# carpeta bin al PATH. Así `cargo install` y el toolchain funcionan por proyecto.
if [[ -d /root/.cargo/bin && -n "${CARGO_HOME:-}" ]]; then
    mkdir -p "${CARGO_HOME}/bin"
    for f in /root/.cargo/bin/*; do
        [[ -e "$f" ]] && ln -sf "$f" "${CARGO_HOME}/bin/$(basename "$f")"
    done
    export PATH="${CARGO_HOME}/bin:${PATH}"
fi

# Python (venv-first): si la carpeta python/ de la raíz del proyecto es un venv,
# se activa en este proceso (opencode y sus hijos heredan PATH/VIRTUAL_ENV).
# Siendo un export a nivel de proceso, no depende de que los shells no
# interactivos lean .bashrc. No se usa pip --user ni PYTHONUSERBASE.
# Si python/ no existe, se crea el venv (idempotente, persiste en el volumen).
# Si python/ existe pero NO parece un venv (p. ej. código fuente), no se toca.
if [[ ! -d /workspace/python ]]; then
    python3 -m venv /workspace/python
fi
if [[ -x /workspace/python/bin/python && -f /workspace/python/pyvenv.cfg ]]; then
    export VIRTUAL_ENV=/workspace/python
    export PATH="/workspace/python/bin:${PATH}"
    unset PIP_USER
fi

MODE="${OPENCODE_MODE:-web}"

case "$MODE" in
  tui)
    exec opencode
    ;;
  web)
    exec opencode "$@"
    ;;
  *)
    echo "[ERROR] OPENCODE_MODE desconocido: '$MODE' (valores válidos: 'web', 'tui')" >&2
    exit 1
    ;;
esac
