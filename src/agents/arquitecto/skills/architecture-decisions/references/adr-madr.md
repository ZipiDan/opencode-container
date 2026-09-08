# Plantilla MADR (default del agente)

Basado en: adr/madr (MIT OR CC0-1.0), https://github.com/adr/madr y
https://adr.github.io/madr/ — las secciones están reformuladas en español con
criterio propio; no es el template verbatim del repo.

Usar para toda decisión con trade-offs que hay que poder auditar. Secciones:

```markdown
# NNNN - <Título de la decisión: presente, indicativo, sin "propuesta de...">

## Status
Aceptada | Deprecated | Superseded by [NNNN](./NNNN-titulo.md)

## Context
<Qué fuerza la decisión: restricciones, posición en el ranking de atributos de
calidad, estado del proyecto. Hechos y números, no opiniones.>

## Decision
<La decisión en una frase imperativa + el alcance de su aplicación (qué módulos
y contratos toca).>

## Considered Options
- <Opción A>
- <Opción B>
- <mínimo dos; si solo hubo una, registrar por qué no había alternativa real>

## Pros and Cons of the Options

### <Opción A>
- GOOD, porque <beneficio concreto>
- BAD, porque <costo o riesgo concreto>

### <Opción B>
- ...

## Consequences
<Consecuencias —positivas, negativas y neutrales— de la opción ELEGIDA, con la
mitigación de cada negativa. Acá viven los riesgos; no hay sección "Riesgos".>
```

## Variantes

MADR define versiones "minimal" y "full". Para este agente: la plantilla de
arriba es el default (full reducido a lo que se audita); para trivialidades
que igual pasan el gate, el esqueleto de 5 secciones de `adr-nygard.md`.
Si una decisión empieza en Nygard y aparece el debate de opciones, migrar a
MADR en un ADR nuevo (la inmutabilidad no se negocia).
