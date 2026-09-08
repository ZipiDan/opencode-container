---
name: delivery-planning
description: >-
  Planificación de entregas para el agente arquitecto: WBS con regla del 100% →
  subproyectos solo por ejes de cambio distintos → MoSCoW 60-20-20 → hitos con
  criterios de aceptación verificables → tareas con DoD, ruta exacta y paso de
  verificación → handoff a plan/developer → gate anti-plan-obsoleto. Usar en las
  fases Planificación y Tareas, o al armar un plan de desarrollo y priorizar
  alcance.
version: 1
---

# Delivery Planning — del diseño a packs de tareas ejecutables

Objetivo: convertir `design.md` en un plan maestro (`plan/PLAN.md`) y en packs
de tareas (`plan/tareas/hito-NN/`) que `plan`/`developer` ejecuten sin
reinterpretar el diseño. El arquitecto produce el pack; no ejecuta.

Fuentes inline por paso; patrón de interacción (gate de aprobación humana)
adaptado de obra/superpowers (MIT) — PROVENANCE.md piezas 7 y 13-15.

## 0. Gate de vigencia (antes de nada)

Si `plan/PLAN.md` o `plan/tareas/` ya existen: compararlos contra `design.md`
y contra el pedido actual del usuario. Si difieren → actualizar primero el
plan y repetir el gate de aprobación humana. Nunca generar un pack de tareas
sobre un plan obsoleto.

## 1. WBS con la regla del 100%

Descomponer TODO el alcance del diseño (no el alcance que se desea): la suma
de los hijos cubre el 100% del padre y ningún hijo agrega alcance que el padre
no tenga — sin cajones "otros". Cada hoja es un entregable verificable.
Fuente: https://www.projectmanager.com/guides/work-breakdown-structure

## 2. Subproyectos SOLO si los ejes de cambio son distintos

Separar en subproyectos solo cuando cada uno cambia por una razón distinta
(otro dominio, otro contrato externo, otro calendario). Si dos "subproyectos"
tocan los mismos archivos cada semana, son uno solo.
Lente de urbanización (Zone→Quartier→Îlot→Bloc) como jerarquía de
descomposición: https://esnenfrance.com/urbanisation-des-si/ ·
https://www.softyflow.io/urbanisation-informatique-definition-enjeux-methodes-roi/

## 3. MoSCoW con regla 60-20-20

Clasificar los entregables de la WBS por esfuerzo: Must ≈60%, Should ≈20%,
Could ≈20%, Won't (this time) explícito y registrado. Si todo es Must, el
ranking de atributos de calidad de la elicitación está mal: volver a
elicitación, no "priorizar" sobre la marcha.
Fuente: https://en.wikipedia.org/wiki/MoSCoW_method

Distinción AC vs DoD (para no mezclar en los templates):

- **AC (criterios de aceptación)**: lo que el hito debe cumplir para que el
  usuario lo acepte — observable desde afuera.
- **DoD (definition of done)**: checklist de calidad que toda tarea debe
  cumplir para llamarse terminada — estándar interno, aplica a todas.
- Fuentes: https://scrumguides.org/scrum-guide.html (DoD canónico) ·
  https://www.storypointlab.com/docs/quality/acceptance-criteria-vs-definition-of-done

## 4. Hitos con criterios de aceptación verificables

Cada hito se define con AC que se pueden verificar sin discusión: un script,
una demo, una métrica. Hito sin AC verificables no es un hito, es una fecha.
Template: `references/hito-template.md`.

## 5. Tareas (granularidad: minutos, no días)

Desgranar cada hito hasta "múltiples tareas de minutos, no días" (patrón de
granularidad de superpowers `writing-plans`, adaptado: no se copia el
framework, solo la regla de tamaño). Cada tarea con DoD, ruta de archivos
exacta y paso de verificación: `references/tarea-template.md`.
La tarea que no puede nombrar sus archivos no está lista: falta diseño.

## 6. Handoff a `plan` built-in (formato OpenSpec-style)

Empaquetar cada hito como `design.md → tasks.md` con la estructura de
`references/handoff-design-md.md` (Estructura adaptada de Fission-AI/OpenSpec,
MIT). `plan` toma el pack y desglosa la ejecución; `developer` escribe el
código. Cadena entrevista→PRD→issues como pattern de flujo: pieza 15 del
ledger (https://github.com/serejaris/personal-corp-os, MIT — solo el patrón).

## 7. Cierre del pack

- Actualizar `INDEX.md`: tabla hito → estado → ruta del pack → ADRs que lo
  condicionan.
- Toda tarea referencia el módulo/contrato del canvas que toca; si no lo hay,
  la fase Arquitectura quedó incompleta: volver, no improvisar.
- Aprobación humana explícita del pack antes de entregarlo a `plan`.
