<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Terceros: licencias y agradecimientos

Este proyecto no sería posible sin trabajo ajeno. Este archivo declara **qué
parte del repo es propia y qué parte viene de terceros**, con su licencia y su
titular, para que nadie confunda autoría.

- Código y artefactos funcionales propios: **MPL-2.0** (ver `LICENSE`).
- Documentación propia: **CC BY-SA 4.0**.
- Componentes de terceros: **su licencia original**, que se conserva intacta.

Los textos completos de las licencias están en `LICENSES/`. Este archivo no
reemplaza esos textos: los referencia.

## Mapa rápido

| Componente | Titular | Licencia | Dónde vive | Se modificó |
|---|---|---|---|---|
| OpenCode | opencode (SST) | MIT | binario instalado en la imagen (`Containerfile`) | No |
| heinzel | Stefan Wintermeyer | MIT | `src/agents/sysadmin/**` (vendorizado y adaptado a opencode) | Sí: reescrituras Claude Code → opencode, memoria por proyecto, add-on landlock |
| frontend-slides | Zara Zhang | MIT | `src/skills/frontend-slides/**` | Parcial: ver detalle abajo |
| cybersecurity-skills | Bri Russell | MIT | `src/agents/cyberseguridad/skills/cyberseguridad-catalog/references/**` | No (catálogo regenerado desde upstream) |
| MADR | Oliver Kopp y contribuidores | MIT OR CC0-1.0 | `src/agents/arquitecto/skills/architecture-decisions/references/adr-madr.md` | Sí: estructura adaptada al flujo del agente |
| ADR de Nygard | Michael Nygard | Solo patrón conceptual (sin texto verbatim) | `src/agents/arquitecto/skills/architecture-decisions/references/adr-nygard.md` | N/A |
| ddd-crew | ddd-crew | CC BY-SA 4.0 | `src/agents/arquitecto/skills/module-decomposition/references/canvas-modulo.md`, `vocabulario-relaciones.md` | Sí: campos y vocabulario reformulados |
| Debian | Debian Project y mantenedores de cada paquete | Diversas (GPL, LGPL, Apache, BSD, MIT…) | imagen base del contenedor | No |

## OpenCode

- Repositorio: <https://github.com/sst/opencode>
- Licencia: MIT — Copyright (c) 2025 opencode
- Cómo se usa: la imagen descarga el binario oficial con el instalador v2
  (`src/Containerfile`). **No se modifica ni se redistribuye como código
  propio.** El aviso MIT viaja con el repo y con el tarball de fuentes
  (este archivo + `LICENSES/MIT.txt`), que es el artefacto que se distribuye.
- **Si en el futuro se publica la imagen ya construida** (por ejemplo en un
  registry), MIT exige que el aviso acompañe al binario: en ese caso hay que
  copiar `LICENSES/MIT.txt` dentro de la imagen. Hoy no se hace para no tocar
  el `Containerfile`, que está congelado por ser código probado.

## heinzel

- Repositorio: <https://github.com/wintermeyer/heinzel>
- Licencia: MIT — Copyright (c) 2026 Stefan Wintermeyer
- Cómo se usa: el agente `sysadmin` y sus skills `heinzel-*` son un
  **vendorizado con reescrituras** (adaptación del ruleset a opencode, memoria
  100% por proyecto, disambiguación por cliente). Los archivos derivados llevan
  en su header SPDX las dos líneas de copyright. El procedimiento de
  actualización está en `src/agents/sysadmin/upgrade-heinzel.md`.
- Excepción propia: `src/agents/sysadmin/skills/calisto-landlock/**` es un
  add-on de Calisto, no de heinzel (ver `src/agents/sysadmin/ADDONS.md`).

## frontend-slides

