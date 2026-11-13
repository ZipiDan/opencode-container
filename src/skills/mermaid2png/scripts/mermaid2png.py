#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# mermaid2png.py — renderiza diagramas Mermaid (.mmd) a PNG localmente.
# Pipeline: npx @mermaid-js/mermaid-cli sobre el Chromium del sistema (sin servicios de terceros).
# Uso:  python3 mermaid2png.py caso_1c.mmd            -> caso_1c.png al lado
#       python3 mermaid2png.py caso_1c.mmd -o out.png -s 3
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PUPPETEER_FLAGS = ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]


def renderMmdToPng(mmd_path: Path, png_path: Path | None = None, scale: int = 2, background: str = "white") -> Path:
    """Genera el PNG desde un archivo .mmd. Si png_path es None, deriva el nombre."""
    if not mmd_path.is_file():
        raise FileNotFoundError(f"No existe el diagrama: {mmd_path}")
    out = png_path or mmd_path.with_suffix(".png")

    # Config de puppeteer en un transitorio: chrome necesita --no-sandbox en contenedores.
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as cfg:
        json.dump({"args": PUPPETEER_FLAGS}, cfg)
        cfg_path = Path(cfg.name)
    try:
        cmd = [
            "npx",
            "--yes",
            "@mermaid-js/mermaid-cli",
            "-i",
            str(mmd_path),
            "-o",
            str(out),
            "-b",
            background,
            "-s",
            str(scale),
            "-p",
            str(cfg_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False)
        if result.returncode != 0 or not out.is_file():
            tail = (result.stderr or result.stdout).strip().splitlines()[-5:]
            raise RuntimeError(f"mmdc fallo para {mmd_path}:\n  " + "\n  ".join(tail))
    finally:
        cfg_path.unlink(missing_ok=True)
    return out


def renderAllInDir(source_dir: Path, scale: int = 2) -> list:
    """Renders every .mmd found recursively (ej: los 17 casos del repo)."""
    return [renderMmdToPng(mmd, scale=scale) for mmd in sorted(source_dir.rglob("*.mmd"))]


def main():
    parser = argparse.ArgumentParser(description="Mermaid (.mmd) -> PNG local, sin servicios externos")
    parser.add_argument("mmd", nargs="+", type=Path, help="archivos .mmd a renderizar (o --all DIR)")
    parser.add_argument("-o", "--output", type=Path, help="PNG de salida (solo con UN archivo)")
    parser.add_argument("-s", "--scale", type=int, default=2, help="factores de escala (def. 2)")
    parser.add_argument("-b", "--background", default="white", help="color de fondo (def. white)")
    parser.add_argument("--all", type=Path, metavar="DIR", help="renderizar todos los *.mmd de un directorio")
    args = parser.parse_args()

    try:
        if args.all:
            made = renderAllInDir(args.all, scale=args.scale)
            for png in made:
                print(f"OK  {png}")
            return 0
        if args.output and len(args.mmd) > 1:
            parser.error("-o solo es valido con un unico .mmd")
        for mmd in args.mmd:
            png = renderMmdToPng(mmd, png_path=args.output, scale=args.scale, background=args.background)
            print(f"OK  {mmd} -> {png}")
    except (RuntimeError, FileNotFoundError) as err:
        print(f"ERROR: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
