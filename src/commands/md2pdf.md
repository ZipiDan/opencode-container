---
description: Genera un PDF a partir de un informe Markdown
---

Convierte un informe en Markdown a PDF estilizado con el conversor `md2pdf`.

1. **Resolver el archivo de entrada:**
   - Si hay argumento (`/md2pdf <ruta>`), usalo tal cual (relativo o absoluto).
   - Si no, buscá el informe `.md` más reciente en `investigaciones/` (por nombre `YYYY-MM-DD-*.md`).

2. **Ejecutar el conversor:**
   - Si el comando `md2pdf` está en el PATH, ejecutá `md2pdf <entrada.md>` (genera `<entrada>.pdf` en el mismo directorio).
   - Si no está en el PATH, ejecutá `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/scripts/md2pdf.py <entrada.md>`.

3. **Si falla por dependencias faltantes (`markdown`/`weasyprint`):**
   - Ejecutá `md2pdf --doctor` (o el script con `--doctor`) y mostrá al usuario las instrucciones de instalación según su sistema operativo (apt/dnf/pacman/brew/WSL).
   - No recurras a otro método de conversión: la respuesta debe indicar que para ejecutar el comando se deben instalar esas librerías.
   - Ofrecé dejar el comando accesible en el PATH ejecutando `md2pdf --install` (se copia a `~/.local/bin`), y pedí confirmación al usuario antes de instalarlo.

4. **Informar al usuario** la ruta del PDF generado.