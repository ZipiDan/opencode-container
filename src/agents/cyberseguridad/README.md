# Agente cyberseguridad — auditor de ciberseguridad para agentes de IA

> **Meta-documento: no se despliega.** `agents_update.sh` solo despliega `.md`
> con `mode:` (stage agents) y el árbol de `skills/` (stage skills). Este README
> no tiene `mode:` ni vive en `skills/`, así que queda en el repo como
> documentación. El procedimiento de actualización está en
> [`upgrade-briiirussell.md`](upgrade-briiirussell.md).

## Qué es

Un agente de opencode (`mode: primary`) que audita ciberseguridad usando un
**catálogo de 29 metodologías profesionales** vendorizado de
[briiirussell/cybersecurity-skills](https://github.com/briiirussell/cybersecurity-skills)
(MIT, Bri Russell). **Solo audita y reporta**: `edit` está denegado; corregir
hallazgos es trabajo de `build`/`sysadmin`.

## Arquitectura: router + catálogo a demanda (mínimo consumo de tokens)

En lugar de instalar las 29 skills como skills activas de opencode (lo que
metería ~29 descripciones largas en el contexto del modelo en cada sesión y
provocaría invocaciones espurias), se usa el patrón **skill-router +
catálogo a demanda** (el mismo que heinzel usa con `heinzel-rules`):

```
src/agents/cyberseguridad/
├── cyberseguridad.md            # AGENTE (cerebro, ~1.5-2k tokens)
├── build-catalog.mjs            # GENERADOR del catálogo (vendorizado repetible)
├── upgrade-briiirussell.md      # PROCEDIMIENTO de actualización del upstream
├── UPSTREAM-LICENSE-MIT.txt     # Atribución MIT (requisito de la licencia)
└── skills/
    └── cyberseguridad-catalog/
        ├── SKILL.md             # SKILL ÍNDICE (router) — lo único "activo"
        │                        #   ~8.7 KB: tablas por familia + crossovers
        └── references/          # CATÁLOGO a demanda (29 × <skill>.md)
                                 #   renombrados (NO SKILL.md) → opencode no los
                                 #   escanea → 0 tokens hasta leerlos con Read
```

### Por qué así

- **OpenCode no tiene flag nativo de "skill desactivada"** (`disable-model-invocation`
  es de Claude Code). Su loader escanea `**/SKILL.md` recursivamente: una skill
  instalada expone su `description` al modelo sí o sí. La única forma real de
  "instalarla sin costo" es no exponerla como skill — de ahí el renombrado a
  `references/<skill>.md` (fuera del escaneo).
- **Costo fijo por sesión:** agente (~1.5-2k) + índice (~1-1.5k) ≈ 2.5-3.5k tokens,
  frente a ~2.6-3.5k solo de descripciones si las 29 estuvieran activas, más el
  riesgo de invocaciones espurias (cuerpos de 2-4k cargados sin uso).
- **Costo variable:** 1-2 `Read` de references (~1.5-4k) **solo** las correctas.
- **Sin pérdida de funcionalidad:** las 29 metodologías completas están
  disponibles a demanda; el índice mantiene las 7 familias oficiales del
  upstream y sus crossovers.

### Flujo de trabajo

Usuario pide una tarea → el agente categoriza (7 familias) → invoca
`cyberseguridad-catalog` (carga el índice) → lee `references/<skill>.md` de la
familia → ejecuta la metodología (respetando sus checks de autorización) →
entrega reporte Markdown. Nunca corrige el código.

## Instalación

Desde el repo:

```bash
./agents_update.sh          # despliega agentes + skills + estilos + comandos
# o, para ver primero qué cambiaría:
./agents_update.sh --check
```

Se despliega:
- `~/.config/opencode/agents/cyberseguridad.md` (el agente)
- `~/.config/opencode/skills/cyberseguridad-catalog/` (índice + 29 references)

Reiniciá opencode para que tome la config. El agente queda disponible como
`cyberseguridad` (puede fijarse como `default_agent` en `opencode.json` si se
quiere, o elegirse por sesión).

## Mantenimiento

- **Actualizar el vendorizado:** ver [`upgrade-briiirussell.md`](upgrade-briiirussell.md).
- **Regenerar el catálogo desde un clon:** `node build-catalog.mjs <ruta-clon>`
  (idempotente; valida que el mapa de familias cubra exactamente las 29 skills
  y falla si el upstream agrega/renombra skills sin actualizar `FAMILIES`).
- **Estado upstream:** MIT, ~363⭐, última release v1.3.0 (27/05/2026),
  maintenance-lite. El mapa `FAMILIES` del generador se deriva del README
  upstream (7 familias oficiales).

## Token rationale (resumen)

| Escenario | Fijo/sesión | Variable/tarea |
|---|---|---|
| 29 skills activas (baseline) | ~2.6-3.5k (descriptions) + invocaciones espurias | skill correcto + cuerpos desperdiciados |
| Router + catálogo (este agente) | ~2.5-3.5k (agente + índice) | 1-2 reads (~1.5-4k), solo correctos |

Ahorro estimado 25-40% en sesiones de auditoría reales, sin perder ninguna
capacidad del catálogo.