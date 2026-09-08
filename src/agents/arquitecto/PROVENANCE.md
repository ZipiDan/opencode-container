# Procedencia — agente `arquitecto` (ledger de piezas y decisiones)

**Fecha de verificación de datos**: 2026-09-07/08 (estrellas/licencias/fechas leídos vía páginas y API de GitHub; cambian con el tiempo — re-verificar antes de cada update).
**Búsqueda**: 6 idiomas, investigadores ES/EN/FR/DE/RU/ZH + checks propios (opencode docs, `opencode agents list`).
**Propósito**: permitir reconstruir cada pieza, justificar su elección y actualizarla (equivalente a `upgrade-heinzel.md` / `UPSTREAM-LICENSE-MIT.txt` del patrón sysadmin/cyberseguridad).
**Destino en el build**: migrar a `src/agents/arquitecto/PROVENANCE.md` (meta-archivo, versionado en git, no desplegado); cada skill llevará además atribución inline con su fuente exacta.

## Criterios aplicados (los 4 filtros)

1. Cubre un hueco no cubierto por `developer`/`mermaid2png`/`api-and-interface-design`/`investigador`.
2. Licencia compatible: MIT/CC0/Apache vendorizable · CC BY-SA → adaptar+atribuir · GPL → excluido verbatim · propietario → solo inspiración.
3. Seguridad/mantenimiento: activo, sin `curl|bash` oculto, sin exfiltración, sin instrucciones que overrideen al usuario.
4. Formato opencode-nativo o reescritura barata (Claude→opencode).

## Piezas ACEPTADAS (pieza → destino → fuente → por qué)

