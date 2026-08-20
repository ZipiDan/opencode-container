#!/usr/bin/python3
"""Genera un PDF estilizado a partir de un informe Markdown.

Uso:
  md2pdf <entrada.md> [salida.pdf]   Genera el PDF (con 1 argumento deriva el .pdf)
  md2pdf --doctor                    Diagnostica dependencias y PATH; instrucciones por OS
  md2pdf --install [dir]             Se copia a ~/.local/bin/md2pdf (u otro dir) para
                                     dejarlo accesible en el PATH (pide confirmación)
  md2pdf --install --yes [dir]       Igual que --install pero sin confirmación
  md2pdf --help                      Muestra esta ayuda

Requiere los paquetes de Python 'markdown' y 'weasyprint' en el intérprete con el
que se ejecuta (python del sistema, p. ej. /usr/bin/python3). NO hay fallback
silencioso: si faltan las dependencias, el script lo informa y guía la instalación
según el sistema operativo del anfitrión ('md2pdf --doctor').
"""

import os
import platform
import shutil
import stat
import sys

VERSION = 1

CSS = """
@page {
    size: A4;
    margin: 2cm 2.5cm;
    @bottom-center { content: counter(page) " / " counter(pages); font-size: 9px; color: #888; }
}
body {
    font-family: 'DejaVu Sans', 'Noto Sans', Helvetica, Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #1a1a1a;
}
h1 {
    font-size: 20pt;
    color: #1a1a1a;
    border-bottom: 3px solid #1a1a1a;
    padding-bottom: 8px;
    margin-top: 0;
}
h2 {
    font-size: 15pt;
    color: #1a1a1a;
    border-bottom: 1.5px solid #ccc;
    padding-bottom: 4px;
    margin-top: 28px;
    page-break-after: avoid;
}
h3 {
    font-size: 12.5pt;
    color: #1a1a1a;
    margin-top: 20px;
    page-break-after: avoid;
}
h4 {
    font-size: 11.5pt;
    color: #333;
    margin-top: 16px;
    page-break-after: avoid;
}
p { margin: 6px 0; text-align: justify; }
strong { color: #1a1a1a; }
a { color: #1565c0; text-decoration: none; }
ul, ol { margin: 8px 0 8px 20px; }
li { margin: 3px 0; }
hr {
    border: none;
    border-top: 1px solid #ccc;
    margin: 20px 0;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 10pt;
}
th {
    background: #1a1a1a;
    color: white;
    padding: 8px 12px;
    text-align: left;
    font-weight: 600;
}
td {
    padding: 7px 12px;
    border-bottom: 1px solid #e0e0e0;
}
tr:nth-child(even) td { background: #f5f9ff; }
.meta { font-size: 10pt; color: #555; margin-bottom: 16px; }
.meta strong { color: #333; }
"""

HELP = (__doc__ or "").strip()


def check_deps():
    """Estado de las dependencias requeridas (markdown, weasyprint)."""
    def _try(mod):
        try:
            __import__(mod)
            return True
        except ImportError:
            return False
    return {"markdown": _try("markdown"), "weasyprint": _try("weasyprint")}


def detect_distro():
    """Distribución Linux (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE...)."""
    if platform.system().lower() != "linux":
        return ""
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            data = {}
            for line in f:
                if "=" in line:
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip().strip('"')
        id_like = str(data.get("ID_LIKE") or data.get("ID") or "").lower()
        if "debian" in id_like or "ubuntu" in id_like:
            return "debian"
        if "fedora" in id_like or "rhel" in id_like or "centos" in id_like:
            return "fedora"
        if "arch" in id_like:
            return "arch"
        if "suse" in id_like or "opensuse" in id_like:
            return "suse"
        return data.get("ID", "desconocido").lower()
    except OSError:
        return "desconocido"


def install_instructions():
    """Instrucciones de instalación de las deps según el OS del anfitrión."""
    system = platform.system().lower()
    if system == "linux":
        distro = detect_distro()
        if distro == "debian":
            return ("Linux (Debian/Ubuntu):\n"
                    "  sudo apt-get install -y python3-markdown weasyprint")
        if distro == "fedora":
            return ("Linux (Fedora/RHEL/CentOS):\n"
                    "  sudo dnf install -y python3-markdown python3-weasyprint")
        if distro == "arch":
            return ("Linux (Arch/Manjaro):\n"
                    "  sudo pacman -S python-markdown python-weasyprint")
        if distro == "suse":
            return ("Linux (openSUSE):\n"
                    "  sudo zypper install -y python3-markdown python3-weasyprint")
        return (f"Linux (distribución '{distro}'):\n"
                "  instala los paquetes 'python3-markdown' y 'weasyprint' con el gestor "
                "de paquetes de tu distribución.")
    if system == "darwin":
        return ("macOS:\n"
                "  opción 1 (Homebrew):  brew install python-markdown weasyprint\n"
                "  opción 2 (pip):       brew install pango && pip3 install --user markdown weasyprint")
    if system == "windows":
        return ("Windows:\n"
                "  weasyprint nativo es problemático (requiere GTK/Pango).\n"
                "  Se recomienda WSL (Ubuntu): dentro de WSL ejecutá\n"
                "    sudo apt-get install -y python3-markdown weasyprint")
    return (f"Sistema '{platform.system()}' no reconocido:\n"
            "  instalá los paquetes de Python 'markdown' y 'weasyprint' "
            "con el gestor de paquetes de tu sistema.")


