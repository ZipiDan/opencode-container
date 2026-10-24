---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: mermaid2png
description: Renderiza diagramas Mermaid (.mmd) a PNG localmente con mermaid-cli y Chrome headless, sin servicios de terceros. Usar cuando el usuario pida generar PNG/imagen desde un diagrama Mermaid o un archivo .mmd.
version: 2
---

# Mermaid → PNG local

Convierte archivos `.mmd` (Mermaid) en `.png` sin usar ningún servicio web
(kroki/mermaid.ink quedan excluidos: son terceros).

## Requisitos

1. `node` + `npx`.
2. **Contenedor de opencode.sh**: `@mermaid-js/mermaid-cli` y un Chrome headless están
   **horneados en la imagen**, junto con las librerías del sistema (libnspr4, libnss3, etc.).
   No hay que instalar nada.
3. **opencode en host**: el paquete se resuelve con `npx` (que lo baja on-demand la primera vez).
   Si Chrome falla por librerías faltantes, instalalas según tu distro:

```bash
# Debian/Ubuntu
apt-get install -y -qq libnspr4 libnss3 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0t64 \
  libatspi2.0-0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libxkbcommon0 \
  libasound2t64 libcups2 libpango-1.0-0 libcairo2 fonts-liberation
```

4. En contenedores, Chrome necesita `--no-sandbox`: el script ya lo inyecta vía
   puppeteer-config (`-p`).

## Uso

```bash
# Un diagrama -> PNG al lado (caso_1c.mmd -> caso_1c.png)
python3 scripts/mermaid2png.py caso_1c.mmd

# Salida y escala explícitas
python3 scripts/mermaid2png.py caso_1c.mmd -o flujo.png -s 3

# Todos los .mmd de un árbol (ej: los 17 casos del Mapa de Mesa)
python3 scripts/mermaid2png.py --all states/
```

## Ejemplo real (este proyecto)

El caso 1c del *Mapa casos de Mesa.odt* bloqueado como `investigaciones/caso_1c.mmd`
(stateDiagram-v2 con timer de 24 h) renderiza a `investigaciones/caso_1c.png` con:

```bash
python3 scripts/mermaid2png.py /workspace/investigaciones/caso_1c.mmd
```

## Origen del Mermaid: generado desde el YAML de la FSM (opcional)

Si el flujo vive en YAML de `python-statemachine`, el .mmd NO se escribe a mano:
se deriva del archivo ejecutable (única fuente de verdad) con el extra `io`:

```python
from statemachine.io import load
sm = load("states/caso_1c_bloqueo.yaml")()
Path("caso_1c.mmd").write_text(f"{sm:mermaid}")   # Mermaid autogenerado
# luego: python3 scripts/mermaid2png.py caso_1c.mmd
```

Nota honesta: `f"{sm:mermaid}"` emite el diagrama plano (sin colores/títulos); para
diagramas "de presentación" (classDef, subgraphs) editar el .mmd generado o mantener
una plantilla aparte. El pipeline de CI (render + validación `validate=True`) usa la
derivación automática para que el diagrama nunca mienta sobre el flujo.

## Troubleshooting

| Síntoma | Causa y arreglo |
|---|---|
| `error while loading shared libraries: libnspr4.so` | Falta deps de Chrome → instalar lote de arriba (en contenedor ya están) |
| `Failed to connect to socket /run/dbus` | Warning inofensivo en contenedores |
| `Chromium instantiation failed` | Agregar `--no-sandbox` (el script ya usa `-p` con config propia) |
| Render trancado/lento | `npx` resuelve el paquete la primera vez (~1 min); siguientes, cache |
