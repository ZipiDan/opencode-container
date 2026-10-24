<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Upgrade arquitecto — procedimiento de actualización del agente

> **Meta-archivo: NO se despliega.** Sin `mode:` y fuera de `skills/`, queda en
> el repo como documento de procedimiento (patrón de `sysadmin/upgrade-heinzel.md`).
> No le agregues `mode:`.

A diferencia de `sysadmin` (que vendoriza un repo único), este agente no tiene
un upstream central: cada pieza tiene su fuente registrada en `PROVENANCE.md`.
La actualización es **por pieza**, no por clon, y es un procedimiento guiado:
aplicar cambios requiere criterio (las plantillas están adaptadas a español y a
las convenciones del repo), no un `sed` ciego.

## Invariantes (no re-vendorizar)

Decisiones **propias** del agente (no vienen de upstream). Una actualización desde
internet NO debe revertirlas; si un cambio upstream choca, gana el invariante y
cualquier relajación se decide con el operador (nunca en automático):

1. **Permisos**: `edit: allow` y `write: allow` en el frontmatter. La restricción
   de alcance a `documents/arquitectura/**` + scratch `/tmp/opencode/arquitecto/**`
   es **por prompt** (guardrails 2 y 4), no por el motor. No "re-endurecer" con
   mapas de patrones sin decisión explícita (ver `BITACORA.md` 2026-09-29).
2. **Home + registro**: `documents/arquitectura/INDEX.md` es la tabla de proyectos
   (`| Proyecto | Descripción | Estado | Fecha de creación | Fecha de última actualización |`)
   y cada proyecto vive en su subcarpeta `documents/arquitectura/<proyecto>/` con
   `design.md`, `modulos/`, `adr/`, `diagramas/` y `plan/`.
3. **Skills propias**: `module-decomposition`, `architecture-decisions` y
   `delivery-planning` se actualizan por pieza según `PROVENANCE.md`; no se
   reemplazan por versiones upstream sin plegar al estilo propio.

## Cuándo correrlo

- El operador pide "actualizá el agente arquitecto".
- Cambia una pieza upstream: nueva versión, cambio de licencia, repo archivado
  o abandonado.
- Se cierra alguno de los checks abiertos de abajo.
- Sugerencia: revisar cada tanto las fuentes del ledger (los números de
  estrellas/fechas son del 2026-09-08 y vencen).

## Pasos

1. **Re-verificar por pieza** contra la tabla de `PROVENANCE.md`:
   estrellas/licencia/fecha de cada fuente vía `investigador` (o el operador,
   que sí tiene web). Registrar el resultado como addendum fechado del ledger.
2. **Diff contra la plantilla local**: releer la fuente y compararla contra el
   `SKILL.md`/`references/` que la adaptó. Nunca copiar: re-leer y re-escribir
   al estilo propio; piezas CC BY-SA solo adaptadas, con su línea de
   atribución intacta (regla 3 del ledger).
3. **Plegar cambios** a la skill/prompt correspondiente. Pieza muerta
   upstream → congelar (la copia adaptada ya vive en el repo; regla 5 del
   ledger) y anotarlo.
4. **Bumpear `version:`** en `arquitecto.md` y en cada `SKILL.md` tocado
   (es lo que hace visible el UPDATE en los stages de `agents_update.sh`).
5. **Verificar invariantes** (sección "Invariantes"): que el plegado no revirtió
   `edit/write: allow`, el layout por proyecto ni el esquema de `INDEX.md`.
6. **Gates obligatorios**: checklist de la skill `agent-architecture` +
   auditoría con el agente `cyberseguridad`, scope `src/agents/arquitecto/**`
   (foco: inyección en templates de docs, permisos del frontmatter,
   exfiltración, licencias). Hallazgo medio/alto → STOP y decisión humana.
7. **Deploy**: `./src/agents_update.sh --check` → revisar diff → confirmar →
   `./src/agents_update.sh`. Loguear el hito en `BITACORA.md`.
8. **Limpieza**: borrar todo clon temporal bajo `/tmp/opencode/` usado en el
   procedimiento (`rm -rf`, verificar con `test ! -e`).

## Checks ABIERTOS (estado v1, 2026-09-08)

- [ ] `architecture-decision-record/architecture-decision-record`: leer y
      verificar su `LICENSE.md` (NOASSERTION) **antes** de copiar cualquier
      template suyo (pieza 2; regla 1 del ledger). Mientras siga abierto:
      solo el esqueleto Nygard genérico propio de `adr-nygard.md`.
- [x] Evaluación post-build de `weisser-dev/awesome-opencode` (pieza 14, A*) — **cerrada
      2026-09-08** con decisión humana (fix post-audit; traza en la sección "Evaluación A*"
      de `PROVENANCE.md`): `adr-write` RECHAZADA (redundante con la MADR de pieza 1);
      `architect-reviewer` INTEGRADA como auto-revisión de la fase 3 en `arquitecto.md`
      (pieza 16). Nunca hubo deploy automático de estas piezas (★ bajas).
- [ ] `api-contract` (sub-pieza de la 14, RECHAZADA para v1 — decisión usuario 2026-09-08):
      reevaluar en este primer update como reference `contratos-tablas.md` en
      `module-decomposition` (tablas naming/error envelope/pagination/checklist, MIT). Hasta la
      reevaluación: nada de ese archivo en los artefactos del agente.

## Rollback

Todo el agente está versionado en git:

```bash
git checkout -- src/agents/arquitecto && ./src/agents_update.sh --force
```
