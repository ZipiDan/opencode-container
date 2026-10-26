#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

"""Gestiona las credenciales compartidas de opencode entre proyectos.

OpenCode v2 guarda las credenciales en SQLite (tabla `credential` de
`opencode.db`) y esa base es POR PROYECTO. El `auth.json` heredado de v1 sólo se
importa una vez, en el primer arranque de v2 sobre cada base; después opencode
no lo vuelve a mirar. Por eso el launcher mantiene un `auth.json` canónico
compartido y este programa reconcilia cada proyecto contra él.

Uso:
  opencode-credentials seed [--auth RUTA] [--db RUTA]
      Siembra o actualiza la base del proyecto desde auth.json. Lo llama el
      entrypoint en cada arranque. Procesa sólo credenciales de tipo API key.
  opencode-credentials export [--db RUTA] [--auth RUTA]
      Vuelca las API keys de la base del proyecto a auth.json: promueve un
      login hecho con la TUI a todos los proyectos.
  opencode-credentials put <integración> [--auth RUTA]
      Escribe la key de una integración en auth.json. La key se lee por stdin
      para no dejarla en el historial del shell ni en el listado de procesos.

Precedencia al sembrar:
  1. credencial manual del proyecto (login hecho en la TUI) → gana, no se toca
  2. la key canónica ya está en la base (aunque el id difiera) → no-op
  3. credencial sembrada por el launcher con key vieja → se reemplaza
  4. integración sin credencial → se siembra
"""

import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import dataclass, field

# Prefijo de los ids que siembra el launcher. Permite distinguir una credencial
# gestionada (actualizable) de una que el usuario creó a mano (intocable).
SEED_ID_PREFIX = "cred_seed_"
SEED_LABEL = "API key (launcher)"
# Tipos de auth.json que se siembran: "api" es el formato v1, "key" el de v2.
STATIC_TYPES = {"api", "key"}
LOG_PREFIX = "[credenciales]"
OPENCODE_TIMEOUT = 180


@dataclass
class Credential:
    """Fila de la tabla `credential` del proyecto."""

    id: str
    integration_id: str
    label: str
    value: dict
    active: int = None

    @property
    def key(self):
        """API key si la credencial es estática; None si es OAuth."""
        if self.value.get("type") not in ("key", "api"):
            return None
        key = self.value.get("key")
        return key if isinstance(key, str) and key else None

    @property
    def is_seeded(self):
        """True si la sembró el launcher (id con prefijo propio)."""
        return self.id.startswith(SEED_ID_PREFIX)


@dataclass
class Plan:
    """Qué hacer con cada integración del archivo canónico."""

    imports: dict = field(default_factory=dict)  # integración -> key
    logouts: list = field(default_factory=list)  # (integración, id)
    overrides: list = field(default_factory=list)  # integraciones con login local
    unchanged: list = field(default_factory=list)


def log(message):
    print(f"{LOG_PREFIX} {message}", flush=True)


def warn(message):
    print(f"{LOG_PREFIX} AVISO: {message}", file=sys.stderr, flush=True)


def seeded_id(integration_id):
    """Id determinístico: el mismo en todos los proyectos para esa integración."""
    digest = hashlib.sha256(integration_id.encode("utf-8")).hexdigest()
    return f"{SEED_ID_PREFIX}{digest[:24]}"


def read_canonical(path):
    """Lee auth.json como dict crudo; {} si no existe o está roto."""
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as exc:
        warn(f"no se pudo leer {path}: {exc}")
        return {}
    return raw if isinstance(raw, dict) else {}


def write_canonical(path, entries):
    """Escribe auth.json de forma atómica y con permisos 0600."""
    tmp_path = f"{path}.tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(entries, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, path)


