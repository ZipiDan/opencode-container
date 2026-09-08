# Agente investigador

Agente de investigación web multilingüe. Orquesta búsquedas en paralelo mediante subagentes, unifica los hallazgos en español citando fuentes, los muestra en pantalla y los guarda en `documents/investigaciones/`.

Tiene **dos modos**:
- **Simplificado (por defecto):** solo busca en español e inglés (`investigador-es`, `investigador-en`).
- **Extendido:** busca en todos los idiomas disponibles (`investigador-en/fr/es/de/zh/ru`).

Además, **reutiliza búsquedas recientes**: si ya se investigó el mismo tema con un subagente hace menos de 1 día (y el tema no cambió), no vuelve a ejecutar esa búsqueda; reutiliza los hallazgos del informe previo.

Este directorio (`src/agents/investigador/`) contiene todos los archivos del agente. El deploy **preserva la subcarpeta** en la config global, y cada archivo lleva un `name:` en el frontmatter que **fija el nombre del agente** (idéntico al descriptor `name:` de OpenCode): aunque el archivo viva en una subcarpeta, el agente se llama simplemente `investigador` (primario) o `investigador-en`, `investigador-fr`, etc. (subagentes).

## Componentes

| Archivo (repo) | Archivo desplegado | Agente (via `name:`) | Modo | Versión | Idioma |
|----------------|--------------------|----------------------|------|---------|--------|
| `investigador.md` | `agents/investigador/investigador.md` | `investigador` | primary | 9 | — (orquesta) |
| `investigador-en.md` | `agents/investigador/investigador-en.md` | `investigador-en` | subagent | 2 | EN |
| `investigador-fr.md` | `agents/investigador/investigador-fr.md` | `investigador-fr` | subagent | 2 | FR |
| `investigador-es.md` | `agents/investigador/investigador-es.md` | `investigador-es` | subagent | 2 | ES |
| `investigador-de.md` | `agents/investigador/investigador-de.md` | `investigador-de` | subagent | 2 | DE |
| `investigador-zh.md` | `agents/investigador/investigador-zh.md` | `investigador-zh` | subagent | 2 | ZH |
| `investigador-ru.md` | `agents/investigador/investigador-ru.md` | `investigador-ru` | subagent | 1 | RU |

## Uso

- Seleccionar el agente **investigador** en el selector de agentes (Tab) y darle el tema.
- Pedir el modo extendido explícitamente ("extendido", "extended", "todos los idiomas") si se quiere más allá de EN/ES.
- El informe final se redacta en español con fuentes citadas: **introducción** (tipo abstract), **cuerpo unificado** con los hallazgos de todos los subagentes organizados por temas (no por idioma), **discrepancias** entre fuentes cuando existen (con el idioma de cada fuente), **conclusión** y una **lista numerada compacta de fuentes** al final. Se muestra en pantalla y se guarda en `documents/investigaciones/YYYY-MM-DD-<tema>.md` del proyecto.
- Si el usuario pide la versión **PDF** del informe, el agente la genera con el comando global `/md2pdf` (o `md2pdf` si está en `PATH`). No degrada a otro método de conversión: si falta la herramienta o sus dependencias, reporta las instrucciones de instalación por OS de `md2pdf --doctor` y ofrece ejecutar `/md2pdf` cuando esté instalada.

## Mantenimiento

- Editar los `.md` de este directorio y subir la `version:` correspondiente.
- Aplicar con `../../agents_update.sh` (o `--check` para ver antes).