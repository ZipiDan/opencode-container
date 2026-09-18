# opencode-container

Un lugar seguro donde pensar, construir y operar con [opencode](https://opencode.ai):
el mismo opencode que ya conocés, pero dentro de un contenedor Debian aislado por
proyecto, con las herramientas ya dispuestas y tus carpetas locales siempre a la mano.

> **Compatibilidad ante todo.** Este launcher no reemplaza a opencode: lo acompaña.
> Los agentes, comandos, skills y configuraciones que viajan acá se despliegan igual
> de bien en el contenedor como en una instalación tradicional de opencode.

---

## Por qué existe este proyecto

Cuando trabajamos en una idea, no queremos que la máquina local sea parte del
experimento. Instalar toolchains, pelear con versiones, mezclar credenciales o
dejar rastros en el sistema son distracciones que rompen el ritmo. La motivación de
este proyecto es simple: **darte un espacio aislado, reproducible y completo para
trabajar con opencode**, sin sacrificar nada de lo que ya ofrece la versión
tradicional.

El contenedor es una base equipada. Trae preinstaladas las herramientas de
desarrollo, redes, automatización y seguridad que solés necesitar, así no tenés que
ensuciar tu máquina ni empezar de cero cada vez. Y como todo el estado vive en tu
proyecto (no en el sistema), podés entrar y salir sin miedo: tu entorno local queda
tal como estaba.

## Qué te llevás

- **Un opencode completo y familiar**: mismos agentes base (`build`, `plan`) y toda
  la configuración global compartida entre proyectos.
- **Cuatro entornos de programación integrados**: Python, JavaScript, TypeScript y
  Rust, listos para usar sin instalación previa.
- **Herramientas de apoyo ya presentes**: diagnóstico de redes, DevOps, control de
  versiones, automatización y auditoría.
- **Agentes especializados** que se suman a los de opencode para cubrir las tareas
  del día a día, desde la investigación hasta la operación de servidores.
- **Tus carpetas locales, primero**: el contenedor trabaja sobre tus directorios
  reales; nada de islas desconectadas.
- **Un solo flujo de actualización** para el contenedor y para opencode tradicional.

## Cuatro entornos, un mismo espacio

| Entorno | Qué encontrás |
|---------|---------------|
| **Python** | Python 3, pip y `python3-dev` para extensiones nativas. El venv canónico vive en `<proyecto>/python/`, se crea y activa solo, y el type checking corre con pyright. Ruff disponible como linter/formatter. |
| **JavaScript** | Node.js y npm para scripts, paquetes del ecosistema y soporte de lenguaje vía LSP. |
| **TypeScript** | El mismo toolchain de Node.js más el soporte de TypeScript que opencode activa a través de su LSP integrado. |
| **Rust** | Toolchain estable vía rustup, con objetivo `x86_64-unknown-linux-musl` para binarios estáticos. Registry, `target/` y binarios quedan aislados en `<proyecto>/rust/`. |

Además: `git`, `ssh` y `gpg`; `curl`, `wget` y `jq` para APIs; `iptables` y Ansible
para automatización y configuración remota; y una caja de redes con `ping`,
`traceroute`, `mtr`, `dig`, `ss`, `nmap`, `tcpdump` y `tshark`.

## Agentes que te acompañan

Además de `build` y `plan`, este proyecto incorpora agentes pensados para cubrir
frentes concretos. Se eligen por sesión (en TUI, con `Tab`) o se invocan por comando.

| Agente | Para qué sirve |
|--------|----------------|
| `investigador` | Investiga un tema en la web orquestando subagentes en varios idiomas y entrega un informe en español, con fuentes citadas, listo para leer o convertir a PDF y HTML con estilos predefinidos. |
| `arquitecto` | Convierte una idea en arquitectura documentada y un plan de trabajo por hitos. No escribe código: piensa, decide y entrega tareas. |
| `developer` | Escribe y refactoriza código limpio y mantenible, con reglas de calidad siempre activas y skills que se cargan solo cuando la tarea lo pide. |
| `sysadmin` | Administra servidores Linux, FreeBSD y macOS con disciplina y guardarraíles de seguridad, guardando la memoria de cada cliente en el proyecto. |
| `cyberseguridad` | Audita código, infraestructura y agentes de IA. Es el filtro de seguridad obligatorio antes de dar por aprobado cualquier agente nuevo. |
| `agent-builder` | Meta-agente que crea otros agentes: investiga, planifica, construye y audita antes de proponerte el resultado. |

### Cómo se construyeron

Algunos agentes nacieron de una idea propia, como el `investigador`. Otros, como el
`arquitecto`, se levantaron con `agent-builder`: un asistente que usó al
`investigador` para rastrear repositorios públicos en español, inglés, francés,
alemán, ruso y chino, seleccionar las fuentes más adecuadas y complementarias, y
vendorizar el agente a partir de ellas. Cada pieza pasó después por el agente de
`cyberseguridad` para asegurar que el agente y sus skills no contuvieran, por
ejemplo, prompt injection y que sus permisos fueran seguros.

Ese mismo rigor es reproducible: cada agente documenta el procedimiento para
actualizarse desde sus fuentes originales, de modo que el trabajo pueda repetirse y
mantenerse en el tiempo.

## Informes listos para compartir

Los agentes generan Markdown, y el proyecto incluye `md2pdf`, una herramienta que
convierte cualquier informe a **PDF o HTML** con estilos agradables para lectura y
publicación: `github`, `pandoc`, `newsprint`, `notion` y `paper`. Está disponible
como comando global `/md2pdf`.

## Compatibilidad y actualización

Este desarrollo se esfuerza por mantenerse **completamente compatible con opencode
tradicional**. Un único script, `agents_update.sh`, se encarga de actualizar los
agentes, las skills, los estilos y los comandos, tanto para el launcher
contenedorizado como para una instalación tradicional de opencode.

La diferencia es mínima:

- **En el contenedor**, las herramientas (`md2pdf`, etc.) ya vienen integradas en la
  imagen.
- **En opencode tradicional**, las herramientas se instalan de forma explícita con
  `./agents_update.sh --install-tools`.

El flujo de deploy y actualización es el mismo en ambos casos y se describe en
detalle más abajo, en [Agentes personalizados](#agentes-personalizados-deploy-y-actualización).

---

# Especificaciones técnicas

A partir de acá, el detalle operativo: comandos, montajes, variables y flujo de
actualización. Es la referencia para usuarios técnicos y también una ayuda-memoria
para los propios agentes.

## Cheatsheet

| Acción | Comando |
|--------|---------|
| Modo web (puerto 4096) | `opencode.sh /ruta/a/tu/proyecto` |
| Modo TUI | `opencode.sh /ruta/a/tu/proyecto --tui` |
| Puerto personalizado | `opencode.sh /ruta/a/tu/proyecto --port 4097` |
| Auth básica web | `opencode.sh /ruta/a/tu/proyecto --password "pwd" --user "admin"` |
| Datos en otra ubicación | `opencode.sh /ruta/a/tu/proyecto -config /mnt/opencode-data` |
| Compartir red del host | `opencode.sh /ruta/a/tu/proyecto --network-host` |
| Listar contenedores | `opencode.sh --ps` (o `--ls`) |
| Detener contenedor | `opencode.sh --kill <patrón>` (o `--rm <patrón>`) |
| Reconstruir imagen (caché) | `opencode.sh --rebuild` |
| Actualizar imagen (no-cache) | `opencode.sh --update` |
| Actualizar desde cero y reemplazar | `opencode.sh --renew` |
| Sincronizar agentes/skills/comandos | `./src/agents_update.sh` |
| Instalar tools en host tradicional | `./src/agents_update.sh --install-tools` |

## Prerrequisitos

- [Podman](https://podman.io/) instalado
- Linux o macOS

## Instalación rápida

```bash
git clone <url-del-repo>
cd opencode-container
chmod +x opencode.sh
```

### Acceso cómodo desde cualquier carpeta

Conviene crear un enlace simbólico a `opencode.sh` dentro de un directorio que ya
esté en tu `PATH` (por ejemplo `~/.local/bin` o `~/bin`). Así podés lanzarlo desde
cualquier proyecto sin escribir la ruta completa:

```bash
ln -s "$(pwd)/opencode.sh" ~/.local/bin/opencode.sh
```

### Disponibilizar los agentes en tu entorno

El código de los agentes, skills, estilos y comandos vive en el repo; para que
opencode los vea hay que desplegarlos a la configuración global del usuario
(`~/.config/opencode/`). Es el mismo directorio que lee el opencode tradicional y que
monta el contenedor, así que **un solo paso cubre ambos entornos**:

```bash
# Desde el repo, desplegar agentes + skills + estilos + comandos (pide confirmación)
./src/agents_update.sh

# Ver primero qué cambiaría, sin escribir nada
./src/agents_update.sh --check
```

Reiniciá opencode (contenedor o tradicional) para que tome los agentes.

> **Solo para opencode tradicional (no el contenedor):** las herramientas de software
> como `md2pdf` no vienen preinstaladas y hay que instalarlas explícitamente:
>
> ```bash
> ./src/agents_update.sh --install-tools          # a ~/.local/bin
> ./src/agents_update.sh --install-tools ~/bin    # a un directorio propio
> ```
>
> Una vez instalada, `md2pdf` puede requerir dependencias extra de Python
> (`markdown` y `weasyprint`). Verificalo con el diagnóstico integrado, que además
> muestra las instrucciones de instalación según tu sistema operativo:
>
> ```bash
> md2pdf --doctor
> ```
>
> En el contenedor todas las herramientas y sus dependencias ya están integradas en la
> imagen, por lo que ni `--install-tools` ni `--doctor` son necesarios.

## Uso

> **Es obligatorio pasarle una carpeta local.** El contenedor no es una isla: monta
> tu directorio y trabaja directamente sobre él. La carpeta de trabajo por defecto
> dentro del contenedor es **`/workspace`**, y corresponde al proyecto que pasás
> como argumento.

```bash
# Modo web (puerto 4096 por defecto)
./opencode.sh /ruta/a/tu/proyecto

# Modo TUI (terminal interactiva)
./opencode.sh /ruta/a/tu/proyecto --tui

# Puerto personalizado
./opencode.sh /ruta/a/tu/proyecto --port 4097

# Auth básica web (usuario por defecto: opencode)
./opencode.sh /ruta/a/tu/proyecto --password "mi-secreto"

# Auth básica web (password + usuario custom)
./opencode.sh /ruta/a/tu/proyecto --password "mi-secreto" --user "admin"

# Datos del proyecto en ubicación personalizada
./opencode.sh /ruta/a/tu/proyecto -config /mnt/opencode-data

# Subcarpeta de un proyecto git (resuelve la raíz buscando .git hacia arriba)
./opencode.sh /ruta/a/tu/proyecto/subdir

# Forzar a trabajar exactamente en la subcarpeta sin buscar .git
./opencode.sh /ruta/a/tu/proyecto/subdir --no-climb
```

### Gestión de imagen

| Acción | Comando |
|--------|---------|
| Reconstruir imagen (con caché) | `./opencode.sh --rebuild` |
| Actualizar imagen (no-cache + pull base) | `./opencode.sh --update` |
| Actualizar imagen desde cero, reemplazando la anterior si el build es exitoso | `./opencode.sh --renew` |
| Compartir red del host | `./opencode.sh /path/to/project --network-host` |
| Auth básica web (password) | `./opencode.sh /path/to/project --password "pwd"` |
| Auth básica web (password + user) | `./opencode.sh /path/to/project --password "pwd" --user "admin"` |

> `--renew` y `--rebuild` son mutuamente excluyentes.

### Gestión de contenedores

| Acción | Comando |
|--------|---------|
| Listar contenedores opencode en ejecución | `./opencode.sh --ps` o `./opencode.sh --ls` |
| Detener un contenedor opencode (nombre exacto) | `./opencode.sh --kill opencode-tui2` |
| Detener un contenedor opencode (forma corta) | `./opencode.sh --kill tui2` o `./opencode.sh --kill 2` |
| Detener un contenedor opencode (por puerto) | `./opencode.sh --kill 4096` |
| Alias de `--kill` | `./opencode.sh --rm <patrón>` |

> `--ps`/`--ls` y `--kill`/`--rm` son mutuamente excluyentes y no se pueden combinar
> con flags de gestión de imagen ni de ejecución.

## Combinaciones de parámetros

Los parámetros se distribuyen en tres **mundos mutuamente excluyentes**:

- **Mundo IMAGEN**: `--renew` / `--rebuild` / `--update` — gestionan la imagen del contenedor.
- **Mundo GESTIÓN**: `--ps` / `--ls` / `--kill` / `--rm` — operan sobre contenedores en ejecución.
- **Mundo EJECUCIÓN**: `<proyecto>` + flags runtime (`-config`, `--port`, `--tui`, `--network-host`) — lanzan un contenedor.

Los flags de un mundo **no se cruzan** con los del otro. La referencia formal completa
(tabla única, BNF y reglas del parser) está en [`PARAMETERS.md`](PARAMETERS.md).

### Árbol de combinaciones

```
ℹ️  --help / -h es compatible con cualquier rama (short-circuits y sale)
ℹ️  --version imprime la versión del launcher y sale

parámetros
│
├── --renew                          actualiza la imagen reconstruyendo desde cero;
│                                    elimina la anterior si el build es exitoso
│
├── --rebuild                        reconstruye imagen usando caché
│
├── --update                         actualiza imagen desde cero
│
├── --ps | --ls                      muestra contenedores opencode en ejecución
│
├── --kill <patrón> | --rm <patrón>  detiene un contenedor opencode
│       (patrón: opencode-tui2, opencode-4096, tui2, 2, 4096)
│
└── <proyecto>                       lanza opencode en el proyecto
    │
    ├── --no-climb                   desactiva la búsqueda de .git hacia atrás
    │                                (también: --no-search-git)
    │
    ├── --tui                        arranca terminal interactiva
    │   ├── -config <ruta>
    │   └── --network-host
    │
    └── web (sin --tui, default)     arranca servidor web
        ├── --port <1-65535>
        │   └── default: 4096
        ├── -config <ruta>
        └── --network-host
```

### Reglas clave

- No mezclar flags de mundos distintos (IMAGEN/GESTIÓN/EJECUCIÓN).
- `--renew` y `--rebuild` son mutuamente excluyentes (error del script).
- `--ps`/`--ls` y `--kill`/`--rm` son mutuamente excluyentes entre sí.
- `--tui` ignora `--port` (no hay servidor web).
- `--no-climb` (alias `--no-search-git`) desactiva la resolución automática de `.git`
  hacia arriba; útil para trabajar en una subcarpeta aislada.
- `--network-host` omite `-p` en modo web (podman lo publica vía el host).
- Contenedores TUI se nombran `opencode-tuiN` (numeración `max+1`).
- Contenedores web se nombran `opencode-<puerto>`.

### Ejemplos de invocaciones válidas

```bash
# Mundo IMAGEN
./opencode.sh --renew
./opencode.sh --update

# Mundo GESTIÓN
./opencode.sh --ps
./opencode.sh --ls
./opencode.sh --kill opencode-tui2
./opencode.sh --kill 4096
./opencode.sh --rm tui2

# Mundo EJECUCIÓN — web
./opencode.sh /ruta/proyecto
./opencode.sh /ruta/proyecto/subdir               # busca .git hacia arriba para encontrar la raíz del proyecto
./opencode.sh /ruta/proyecto/subdir --no-climb    # no busca la raíz; trabaja en la subcarpeta
./opencode.sh /ruta/proyecto --port 4097 --network-host
./opencode.sh /ruta/proyecto -config /mnt/data

# Mundo EJECUCIÓN — TUI
./opencode.sh /ruta/proyecto --tui
./opencode.sh /ruta/proyecto --tui --network-host
```

## Identidad del agente

El launcher crea una **identidad propia para el agente**, separada de la del usuario:

- Una **llave SSH** que podés usar en servidores remotos sin exponer tu llave personal.
- Un **`gitconfig`** que define el autor de los commits del agente y que podés
  personalizar.

Ambas viven en `~/.config/opencode/identity/` y se enlazan dentro del contenedor al
iniciar. Así los commits y accesos del agente quedan claramente diferenciados de los
tuyos.

## Arquitectura

### Separación de datos

| Alcance | Ubicación (host) | Contenido |
|---------|-------------------|-----------|
| **Global** | `~/.config/opencode/` | `opencode.json` (API keys), `agents/`, `commands/`, `identity/`, `share/` |
| **Por proyecto** | `<project>/.opencode/` | `data/` (opencode.db, sesiones, snapshots, logs), `state/` (locks) |
| **Por proyecto (raíz)** | `<project>/python/` | Venv canónico (venv-first, auto-creado/activado por `entrypoint.sh`, gitignoreado) |
| **Por proyecto (raíz)** | `<project>/rust/` | `CARGO_HOME`/`CARGO_TARGET_DIR`: `registry/`, `target/`, `bin/` de cargo (aislado, gitignoreado) |

### Montajes en el contenedor

| Host | Contenedor | Alcance |
|------|------------|---------|
| `<project>` | `/workspace` | Proyecto |
| `~/.config/opencode/` | `/home/opencode/.config/opencode/` | Global |
| `~/.config/opencode/identity/` | `/root/.identity` | Global |
| `~/.config/opencode/share/` | `/home/opencode/.local/share/opencode-global/` | Global |
| `<project>/.opencode/data/` | `/home/opencode/.local/share/opencode/` | Proyecto |
| `<project>/.opencode/state/` | `/home/opencode/.local/state` | Proyecto |

### Symlinks internos (creados por entrypoint.sh)

Dentro del contenedor, `entrypoint.sh` crea symlinks en `/home/opencode/.local/share/opencode/`:

| Symlink | Destino |
|---------|---------|
| `auth.json` | `/home/opencode/.local/share/opencode-global/auth.json` |
| `db/` | `/home/opencode/.local/share/opencode-global/db/` |
| `repos/` | `/home/opencode/.local/share/opencode-global/repos/` |

## Configuración

La configuración global vive en `~/.config/opencode/` y no se ve afectada por `-config`:

| Ruta | Propósito |
|------|-----------|
| `opencode.json` | API keys, proveedores, modelos, permisos |
| `agents/` | Agentes personalizados |
| `commands/` | Comandos personalizados |
| `identity/` | Git/ssh identity del agente |
| `share/auth.json` | Credenciales de `/connect` |
| `share/db/` | Cuentas OAuth (GitHub, GitLab, Copilot, etc.) |
| `share/repos/` | Clones internos |

## Agentes personalizados: deploy y actualización

Los agentes personalizados viven como **copia canónica** en `src/agents/<agente>/`
(fuente de verdad, versionada en git; una subcarpeta por agente) y se propagan a la
configuración global (`~/.config/opencode/agents/`) con `src/agents_update.sh`.

El script se ejecuta **solo desde el repo** (resuelve su propia ruta, no necesita
instalación), **no modifica `opencode.sh`** y su resultado es el mismo para el
contenedor y para opencode tradicional: la config global se monta dentro del
contenedor y también es leída por cualquier instalación local de opencode.

**Deploy (estándar OpenCode):** el script **preserva el árbol de subcarpetas**:
`src/agents/investigador/investigador-en.md` se copia a
`~/.config/opencode/agents/investigador/investigador-en.md`. OpenCode escanea
`{agent,agents}/**/*.md` **recursivamente** y cada archivo fija su nombre con el campo
`name:` del frontmatter, de modo que se tienen **nombres limpios** (`investigador`,
`investigador-en`…) aunque los archivos estén en subcarpetas. **No hace falta registro**
en `opencode.json`: el directorio global `agents/` se lee solo.

### Un solo script, cinco etapas

`agents_update.sh` gestiona cinco etapas y pide una confirmación por etapa:

| Etapa | Origen (repo) | Destino (global) |
|-------|---------------|------------------|
| **agents** | `src/agents/**/*.md` | `~/.config/opencode/agents/<rel>` |
| **skills** | `src/agents/*/skills/<nombre>/**` | `~/.config/opencode/skills/<nombre>/` |
| **styles** | `src/tools/css-styles/**` | `~/.config/opencode/css-styles/` |
| **commands** | `src/commands/*.md` | `~/.config/opencode/commands/` |
| **tools** | `src/tools/*` (raíz, p.ej. `md2pdf.py`) | `~/.local/bin` (solo con `--install-tools`) |

La etapa **tools** es la única diferencia entre entornos: en el contenedor `md2pdf` y
los estilos ya vienen horneados en la imagen, mientras que en opencode tradicional se
instalan explícitamente con `--install-tools`.

Reglas del script:

- Solo gestiona los agentes bajo `src/agents/` (todos con `version: N` en el frontmatter).
  **Nunca** toca los agentes por defecto de OpenCode (`build`, `plan`, etc.) ni borra
  otros agentes que tengas instalados.
- Compara contra las copias instaladas usando `version:` + `sha256sum` (archivos en
  disco, sin git ni red).
- Muestra primero qué agentes cambiaron, advierte que se reemplazarán (las ediciones
  locales se pierden, el respaldo es responsabilidad del usuario) y pide confirmación
  (`Y`/`s`).

```bash
# Instalar/actualizar agentes, skills, estilos y comandos (pide confirmación)
./src/agents_update.sh

# Ver qué cambiaría, sin tocar nada
./src/agents_update.sh --check

# Aplicar sin confirmación (deploy desatendido)
./src/agents_update.sh --force

# Omitir una etapa concreta
./src/agents_update.sh --no-skills      # agents + styles + commands
./src/agents_update.sh --no-styles      # agents + skills + commands
./src/agents_update.sh --no-commands    # agents + skills + styles

# Instalar SOLO las tools en opencode tradicional (default: ~/.local/bin)
./src/agents_update.sh --install-tools

# Ayuda
./src/agents_update.sh --help
```

Para actualizar un agente: editá los `.md` en `src/agents/<agente>/`, subí su `version:`
y corré el script. El registro completo está en `src/agents/README.md`.

### Alcance global y local

Además del deploy global (default), `agent-builder` soporta **alcance local**: agentes,
skills y commands desarrollados en `/tmp` y copiados a `<proyecto>/.opencode/{agents,skills,commands}/`
(`/workspace/.opencode/...` dentro del contenedor), versionados en el git del proyecto.
El scope local no pasa por `agents_update.sh`.

## Variables de entorno del contenedor

| Variable | Valor | Propósito |
|----------|-------|-----------|
| `XDG_CONFIG_HOME` | `/home/opencode/.config` | Raíz de configuración |
| `XDG_STATE_HOME` | `/home/opencode/.local/state` | Raíz de estado (locks) |
| `XDG_DATA_HOME` | `/home/opencode/.local/share` | Raíz de datos (auth, storage, snapshots) |
| `VIRTUAL_ENV` | `/workspace/python` | Venv del proyecto (lo setea `entrypoint.sh` si `python/` es un venv) |
| `CARGO_HOME` | `/workspace/rust` | Registry/bin de cargo por proyecto |
| `CARGO_TARGET_DIR` | `/workspace/rust/target` | Artefactos de build de cargo por proyecto |
| `RUSTUP_HOME` | `/root/.rustup` | Toolchain de Rust (en la imagen, global) |
| `AGENT_GIT_NAME` | `OpenCode Agent` | Nombre git del agente |
| `AGENT_GIT_EMAIL` | `agent@opencode.local` | Email git del agente |
| `OPENCODE_MODE` | `web` / `tui` | Modo de ejecución |
| `OPENCODE_SERVER_PASSWORD` | — | Password de auth básica web (si no se usa `--password`) |
| `OPENCODE_SERVER_USERNAME` | `opencode` | Usuario de auth básica web (si no se usa `--user`) |

## Red

Por defecto, el contenedor usa el namespace de red propio de Podman (slirp4netns/pasta),
por lo que **no puede acceder a servicios que escuchen en `127.0.0.1` del host** (ej: una
BD local, un proxy LLM).

Usa `--network-host` para agregar `--network host` a `podman run`: el contenedor comparte
la red del host y `localhost` dentro del contenedor resuelve al host. Esto **rompe el
aislamiento de red**, así que úsalo solo cuando sea necesario.

En modo web con `--network-host`, el puerto se publica automáticamente vía la red del host,
por lo que se omite el flag `-p`.

## Auth básica web

El servidor web de opencode soporta HTTP basic auth. `opencode.sh` expone
`--password <pwd>` y `--user <usuario>` (solo modo web; en TUI se avisan y se ignoran):

- Sin `--password` ni env var → no hay auth (comportamiento por defecto).
- `--password <pwd>` → activa auth con usuario por defecto `opencode`.
- `--password <pwd> --user <usuario>` → auth con usuario custom.
- Si no se pasan flags, se usan las env vars del host
  `OPENCODE_SERVER_PASSWORD`/`OPENCODE_SERVER_USERNAME` si existen.
- Precedencia: flag `--password`/`--user` > env var del host.

## Migración desde versiones anteriores

> Las instrucciones de migración son opciones manuales. Si necesitás ayuda, podés
> preguntarle al agente de opencode.

Proyectos creados con versiones anteriores del launcher usaban
`<project>/.opencode/data/opencode/` como raíz completa de `XDG_DATA_HOME`. El layout
actual monta `<project>/.opencode/data/` directamente como `XDG_DATA_HOME/opencode/`.

Para migrar un proyecto existente:

```bash
PROJECT=/path/to/proyecto

# 1. Asegurar que el directorio global share exista
mkdir -p ~/.config/opencode/share

# 2. Copiar auth.json a la ubicación global (solo la primera vez)
cp "${PROJECT}/.opencode/data/opencode/auth.json" ~/.config/opencode/share/auth.json 2>/dev/null || true

# 3. Mover datos del proyecto al nuevo layout
mv "${PROJECT}/.opencode/data/opencode/storage" "${PROJECT}/.opencode/data/storage" 2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/snapshot" "${PROJECT}/.opencode/data/snapshot" 2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/log"      "${PROJECT}/.opencode/data/log"      2>/dev/null || true

# 4. Mover datos globales fuera del proyecto
mv "${PROJECT}/.opencode/data/opencode/db"    ~/.config/opencode/share/db    2>/dev/null || true
mv "${PROJECT}/.opencode/data/opencode/repos" ~/.config/opencode/share/repos 2>/dev/null || true

# 5. Limpiar el subdirectorio antiguo
rm -rf "${PROJECT}/.opencode/data/opencode"
```

La migración es manual para evitar sobrescribir datos. Ejecutala una vez por proyecto
existente. Después de migrar, `opencode.db` se creará dentro de `<project>/.opencode/data/`
en el próximo arranque.

### Carpetas de trabajo de los agentes (v3.0.0)

Desde v3.0.0, las carpetas de trabajo de los agentes viven bajo `documents/`:
`documents/arquitectura/`, `documents/investigaciones/`, `documents/memory/` y
`documents/reports/`. Para migrar un proyecto del layout anterior:

```bash
./src/agents_update.sh --update-directory /path/to/proyecto --check
./src/agents_update.sh --update-directory /path/to/proyecto   # confirmar Y/s
```

Solo mueve directorios preexistentes y nunca sobrescribe.

## Notas

- El contenedor corre como root. `xdg-open` está stubbed con un script no-op.
- Herramientas de diagnóstico de red disponibles dentro del contenedor: nmap, tcpdump,
  tshark, iperf, etc.
- Python es **venv-first**: el venv canónico vive en `<proyecto>/python/` (ignorado por
  git). `entrypoint.sh` lo crea automáticamente en el primer arranque si falta y lo
  activa en cada arranque. No se usa `pip --user` ni `PYTHONUSERBASE`.
- `CARGO_HOME`/`CARGO_TARGET_DIR=/workspace/rust` — cargo guarda registry, target y bin
  en `<proyecto>/rust/`. `opencode.sh` crea el directorio y completa el `.gitignore` con
  `rust/`, `python/` y los temporales (`*.tmp`, `*.swp`, `*~`) si faltan.
- Auth web: `--password`/`--user` (o env vars `OPENCODE_SERVER_PASSWORD`/`OPENCODE_SERVER_USERNAME`
  del host) activan HTTP basic auth; solo web, ignorado en TUI.
- La identidad git/ssh del agente vive en `~/.config/opencode/identity/` y se symlinea a
  `/root/` al iniciar el contenedor.
- Para proyectos sin `.git` ni `opencode.json(c)`, `opencode.sh` crea `opencode.jsonc` en
  el project root (contenido tuneable vía `PROJECT_ANCHOR_CONTENT`) para fijar el root
  dentro del contenedor. La creación es idempotente.
- opencode organiza sesiones y snapshots por `projectID` (derivado del hash del commit
  raíz de git). Los montajes anidados proveen un aislamiento físico adicional entre
  proyectos.
- La carpeta de trabajo por defecto dentro del contenedor es `/workspace`.