def static_keys(entries):
    """Subconjunto {integración: key} de las entradas estáticas del canónico."""
    keys = {}
    for integration_id, entry in entries.items():
        if not isinstance(entry, dict):
            warn(f"{integration_id}: entrada inválida en auth.json, se ignora")
            continue
        entry_type = entry.get("type")
        key = entry.get("key")
        if entry_type not in STATIC_TYPES:
            # OAuth queda afuera a propósito: sus refresh tokens rotan y
            # compartirlos invalida los logins de los otros proyectos.
            log(f"{integration_id}: tipo '{entry_type}' no se comparte (sólo API keys)")
            continue
        if not isinstance(key, str) or not key:
            warn(f"{integration_id}: sin 'key' en auth.json, se ignora")
            continue
        keys[integration_id] = key
    return keys


def read_project_credentials(db_path):
    """Filas de `credential` del proyecto; [] si la base todavía no existe."""
    if not os.path.exists(db_path):
        return []
    try:
        connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error as exc:
        warn(f"no se pudo abrir {db_path}: {exc}")
        return []
    try:
        rows = connection.execute("SELECT id, integration_id, label, value, active FROM credential").fetchall()
    except sqlite3.Error:
        # Base anterior a v2 (sin tabla credential): no hay nada que reconciliar.
        return []
    finally:
        connection.close()

    credentials = []
    for row_id, integration_id, label, value, active in rows:
        try:
            parsed = json.loads(value)
        except (TypeError, json.JSONDecodeError):
            parsed = {}
        credentials.append(Credential(row_id, integration_id, label, parsed if isinstance(parsed, dict) else {}, active))
    return credentials


def reconcile(canonical_keys, credentials):
    """Decide importaciones, bajas y overrides sin tocar nada (función pura)."""
    plan = Plan()
    for integration_id, key in canonical_keys.items():
        mine = [cred for cred in credentials if cred.integration_id == integration_id]
        if not mine:
            plan.imports[integration_id] = key
            continue
        if any(cred.key == key for cred in mine):
            plan.unchanged.append(integration_id)
            continue
        if any(not cred.is_seeded for cred in mine):
            # Login manual del proyecto: es un override deliberado, no se pisa.
            plan.overrides.append(integration_id)
            continue
        plan.logouts.extend((integration_id, cred.id) for cred in mine)
        plan.imports[integration_id] = key
    return plan


def opencode_binary():
    """Ruta del binario de opencode (PATH del contenedor o del host)."""
    return shutil.which("opencode") or "opencode"


