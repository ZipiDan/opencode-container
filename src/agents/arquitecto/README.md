# Agente `arquitecto`

Agente global primario (español) que convierte ideas y requisitos en
arquitectura documentada y planes de trabajo. **No escribe código de
aplicación**: produce artefactos duraderos en `docs/arquitectura/` del proyecto
y packs de tareas listos para `developer`/`plan`.

## Fases

```
Detección → Ellicitación → Arquitectura → Planificación → Tareas
```

Cada fase cierra con un artefacto y **aprobación humana explícita** (gate por
artefacto). Protocolo de elicitación socrático: una pregunta por vez, ranking
de atributos de calidad, estimaciones solo en rangos con supuestos.

## Mapa de archivos

| Archivo | Rol |
|---------|-----|
| `arquitecto.md` | Agente primario (`version: 1`) |
| `skills/module-decomposition/` | Alcance → canvas por módulo → relaciones → capas → C4 |
| `skills/architecture-decisions/` | Gate de 5 preguntas, plantillas ADR, numeración y supersede |
| `skills/delivery-planning/` | WBS 100%, MoSCoW 60-20-20, hitos+AC, tareas+DoD, handoff |
| `PROVENANCE.md` | Ledger de piezas/fuentes/licencias (no se despliega) |
| `upgrade-arquitecto.md` | Procedimiento de actualización desde upstream (no se despliega) |

## Frontera con otros agentes

- `plan` (built-in): ejecución efímera en `.opencode/plans/`; `arquitecto`:
  documentación duradera en `docs/arquitectura/`. Frontera física, no de estilo.
- `developer`: escribe el código a partir de los packs de tareas del hito.
- `investigador*`: research de stack/tecnologías — el arquitecto no tiene web
  (`webfetch`/`websearch` deny, separación de roles).
- `explore`: lectura del código existente para la fase de Detección.

## Uso

- Comando `/arquitecto <idea>` (viaja en `src/commands/arquitecto.md`) o
  mención `@arquitecto`; en TUI, Tab cicla los agentes.
- Skills que exporta al registro global (deploy vía `agents_update.sh`):
  `module-decomposition`, `architecture-decisions`, `delivery-planning`.
- Reusa sin duplicar: `mermaid2png` (render de diagramas) y
  `api-and-interface-design` (interfaces dentro del módulo).
- Procedencia de cada pieza y su licencia: `PROVENANCE.md`. Actualización
  guiada pieza-por-pieza: `upgrade-arquitecto.md`.