| # | Pieza | Destino | Fuente (URL) | Licencia | Qué se toma | Por qué esta y no otra |
|---|-------|---------|--------------|----------|-------------|------------------------|
| 1 | Plantilla ADR completa/minimal/bare | skill `arquitectura-decisiones` | https://github.com/adr/madr (+ https://adr.github.io/madr/) | MIT OR CC0-1.0 (2.456★, push 2026-08-28) | Estructura de secciones con opciones consideradas + pros/contras | Estándar machine-friendly según adr.github.io; lint-friendly; licencia limpia |
| 2 | Esqueleto ADR mínimo (5 secciones) | skill `arquitectura-decisiones` | Nygard: https://cognitect.com/blog/2011-11-15/documenting-architecture-decisions · hub: https://github.com/architecture-decision-record/architecture-decision-record (16.8k★, push 2026-09-05) | Original blog; hub: NOASSERTION — pendiente LICENSE.md (check abierto en `upgrade-arquitecto.md`) | Title/Context/Decision/Status/Consequences + convención `adr-NNN`, superseded sin reescribir | Mínimo humano para decisiones triviales; MADR para auditar trade-offs |
| 3 | Lógica "qué justifica un ADR" (5 preguntas) + ciclo de vida | skill `arquitectura-decisiones` | https://blog.stephane-robert.info/docs/documenter/concevoir/adr/ (criterio cambio/impacto/duración/alternativas/reinterpretación) | Blog (referencia, no se copia texto) | Gate de omisión de ADR | Único hallado con test de omisión explícito operable |
| 4 | Esquema canvas de módulo (in/out messages = contratos) | skill `descomposicion-modulos` (esquema adaptado, NO verbatim) | https://github.com/ddd-crew/bounded-context-canvas (2.051★) | CC BY-SA 4.0 → **atribución obligatoria** | Campos: nombre, propósito, clasificación core/supporting/generic, mensajes inbound/outbound (command/query/event), lenguaje ubicuo, reglas, supuestos, métricas | Único schema 1-página por módulo probado por la comunidad DDD |
| 5 | Vocabulario de relaciones entre módulos | skill `descomposicion-modulos` | https://github.com/ddd-crew/context-mapping (1.851★) + https://martinfowler.com/bliki/BoundedContext.html | CC BY-SA / referencia | ACL, Customer-Supplier, Shared Kernel, OHS… (nombres, no poster) | Contract-first necesita nombrar relaciones; sin vocabulario se alucina prosa |
| 6 | Proceso elicitación→descomposición→agregados | skill `descomposicion-modulos` (pasos adaptados) | https://github.com/ddd-crew/ddd-starter-modelling-process (6.010★) · heurísticas RU/DE: https://www.openknowledge.de/blog/mit-domain-driven-design-gute-bounded-contexts-finden (pivotal events, conflictos de vocabulario) | CC BY-SA / blog | Secuencia Big Picture ES → candidatos → flow → canvas; heurísticas de corte | "Receta" completa verificada; openknowledge la hace operable sin workshop |
| 7 | Protocolo socrático Q&A→design doc→aprobación | prompt `arquitecto` + skill | https://github.com/obra/superpowers (282.8k★, MIT, v6.3.0 2026-08-12) — skills `brainstorming`, `writing-plans` | MIT | El patrón de interacción (una pregunta por vez, gate de aprobación humana antes de action) | Estándar de facto agente-side; NOT el framework completo (choca con TDD/code-review existentes) |
| 8 | Protocolo de interrogación 7 fases (arquitectura) | prompt `arquitecto` (reescrito, sin promo) | https://github.com/study8677/architecture-copilot (80★, MIT, push 2026-07-10) | MIT | Secuencia: preguntas alma → estimación sobre-sobre → ranking de quality attributes → A vs B → convergencia → contra-challenge | Único encontrado con fases de interrogación orientadas a ARQUITECTURA (no a producto) |
| 9 | Regla "dónde vive cada regla" (domain/app/infra) | skill `descomposicion-modulos` | https://www.thoughtworks.com/insights/blog/architecture/hexagonal-architecture-explained-practical-example · https://hld.handbook.academy/curriculum/architecture-patterns/hexagonal-clean-architecture/ | Referencia (no copia) | Heurística BD/Stripe→application; multi-entidad→domain service; campos propios→entidad | Resuelve el "capas como puente requisitos→código" pedido |
| 10 | Híbrido capas+slices + criterios de corte monolith/modular/micro | skill `descomposicion-modulos` | https://www.jimmybogard.com/vertical-slice-architecture/ · https://milanjovanovic.tech/blog/vertical-slice-vs-clean-architecture · https://encore.dev/articles/microservices-vs-modular-monolith · receta modular ES: https://markovpavel.ru/proektirovanie/modulnyj-monolit-polnoe-rukovodstvo | Blogs (referencia) | Default modular monolith; criterios verificables de split; frontiers que fallan el build | Consenso multi-fuente 2026 para equipos chicos |
| 11 | Generación C4 como texto + mapeo arc42↔C4 | skill via `mermaid2png` + referencia | https://c4model.com · https://github.com/plantuml-stdlib/C4-PlantUML (7.4k★, MIT) · mermaid-C4 (experimental): https://github.com/mermaid-js/mermaid/blob/f0ffb41c/docs/syntax/c4.md · mapeo: https://www.codecentric.de/en/knowledge-hub/blog/architecture-documentation-as-code-with-structurizr-and-asciidoctor-part-3-structurizr | MIT | Sintaxis C4Context/C4Container; "context+containers suficientes" (Brown) | Renderer local ya existe; Mermaid inline en Markdown |
| 12 | Contract-first: contrato como interfaz estable, versionado, idempotencia | skill `descomposicion-modulos` + reuso `api-and-interface-design` | https://github.com/VoltAgent/awesome-codex-subagents/blob/main/categories/01-core-development/api-designer.toml (6.1k★, MIT; read-only sandbox) | MIT (archivo individual, auditar) | Reglas de redacción de contratos + patrón read-only | El único prompt de contratos con principio "smallest contract" verificable y sandbox |
| 13 | Formato de handoff design.md/tasks.md (proposal→specs→design→tasks) | artefactos `docs/arquitectura/` | https://github.com/Fission-AI/OpenSpec (67.5k★, MIT, push 2026-09-07) docs/overview.md | MIT | Estructura de cambio: proposal/delta-specs/design/tasks + archive | Pipeline artifact-file más simple y probado; sin tooling node |
| 14 | Piezas opencode-nativas: `adr-write` (Nygard), `api-contract` (OpenAPI/AsyncAPI), `architect-reviewer` | A* en /tmp para evaluación | https://github.com/weisser-dev/awesome-opencode (30★, MIT, 29 commits) | MIT | Los 3 archivos, leídos y reescritos a ES | Únicos ya en formato opencode; ★ bajas → evaluación humana obligatoria, no deploy automático |
| 15 | Skills pm para F2: `grill-me` → `to-prd` → `to-issues` + priorización RICE/ICE/MoSCoW/Kano | skill `planificacion-entregas` (referencia de flujo) | https://github.com/serejaris/personal-corp-os (224★, MIT, push reciente; redirect desde personal-corp-skills) | MIT | Cadena entrevista→PRD→issues como pattern para el agente `plan` | MIT y orientada a solo-dev; F2 la ejecuta `plan` built-in (puede cargar skills — verificado) |
| 16 | Auto-revisión antes del gate (architect-reviewer) | prompt `arquitecto` → fase 3, sección "Auto-revisión antes del gate" | https://github.com/weisser-dev/awesome-opencode (templates/agents/architect-reviewer.md, 43 líneas) | MIT | Checklist de 8 puntos + formato de hallazgo Area/Severity/Impact/Recommendation + regla Critical/Warning→ADR/usuario | Única pieza opencode-nativa de revisión arquitectónica; evaluación humana A* cerrada en fase [5] fix (2026-09-08; ver sección "Evaluación A*") |

