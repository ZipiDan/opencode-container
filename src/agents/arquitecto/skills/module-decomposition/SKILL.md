---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: module-decomposition
description: >-
  Procedimiento de descomposición modular (agente arquitecto): elicitación de
  alcance → candidatos de módulo (pivotal events, conflictos de vocabulario) →
  canvas por módulo → vocabulario de relaciones → capas y fronteras → diagramas
  C4 en Mermaid → checklist "cuándo dividir". Usar en la fase Arquitectura, o al
  identificar módulos, límites de contexto y contratos entre ellos.
version: 1
---

# Module Decomposition — de requisitos a módulos con contratos

Objetivo: partir el alcance en módulos con contratos explícitos y un mapa C4
(context + containers) documentado en `documents/arquitectura/`. Los pasos van en
orden; cada paso deja artefacto.

Fuente general: PROVENANCE.md piezas 4, 5, 6, 9, 10, 11 y 12. Piezas 4 y 5:
https://github.com/ddd-crew/bounded-context-canvas · https://github.com/ddd-crew/context-mapping
(CC BY-SA 4.0 → atribución inline en las references). Todo está **adaptado** (paráfrasis propia
en español); donde la licencia lo exige, la referencia lleva su línea de atribución inline.

## 1. Elicitación de alcance

- Listá los **pivotal events**: sucesos que el sistema debe procesar ("el
  cliente paga", "el operador recibe un parte"). Si no salieron de la fase de
  elicitación del agente, pedilos al usuario: no los inventes.
- Agrupá los eventos por el asunto del mundo real que atienden —no por pantalla
  ni por tabla de base de datos.
- Fuente: https://github.com/ddd-crew/ddd-starter-modelling-process ·
  https://www.openknowledge.de/blog/mit-domain-driven-design-gute-bounded-contexts-finden

## 2. Candidatos de módulo

- Cada grupo de eventos con vocabulario propio → candidato de módulo.
- Buscá **conflictos de vocabulario** entre grupos: la misma palabra con dos
  significados, o dos palabras para la misma cosa → puntos de corte de límite.
- Regla de fusión: dos candidatos que comparten casi todo el vocabulario son
  un solo módulo; no los separes "por si acaso".
- Fuente: ddd-starter-modelling-process (Big Picture → candidatos → flow →
  canvas, secuencia adaptada a sesión individual sin workshop) + openknowledge.

## 3. Canvas por módulo

Completá la plantilla de `references/canvas-modulo.md` por candidato y
escribila en `documents/arquitectura/modulos/<slug>.md`.

Cláusula central: **los mensajes inbound/outbound del canvas SON el contrato
del módulo**; todo lo demás es detalle interno que el vecino no puede tocar
(smallest contract: pedir solo los campos que el caso necesita).

## 4. Vocabulario de relaciones

Nombrá cada arista entre módulos con un patrón de
`references/vocabulario-relaciones.md` (Partnership, Shared Kernel,
Customer-Supplier, Conformist, ACL, OHS, Published Language). Una relación sin
nombre se alucina en prosa; una relación nombrada se audita.

## 5. Capas y fronteras

Aplicá `references/capas-heuristicas.md`: la heurística "dónde vive cada
regla", el default modular monolith con criterios de split verificables, las
slices verticales y las fronteras que fallan el build. Resultado: sección
Capas de `design.md`.

## 6. Diagramas C4 (Mermaid)

- Nivel 1 `C4Context` y nivel 2 `C4Container` como bloques `mermaid` en
  `design.md`; los fuentes `.mmd` quedan en `documents/arquitectura/diagramas/`.
- Con context + containers alcanza (Brown, minimal approach); componentes solo
  si un container no es obvio para el próximo mantenedor.
- Render a PNG: delegar en la skill existente `mermaid2png` — no inventar
  pipeline de render ni depender de servicios externos.
- Fuentes: https://c4model.com · https://github.com/plantuml-stdlib/C4-PlantUML (MIT) ·
  sintaxis C4 de Mermaid (experimental): validar contra el renderer instalado
  antes de publicar PNG.

## 7. Cuándo dividir (checklist antes de cerrar un módulo)

- [ ] ¿El propósito del módulo tiene un solo verbo de negocio?
- [ ] ¿Todo mensaje entre módulos tiene contrato (canvas) y nombre de relación?
- [ ] ¿La frontera se puede hacer cumplir en el build (linter/ArchUnit u
      equivalente del stack)?
- [ ] ¿El split propuesto está justificado por un criterio verificable de
      `references/capas-heuristicas.md`, o es estético? Estético → monolito
      modular, y queda anotado en `design.md`.

## Anti-patrones

- Módulo = carpeta técnica (`controllers/`, `services/`): parte por tecnología,
  no por dominio; los candidatos con un solo verbo se pierden.
- Contrato "objeto completo": expone todo el modelo del vecino; violación del
  smallest contract.
- Frontera sin ACL cuando el modelo externo entra crudo al core.
- Diagrama como única frontera: si ningún linter la rompe, no existe.