- Repositorio: <https://github.com/zarazhangrui/frontend-slides>
- Licencia: MIT — Copyright (c) 2025 Zara Zhang
- Snapshot: commit `9906a34` (2026-06-23), ver `src/skills/frontend-slides/PROVENANCE.md`.
- **Copias literales, sin tocar** (conservan su licencia, sin header propio):
  `STYLE_PRESETS.md`, `animation-patterns.md`, `html-template.md`,
  `viewport-base.css` y todo `bold-template-pack/**`.
- **Reescrituras propias** (MPL-2.0, con el copyright de Zara Zhang
  conservado): `SKILL.md` y `scripts/*` (deps, export-pdf, export-slides,
  extract-pptx, pptx-extract), según la tabla de reescrituras del PROVENANCE.

## cybersecurity-skills

- Repositorio: <https://github.com/briiirussell/cybersecurity-skills>
- Licencia: MIT — Bri Russell
- Texto original: `src/agents/cyberseguridad/UPSTREAM-LICENSE-MIT.txt`
- Los 29 `references/*.md` son copias del catálogo upstream (regenerables con
  `build-catalog.mjs`) y llevan su marca de licencia en un comentario HTML.
  No se les agrega header propio.

## MADR y ADR de Nygard

- MADR: <https://github.com/adr/madr> — MIT OR CC0-1.0.
- Nygard: <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions> —
  se toma el **patrón** de cinco secciones, sin copiar texto.
- El hub `architecture-decision-record/architecture-decision-record` sigue con
  licencia NOASSERTION: **no se copia nada de ahí** (check abierto en
  `src/agents/arquitecto/PROVENANCE.md`).

## ddd-crew

- Repositorios: <https://github.com/ddd-crew/bounded-context-canvas>,
  <https://github.com/ddd-crew/context-mapping>
- Licencia: CC BY-SA 4.0. Los dos archivos derivados **permanecen en CC BY-SA
  4.0** (el share-alike no permite relicenciarlos a MPL) y llevan su header
  SPDX con la atribución correspondiente.

## Debian y paquetes horneados en la imagen

La imagen parte de `docker.io/debian:stable-backports` y agrega paquetes del
sistema, además de herramientas instaladas con npm y pip (pyright, ruff,
playwright + Chromium, mermaid-cli, python-pptx).

- Cada paquete Debian trae su atribución en `/usr/share/doc/<paquete>/copyright`.
- Los textos de licencia comunes están en `/usr/share/common-licenses/`
  (GPL, LGPL, Apache, BSD).
- Los paquetes npm y pip traen su `LICENSE` dentro del paquete instalado
  (`node_modules/**/LICENSE`, `*.dist-info/licenses/`).

No se enumeran uno por uno porque **no se modifican ni se relicencian**: se
distribuyen tal cual los publica su mantenedor, con su atribución original
intacta.

## Texto MIT aplicado a los componentes de terceros

El cuerpo de la licencia MIT es idéntico para todos; lo que cambia es la línea
de copyright, que está en la tabla de arriba y en el header de cada archivo
derivado. El texto completo está en `LICENSES/MIT.txt`, que viaja junto a este
archivo (repo e imagen), de modo que el aviso y la licencia siempre acompañan a
las copias.

## Código fuente de los componentes MPL-2.0

MPL-2.0 exige que quien reciba un binario cubierto pueda obtener su código
fuente. El fuente de todo lo MPL-2.0 de este proyecto (incluido el binario
`landlock_rosh` que viaja en la imagen) está en el repositorio del proyecto,
desde el que se construyó la imagen. La ruta exacta de cada pieza está en la
tabla de arriba.

## Agradecimientos

Gracias a opencode (SST), a Stefan Wintermeyer, a Zara Zhang, a Bri Russell, a
ddd-crew, a Oliver Kopp y a la comunidad MADR, y al Proyecto Debian y a cada
mantenedor de paquete que hace que este contenedor exista. Este proyecto se
apoya en ese trabajo; la licencia MPL-2.0 aplica solo a lo desarrollado acá y
no reclama nada sobre lo ajeno.
