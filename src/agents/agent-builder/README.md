# agent-builder — creador de agentes

Meta-agente que crea nuevos agentes opencode vía `investigador → plan → developer → cyberseguridad`, aplicando la **Regla de Oro de los Labs** y exigiendo decisión humana ante hallazgos medios/altos.

## Regla de Oro

> **Lo determinístico va a hooks (`PreToolUse`) — emulado como bloque `## Guardrails` en opencode, lo reutilizable a `skills`, lo universal y corto queda en el `.md`.**

Ver `skills/agent-architecture/SKILL.md` para la tabla de enrutamiento y checklist.

## Flujo (efímero en /tmp)

Todos los artefactos intermedios viven en `/tmp/opencode/agent-builder/<slug>/` y se borran al final (éxito o fallo). No se escribe en `documents/investigaciones/` durante este flujo. El agente final, una vez aprobado, se materializa en `src/agents/<slug>/` y se despliega con `agents_update.sh`.

`developer` y `cyberseguridad` son `mode: all`: se pueden usar como primarios o como subagentes del `agent-builder`. El planning lo hace el propio `agent-builder` y debe pasar el Planning Gate antes de invocar a `developer`.

```mermaid
flowchart TD
    U[Usuario: quiero agente X que haga Y] --> I0[Intake agent-builder<br/>valida idea, slug, mkdir /tmp/.../slug]
    I0 --> I1[Investigación<br/>task: investigador/investigador-en + -es<br/>→ /tmp/.../01-investigation.md<br/>busca repos/skills reutilizables,<br/>evalúa stars/licencia/comentarios]
    I1 --> D{Decisión usuario<br/>A / B / C / D / A*}
    D -- A: Vendorizar repo --> P
    D -- "A*: Pre-vendorizado<br/>(solo si >500★ + MIT,<br/>preparado en /tmp/.../03-vendor/)<br/>muestra desc + skills" --> P
    D -- B: Construcción propia --> P
    D -- C: Híbrido --> P
    D -- D: Reutilizar skill --> END1[Fin, sin nuevo agente]
    P[Plan (self)<br/>→ /tmp/.../02-plan.md<br/>+ Planning Gate<br/>objetivo, archivos, Golden Rule,<br/>riesgos, gates] --> B
    B[Build<br/>task: developer<br/>scaffold src/agents/slug/,<br/>frontmatter mínimo,<br/>skills, rewrites] --> C1
    C1[Auditoría<br/>task: cyberseguridad<br/>→ /tmp/.../04-audit.md<br/>prompt injection, exfiltración,<br/>permisos, secrets] --> SEV{Severidad}
    SEV -- medio/alto --> U2[STOP + aviso a usuario<br/>decide: abortar/mitigar/<br/>aceptar riesgo documentado]
    U2 --> B
    SEV -- bajo/ok --> L{¿Cambia arquitectura?}
    L -- sí --> P
    L -- no --> C2[Gate final<br/>task: cyberseguridad<br/>re-auditoría completa]
    C2 --> DEP{¿Aprobado?}
    DEP -- no --> B
    DEP -- sí --> REV[Revisión usuario<br/>agents_update.sh --check]
    REV --> DEPLOY[Deploy<br/>agents_update.sh --force<br/>bump version, BITACORA.md]
    DEPLOY --> RM[Cleanup<br/>rm -rf /tmp/opencode/agent-builder/slug]
    RM --> END2[Agente en src/agents/slug/<br/>y ~/.config/opencode/agents/]
```

Notas:
- **Nunca auto-vendoriza**: `A*` es solo opción adicional para evaluar; por defecto `B`.
- Múltiples ciclos `plan↔developer` permitidos; nunca se salta el gate final.
- Hook = bloque `## Guardrails` en el `.md` final (opencode no tiene hook nativo; opcional plugin `tool.execute.before`).
- Todo en `/tmp` se borra con `trap` si el proceso es no interactivo.
