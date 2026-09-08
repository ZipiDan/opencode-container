---
name: architecture-decisions
description: >-
  Ciclo de vida de decisiones de arquitectura para el agente arquitecto: gate de
  5 preguntas para decidir si un ADR se justifica, plantillas (MADR default,
  esqueleto Nygard de 5 secciones), numeración NNNN, inmutabilidad, supersede y
  riesgos como consecuencias. Usar ante toda decisión de arquitectura no
  trivial, o cuando se pida documentar o revisar una decisión tomada.
version: 1
---

# Architecture Decisions — qué merece un ADR y cómo se escribe

Un ADR (Architecture Decision Record) documenta el **por qué**: contexto,
opciones y consecuencias de una decisión tomada. El **cómo** lo dice el C4 y el
**cuándo** el plan; no duplicar contenido entre los tres.

Fuente del gate y del ciclo de vida:
https://blog.stephane-robert.info/docs/documenter/concevoir/adr/ (referencia
conceptual: se toma el criterio, no el texto). Plantillas:
`references/adr-madr.md` (default) y `references/adr-nygard.md`.

## 1. Gate: ¿se justifica un ADR? (5 preguntas)

Responder ANTES de abrir el archivo:

1. **Costo de cambio**: ¿cuánto cuesta revertir o modificar esto más adelante
   (código, datos, contratos publicados)?
2. **Impacto en equipos**: ¿afecta a más de un módulo/equipo, o a terceros
   (contratos externos, consumidores del OHS)?
3. **Reversibilidad / duración**: ¿es reversible? ¿cuánto tiempo vivirá la
   decisión: días, trimestres, años?
4. **Alternativas reales**: ¿existían otras opciones con trade-offs que alguien
   va a querer reconsiderar algún día?
5. **Riesgo de reinterpretación**: ¿dos personas leerían distinto el "por qué"
   de esta decisión dentro de seis meses?

Decisiones con respuestas triviales en todas (barato, local, reversible, sin
alternativas, obvio) → **no hay ADR**: una línea en `design.md` alcanza. Dos o
más señales fuertes → ADR. Ante la duda, escribir: la omisión silenciosa cuesta
más que un archivo.

## 2. Elegir plantilla

- **Default: MADR** — estructura con opciones consideradas y pros/contras,
  machine y lint friendly: `references/adr-madr.md` (Basado en adr/madr,
  MIT OR CC0-1.0).
- Decisión simple, con pocas opciones reales: esqueleto mínimo de 5 secciones
  estilo Nygard: `references/adr-nygard.md`.
- **No usar** los templates del repo
  https://github.com/architecture-decision-record/architecture-decision-record:
  su `LICENSE.md` es NOASSERTION y la verificación está pendiente (PROVENANCE.md
  regla 1); check abierto en `upgrade-arquitecto.md`.

## 3. Convenciones (ciclo de vida)

- Ruta: `documents/arquitectura/adr/NNNN-<titulo-kebab>.md`; numeración NNNN
  correlativa de 4 dígitos (0001, 0002, ...), sin huecos ni reuse.
- **Inmutabilidad**: un ADR aceptado no se edita para cambiar de opinión. Lo
  único editable es su `Status:`.
- **Supersede**: se escribe un ADR nuevo cuyo Status referencia al viejo; en el
  viejo se cambia `Status: Superseded by [NNNN](./NNNN-titulo.md)` con link
  relativo. Nunca se reescribe la decisión original.
- **Riesgos como Consequences**: no existe una sección "Riesgos" aparte; las
  desventajas y lo que puede salir mal se redactan en `Consequences` (de la
  decisión tomada), con su mitigación cuando exista.
- Todo ADR que toca un contrato entre módulos obliga a actualizar el canvas del
  módulo y el diagrama C4 si corresponde.

## 4. Ejemplo corto (Nygard, stack hipotético)

```markdown
# 0001 - Usar SQLite como base de datos embebida

Fecha: 2026-09-08 · Estado: Aceptada

## Contexto
App de escritorio single-user con sync diferido; un servidor de BD agregado
suma operación sin beneficio para el perfil de carga (escrituras: <100/s
estimadas).

## Decisión
SQLite en modo WAL, accedido solo desde la capa de aplicación, con migraciones
versionadas.

## Consecuencias
+ Un archivo de datos, backup trivial, sin red que administrar.
- Escala de escritura acotada: si aparecen multi-writer, reabrir la decisión.
- El sync diferido debe resolver conflictos de clave en la aplicación.
```

## 5. Handoff

El índice de ADRs activos se refleja en la tabla de `INDEX.md` (decisión →
módulos afectados → estado). Un plan de tareas nunca "redescubre" una decisión:
si una tarea parece contradecir un ADR vigente, se abre un ADR nuevo o se
detiene la tarea — no se interpreta al gusto.
