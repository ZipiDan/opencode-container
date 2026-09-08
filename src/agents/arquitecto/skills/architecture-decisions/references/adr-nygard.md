# Esqueleto mínimo de ADR (5 secciones, estilo Nygard)

Esquema conceptual del post original de Michael Nygard:
https://cognitect.com/blog/2011-11-15/documenting-architecture-decisions
(referencia conceptual; aquí se formula el esqueleto propio, en español).

**Nota de licencia (check abierto):** el hub
https://github.com/architecture-decision-record/architecture-decision-record
tiene `LICENSE.md` NOASSERTION / pendiente de verificación (ledger
PROVENANCE.md, regla 1). Por eso **no se copia ningún texto de ese repo**:
esto es un esquema genérico de 5 secciones escrito a mano. Verificar ese
LICENSE.md antes de enriquecer esta referencia (procedimiento en
`upgrade-arquitecto.md`).

## Esqueleto

```markdown
# NNNN - <Título>

Fecha: AAAA-MM-DD · Estado: Propuesta | Aceptada | Superseded by [NNNN](./NNNN-titulo.md)

## Context
<La fuerza que requiere la decisión: problema, restricciones, presión de
atributos de calidad.>

## Decision
<Qué se decide hacer, en imperativo.>

## Consequences
<Qué se vuelve fácil, difícil, posible o imposible tras la decisión. Lo malo
también: es la sección de riesgos.>
```

## Cuándo usarlo

Decisión local, con pocas opciones reales, y un gate de 5 preguntas
(SKILL.md) que marcó costo de cambio bajo/medio. Apenas aparezca un debate de
opciones con trade-offs que documentar → migrar a `adr-madr.md` con un ADR
nuevo.

## Convenciones compartidas

Idénticas a las de la SKILL: numeración NNNN, ruta
`docs/arquitectura/adr/NNNN-<titulo-kebab>.md`, inmutabilidad, y `Status:`
como único campo editable de un ADR aceptado.
