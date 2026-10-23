# Agentes personalizados

Copia canónica de los agentes personalizados del launcher. Son la **fuente de verdad**: se editan aquí, se versionan en git y se propagan a la configuración global de opencode (`~/.config/opencode/agents/`) con `agents_update.sh`.

> **Importante:** estos son agentes **personalizados**. El script solo gestiona los archivos que viven bajo esta carpeta; nunca reemplaza ni borra los agentes por defecto de OpenCode (`build`, `plan`, etc.) ni ningún otro agente del usuario que no esté gestionado aquí.

## Estructura del repo

Cada agente tiene su **propia subcarpeta** `src/agents/<agente>/` con todos sus archivos `.md` (el agente primario, sus subagentes y un README opcional).

```
src/agents/
├── README.md                 ← este registro
└── <agente>/
    ├── README.md             ← descripción del agente (opcional)
    ├── <agente>.md           ← agente primario
    ├── <agente>-xx.md        ← subagentes
    └── skills/               ← skills propias del agente (opcional)
        └── <skill>/SKILL.md  ← se despliega a ~/.config/opencode/skills/<skill>/
```

Los agentes pueden llevar su **propia carpeta `skills/`**: `src/agents/<agente>/skills/<skill>/SKILL.md`
se despliega a `~/.config/opencode/skills/<skill>/` (opencode detecta las skills como
`skills/<nombre>/SKILL.md`, un nivel). Los `.md` dentro de `skills/` **no** se tratan como
agentes. Los meta-archivos de procedimiento (p. ej. `upgrade-heinzel.md`, sin `mode:`) tampoco
se despliegan.

### Stage `src/skills/` — skills globales sin agente portador

Además de las skills propias de un agente, `agents_update.sh` despliega la fuente standalone
**`src/skills/<skill>/`** (mismo destino global, `~/.config/opencode/skills/<skill>/`). Se usa para
skills que no pertenecen a ningún agente en particular pero deben estar disponibles en la config
global. El stage detecta nombres de skill duplicados **entre ambas fuentes** (agente y standalone) y
aborta con error, porque opencode exige nombres únicos. El árbol standalone se copia completo
(no solo `SKILL.md`), de modo que scripts, templates y referencias viajan junto a la skill.

> **Nota sobre despliegue de skills:** las skills de un agente terminan en el registro **global**
> de skills de opencode (es el único lugar donde opencode las detecta). No es "memoria del agente":
> el estado operacional del agente (servidores, políticas) vive 100% en `<proyecto>/documents/memory/`.

## Deploy (estándar OpenCode)

El deploy aplica un **layout híbrido por rol de archivo**: el dueño (`<agente>/<agente>.md` o un archivo en la raíz) va plano a `~/.config/opencode/agents/<nombre>.md`, y cualquier otro archivo dentro de la carpeta del agente (subagente) conserva su ruta en `~/.config/opencode/agents/<agente>/<subagente>.md`. El layout **no depende de `mode:`**: un dueño puede ser `primary` o `all`. OpenCode escanea `{agent,agents}/**/*.md` de forma **recursiva** (verificado en el source V2, `packages/core/src/agent.ts`, y en los tests oficiales).

**ID del agente:** OpenCode V2 lo deriva de la ruta relativa y **no usa el campo `name:` del frontmatter** (se ignora). Por eso el layout importa:

| Archivo desplegado | ID resultante |
|--------------------|---------------|
| `agents/investigador.md` | `investigador` |
| `agents/investigador/investigador-en.md` | `investigador/investigador-en` |

Los prompts que invoquen subagentes deben usar el ID completo (`investigador/investigador-en`); el `subagent` tool resuelve por ID exacto.

**No hace falta registrar nada** en `opencode.json`: el directorio global `~/.config/opencode/agents/` se lee automáticamente en cada inicio (`ConfigPaths.directories` siempre incluye la config global). Desde v2.7.0-pre1 también se soporta **alcance local**: `<proyecto>/.opencode/agents/<agente>.md` (primario) y `<proyecto>/.opencode/agents/<agente>/<subagente>.md` (`/workspace/.opencode/...` en contenedor) para agentes/skills/commands versionados solo en ese proyecto — ambos scopes desarrollan en `/tmp` y se mueven tras aprobación (global vía `agents_update.sh`, local vía `cp` a `.opencode/` del proyecto). Ver `agent-builder` (pregunta global/local, default global).