## Guías normativas citadas (no vendorizadas — base conceptual)

- arc42 (12 secciones; CC BY-SA): https://arc42.org/overview · https://github.com/arc42/arc42-template — se referencia, plantilla propia "minimal but sufficient".
- Doc mínima (Brown 2020): https://dev.to/simonbrown/a-minal-approach... → correcta: https://dev.to/simonbrown/a-minimal-approach-to-software-architecture-documentation-4k6k
- ISO/IEC/IEEE 42010 (vocabulario): https://www.iso.org/standard/74393.html
- WBS/100% Rule: https://www.projectmanager.com/guides/work-breakdown-structure · DoD canónico: https://scrumguides.org/scrum-guide.html · AC vs DoD: https://www.storypointlab.com/docs/quality/acceptance-criteria-vs-definition-of-done · MoSCoW 60-20-20: https://en.wikipedia.org/wiki/MoSCoW_method · INVEST: https://xp123.com/articles/invest-in-good-stories-and-smart-tasks
- Urbanización FR Zone→Quartier→Îlot→Bloc (lente de descomposición): https://esnenfrance.com/urbanisation-des-si/ · https://www.softyflow.io/urbanisation-informatique-definition-enjeux-methodes-roi/
- INNOQ Starke (estructuras/conceptos/comunicación): https://www.innoq.com/de/blog/2023/10/grandlagen... → correcta: https://www.innoq.com/de/blog/2023/10/grundlagen-der-softwarearchitektur-teil-3
- awesome-software-architecture (índice curado, CC0): https://github.com/mehdihadeli/awesome-software-architecture
- Base ZH (esqueleto 14 secciones, MIT): https://github.com/study8677/awesome-architecture
- LLMs+arquitectura (dúplex DE): https://software-architektur.tv/ ep. 242/266

## Piezas RECHAZADAS (con justificación futura)

