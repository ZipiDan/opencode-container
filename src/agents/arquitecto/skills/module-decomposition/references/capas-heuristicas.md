<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Capas: dónde vive cada regla + criterios de split

Fuentes conceptuales (referencias, sin texto copiado):
https://www.thoughtworks.com/insights/blog/architecture/hexagonal-architecture-explained-practical-example ·
https://hld.handbook.academy/curriculum/architecture-patterns/hexagonal-clean-architecture/ ·
https://www.jimmybogard.com/vertical-slice-architecture/ ·
https://milanjovanovic.tech/blog/vertical-slice-vs-clean-architecture ·
https://encore.dev/articles/microservices-vs-modular-monolith ·
receta modular: https://markovpavel.ru/proektirovanie/modulnyj-monolit-polnoe-rukovodstvo

## Dónde vive cada regla (dentro del monolito modular)

| La regla... | Vive en |
|-------------|---------|
| Orquesta entidades + datos + efectos externos (un caso de uso) | servicio de aplicación |
| Invariante que cruza ≥ 2 entidades | domain service |
| Valida o cuida los campos de UNA entidad | entidad / value object |
| Formato externo: HTTP, colas, serialización, SDK de terceros | adapter de infraestructura |

Regla dura: ningún concepto del dominio dentro de un adapter; el dominio nunca
importa infra. Si una "regla de negocio" vive en un controller, está mal
ubicada: subirla al servicio de aplicación.

## Default: modular monolith

Empezar con un monolito modular: módulos con canvas, contratos y fronteras
propias, un solo deploy. Microservicios SOLO si algún criterio de split se
verifica con datos, no con opinión:

- [ ] Dos equipos distintos, ritmo de release independiente y contrato estable
      medido (casi no se rompen entre sí).
- [ ] Perfil de escala radicalmente distinto que el resto no aguanta.
- [ ] Compliance o blast radius exigen aislamiento físico (datos PCI, claves).
- [ ] Runtime/lenguaje distinto por necesidad comprobada, no por moda.
- [ ] Lead time de deploy medido: el módulo ya frena a los demás.

Ninguno cumple → monolito modular. Split sin criterio = distributed monolith.

## Slices verticales dentro del módulo

Feature-first: cada caso de uso atraviesa todas las capas en una carpeta
propia (`facturar/` con su adapter, servicio y modelo de vista); lo compartido
se extrae solo cuando dos features lo usan de verdad. El híbrido capas +
slices es el default práctico para equipos chicos.

## Fronteras que fallan el build

Un límite que solo vive en un diagrama no existe: tiene que romper el
compile/lint. Cada contrato del canvas se traduce a ≥ 1 regla ejecutable:

| Ecosistema | Mecanismo de frontera |
|------------|------------------------|
| TypeScript/JS | dependency-cruiser, o eslint con eslint-plugin-boundaries |
| Python | import-linter (contratos de import por módulo) |
| Java/Kotlin | ArchUnit (test de arquitectura en CI) |
| Go | paquetes `internal/` por módulo; nadie importa dentro del vecino |
| Rust | workspace de crates con dependencias explícitas y `pub(crate)` |

Si el stack no tiene mecanismo, el módulo no es frontera: es carpeta. Anotar
en `design.md` y elegir el más cercano (convención de imports + review).