## Registro de agentes

| Agente (agrupación) | Subcarpeta | Versión primario | Rol |
|---------------------|------------|------------------|------|
| `investigador` | `src/agents/investigador/` | 10 | Investigación web por subagentes con dos modos (simplificado EN/ES y extendido EN/FR/ES/DE/ZH/RU); reutiliza búsquedas recientes; informe en español citado (introducción, cuerpo unificado por temas, discrepancias, conclusión y fuentes), guardado en `documents/investigaciones/` y convertible a PDF con `/md2pdf` |
| `sysadmin` | `src/agents/sysadmin/` | 3 | Sysadmin disciplinado (ruleset **heinzel** adaptado a opencode + add-on **`calisto-landlock`** de Calisto): gestión de servidores Linux/FreeBSD/macOS vía SSH o local, con guardarraíles de seguridad, memoria 100% por proyecto (`<proyecto>/documents/memory/`, un cliente por proyecto), disambiguación por cliente y skills on-demand (`heinzel-rules`, `heinzel-housekeeping`, `heinzel-security`, `heinzel-email`, `heinzel-fleet-audit`, `calisto-landlock`). Actualización desde upstream: ver `upgrade-heinzel.md` (meta-archivo, no se despliega); add-ons custom: `ADDONS.md` |
| `developer` | `src/agents/developer/` | 8 | Desarrollador senior que escribe código limpio, mantenible y bien estructurado (reglas en inglés, lenguaje-agnósticas): DRY inteligente, modularidad progresiva, diseño de clases, naming, comentarios mínimos, KISS/YAGNI. Referencia de estilo `python-style.md` con jerarquía (custom > PEP 8 > SOTA > Google) aplicable a otros lenguajes. 7 skills on-demand (python-style, code-review, code-simplification, test-driven-development, api-and-interface-design, incremental-implementation, frontend-engineering). **No incluye reglas de ciberseguridad** (rol del agente `cyberseguridad`); construcción y cada actualización pasan por el gate de seguridad de `cyberseguridad`. Actualización desde upstream: ver `upgrade-developer.md` (meta-archivo, no se despliega) |
| `agent-builder` | `src/agents/agent-builder/` | 5 | Meta-agente creador de agentes: orquesta `investigador → planificación propia (Planning Gate) → developer → cyberseguridad` aplicando la **Regla de Oro (determinístico→Guardrails, reutilizable→skills, universal→.md)**, efímero en `/tmp` (sin escribir en `documents/investigaciones/`), requiere decisión humana ante hallazgos medios/altos, múltiples ciclos plan↔developer y gate final obligatorio. Hook como bloque `## Guardrails` (opencode sin hook nativo). Ver `README.md` para diagrama y `skills/agent-architecture/SKILL.md` para checklist. Actualización: ver `upgrade-agent-builder.md` |
| `cyberseguridad` | `src/agents/cyberseguridad/` | 5 | Auditor de ciberseguridad (catálogo de 29 metodologías vendorizado de `briiirussell/cybersecurity-skills`, MIT): auditoría de código, APIs, dependencias, secretos, cripto, cloud/container/IAM, seguridad de IA, threat modeling, CVE, cumplimiento y respuesta a incidentes. Solo audita y reporta; no corrige. `mode: all` para poder ejecutarse como primario o como subagente del `agent-builder` |
| `arquitecto` | `src/agents/arquitecto/` | 6 | Agente global arquitecto de software: elicitación socrática de ideas/requisitos → canvas por módulo con contratos (command/query/event), diagramas C4 en Mermaid, ADRs y riesgos → plan maestro con subproyectos/hitos/MoSCoW → packs de tareas por hito. No escribe código: su home es `<proyecto>/documents/arquitectura/` con `INDEX.md` (registro de proyectos: `| Proyecto | Descripción | Estado | Fecha de creación | Fecha de última actualización |`) y una subcarpeta `<proyecto>/` por proyecto gestionado; `edit/write: allow` con el alcance restringido **por prompt** (guardrails). Handoff a `plan` (built-in, F2) y `developer`. 3 skills on-demand (`module-decomposition`, `architecture-decisions`, `delivery-planning`) + comando `/arquitecto`. Decisiones de diseño y piezas vendorizadas: `PROVENANCE.md`; actualización de piezas upstream: `upgrade-arquitecto.md` (meta-archivo, no se despliega). Auditorías y gate final: `documents/reports/cyberseguridad-2026-09-08-arquitecto*.md` |

