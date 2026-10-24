<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Estilos CSS para md2pdf

Estilos alternativos para dar formato a los informes Markdown generados con
`md2pdf`. Cada archivo es un CSS autocontenido (tipografías del sistema, sin
dependencias externas) listo para usarse en PDF (WeasyPrint) y en HTML.

## Ubicación de los estilos y precedencia

`md2pdf --style <nombre>` busca el archivo `<nombre>.css` en las siguientes
carpetas, en orden de precedencia (la primera que exista gana):

1. `$MD2PDF_STYLES_DIR` (variable de entorno, si está definida)
2. `~/.config/opencode/css-styles/` — **config global del usuario** (desplegada
   por `agents_update.sh`; se monta dentro del contenedor, gana sobre la imagen)
3. `/usr/local/share/md2pdf/css-styles/` — **horneada en la imagen** del contenedor
4. `<dir del script>/css-styles/` — junto a `md2pdf.py` (repo o instalación local)
5. relativo al directorio del `.md` de entrada (fallback local)

Si el estilo no se encuentra en ninguna carpeta, se usa el **CSS embebido por
defecto** en `md2pdf.py`.

Para ver los estilos detectados: `md2pdf --list-styles`.

## Uso

```bash
md2pdf informe.md --style github        # PDF con estilo GitHub
md2pdf informe.md --style paper --html  # HTML con estilo paper
md2pdf informe.md --list-styles         # lista estilos disponibles y detectados
```

## Estilos

| Archivo | Nombre (`--style`) | Descripción |
|---------|--------------------|-------------|
| `github.css` | `github` | Replica el render de GitHub en modo claro: sans-serif (`-apple-system`, `Segoe UI`, `Noto Sans`), tablas con líneas, bloques de código, alerts (note/warning/tip/caution). Ideal para documentación técnica. |
| `pandoc.css` | `pandoc` | Estilo académico tipo Pandoc: tipografía serif (Georgia/Times), márgenes amplios, notas y bibliografía. Ideal para artículos y documentos formales. |
| `newsprint.css` | `newsprint` | Estilo periódico/noticias (adaptado del tema Newsprint de Typora): serif elegante, buen contraste, lectura cómoda. Ideal para informes de lectura. |
| `notion.css` | `notion` | Estilo moderno y limpio tipo Notion: sans-serif, espaciado generoso, bloques de código con fondo gris suave. Ideal para notas e informes de investigación. |
| `paper.css` | `paper` | Estilo formal para papers/publicaciones científicas: serif, numeración de páginas, secciones claras. Ideal para trabajos de investigación. |

Todos los estilos usan `text-align: justify` en el cuerpo y página A4 con
numeración (`@page`).

## CSS personalizado

Para usar un CSS propio en lugar de un estilo predefinido:

```bash
md2pdf informe.md --custom-css /ruta/mi-estilo.css
```

`--custom-css` tiene prioridad sobre `--style`.

## Añadir un estilo nuevo

1. Crear `<nombre>.css` en esta carpeta.
2. Incluir `@page` (tamaño A4, márgenes, numeración) si va a usarse en PDF.
3. Documentarlo en la tabla de arriba.

## Deploy

- En el **contenedor**: los estilos se hornean en `/usr/local/share/md2pdf/css-styles/`
  (ver `Containerfile`).
- En **host y contenedor**: `agents_update.sh` despliega `src/tools/css-styles/`
  a `~/.config/opencode/css-styles/` (stage `styles`, por defecto; `--no-styles`
  para omitirlo). Ese README viaja junto a los estilos para dar contexto a los
  agentes (alternativas y ayuda con estilos).