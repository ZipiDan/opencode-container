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

> **Nota sobre despliegue de skills:** las skills de un agente terminan en el registro **global**
> de skills de opencode (es el único lugar donde opencode las detecta). No es "memoria del agente":
> el estado operacional del agente (servidores, políticas) vive 100% en `<proyecto>/documents/memory/`.

## Deploy (estándar OpenCode)

El deploy **preserva el árbol de subcarpetas**: cada archivo `src/agents/<rel>` se copia a `~/.config/opencode/agents/<rel>`. OpenCode escanea `{agent,agents}/**/*.md` de forma **recursiva** (verificado en el source, `packages/opencode/src/config/agent.ts`, y en los tests oficiales).

**Nombre del agente:** por defecto OpenCode nombra al agente por su ruta relativa (`agents/investigador/investigador-en.md` → `investigador/investigador-en`). Cada archivo puede fijar su nombre con el campo `name:` del frontmatter (soportado por el loader, que aplica el frontmatter sobre el nombre del path). Con eso se tienen **nombres limpios aunque el archivo viva en subcarpeta**:

| Archivo desplegado | `name:` en frontmatter | Agente resultante |
|--------------------|------------------------|-------------------|
| `agents/investigador/investigador.md` | `investigador` | `investigador` |
| `agents/investigador/investigador-en.md` | `investigador-en` | `investigador-en` |

**No hace falta registrar nada** en `opencode.json`: el directorio global `~/.config/opencode/agents/` se lee automáticamente en cada inicio (`ConfigPaths.directories` siempre incluye la config global). Desde v2.7.0-pre1 también se soporta **alcance local**: `<proyecto>/.opencode/agents/` (`/workspace/.opencode/agents/` en contenedor) para agentes/skills/commands versionados solo en ese proyecto — ambos scopes desarrollan en `/tmp` y se mueven tras aprobación (global vía `agents_update.sh`, local vía `cp` a `.opencode/` del proyecto). Ver `agent-builder` (pregunta global/local, default global).

## Registro de agentes

| Agente (agrupación) | Subcarpeta | Versión primario | Rol |
|---------------------|------------|------------------|------|
| `investigador` | `src/agents/investigador/` | 8 | Investigación web por subagentes con dos modos (simplificado EN/ES y extendido EN/FR/ES/DE/ZH/RU); reutiliza búsquedas recientes; informe en español citado (introducción, cuerpo unificado por temas, discrepancias, conclusión y fuentes), guardado en `documents/investigaciones/` y convertible a PDF con `/md2pdf` |
| `sysadmin` | `src/agents/sysadmin/` | 1 | Sysadmin disciplinado (ruleset **heinzel** adaptado a opencode): gestión de servidores Linux/FreeBSD/macOS vía SSH o local, con guardarraíles de seguridad, memoria 100% por proyecto (`<proyecto>/documents/memory/`, un cliente por proyecto), disambiguación por cliente y skills on-demand (`heinzel-rules`, `heinzel-housekeeping`, `heinzel-security`, `heinzel-email`, `heinzel-fleet-audit`). Actualización desde upstream: ver `upgrade-heinzel.md` (meta-archivo, no se despliega) |
| `developer` | `src/agents/developer/` | 7 | Desarrollador senior que escribe código limpio, mantenible y bien estructurado (reglas en inglés, lenguaje-agnósticas): DRY inteligente, modularidad progresiva, diseño de clases, naming, comentarios mínimos, KISS/YAGNI. Referencia de estilo `python-style.md` con jerarquía (custom > PEP 8 > SOTA > Google) aplicable a otros lenguajes. 7 skills on-demand (python-style, code-review, code-simplification, test-driven-development, api-and-interface-design, incremental-implementation, frontend-engineering). **No incluye reglas de ciberseguridad** (rol del agente `cyberseguridad`); construcción y cada actualización pasan por el gate de seguridad de `cyberseguridad`. Actualización desde upstream: ver `upgrade-developer.md` (meta-archivo, no se despliega) |
| `agent-builder` | `src/agents/agent-builder/` | 1 | Meta-agente creador de agentes: orquesta `investigador → plan → developer → cyberseguridad` aplicando la **Regla de Oro (determinístico→Guardrails, reutilizable→skills, universal→.md)**, efímero en `/tmp` (sin escribir en `documents/investigaciones/`), requiere decisión humana ante hallazgos medios/altos, múltiples ciclos plan↔developer y gate final obligatorio. Hook como bloque `## Guardrails` (opencode sin hook nativo). Ver `README.md` para diagrama y `skills/agent-architecture/SKILL.md` para checklist. Actualización: ver `upgrade-agent-builder.md` |
| `arquitecto` | `src/agents/arquitecto/` | 1 | Agente global arquitecto de software: elicitación socrática de ideas/requisitos → canvas por módulo con contratos (command/query/event), diagramas C4 en Mermaid, ADRs y riesgos → plan maestro con subproyectos/hitos/MoSCoW → packs de tareas por hito. No escribe código: artefactos a `<proyecto>/documents/arquitectura/**`, handoff a `plan` (built-in, F2) y `developer`. 3 skills on-demand (`module-decomposition`, `architecture-decisions`, `delivery-planning`) + comando `/arquitecto`. Decisiones de diseño y piezas vendorizadas: `PROVENANCE.md`; actualización de piezas upstream: `upgrade-arquitecto.md` (meta-archivo, no se despliega). Auditorías y gate final: `documents/reports/cyberseguridad-2026-09-08-arquitecto*.md` |

## Actualización de heinzel (agente sysadmin)

El agente `sysadmin` vendoriza el ruleset de [`wintermeyer/heinzel`](https://github.com/wintermeyer/heinzel):
las reglas viven en `src/agents/sysadmin/skills/heinzel-rules/references/` y las 4 skills en
`src/agents/sysadmin/skills/`. No hay flag `--download` en `agents_update.sh`: la actualización se
hace siguiendo el **procedimiento guiado** `src/agents/sysadmin/upgrade-heinzel.md` (fetch de
upstream → diff estructurado → re-vendorizar con mapa de reescrituras Claude-Code→opencode →
plegar cambios a `sysadmin.md` y bumpear `version:` → validación → deploy).

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