## Skills globales (standalone, `src/skills/`)

Skills sin agente portador, horneadas en la imagen y desplegadas a la config global:

| Skill | Subcarpeta | Versión | Rol |
|-------|------------|---------|------|
| `frontend-slides` | `src/skills/frontend-slides/` | 1 | Crea presentaciones HTML autocontenidas (animadas) desde cero o convirtiendo PPT, con descubrimiento visual de estilo anti-"AI slop" y 34 bold templates; export a PDF local. Vendorizada de `zarazhangrui/frontend-slides` (MIT). Scripts: `deps.sh` (doctor/install aislado en `.deps/` en host), `export-pdf.sh` + `export-slides.mjs` (playwright+Chromium), `pptx-extract.sh` + `extract-pptx.py` (python-pptx). Comando `/frontend-slides`. Vercel excluido. Ver `PROVENANCE.md` y `upgrade-frontend-slides.md` |
| `mermaid2png` | `src/skills/mermaid2png/` | 2 | Renderiza diagramas Mermaid (`.mmd`) a PNG localmente con `@mermaid-js/mermaid-cli` y Chrome headless, sin servicios de terceros (kroki/mermaid.ink excluidos). Antes vivía huérfana en la config global; ahora es fuente versionada en el repo |

## Actualización de heinzel (agente sysadmin)

El agente `sysadmin` vendoriza el ruleset de [`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel):
las reglas viven en `src/agents/sysadmin/skills/heinzel-rules/references/` y las
skills en `src/agents/sysadmin/skills/`. No hay flag `--download` en
`agents_update.sh`: la actualización se hace siguiendo el **procedimiento guiado**
`src/agents/sysadmin/upgrade-heinzel.md` (fetch de upstream → diff estructurado →
re-vendorizar con mapa de reescrituras Claude-Code→opencode → plegar cambios a
`sysadmin.md` y bumpear `version:` → validación → deploy).

### Add-ons custom (`calisto-*`)

No todo lo que lleva el agente viene de heinzel. Los componentes propios se
declaran en `src/agents/<agente>/ADDONS.md` (meta-archivo, no se despliega) y usan
el prefijo `calisto-` para distinguirlos. El caso actual es
`src/agents/sysadmin/skills/calisto-landlock/`:

- **No** se copia desde upstream ni se sobrescribe.
- **No** se borra cuando se limpian skills que desaparecieron de heinzel.
- Se valida en el Paso 3b/6 de `upgrade-heinzel.md` y se incluye en el gate de
  `cyberseguridad`.
- La documentación de desarrollo del binario vive en
  `src/tools/landlock/DEVELOPMENT.md`; la skill es solo el procedimiento
  operativo del agente.

## Política de versiones

- Cada agente lleva `version: N` (entero) en el frontmatter.
- Se sube la versión cuando el contenido del agente cambia en el repo.
- `agents_update.sh` compara la versión instalada contra la del repo y, además, el checksum (`sha256sum`) para detectar ediciones locales.

## Cómo actualizar un agente

```bash
# 1. Editar el/los .md de src/agents/<agente>/ y subir su version:
#    version: 1 -> version: 2

# 2. Ver qué cambiaría sin tocar nada:
./src/agents_update.sh --check

# 3. Aplicar (pide confirmación):
./src/agents_update.sh
```

Ver `agents_update.sh --help` para todos los modos.