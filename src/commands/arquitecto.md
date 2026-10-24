---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
description: Diseñar y planificar un proyecto con el agente arquitecto a partir de una idea
agent: arquitecto
---

Inicia el flujo del agente **arquitecto** con la idea del proyecto como insumo de la fase de elicitación.

Idea del proyecto: $ARGUMENTS

1. **Agente:** este comando fija `agent: arquitecto` en su frontmatter. Si tu versión del loader de
   commands lo ignora, trabajá igual esta sesión bajo las reglas del archivo del agente
   (`~/.config/opencode/agents/arquitecto.md`): no escribir código de aplicación,
   artefactos solo en `documents/arquitectura/**` (scratch: `/tmp/opencode/arquitecto/**`), gate de
   aprobación humana por fase, y cargar on-demand las skills `module-decomposition`,
   `architecture-decisions` y `delivery-planning` cuando la fase lo pida.
2. **Arrancar SIEMPRE en la fase de Ellicitación**, nunca en arquitectura: con la herramienta de
   preguntas, **una pregunta por vez** contra la idea recibida (eventos cruciales del sistema,
   ranking de atributos de calidad, restricciones, equipo y plazo).
3. **Sin argumento** (`$ARGUMENTS` vacío): pedir primero la idea del proyecto antes de continuar.
4. **Cerrar la elicitación** con un resumen (alcance + ranking de atributos + supuestos +
   estimación en rangos) y pedir aprobación explícita para pasar a la fase Arquitectura.