def doctor():
    deps = check_deps()
    missing = [name for name, ok in deps.items() if not ok]
    in_path = shutil.which("md2pdf")

    print("md2pdf -- diagnóstico")
    print("=" * 40)
    print(f"  versión:       {VERSION}")
    print(f"  python:        {sys.executable}")
    print(f"  OS:            {platform.system()} ({platform.release()})")
    if platform.system().lower() == "linux":
        print(f"  distro:        {detect_distro()}")
    print(f"  markdown:      {'OK' if deps['markdown'] else 'FALTA'}")
    print(f"  weasyprint:    {'OK' if deps['weasyprint'] else 'FALTA'}")
    print(f"  md2pdf en PATH: {'sí (' + in_path + ')' if in_path else 'no'}")
    print(f"  script actual: {os.path.abspath(__file__)}")
    print()

    if missing:
        print("FALTAN dependencias. Para ejecutar este comando se deben instalar las")
        print("librerías 'python3-markdown' y 'weasyprint'. Instalación según el sistema")
        print("operativo del anfitrión:\n")
        print("  " + install_instructions().replace("\n", "\n  "))
        print()
        print("Tras instalarlas, verificá de nuevo con 'md2pdf --doctor'.")
        if not in_path:
            print("El comando 'md2pdf' no está en el PATH. Para dejarlo accesible por")
            print("opencode ejecutá 'md2pdf --install' (se copia a ~/.local/bin).")
        sys.exit(1)

    print("Todas las dependencias están presentes.")
    if not in_path:
        print("El comando 'md2pdf' no está en el PATH. Ejecutá 'md2pdf --install' para")
        print("dejarlo accesible por opencode (se copia a ~/.local/bin).")
    sys.exit(0)


def install_to_path(target_dir=None, yes=False):
    """Se copia a sí mismo a ~/.local/bin (u otro dir) y lo hace ejecutable."""
    if not target_dir:
        target_dir = os.path.join(os.path.expanduser("~"), ".local", "bin")
    target_dir = os.path.abspath(os.path.expanduser(target_dir))
    target = os.path.join(target_dir, "md2pdf")

    print(f"Se instalará 'md2pdf' en: {target}")
    if shutil.which("md2pdf"):
        print(f"AVISO: ya hay un 'md2pdf' en el PATH: {shutil.which('md2pdf')}")
        print("       Este script lo reemplazará en el directorio elegido.")

    if not yes:
        try:
            ans = input("¿Continuar? (Y/s) ")
        except EOFError:
            ans = "s"
        if ans.strip().lower() not in ("y", "s", ""):
            print("Instalación cancelada.")
            sys.exit(0)

    os.makedirs(target_dir, exist_ok=True)
    shutil.copy2(os.path.abspath(__file__), target)
    mode = os.stat(target).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    os.chmod(target, mode)
    print(f"Instalado en: {target}")

    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    if target_dir in path_dirs:
        print("El directorio está en el PATH. Ya podés usar 'md2pdf'.")
    else:
        print("AVISO: el directorio NO está en el PATH. Agregalo, p. ej. con:")
        print(f"  echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc")
        print("  source ~/.bashrc")
    sys.exit(0)


def convert(md_path, pdf_path):
    if not os.path.isfile(md_path):
        print(f"ERROR: el archivo '{md_path}' no existe.", file=sys.stderr)
        sys.exit(1)

    deps = check_deps()
    missing = [name for name, ok in deps.items() if not ok]
    if missing:
        print("ERROR: faltan dependencias para generar el PDF: " + ", ".join(missing))
        print("Para ejecutar este comando se deben instalar las librerías")
        print("'python3-markdown' y 'weasyprint'. Ejecutá 'md2pdf --doctor' para ver")
        print("las instrucciones de instalación según el sistema operativo del anfitrión.")
        sys.exit(1)

    import markdown
    from weasyprint import HTML

    with open(md_path, "r", encoding="utf-8") as f:
        md_text = f.read()

    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "smarty"],
        output_format="html",
    )

    full_html = f"""<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8"><style>{CSS}</style></head>
<body>{html_body}</body>
</html>"""

    HTML(string=full_html).write_pdf(pdf_path)
    print(f"PDF generado: {pdf_path}")


def main():
    args = sys.argv[1:]

    if len(args) == 1 and args[0] in ("-h", "--help"):
        print(HELP)
        sys.exit(0)

    if args and args[0] in ("--doctor", "-d"):
        doctor()

    if args and args[0] in ("--install", "-i"):
        rest = args[1:]
        yes = "--yes" in rest or "-y" in rest
        rest = [a for a in rest if a not in ("--yes", "-y")]
        install_to_path(rest[0] if rest else None, yes=yes)

    if len(args) not in (1, 2):
        print(HELP, file=sys.stderr)
        sys.exit(1)

    md_path = args[0]
    if len(args) == 2:
        pdf_path = args[1]
    else:
        if not md_path.lower().endswith(".md"):
            print("ERROR: la salida se deriva del nombre de entrada; usá 'md2pdf <entrada.md> [salida.pdf]'.", file=sys.stderr)
            sys.exit(1)
        pdf_path = os.path.splitext(md_path)[0] + ".pdf"

    convert(md_path, pdf_path)


if __name__ == "__main__":
    main()