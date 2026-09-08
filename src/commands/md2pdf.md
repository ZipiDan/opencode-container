---
description: Genera un PDF (o HTML) a partir de un informe Markdown
---

Convierte un informe en Markdown a PDF estilizado con el conversor `md2pdf`. También puede generar HTML.

1. **Resolver el archivo de entrada:**
   - Si hay argumento (`/md2pdf <ruta>`), usalo tal cual (relativo o absoluto).
   - Si no, buscá el informe `.md` más reciente en `documents/investigaciones/` (por nombre `YYYY-MM-DD-*.md`).

2. **Ejecutar el conversor:**
   - Si el comando `md2pdf` está en el PATH, ejecutá `md2pdf <entrada.md>` (genera `<entrada>.pdf` en el mismo directorio).
   - Si no está en el PATH, ejecutá `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/scripts/md2pdf.py <entrada.md>`.

3. **Flags opcionales:**
   - `--style <nombre>`: estilo CSS (`github`, `pandoc`, `newsprint`, `notion`, `paper`). Sin flag se usa el estilo embebido por defecto. Para conocer los estilos disponibles y detectados, ejecutá `md2pdf --list-styles`.
   - `--custom-css <archivo.css>`: CSS personalizado (ruta absoluta o relativa); tiene prioridad sobre `--style`.
   - `--html`: genera HTML autocontenido en lugar de PDF (deriva `<entrada>.html`).
   - Ejemplos: `md2pdf <entrada.md> --style paper`, `md2pdf <entrada.md> --html`, `md2pdf <entrada.md> --style notion --html`.

4. **Si falla por dependencias faltantes (`markdown`/`weasyprint`):**
   - Ejecutá `md2pdf --doctor` (o el script con `--doctor`) y mostrá al usuario las instrucciones de instalación según su sistema operativo (apt/dnf/pacman/brew/WSL).
   - No recurras a otro método de conversión: la respuesta debe indicar que para ejecutar el comando se deben instalar esas librerías.
   - Ofrecé dejar el comando accesible en el PATH ejecutando `md2pdf --install` (se copia a `~/.local/bin`), y pedí confirmación al usuario antes de instalarlo.

5. **Informar al usuario** la ruta del archivo generado.