| Candidato | Razón del rechazo | Vía de re-evaluación |
|-----------|-------------------|----------------------|
| obra/superpowers (completo) | Framework SDLC completo con hooks/plugin/telemetría; solapa TDD/code-review de `developer` | Si el usuario adopta plugin aparte, no por este agente |
| Byndyusoft/aact + ChS23/aact-architect-skill | **GPL-3.0** (no mezclable con agente propio MIT) | Usable como validador externo opt-in vía `bash`, nunca verbatim |
| cycleuser/Skills (ZH) | Conflicto de licencia README(MIT)-vs-About(GPL-3.0) + instaladores `curl\|bash` sin auditar | Clarificar licencia + auditar scripts → entonces skills `master-architect`/`software-planner` |
| anthropics/claude-code `code-architect` | Licencia propietaria (All rights reserved) | Solo patrón conceptual ya documentado arriba |
| ddd-crew verbatim | CC BY-SA share-alike | Solo adaptado + atribución (piezas 4-6) |
| osmontero/opencode-skills | 9★, single-maintainer, sin auditoría comunitaria | Revisión archivo-por-archivo si se necesita spec-reviewer |
| sickn33/agentic-awesome-skills `--all` | Contiene skills `critical/offensive` declaradas | Solo la skill `software-architecture`, quirúrgico |
| github/spec-kit | Heavyweight para solo-dev (su propio README OpenSpec lo dice) | No |
| gsd-build/get-shit-done | Repo ARCHIVADO (move a open-gsd/gsd-core no verificado) | Verificar sucesor si interesa |
| TOGAF/Zachman | Enterprise-only; consenso multi-fuente | No |
| DocHub (RU) | Plataforma EAM pesada + "comunidad fee" v3.13.1 | No |
| VoltAgent (catálogo) | Auto-declarado "no auditamos" | Por archivo individual (pieza 12) |

## Reglas de reconstrucción/actualización

1. **check pendiente**: `architecture-decision-record/architecture-decision-record` LICENSE.md antes de copiar cualquier template (pieza 2). Si NOASSERTION/NC → usar solo Nygard del blog original (dominio público conceptual) o MADR.
2. **A*** (pieza 14): nunca se despliega sin lectura humana de los 3 archivos + elección explícita en [1b].
3. Cada skill con pieza adaptada (4, 5, 6, 7, 14, 15) lleva en su SKILL.md una línea `Fuente:` con la URL de este ledger y, donde aplica, `Adaptado de X (CC BY-SA 4.0), licencia original en URL`.
4. Ante update: re-verificar stars/licencia/fecha (los números de este ledger son del 2026-09-08), re-difear contra la fuente, y registrar en `upgrade-arquitecto.md` (patrón heinzel).
5. Si una pieza deja de mantenerse upstream: la copia adaptada ya vive en el repo → se puede congelar (fork interno) sin bloquear al agente.

## Evaluación A* (2026-09-08)

Decisión humana sobre la pieza 14 (`weisser-dev/awesome-opencode`, MIT), en el flujo
agent-builder fase [5] fix y documentada en `/tmp/opencode/agent-builder/arquitecto/05-fix.md`:

- `adr-write` (Nygard): **RECHAZADA** — redundante con la plantilla MADR ya adoptada (pieza 1) y
  con el esqueleto propio de `adr-nygard.md` (pieza 2).
- `architect-reviewer`: **INTEGRADA** como auto-revisión de la fase 3 en `arquitecto.md`
  (sección "Auto-revisión antes del gate"). Registro canónico: **fila 16 de la tabla de
  ACEPTADAS**; atribución inline en el punto de uso (regla 3).
- `api-contract` (OpenAPI/AsyncAPI): **RECHAZADA para v1** (decisión usuario 2026-09-08):
  reevaluar en primer update como reference `contratos-tablas.md` en `module-decomposition`
  (tablas naming/error envelope/pagination/checklist, MIT). Check de reevaluación en
  `upgrade-arquitecto.md`.