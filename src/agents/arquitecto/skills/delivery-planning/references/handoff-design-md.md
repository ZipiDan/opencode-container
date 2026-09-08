# Handoff design.md → tasks.md (formato del pack)

Estructura adaptada de: Fission-AI/OpenSpec (MIT),
https://github.com/Fission-AI/OpenSpec (docs/overview.md) — se toma el pipeline
de archivos de artefactos (proposal → specs → design → tasks → archive), no su
tooling ni su texto.

Propósito: que `plan` (built-in) y `developer` reciban un pack autocontenido
por hito, sin necesidad de reconstruir el contexto del arquitecto.

## Estructura del pack `documents/arquitectura/plan/`

```
plan/
├── PLAN.md                  ← WBS completa + subproyectos + tabla de hitos
└── tareas/hito-NN/
    ├── design.md            ← delta de diseño de ESTE hito (no todo el sistema)
    └── tasks.md             ← checklist ordenado de tareas del hito
```

### `design.md` del hito (delta)

```markdown
# Diseño del hito NN — <nombre>

## Proposal
<1 párrafo: qué se entrega y por qué ahora (posición MoSCoW)>

## Delta de specs
<Qué contratos/módulos del canvas cambian o nacen: mensajes in/out nuevos,
relaciones, fronteras. Solo el delta: lo demás ya vive en modulos/<slug>.md>

## Decisiones aplicadas
<ADRs vigentes que este hito consume, por número: 0001, 0007...>

## Fuera de alcance (Won't this time)
<lo que explícitamente NO toca este hito — blindaje contra scope creep>
```

### `tasks.md` del hito

```markdown
# Tareas del hito NN

- [ ] NN.1 <tarea minuto-a-minuto> → ver <slug>.md o inline con DoD
- [ ] NN.2 ...
```

Cada ítem con la granularidad de `tarea-template.md`; el orden es el orden de
ejecución, no el de archivo.

## Flujo

1. `arquitecto` escribe `PLAN.md` + pack del hito y pide aprobación humana.
2. `plan` (built-in) lee el pack, razona la ejecución y desglosa en su
   `.opencode/plans/` (efímero — la frontera con el arquitecto).
3. `developer` ejecuta las tareas contra sus rutas exactas.
4. Al cerrar el hito: el pack se marca como entregado en `INDEX.md` (papel de
   "archive" de OpenSpec, sin mover archivos a otro lado).
