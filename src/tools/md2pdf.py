#!/usr/bin/python3
"""Genera un PDF (o HTML) estilizado a partir de un informe Markdown.

Uso:
  md2pdf <entrada.md> [salida]           Genera el PDF (con 1 argumento deriva el .pdf)
  md2pdf <entrada.md> --style <nombre>   Usa un estilo CSS de la carpeta css-styles
  md2pdf <entrada.md> --custom-css <archivo.css>  Usa un CSS personalizado
  md2pdf <entrada.md> --html             Genera HTML en lugar de PDF (deriva el .html)
  md2pdf --list-styles                   Lista los estilos disponibles y detectados
  md2pdf --doctor                        Diagnostica dependencias y PATH; instrucciones por OS
  md2pdf --install [dir]                 Se copia a ~/.local/bin/md2pdf (u otro dir) para
                                         dejarlo accesible en el PATH (pide confirmación)
  md2pdf --install --yes [dir]           Igual que --install pero sin confirmación
  md2pdf --help                          Muestra esta ayuda

Flags opcionales:
  --style <nombre>       Estilo CSS detectado en las carpetas de estilos (ver más
                         abajo). Si no se indica, se usa el CSS embebido por defecto.
  --custom-css <archivo> CSS propio (ruta absoluta o relativa). Tiene prioridad
                         sobre --style.
  --html                 Genera un archivo HTML autocontenido en lugar de PDF.
  --list-styles          Lista los estilos detectados (no requiere dependencias).

Búsqueda de estilos (orden de precedencia):
  1. --custom-css <archivo> (ruta explícita, prioridad absoluta)
  2. $MD2PDF_STYLES_DIR (variable de entorno)
  3. $XDG_CONFIG_HOME/opencode/css-styles/ (config global del usuario;
     montada dentro del contenedor, gana sobre la imagen)
  4. /usr/local/share/md2pdf/css-styles/ (horneado en la imagen del contenedor)
  5. <dir del script>/css-styles/ (repo/desarrollo o instalación local)
  6. relativo al directorio del .md de entrada (fallback local)
  Si el estilo no se encuentra en ninguna, se usa el CSS embebido por defecto.

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

VERSION = "1.3"

CSS = """
@page {
    size: A4;
    margin: 2cm 2.5cm;
    @bottom-center { content: counter(page) " / " counter(pages); font-size: 9px; color: #888; }
}
body {
    font-family: 'DejaVu Sans', 'Noto Sans', Helvetica, Arial, sans-serif;
    font-size: 10px;
    line-height: 1.6;
    color: #1a1a1a;
    text-align: justify;
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
    font-size: 8.5pt;
    line-height: 1.35;
    table-layout: auto;
    page-break-inside: auto;
}
thead { display: table-header-group; }
th {
    background: #1a1a1a;
    color: white;
    padding: 6px 10px;
    text-align: left;
    font-weight: 600;
    page-break-inside: avoid;
}
td {
    padding: 5px 10px;
    border-bottom: 1px solid #e0e0e0;
    vertical-align: top;
    text-align: left;
    overflow-wrap: break-word;
    word-wrap: break-word;
    word-break: break-word;
    hyphens: auto;
}
tr { page-break-inside: avoid; }
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


def style_search_dirs(md_path=None):
    """Carpetas de estilos en orden de precedencia (lista de rutas)."""
    dirs = []
    env_dir = os.environ.get("MD2PDF_STYLES_DIR")
    if env_dir:
        dirs.append(env_dir)
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    dirs.append(os.path.join(config_home, "opencode", "css-styles"))
    dirs.append("/usr/local/share/md2pdf/css-styles")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dirs.append(os.path.join(script_dir, "css-styles"))
    dirs.append(script_dir)
    if md_path:
        md_dir = os.path.dirname(os.path.abspath(md_path))
        dirs.append(os.path.join(md_dir, "css-styles"))
        dirs.append(md_dir)
    return dirs


def find_style_css(style, md_path=None):
    """Localiza el CSS de un estilo por nombre (devuelve la ruta o None)."""
    if not style:
        return None
    fname = style if style.endswith(".css") else style + ".css"
    for base in style_search_dirs(md_path):
        candidate = os.path.join(base, fname)
        if os.path.isfile(candidate):
            return candidate
    return None


def list_styles():
    """Lista los estilos detectados en las carpetas de búsqueda (sin duplicados)."""
    found = {}
    for base in style_search_dirs():
        if not os.path.isdir(base):
            continue
        try:
            for name in sorted(os.listdir(base)):
                if not name.endswith(".css"):
                    continue
                style = name[:-4]
                if style not in found:
                    found[style] = os.path.join(base, name)
        except OSError:
            continue
    print("Estilos disponibles:")
    print(f"  default   (embebido en md2pdf.py)")
    for style in sorted(found):
        print(f"  {style:<10} ({found[style]})")
    print()
    print("Uso: md2pdf <entrada.md> --style <nombre>")
    print("     md2pdf <entrada.md> --custom-css <archivo.css> (CSS propio)")
    sys.exit(0)


def load_css(style=None, custom_css=None, md_path=None):
    """Devuelve el CSS a usar. Prioridad: --custom-css > --style > CSS embebido."""
    if custom_css:
        if not os.path.isfile(custom_css):
            print(f"ERROR: el archivo CSS '{custom_css}' no existe.", file=sys.stderr)
            sys.exit(1)
        with open(custom_css, encoding="utf-8") as f:
            return f.read()
    if style:
        path = find_style_css(style, md_path)
        if not path:
            print(f"ERROR: no se encontró el estilo '{style}'.", file=sys.stderr)
            print("Estilos disponibles: github, pandoc, newsprint, notion, paper.", file=sys.stderr)
            print("Usá 'md2pdf --help' para más ayuda.", file=sys.stderr)
            sys.exit(1)
        with open(path, encoding="utf-8") as f:
            return f.read()
    return CSS


def build_full_html(md_text, css):
    """Convierte el Markdown a HTML completo con el CSS embebido (autocontenido)."""
    import markdown
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "smarty"],
        output_format="html",
    )
    return f"""<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8"><style>{css}</style></head>
<body>{html_body}</body>
</html>"""


