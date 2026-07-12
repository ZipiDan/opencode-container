# opencode-container

Lanzador containerizado de [opencode](https://opencode.ai) usando Podman. Ejecuta opencode dentro de un contenedor Debian aislado por proyecto, con separación estricta de datos y configuración global compartida. El contenedor es un entorno de desarrollo y administración de sistema completo listo para tareas de desarrollo Python y Node.js, diagnóstico de redes, devops, automatización, seguridad, implementacion de sistemas SAAS y análisis asistido por IA — sin instalar nada adicional.

## Características

- **Aislamiento por proyecto**: Cada proyecto tiene su propia `opencode.db`, sesiones, snapshots y logs.
- **Datos globales compartidos**: Credenciales (`auth.json`), cuentas OAuth (`db/`) y clones internos (`repos/`) se comparten entre proyectos.
- **Identidad del agente**: Git/ssh keys separadas del usuario, almacenadas en `~/.config/opencode/identity/`.
- **Modos de ejecución**: Web (servidor HTTP) y TUI (terminal interactiva).
- **Gestión de imagen**: Reconstrucción con caché (`--rebuild`), actualización completa (`--update`) y actualización desde cero reemplazando la imagen anterior si el build es exitoso (`--renew`).
- **Gestión de contenedores**: Listar (`--ps` / `--ls`) y detener (`--kill` / `--rm`) contenedores opencode en ejecución. Contenedores TUI se numeran automáticamente (`opencode-tuiN`).
- **Red configurable**: Aislada por defecto; `--network-host` para acceder a servicios del host.
- **Resolución de project root**: si pasás un subdirectorio, `opencode.sh` trepa buscando `.git` (tope en `$HOME`) y monta la raíz real. `--no-climb` (alias `--no-search-git`) lo desactiva.

## Capacidades del contenedor

### 🐍 Desarrollo Python
Python 3, pip, `venv` y `python3-dev` para compilar extensiones nativas. Instalá dependencias, creá entornos virtuales, corré tests y usá pyright como LSP para type checking, todo dentro del contenedor.

### 🌐 Diagnóstico y debugging de red
Herramientas completas de red: `ping`, `traceroute` y `mtr` para verificar conectividad; `dig`, `nslookup` y `host` para resolución DNS; `ss` y `netstat` para inspeccionar conexiones activas; `nmap` para escaneo de puertos; `tcpdump` y `tshark` (Wireshark CLI) para captura y análisis de tráfico en vivo.

### 🔧 DevOps / Automatización
Git, SSH y GPG para control de versiones y autenticación segura. Curl, wget y jq para interactuar con APIs REST y procesar JSON. Bash scripting para automatización de tareas administrativas. Iptables para configuración de firewall. Ansible para aplicar configuraciones estándar sobre hosts remotos (playbooks, roles y módulos).

### 🤖 Inteligencia Artificial
OpenCode integrado con acceso a 75+ proveedores de LLM para análisis, generación, refactorización y debugging de código asistido por IA.

### 📦 Node.js / JavaScript
Node.js y npm permiten ejecutar scripts JS, instalar paquetes del ecosistema y utilizar LSPs para desarrollo JavaScript.

### 🔐 Seguridad
SSH a servidores remotos, verificación de certificados SSL/TLS, escaneo de puertos con nmap y captura de paquetes para auditoría de red.

## Prerrequisitos

- [Podman](https://podman.io/) instalado
- Linux o macOS

## Instalación rápida

```bash
git clone <url-del-repo>
cd opencode-container
chmod +x opencode.sh
```

## Uso

```bash
# Modo web (puerto 4096 por defecto)
./opencode.sh /ruta/a/tu/proyecto

# Modo TUI (terminal interactiva)
./opencode.sh /ruta/a/tu/proyecto --tui

# Puerto personalizado
./opencode.sh /ruta/a/tu/proyecto --port 4097

# Datos del proyecto en ubicación personalizada
./opencode.sh /ruta/a/tu/proyecto -config /mnt/opencode-data

# Subcarpeta de un proyecto git (resuelve la raíz buscando .git hacia arriba)
./opencode.sh /ruta/a/tu/proyecto/subdir

# Forzar a trabajar exactamente en la subcarpeta sin buscar .git
./opencode.sh /ruta/a/tu/proyecto/subdir --no-climb
```

### Comandos de gestión de imagen

| Acción | Comando |
|--------|---------|
| Reconstruir imagen (con caché) | `./opencode.sh --rebuild` |
| Actualizar imagen (no-cache + pull base) | `./opencode.sh --update` |
| Actualizar imagen desde cero, reemplazando la anterior si el build es exitoso | `./opencode.sh --renew` |
| Compartir red del host | `./opencode.sh /path/to/project --network-host` |

> `--renew` y `--rebuild` son mutuamente excluyentes.

### Comandos de gestión de contenedores

| Acción | Comando |
|--------|---------|
| Listar contenedores opencode en ejecución | `./opencode.sh --ps` o `./opencode.sh --ls` |
| Detener un contenedor opencode (nombre exacto) | `./opencode.sh --kill opencode-tui2` |
| Detener un contenedor opencode (forma corta) | `./opencode.sh --kill tui2` o `./opencode.sh --kill 2` |
| Detener un contenedor opencode (por puerto) | `./opencode.sh --kill 4096` |
| Alias de `--kill` | `./opencode.sh --rm <patrón>` |

> `--ps`/`--ls` y `--kill`/`--rm` son mutuamente excluyentes y no se pueden combinar con flags de gestión de imagen ni de ejecución.

## Combinaciones de parámetros

Los parámetros se distribuyen en tres **mundos mutuamente excluyentes**:

- **Mundo IMAGEN**: `--renew` / `--rebuild` / `--update` — gestionan la imagen del contenedor.
- **Mundo GESTIÓN**: `--ps` / `--ls` / `--kill` / `--rm` — operan sobre contenedores en ejecución.
- **Mundo EJECUCIÓN**: `<proyecto>` + flags runtime (`-config`, `--port`, `--tui`, `--network-host`) — lanzan un contenedor.

Los flags de un mundo **no se cruzan** con los del otro. La referencia formal completa (tabla única, BNF y reglas del parser) está en [`PARAMETERS.md`](PARAMETERS.md).

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
- `--no-climb` (alias `--no-search-git`) desactiva la resolución automática de `.git` hacia arriba; útil para trabajar en una subcarpeta aislada.
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
./opencode.sh /ruta/proyecto/subdir         # busca .git hacia arriba para encontrar la raíz del proyecto
./opencode.sh /ruta/proyecto/subdir --no-climb  # no busca la raíz; trabaja en la subcarpeta
./opencode.sh /ruta/proyecto --port 4097 --network-host
./opencode.sh /ruta/proyecto -config /mnt/data

# Mundo EJECUCIÓN — TUI
./opencode.sh /ruta/proyecto --tui
./opencode.sh /ruta/proyecto --tui --network-host
```

## Arquitectura

### Separación de datos

| Alcance | Ubicación (host) | Contenido |
|---------|-------------------|-----------|
| **Global** | `~/.config/opencode/` | `opencode.json` (API keys), `agents/`, `commands/`, `identity/`, `share/` |
| **Por proyecto** | `<project>/.opencode/` | `data/` (opencode.db, sesiones, snapshots, logs), `state/` (locks), `python/` (paquetes pip) |

### Montajes en el contenedor

| Host | Contenedor | Alcance |
|------|------------|---------|
| `<project>` | `/workspace` | Proyecto |
| `~/.config/opencode/` | `/home/opencode/.config/opencode/` | Global |
| `~/.config/opencode/identity/` | `/root/.identity` | Global |
| `~/.config/opencode/share/` | `/home/opencode/.local/share/opencode-global/` | Global |
| `<project>/.opencode/data/` | `/home/opencode/.local/share/opencode/` | Proyecto |
| `<project>/.opencode/state/` | `/home/opencode/.local/state` | Proyecto |
| `<project>/.opencode/python/` | `/home/opencode/.pythonuser` | Proyecto |

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

## Variables de entorno del contenedor

| Variable | Valor | Propósito |
|----------|-------|-----------|
| `XDG_CONFIG_HOME` | `/home/opencode/.config` | Raíz de configuración |
| `XDG_STATE_HOME` | `/home/opencode/.local/state` | Raíz de estado (locks) |
| `XDG_DATA_HOME` | `/home/opencode/.local/share` | Raíz de datos (auth, storage, snapshots) |
| `PYTHONUSERBASE` | `/home/opencode/.pythonuser` | Destino de installs pip `--user` |
| `AGENT_GIT_NAME` | `OpenCode Agent` | Nombre git del agente |
| `AGENT_GIT_EMAIL` | `agent@opencode.local` | Email git del agente |
| `OPENCODE_MODE` | `web` / `tui` | Modo de ejecución |

## Red

Por defecto, el contenedor usa el namespace de red propio de Podman (slirp4netns/pasta), por lo que **no puede acceder a servicios que escuchen en `127.0.0.1` del host** (ej: una BD local, un proxy LLM).

Usa `--network-host` para agregar `--network host` a `podman run`: el contenedor comparte la red del host y `localhost` dentro del contenedor resuelve al host. Esto **rompe el aislamiento de red**, así que úsalo solo cuando sea necesario.

En modo web con `--network-host`, el puerto se publica automáticamente vía la red del host, por lo que se omite el flag `-p`.

## Migración desde versiones anteriores

> Las instrucciones de migración son opciones manuales. Si necesitas ayuda, puedes preguntarle al agente de opencode.

Proyectos creados con versiones anteriores del launcher usaban `<project>/.opencode/data/opencode/` como raíz completa de `XDG_DATA_HOME`. El layout actual monta `<project>/.opencode/data/` directamente como `XDG_DATA_HOME/opencode/`.

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

La migración es manual para evitar sobrescribir datos. Ejecútala una vez por proyecto existente. Después de migrar, `opencode.db` se creará dentro de `<project>/.opencode/data/` en el próximo arranque.

## Notas

- El contenedor corre como root. `xdg-open` está stubbed con un script no-op.
- Herramientas de diagnóstico de red disponibles dentro del contenedor: nmap, tcpdump, tshark, iperf, etc.
- `PYTHONUSERBASE=/home/opencode/.pythonuser` — los installs pip `--user` van al volumen de python montado.
- La identidad git/ssh del agente vive en `~/.config/opencode/identity/` y se symlinea a `/root/` al iniciar el contenedor.
- Para proyectos sin `.git` ni `opencode.json(c)`, `opencode.sh` crea `opencode.jsonc` en el project root (contenido tuneable vía `PROJECT_ANCHOR_CONTENT`) para fijar el root dentro del contenedor. La creación es idempotente.
- opencode organiza sesiones y snapshots por `projectID` (derivado del hash del commit raíz de git). Los montajes anidados proveen un aislamiento físico adicional entre proyectos.