def run_opencode(args, stdin_text=None):
    """Ejecuta el CLI de opencode. Devuelve (ok, salida_o_error)."""
    try:
        proc = subprocess.run(
            [opencode_binary(), *args],
            check=False,
            input=stdin_text,
            capture_output=True,
            text=True,
            timeout=OPENCODE_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip().splitlines()
        return False, detail[-1] if detail else f"exit {proc.returncode}"
    return True, (proc.stdout or "").strip()


def import_credentials(entries):
    """Importa credenciales por stdin con el CLI oficial (idempotente por id)."""
    payload = [
        {
            "id": seeded_id(integration_id),
            "integrationID": integration_id,
            "label": SEED_LABEL,
            "active": True,
            "value": {"type": "key", "key": key},
        }
        for integration_id, key in entries.items()
    ]
    return run_opencode(["auth", "import", "--standalone"], json.dumps(payload))


def logout_credential(integration_id, credential_id):
    """Borra una credencial puntual (sin picker interactivo: id explícito)."""
    return run_opencode(["auth", "logout", "--standalone", integration_id, credential_id])


def default_paths():
    """Rutas por defecto dentro del contenedor (XDG_DATA_HOME de opencode)."""
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return (
        os.path.join(data_home, "opencode-global", "auth.json"),
        os.path.join(data_home, "opencode", "opencode.db"),
    )


def cmd_seed(auth_path, db_path):
    """Reconcilia la base del proyecto contra el auth.json canónico."""
    canonical = static_keys(read_canonical(auth_path))
    if not canonical:
        return 0

    log(f"canónicas: {', '.join(sorted(canonical))} ({auth_path})")
    log("login en la TUI = override local; para compartirlo: opencode.sh --credentials-export <proyecto>")

    plan = reconcile(canonical, read_project_credentials(db_path))

    for integration_id, credential_id in plan.logouts:
        ok, detail = logout_credential(integration_id, credential_id)
        if not ok:
            warn(f"{integration_id}: no se pudo quitar la credencial vieja ({detail})")
            plan.imports.pop(integration_id, None)

    for integration_id in plan.overrides:
        log(f"{integration_id}: override local, se respeta")

    if not plan.imports:
        return 0

    ok, detail = import_credentials(plan.imports)
    if not ok:
        warn(f"no se pudieron importar las credenciales ({detail})")
        return 0
    rotated = {integration_id for integration_id, _ in plan.logouts}
    for integration_id in plan.imports:
        action = "actualizada (key rotada)" if integration_id in rotated else "sembrada"
        log(f"{integration_id}: {action}")
    return 0


def cmd_export(db_path, auth_path):
    """Vuelca las API keys del proyecto al auth.json canónico."""
    if not os.path.exists(db_path):
        warn(f"no existe la base del proyecto: {db_path}")
        return 1

    # De cada integración se prefiere la credencial activa; si hay varias con
    # keys distintas se avisa, porque elegir una es una decisión del usuario.
    exported = {}
    candidates = {}
    for cred in read_project_credentials(db_path):
        key = cred.key
        if not key:
            continue
        candidates.setdefault(cred.integration_id, []).append(cred)
    for integration_id, creds in candidates.items():
        keys = {cred.key for cred in creds}
        chosen = next((cred for cred in creds if cred.active), creds[0])
        exported[integration_id] = chosen.key
        if len(keys) > 1:
            warn(f"{integration_id}: {len(keys)} keys distintas en el proyecto, se exporta la activa")

    if not exported:
        warn("el proyecto no tiene API keys para exportar")
        return 1

    entries = read_canonical(auth_path)
    for integration_id, key in exported.items():
        entries[integration_id] = {"type": "api", "key": key}
    write_canonical(auth_path, entries)
    for integration_id in sorted(exported):
        log(f"{integration_id}: exportada (…{exported[integration_id][-4:]})")
    log(f"archivo canónico actualizado: {auth_path}")
    return 0


def cmd_put(integration_id, auth_path):
    """Escribe la key de una integración en auth.json (key por stdin)."""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", integration_id or ""):
        warn(f"id de integración inválido: {integration_id!r}")
        return 1
    key = sys.stdin.read().strip()
    if not key or any(char.isspace() for char in key):
        warn("la key llegó vacía o con espacios")
        return 1

    entries = read_canonical(auth_path)
    entries[integration_id] = {"type": "api", "key": key}
    write_canonical(auth_path, entries)
    log(f"{integration_id}: guardada (…{key[-4:]}) en {auth_path}")
    return 0


def parse_args(argv):
    """Parsea el subcomando y sus argumentos (sin dependencias externas)."""
    if not argv or argv[0] in ("-h", "--help"):
        print((__doc__ or "").strip())
        return None

    command = argv[0]
    auth_path, db_path = default_paths()
    positional = []
    index = 1
    while index < len(argv):
        arg = argv[index]
        if arg == "--auth":
            index += 1
            auth_path = argv[index] if index < len(argv) else auth_path
        elif arg == "--db":
            index += 1
            db_path = argv[index] if index < len(argv) else db_path
        else:
            positional.append(arg)
        index += 1
    return command, positional, auth_path, db_path


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return 0
    command, positional, auth_path, db_path = parsed

    if command == "seed":
        return cmd_seed(auth_path, db_path)
    if command == "export":
        return cmd_export(db_path, auth_path)
    if command == "put" and len(positional) == 1:
        return cmd_put(positional[0], auth_path)
    warn(f"uso inválido: {' '.join(argv)}")
    print((__doc__ or "").strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