def convert(md_path, output_path, css=None, as_html=False):
    if not os.path.isfile(md_path):
        print(f"ERROR: el archivo '{md_path}' no existe.", file=sys.stderr)
        sys.exit(1)

    deps = check_deps()
    need = ["markdown"] if as_html else ["markdown", "weasyprint"]
    missing = [name for name in need if not deps.get(name)]
    if missing:
        print("ERROR: faltan dependencias: " + ", ".join(missing))
        print("Para ejecutar este comando se deben instalar las librerías")
        print("'python3-markdown' y 'weasyprint'. Ejecutá 'md2pdf --doctor' para ver")
        print("las instrucciones de instalación según el sistema operativo del anfitrión.")
        sys.exit(1)

    with open(md_path, "r", encoding="utf-8") as f:
        md_text = f.read()

    full_html = build_full_html(md_text, css or CSS)

    if as_html:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(full_html)
        print(f"HTML generado: {output_path}")
    else:
        from weasyprint import HTML
        HTML(string=full_html).write_pdf(output_path)
        print(f"PDF generado: {output_path}")


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

    if args and args[0] in ("--list-styles", "-ls"):
        list_styles()

    positional = []
    style_name = None
    custom_css = None
    as_html = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--style":
            if i + 1 >= len(args):
                print("ERROR: --style requiere un nombre de estilo.", file=sys.stderr)
                sys.exit(1)
            style_name = args[i + 1]
            i += 2
        elif a == "--custom-css":
            if i + 1 >= len(args):
                print("ERROR: --custom-css requiere la ruta de un archivo .css.", file=sys.stderr)
                sys.exit(1)
            custom_css = args[i + 1]
            i += 2
        elif a == "--html":
            as_html = True
            i += 1
        elif a.startswith("-"):
            print(f"ERROR: opción desconocida: {a}", file=sys.stderr)
            sys.exit(1)
        else:
            positional.append(a)
            i += 1

    if len(positional) not in (1, 2):
        print(HELP, file=sys.stderr)
        sys.exit(1)

    md_path = positional[0]
    if len(positional) == 2:
        output_path = positional[1]
    else:
        if not md_path.lower().endswith(".md"):
            print("ERROR: la salida se deriva del nombre de entrada; usá 'md2pdf <entrada.md> [salida]'.", file=sys.stderr)
            sys.exit(1)
        ext = ".html" if as_html else ".pdf"
        output_path = os.path.splitext(md_path)[0] + ext

    css = load_css(style_name, custom_css, md_path)
    convert(md_path, output_path, css=css, as_html=as_html)


if __name__ == "__main__":
    main()