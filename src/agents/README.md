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
    └── <agente>-xx.md        ← subagentes
```

## Deploy (estándar OpenCode)

El deploy **preserva el árbol de subcarpetas**: cada archivo `src/agents/<rel>` se copia a `~/.config/opencode/agents/<rel>`. OpenCode escanea `{agent,agents}/**/*.md` de forma **recursiva** (verificado en el source, `packages/opencode/src/config/agent.ts`, y en los tests oficiales).

**Nombre del agente:** por defecto OpenCode nombra al agente por su ruta relativa (`agents/investigador/investigador-en.md` → `investigador/investigador-en`). Cada archivo puede fijar su nombre con el campo `name:` del frontmatter (soportado por el loader, que aplica el frontmatter sobre el nombre del path). Con eso se tienen **nombres limpios aunque el archivo viva en subcarpeta**:

| Archivo desplegado | `name:` en frontmatter | Agente resultante |
|--------------------|------------------------|-------------------|
| `agents/investigador/investigador.md` | `investigador` | `investigador` |
| `agents/investigador/investigador-en.md` | `investigador-en` | `investigador-en` |

**No hace falta registrar nada** en `opencode.json`: el directorio global `~/.config/opencode/agents/` se lee automáticamente en cada inicio (`ConfigPaths.directories` siempre incluye la config global).

## Registro de agentes

| Agente (agrupación) | Subcarpeta | Versión primario | Rol |
|---------------------|------------|------------------|------|
| `investigador` | `src/agents/investigador/` | 8 | Investigación web por subagentes con dos modos (simplificado EN/ES y extendido EN/FR/ES/DE/ZH/RU); reutiliza búsquedas recientes; informe en español citado (introducción, cuerpo unificado por temas, discrepancias, conclusión y fuentes), guardado en `investigaciones/` y convertible a PDF con `/md2pdf` |

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