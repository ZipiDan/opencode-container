#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
"""Preparación e higiene de las hojas del comando /hand-off (stdlib pura, Python 3.8+).

Subcomandos: prep, slug, seal, scan, delete, discard.

Regla de oro: ningún dato del humano viaja por argv. La tarea la escribe la tool
`write` en .opencode/handoffs/.task y acá se lee con O_NOFOLLOW; el único
argumento que acepta el script es la ruta de la hoja (`seal --brief`), validada
contra el directorio de handoffs. El disparo del subagente no vive acá: lo hace
el comando con la tool `subagent`.
"""

import argparse
import errno
import json
import os
import re
import stat
import sys
import unicodedata
from datetime import date, datetime
from pathlib import Path

# Retención: antigüedad máxima y cantidad de hojas vivas.
RETENTION_DAYS = 14
MAX_FILES = 10

SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,39}\Z")

# Los keywords exigen `:` o `=` para no matchear prosa («password reset flow»).
SECRET_PATTERNS = (
    re.compile(r"(?i)(api[_-]?key|secret|password|passwd|token|db_pass|secret_key)\s*[:=]\s*\S+"),
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_"),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"sk-(proj|ant)-[A-Za-z0-9_-]{10,}"),
    re.compile(r"glpat-[A-Za-z0-9_-]{10,}"),
    re.compile(r"sk_live_"),
    re.compile(r"xox[baprs]-"),
    re.compile(r"eyJ[A-Za-z0-9_-]{10,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"postgres(ql)?://[^:\s]+:[^@\s]+@"),
)


class HandoffError(Exception):
    """Falla controlada: `main` imprime el mensaje en stderr y sale con `code`."""

    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def isSymlink(path):
    """lstat sin seguir el link (también detecta symlinks rotos)."""
    try:
        return stat.S_ISLNK(os.lstat(str(path)).st_mode)
    except OSError:
        return False


def resolveProject(project):
    """Raíz del proyecto: absoluta, sin `..`, existente y distinta de `/`."""
    raw = Path(project) if project else Path.cwd()
    if not raw.is_absolute() or ".." in raw.parts:
        raise HandoffError(f"la raíz del proyecto debe ser absoluta y sin '..': {raw}")
    root = Path(os.path.realpath(str(raw)))
    if str(root) == os.sep:
        raise HandoffError(f"la raíz del proyecto no puede ser /: {raw}")
    if not root.is_dir():
        raise HandoffError(f"la raíz del proyecto no existe o no es un directorio: {root}")
    return root


def resolveInside(root, path, what="la ruta"):
    """realpath + commonpath: `path` tiene que quedar dentro de `root` y no ser `root`."""
    real = Path(os.path.realpath(str(path)))
    try:
        common = os.path.commonpath([str(root), str(real)])
    except ValueError:
        common = None
    if common != str(root) or str(real) == str(root):
        raise HandoffError(f"{what} resuelve fuera del proyecto ({root}): {real}")
    return real


def handoffsPath(root):
    """Ruta nominal del directorio de trabajo, sin tocar el disco."""
    return root / ".opencode" / "handoffs"


def requireHandoffsDirectory(root, create=False):
    """Valida (y opcionalmente crea) `.opencode/handoffs`; devuelve su realpath."""
    path = handoffsPath(root)
    if isSymlink(path):
        raise HandoffError(f"{path} es un symlink; no se escribe ni se borra ahí")
    # Se valida el padre ANTES de crear: un `.opencode` symlink hacia afuera no debe crear nada.
    if isSymlink(path.parent) or path.parent.exists():
        resolveInside(root, path.parent, "'.opencode'")
    if create:
        try:
            path.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            raise HandoffError(f"no se pudo crear {path}: {error}")
    if not path.exists():
        raise HandoffError(f"no existe {path}; corré primero 'prep'")
    real = resolveInside(root, path, "el directorio de handoffs")
    if not real.is_dir():
        raise HandoffError(f"{path} no es un directorio")
    return real


def openRegular(path, flags, mode=0):
    """Abre un archivo regular: `O_NOFOLLOW` corta symlinks, `O_NONBLOCK` no se cuelga en un FIFO
    y el `fstat` posterior rechaza lo que no sea regular."""
    try:
        descriptor = os.open(str(path), flags | os.O_NOFOLLOW | os.O_NONBLOCK, mode)
    except OSError as error:
        if error.errno == errno.ELOOP:
            hint = "es un symlink"
        elif error.errno == errno.ENXIO:
            hint = "es un FIFO sin lector"
        else:
            hint = str(error)
        raise HandoffError(f"no se pudo abrir {path} ({hint})")
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise HandoffError(f"{path} no es un archivo regular; no se abre")
    return descriptor


def readNoFollow(path):
    with os.fdopen(openRegular(path, os.O_RDONLY), "rb") as handle:
        return handle.read()


def writeNoFollow(path, content):
    """Escribe 0600 sin seguir symlinks, sin bloquearse y sólo sobre archivos regulares."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    with os.fdopen(openRegular(path, flags, 0o600), "wb") as handle:
        handle.write(content)


def removeFile(path):
    """Borra un archivo; que no exista no es un error."""
    try:
        os.unlink(str(path))
    except FileNotFoundError:
        return
    except OSError as error:
        raise HandoffError(f"no se pudo borrar {path}: {error}")


def candidatesPath(handoffs):
    """`.candidates` del directorio: un symlink ahí aborta la operación."""
    path = handoffs / ".candidates"
    if isSymlink(path):
        raise HandoffError(f"{path} es un symlink; no se escribe ni se borra")
    return path


def requireBriefFile(root, brief, what="la hoja"):
    """Regla única de la hoja: `.md` regular del primer nivel de `.opencode/handoffs`, sin symlinks."""
    text = str(brief or "").strip()
    if not text:
        raise HandoffError(f"falta la ruta de {what}")
    handoffs = requireHandoffsDirectory(root)
    path = Path(text)
    if not path.is_absolute():
        raise HandoffError(f"{what} debe ser una ruta absoluta: {path}")
    if ".." in path.parts:
        raise HandoffError(f"{what} no puede contener '..': {path}")
    if isSymlink(path):
        raise HandoffError(f"{what} es un symlink: {path}")
    if not path.is_file():
        raise HandoffError(f"no existe {what}: {path}")
    if path.suffix != ".md":
        raise HandoffError(f"{what} debe terminar en .md: {path}")
    real = resolveInside(root, path, what)
    if real.parent != handoffs:
        raise HandoffError(f"{what} no está en el primer nivel de {handoffs}: {real}")
    return real


def makeSlug(text):
    """Slug kebab-case ASCII, cortado en límite de palabra, 1..40 caracteres."""
    normalized = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    full = "-".join(re.findall(r"[a-z0-9]+", normalized.lower()))
    truncated = full[:40]
    slug = truncated
    # Si el corte parte una palabra, se descarta el fragmento final.
    if len(full) > 40 and full[40] != "-" and "-" in truncated:
        slug = truncated.rsplit("-", 1)[0]
    slug = slug.strip("-") or truncated.strip("-") or "handoff"
    if not SLUG_RE.fullmatch(slug):
        raise HandoffError(f"slug inválido: {slug!r}")
    return slug


def escapeForPrint(text):
    """Neutraliza ANSI/controles antes de imprimir un nombre que no controlamos."""
    if any(ord(char) < 32 or ord(char) == 127 for char in text):
        return text.encode("unicode_escape").decode("ascii")
    return text


def fileAgeDays(path):
    """Días completos transcurridos, mismo criterio que `find -mtime +N`."""
    return (datetime.now() - datetime.fromtimestamp(path.stat().st_mtime)).days


def retentionCandidates(handoffs):
    """Hojas del primer nivel con más de RETENTION_DAYS o fuera de las MAX_FILES más nuevas."""
    entries = []
    for entry in os.scandir(str(handoffs)):
        if entry.name.startswith(".") or not entry.name.endswith(".md"):
            continue
        if not entry.is_file(follow_symlinks=False):
            continue
        entries.append(Path(entry.path))
    newest_first = sorted(entries, key=lambda item: (-item.stat().st_mtime, item.name))
    stale = [item for item in newest_first if fileAgeDays(item) > RETENTION_DAYS]
    excess = newest_first[MAX_FILES:]
    return sorted({str(item) for item in stale} | {str(item) for item in excess})


def findSecretLines(text):
    """Números de línea con posibles secretos. Nunca devuelve el contenido."""
    return [number for number, line in enumerate(text.splitlines(), 1)
            if any(pattern.search(line) for pattern in SECRET_PATTERNS)]


def cmdPrep(root, args):
    handoffs = requireHandoffsDirectory(root, create=True)
    # `.task` incluido: un symlink commiteado ahí haría que la tool `write` (que sigue links) escriba
    # fuera del proyecto. `unlink` borra el link, nunca el destino (A-01). Se borra, no se aborta.
    for name in (".task", ".candidates"):
        removeFile(handoffs / name)
    print("OK prep")
    return 0


def cmdSlug(root, args):
    handoffs = requireHandoffsDirectory(root)
    task_path = handoffs / ".task"
    if isSymlink(task_path):
        raise HandoffError(f"{task_path} es un symlink; no se lee")
    if not task_path.is_file():
        raise HandoffError(f"no existe {task_path}; escribí la tarea primero")

    slug = makeSlug(readNoFollow(task_path).decode("utf-8", "replace"))

    stem = f"{date.today().isoformat()}-{slug}"
    brief = handoffs / f"{stem}.md"
    counter = 2
    while brief.exists() or isSymlink(brief):
        brief = handoffs / f"{stem}-{counter}.md"
        counter += 1

    # La ruta se valida antes de borrar .task: si algo falla, la tarea sigue ahí para reintentar.
    real_brief = resolveInside(root, brief, "la ruta de la hoja")
    if real_brief.parent != handoffs or real_brief.suffix != ".md":
        raise HandoffError(f"ruta de hoja inválida: {real_brief}")
    removeFile(task_path)

    print(f"SLUG={slug}")
    print(f"BRIEF={real_brief}")
    return 0


def cmdSeal(root, args):
    """Scan de secretos: imprime SÓLO el número de línea, nunca el contenido."""
    path = requireBriefFile(root, args.brief)
    raw = readNoFollow(path)
    if not raw.strip():
        raise HandoffError(f"la hoja está vacía: {path}")

    lines = findSecretLines(raw.decode("utf-8", "replace"))
    if lines:
        for number in lines:
            print(f"LINEA {number}")
        raise HandoffError(
            f"posibles secretos en {path}; reemplazá la línea completa por <REDACTADO> "
            f"y volvé a correr 'seal --brief {path}'")

    print("SCAN=limpio")
    return 0


def cmdScan(root, args):
    path = handoffsPath(root)
    if isSymlink(path):
        raise HandoffError(f"{path} es un symlink; no se escribe ni se borra ahí")
    if not path.is_dir():
        print("nada para borrar")
        return 0
    handoffs = resolveInside(root, path, "el directorio de handoffs")
    candidates_path = candidatesPath(handoffs)

    candidates = retentionCandidates(handoffs)
    if not candidates:
        removeFile(candidates_path)
        print("nada para borrar")
        return 0

    payload = json.dumps(candidates) + "\n"  # JSON: un nombre con `\n` no puede partir el conjunto (A-04)
    writeNoFollow(candidates_path, payload.encode("utf-8"))
    for number, item in enumerate(candidates, 1):
        print(f"{number}. {escapeForPrint(item)}")
    print(f"TOTAL={len(candidates)}")
    return 0


def deleteCandidate(root, target):
    """Borra un candidato de `.candidates` sin salirse de las hojas del primer nivel."""
    if Path(target).name.startswith("."):
        raise HandoffError(f"es un archivo de trabajo (.task/.candidates): {target}")
    requireBriefFile(root, target, "el candidato")
    try:
        os.unlink(str(Path(target)))
    except OSError as error:
        raise HandoffError(f"no se pudo borrar {target}: {error}")


def cmdDelete(root, args):
    handoffs = requireHandoffsDirectory(root)
    candidates_path = candidatesPath(handoffs)
    if not candidates_path.is_file():
        raise HandoffError(f"no existe {candidates_path}; corré primero 'scan'")

    # JSON: un nombre con `\n` no puede partir el conjunto (A-04).
    try:
        targets = json.loads(readNoFollow(candidates_path).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as error:
        raise HandoffError(f"no se pudo interpretar {candidates_path}: {error}")
    if not isinstance(targets, list) or not all(isinstance(item, str) for item in targets):
        raise HandoffError(f"{candidates_path} no contiene una lista de rutas")

    deleted = 0
    failures = 0
    for target in targets:
        if not target:
            continue
        try:
            deleteCandidate(root, target)
        except HandoffError as error:
            # Un candidato hostil no corta el resto del barrido.
            print(f"ERROR: {error}", file=sys.stderr)
            failures += 1
        else:
            deleted += 1

    removeFile(candidates_path)
    print(f"BORRADOS={deleted} FALLOS={failures}")
    return 1 if failures else 0


def cmdDiscard(root, args):
    handoffs = requireHandoffsDirectory(root)
    removeFile(candidatesPath(handoffs))
    print("descartado")
    return 0


HANDLERS = {
    "prep": cmdPrep,
    "slug": cmdSlug,
    "seal": cmdSeal,
    "scan": cmdScan,
    "delete": cmdDelete,
    "discard": cmdDiscard,
}


def buildParser():
    common = argparse.ArgumentParser(add_help=False)
    # SUPPRESS evita que el default del subparser pise el valor del parser principal.
    common.add_argument("--project", default=argparse.SUPPRESS, metavar="DIR",
                        help="raíz del proyecto (por defecto: cwd)")

    parser = argparse.ArgumentParser(
        prog="handoff.py", parents=[common],
        description="Prepara y mantiene las hojas del comando /hand-off (.opencode/handoffs).")
    commands = parser.add_subparsers(dest="command", required=True)
    for name, help_text in (
        ("prep", "valida la raíz y prepara .opencode/handoffs"),
        ("slug", "calcula el slug y la ruta de la hoja desde .task"),
        ("seal", "escanea secretos en la hoja indicada"),
        ("scan", "detecta hojas fuera de retención y escribe .candidates"),
        ("delete", "borra las hojas listadas en .candidates"),
        ("discard", "descarta .candidates sin borrar nada"),
    ):
        subparser = commands.add_parser(name, parents=[common], help=help_text, description=help_text)
        if name == "seal":
            subparser.add_argument("--brief", required=True, metavar="RUTA",
                                   help="ruta absoluta de la hoja a escanear")
    return parser


def main(argv=None):
    args = buildParser().parse_args(argv)
    try:
        root = resolveProject(getattr(args, "project", None))
        return HANDLERS[args.command](root, args)
    except HandoffError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return error.code


if __name__ == "__main__":
    sys.exit(main())
