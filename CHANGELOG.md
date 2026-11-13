<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Changelog

Todas las versiones notables de **opencode-container** (launcher de opencode en
contenedor Podman).

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
proyecto respeta [SemVer](https://semver.org/lang/es/).

> **Nota sobre versionado:** el campo `VERSION` se incorporó al launcher en
> v1.5.0. Las iteraciones anteriores (v1.0–v1.4) no llevan número en el script;
> su historial se reconstruye desde los mensajes de commit.

## [4.7.0] — 2026-11-13 · refactor de Containerfile

> **Actualización requerida.** Esta versión corrige errores (export a PDF de `frontend-slides` y build de
> ruff), así que hay que **regenerar la imagen** y **redesplegar los agentes/skills**:
>
> ```bash
> ./opencode.sh --renew      # regenera la imagen desde cero y la reemplaza
> ./src/agents_update.sh     # deploy de agentes, skills, estilos y comandos
> ```
>
> Reconstruir la imagen **no alcanza**: el fix del export a PDF vive en el script del skill
> (`frontend-slides`), que solo llega al contenedor con `agents_update.sh`.

### Added
- **ffmpeg en la imagen**: `ffmpeg` 7.1.5 + `ffprobe` (apt, +171 MB instalados, 87 dependencias) para
  **procesar y editar video/audio** y para **armar videos a partir de capturas** —de programas o de
  sitios que se naveguen por web— generadas con otras herramientas del contenedor: cortar, concatenar,
  transcodificar, extraer audio, cambiar de formato y reescribir streams.
- **Grabación de páginas web**: se instala también el `ffmpeg` propio de Playwright (`playwright install
  ffmpeg`, 2,2 MB), el único que acepta `recordVideo` para capturar una página headless a `.webm`. **No**
  reemplaza al de apt: aquel es un build mínimo (`--disable-everything`: solo VP9/webm, sin audio ni
  `ffprobe`) y este es el CLI completo. Nunca se descarga un navegador de Playwright: el único es
  `/usr/bin/chromium`.

### Changed
- `src/Containerfile` (**refactor**): build **más rápido y más liviano**.
  - **Cache mounts** (`--mount=type=cache`) en `/var/cache/apt`, `/var/lib/apt/lists`, `/root/.npm` y
    `/root/.cache/pip`. `--renew`/`--update` usan `--no-cache`, pero el cache mount persiste: dejan de
    re-descargarse ~520 MB de `.deb` por rebuild. Por eso ya no se hace `apt-get clean` ni se borra
    `/var/lib/apt/lists`.
  - Se elimina `playwright install --with-deps`: disparaba un **tercer** ciclo de apt y sumaba ~94 MB
    (servidor X de xvfb + fuentes `unifont`/`freefont`). Se declaran explícitamente `fonts-noto-color-emoji`,
    `fonts-wqy-zenhei` y `fonts-ipafont-gothic` (~39 MB) para que emoji y etiquetas CJK de los diagramas
    Mermaid sigan renderizando. El único Chromium es `/usr/bin/chromium` (`PUPPETEER_EXECUTABLE_PATH` +
    `PLAYWRIGHT_CHROMIUM_EXECUTABLE`): −128 MB de navegador duplicado.
  - Los `COPY` de `tools/` (`md2pdf.py`, `css-styles/`, `landlock_rosh`) se mueven al final: antes
    estaban por delante de las capas caras (chromium ~300 MB, rustup ~850 MB), así que tocar un CSS
    invalidaba todo eso en el siguiente `--rebuild`.
  - Los cuatro pares `COPY` + `RUN chmod` del bloque final se fusionan en `COPY --chmod=755` (md2pdf,
    landlock_rosh, entrypoint, credentials): el build pasa de 26 a **23 instrucciones** (−3 commits de
    capa, caros con `fuse-overlayfs`). El smoke test de `landlock_rosh` se mantiene como `RUN` porque
    verifica, no cambia permisos. Requiere Podman ≥ 4.4 (buildah 1.31).
  - `npm install` con `--no-audit --no-fund` y sin los `rm -rf` de caché, que ahora viven fuera de la capa.
- `QUICKSTART.md` / `README.md`: Podman **≥ 4.0** como prerrequisito (cache mounts).

### Fixed
- `src/Containerfile`: la instalación de **ruff** rompía el build con
  `tar: ruff-x86_64-unknown-linux-gnu: Cannot change mode to rwxr-xr-x: Operation not permitted`.
  El tarball de GitHub Releases viene empaquetado por el runner de CI con owner `1001:117`
  (`runner/docker`) y `tar`, al correr como root, intentaba imponer ese owner/mode sobre el storage
  del build. Ahora se extrae con `--no-same-owner --no-same-permissions` en un directorio propio
  (`/tmp/ruff-install`) y se copia con `install -m 755`, que deja el binario como `root:root` (el
  `mv` anterior preservaba el uid 1001). Se agrega `ruff --version` como smoke test del paso y
  `curl --retry 3` para los cortes de stream de GitHub. Se sigue usando `latest`: no hay pinning.
- `src/skills/frontend-slides`: el export a PDF estaba **roto en el contenedor**. `playwright install
  --only-shell chromium` bajaba 126 MB a `/root/.cache/ms-playwright` y la capa de rustup los borraba
  después con `rm -rf /root/.cache`, así que `chromium.launch()` fallaba con *Executable doesn't exist*.
  Ahora la imagen usa un solo Chromium (el del sistema) y `export-slides.mjs` lo toma de
  `PLAYWRIGHT_CHROMIUM_EXECUTABLE`. `deps.sh doctor` reporta el origen (`sistema:` o `playwright:`)
  y `has_chromium` acepta el binario del sistema.

## [4.6.0] — 2026-11-10

### Added
- `agents_update.sh`: **backup automático** de cada archivo que un deploy reemplaza. Los `UPDATE` y
  `REPLACE` copian el original a `~/.config/opencode/backups/agents-<timestamp>/` antes del `cp -f`
  (los `INSTALL` no respaldan: no hay nada que perder). Si el backup falla, el deploy aborta antes de
  pisar. Antes solo se respaldaba el `REMOVE` de owners anidados, y el `cp -f` borraba sin copia.

### Changed
- Agentes `investigador` (11→12) y sus 6 subagentes (ES/EN/DE/FR/ZH 2→3, RU 1→2): sección de
  **estilo del informe** en el idioma de cada prompt — lenguaje llano, nada de lectura previa
  presupuesta (la primera mención lleva la formulación completa y el acrónimo, sigla o nombre
  técnico **entre paréntesis**; después se usa la forma corta), explicación breve de los conceptos
  complejos con recomendación de una fuente ya citada, y lista de términos dudosos que el primario
  pliega en un `## Glosario` opcional. El primario cierra el informe ofreciendo explicar lo que
  quedó oscuro. Sin cambios de permisos ni de `mode`.
- `arquitecto` 8→9: `permission.task` pasa de `deny` + allow `investigador*`/`explore` a `"*": allow`.
  Puede delegar en cualquier agente definido (`sysadmin`, `developer`, `cyberseguridad`, …) **solo por
  pedido u OK explícito del driver**; `explore` e `investigador/investigador-*` siguen siendo
  rutinarios. El límite pasa a ser de prompt (`## Delegación`), con anti-auto-spawn incluido
  (`arquitecto` no se invoca a sí mismo: con `mode: all` sería una puerta a bucles). Decisión del driver
  del 2026-11-10, aplicada en dirección instalada→repo.
- `agents_update.sh`: las copias instaladas con **versión superior** a la del repo ya no se informan como
  "skipped" sino como **`[ALTERED]`** — señal de que el archivo desplegado se editó fuera del repo. El
  aviso incluye qué pasa si el repo alcanza esa versión: el deploy la reemplaza y las modificaciones
  locales dejan de estar activas (con copia en el backup).

### Fixed
- `agents_update.sh` **ocultaba el drift**: el bloque que imprime las copias más nuevas que el repo estaba
  después del corte `changed == 0`, así que con el drift como único cambio el script decía "All custom
  agents, skills, styles and commands are up to date". Ahora el aviso se emite antes del corte y el cierre
  pasa a "Nothing to apply, but N deployed file(s) are AHEAD of the repo".
- `agents_update.sh`: **`agent_version` devolvía 0** con frontmatter no canónico (`version: 9 # nota`,
  `version: 8.1`, `version:` ausente). Ese 0 se comparaba como versión real: una copia instalada mal
  formada hacía que el repo la pisara como `UPDATE` sin el aviso `[ALTERED]`, y el caso inverso producía
  un falso `[ALTERED]`. Ahora devuelve vacío y el stage 1 aborta con
  `[ERROR] Cannot read an integer 'version:'` en el lado que corresponda.

### Notes
- **Actualizar los agentes**: alcanza con `./src/agents_update.sh`. Es lo único necesario — no hace falta
  reconstruir la imagen ni tocar `~/.config/opencode/` a mano. El script compara `version:` + `sha256`,
  aplica los stages de agents, skills, styles y commands, respalda lo que reemplaza y avisa de las copias
  alteradas fuera del repo (`[ALTERED]`). Un cambio en el prompt de un agente se ve al abrir **una sesión
  nueva** (las abiertas conservan el prompt con el que nacieron); skills, comandos y estilos se releen solos.
- `AGENTS.md`, el registro `src/agents/README.md` y el README de `arquitecto` documentan la delegación
  abierta y el nuevo comportamiento del script; `TODO.md` cierra los dos defectos (filas 14 y 15).

## [4.5.0] — 2026-11-06

### Changed
- `/hand-off`: el comando ya no crea una sesión nueva por la API. Ahora delega con la tool
  `subagent` (`agent`/`description`/`prompt`), que abre una sesión hija. Desaparecen el
  `POST /api/session`, el link de la sesión, el
  `sha256` de la hoja y los archivos de estado `.state`/`.agent`: el flujo entre subcomandos
  es la ruta que imprime `slug`.
- `/hand-off`: si el subagente devuelve una pregunta en vez del informe, la sesión
  invocadora la pasa al humano con `question` y continúa el **mismo** hijo con su
  `sessionID`. La hoja queda en `.opencode/handoffs/` para el barrido del próximo
  `/hand-off`.
- `handoff.py`: queda en `prep`, `slug`, `seal --brief <ruta>`, `scan`, `delete`,
  `discard` (de 854 a 414 líneas, sin código muerto). `seal` ya no calcula hash: escanea
  secretos en la hoja indicada y el humano redacta.
- `/hand-off`: el modo de disparo se elige con una `question`. **Primer plano** bloquea la sesión hasta
  que el subagente termina y devuelve el informe ahí; **segundo plano** (`background: true`) la deja
  libre y el resultado llega como mensaje al terminar. En segundo plano el subagente no puede consultar
  al padre: si necesita una decisión o un permiso puede quedar esperando, y el comando imprime ese
  riesgo antes de lanzar.
- `handoff-brief`: la skill sube a `version: 4` (subcomandos, disparo por `subagent` con modo
  primer plano / segundo plano y `background`, aviso obligatorio en segundo plano, round-trip y
  prompt del subagente).
- Agentes `investigador` (11), `arquitecto` (8), `sysadmin` (5) y `agent-builder` (7):
  `mode: primary` → `mode: all`, para poder invocarlos también como subagentes. Sin
  cambios de permisos.

### Fixed
- Se van tres defectos del enfoque por sesión, porque su causa dejó de existir: las
  sesiones zombis por un `question` que quedaba esperando en background, los subagentes
  sin `bash` detenidos por la verificación de hash y el `SID` que no se convertía en botón
  en el reporte.

### Notes
- **Actualización**: alcanza con `./src/agents_update.sh`. No hace falta reiniciar el contenedor ni
  reconstruir la imagen: `~/.config/opencode/` está montado y el server relee agentes, comandos y skills
  solo, en segundos (verificado: un cambio en `commands/hand-off.md` aparece en el catálogo sin hacer nada).
  La única excepción es el prompt de un **agente**: una sesión ya abierta conserva el que tenía al nacer, así
  que para ver cambios en un `.md` de agente abrí una sesión nueva. `opencode reload` existe como forzador
  (la web no expone un comando `/reload`), pero no hace falta en el flujo normal.
- Los agentes `investigador`, `arquitecto`, `sysadmin` y `agent-builder` cambian de `mode`: si tenés una
  sesión vieja abierta con uno de ellos, seguí usándola o abrí otra; no hay migración de datos.

## [4.4.0] — 2026-11-06

### Added
- **Comando `/hand-off`** y skill **`handoff-brief`** (oculta del catálogo y
  cableada al comando): convierte una tarea en una hoja de ruta autocontenida en
  `<proyecto>/.opencode/handoffs/<fecha>-<slug>.md` y la dispara a un agente en
  una **sesión nueva**, asíncrona (`POST /api/session` + `/prompt`), sin
  bloquear la sesión que la invoca.
  - Dos modos: directo (`/hand-off <agente> <tarea>`, sólo para texto propio) y
    seguro (sin argumentos: pregunta agente y tarea, obligatorio para texto de
    terceros, porque opencode expande los argumentos antes de los bloques de
    shell del comando).
  - Retención acotada: barrido de 14 días / 10 archivos con confirmación en cada
    invocación, y la sesión nueva pregunta si borra la hoja al terminar.
  - Integridad: `sha256` de la hoja verificado por la sesión receptora antes de
    leerla, scan de secretos antes de disparar, y datos del humano siempre por
    archivo (`.agent`/`.task`), nunca por argv.
- `src/skills/handoff-brief/scripts/handoff.py`: toda la lógica en un script de
  stdlib pura (Python 3.8+, sin dependencias), con 8 subcomandos (`prep`, `scan`,
  `delete`, `discard`, `slug`, `seal`, `agent`, `fire`).
- `scripts/tests/test_handoff.py`: 37 casos con `unittest`, sin red (stub de
  `opencode` por `PATH`).

### Changed
- `agents_update.sh`: el stage de skills ya no despliega `tests/`,
  `__pycache__/` ni `*.pyc`. Son artefactos de desarrollo, no parte de la skill
  en runtime: el árbol instalado queda sólo con lo que se usa.
- `check-skill-wiring.sh`: una skill **standalone oculta** ahora se valida
  contra `src/commands/*.md` y `src/agents/*/*.md`. Antes emitía un `[WARN]` y
  asumía que las standalone siempre se anuncian; ahora falla si nadie la nombra.
- `AGENTS.md`: sección del comando `/hand-off` (qué hace, piezas, modos,
  retención, origen, tests).

### Notes
- **Actualización**: alcanza con `./src/agents_update.sh`. **No hace falta
  regenerar el contenedor**, salvo que quieras actualizar las versiones de todos
  los componentes de opencode-container. Regenerar el contenedor **no**
  reemplaza ni evita `agents_update.sh`: agentes, skills y comandos se despliegan
  aparte, desde el repo a `~/.config/opencode/`, que está montado dentro del
  contenedor.
- Herramienta propia (Calisto con Bj/`agent-builder`), sin repos externos ni
  código de terceros. Gate de `cyberseguridad`: aprobado con notas tras 5
  pasadas; reportes en `documents/reports/cyberseguridad-2026-11-06-*.md`.
- Riesgo residual de plataforma documentado: en opencode v2.1.4 y v2.2.5 los
  argumentos de un comando se expanden **antes** de ejecutar los bloques de shell
  del comando, así que un argumento puede ejecutar shell sin aprobación. El modo
  seguro de `/hand-off` no recibe argumentos y evita el vector; el cuerpo del
  comando y la skill no contienen bloques de shell. Cuerpo del reporte upstream
  en `documents/reports/upstream-opencode-command-arg-injection.md`.

### Documentation
- `README.md`: sección "Delegar trabajo a otra sesión: `/hand-off`" con los dos
  modos, qué hace el comando y cómo se retienen las hojas.

## [4.3.0] — 2026-10-30

### Added
- **Skills ocultas del catálogo por agente**: el catálogo se inyectaba completo
  en cada request a todos los agentes (21 skills, ~2.700 tokens fijos). Ahora 19
  llevan `metadata.opencode/autoinvoke: false` en su `SKILL.md`: dejan de
  anunciarse, siguen registradas y cada agente las carga **por ID** cuando su
  prompt se lo indica. Quedan anunciadas `frontend-slides` y `mermaid2png`, más
  las builtin `opencode` y `report`. Medido en opencode v2.1.4: **−2.442 tokens
  por request (−12,1 %)** en los cinco agentes.
- `src/check-skill-wiring.sh`: verifica que toda skill oculta esté nombrada con
  su ID exacto en el `.md` de su agente dueño y que `name:` coincida con la
  carpeta. Integrado en `agents_update.sh` como validación previa al stage de
  skills (aborta antes de copiar; se saltea con `--no-skills`).
- Skill **`calisto-debian-server-baseline`** (add-on de Calisto, registrada en
  `src/agents/sysadmin/ADDONS.md`): baseline de servidor Debian/Ubuntu con gate
  de confirmación, respaldo verificable con rollback, sumisión al pipeline
  `first-connection` y detección del modo de privilegio (root directo, `sudo -n`
  o root SSH fallback del ruleset).

### Changed
- Los `.md` de `agent-builder`, `developer`, `arquitecto` y `sysadmin` indican
  explícitamente cargar sus skills por ID (versiones 6, 9, 7 y 4).
- `upgrade-*.md` de los cuatro agentes y el checklist de `agent-architecture`:
  toda skill nueva o re-vendorizada nace oculta, cableada en el `.md` del dueño y
  validada con el script.
- README: sección "Catálogo vs. carga de skills" con el mecanismo y el reparto
  (19 ocultas / 2 anunciadas propias).

### Fixed
- YAML inválido en `python-style` y `heinzel-rules` (la `description` tenía `: `
  sin comillas y `yaml.safe_load` fallaba).
- `sysadmin.md` decía "five workflow skills" con siete entradas.

## [4.2.1] — 2026-10-27

### Added
- **`QUICKSTART.md`**: guía de arranque rápido en 11 pasos (prerrequisitos,
  instalación, construcción de la imagen, despliegue de agentes, credenciales,
  primer arranque, los dos ajustes únicos de la web, comandos del día a día,
  problemas típicos y siguientes pasos), pensada para dejar el proyecto
  funcionando sin leer el README completo. Enlaza la presentación y la sección
  "Problemas conocidos" del README.
- `QUICKSTART.md`: nota de `OPENCODE_GUI` para fijar el entorno de trabajo
  por defecto (web o TUI) y hacer la variable permanente en bash, zsh y fish.
- README: sección "Instalación rápida — si estás apurado" antes de "Qué te
  llevás", con enlace al QUICKSTART.

## [4.2.0] — 2026-10-26

### Added
- **Credenciales compartidas entre proyectos**: opencode v2 guarda las
  credenciales en SQLite (`credential` de `opencode.db`) y esa base es por
  proyecto, así que el `auth.json` heredado sólo se importa una vez y se ignora
  después. El launcher ahora trata `~/.config/opencode/share/auth.json` como
  fuente canónica y la siembra en cada proyecto al arrancar.
- `opencode-credentials` (`src/credentials.py`, dentro de la imagen): reconcilia
  la base del proyecto con el canónico usando el CLI oficial
  (`opencode auth import|logout --standalone`). Precedencia: un login hecho a
  mano en el proyecto gana (override), la key canónica presente es no-op, una
  credencial sembrada con key vieja se reemplaza y lo que falta se siembra.
  Sólo se comparten API keys: las OAuth no (sus refresh tokens rotan).
- `opencode.sh --credentials-set <integración>`: alta/rotación con prompt oculto
  (`read -rs`), escritura atómica y permisos `0600`; la key no pasa por `argv`.
- `opencode.sh --credentials-export <proyecto>`: promueve las API keys de un
  proyecto (login hecho en la TUI) al `auth.json` canónico.
- `opencode.sh --sync-credentials <patrón>`: aplica el canónico en un contenedor
  en ejecución (`podman exec` + `opencode reload`).
- `opencode.sh <proyecto> --no-credentials-seed`: desactiva la siembra en ese
  proyecto (`OPENCODE_CREDENTIALS_SEED=0`).
- Banner de una línea al arrancar cuando el canónico tiene integraciones
  gestionadas, recordando que un login en la TUI es override local y se
  promueve con `--credentials-export`.

### Changed
- `resolve_project_paths()` extraído del flujo principal para reutilizar la
  resolución de proyecto en `--credentials-export` (misma trepada a `.git`,
  mismo `-config`).
- Nuevo mundo CREDENCIALES en el parser, excluyente con IMAGEN/GESTIÓN/EJECUCIÓN
  (documentado en `--help`, `PARAMETERS.md` y `AGENTS.md`).
- `entrypoint.sh` reconcilia credenciales antes de lanzar opencode y deja pasar
  los fallos con aviso (nunca bloquea el arranque).

### Note
- La imagen cambió: hay que reconstruirla (`--rebuild` o `--renew`) para que
  `opencode-credentials` exista dentro del contenedor.

## [4.1.1] — 2026-10-24

### Added
- **Licenciamiento del proyecto**: `LICENSE` raíz con **MPL-2.0** para el código
  y los artefactos funcionales propios; documentación propia bajo **CC BY-SA
  4.0**; componentes de terceros conservan su licencia original (OpenCode,
  heinzel, frontend-slides y cybersecurity-skills en MIT; ddd-crew en CC BY-SA
  4.0). Se suman `LICENSES/` (textos íntegros), `THIRD-PARTY.md` (atribución y
  mapa de licencias) y `REUSE.toml` (rutas que no admiten header).
- Headers SPDX en 173 archivos: código, agentes, skills, comandos y
  documentación. Los agentes y skills llevan el comentario dentro del
  frontmatter YAML para no romper el parser de opencode.
- README: sección "Licencia, agradecimientos y uso", con la aclaración de que
  usar el launcher no cambia la licencia de los proyectos del usuario.
- AGENTS.md: regla de headers SPDX obligatorios y qué hacer al vendorizar.

### Changed
- `src/tools/landlock/crate/Cargo.toml`: `license = "MPL-2.0"`.
- `PROVENANCE.md` de landlock, arquitecto y frontend-slides, README de
  cyberseguridad y `ADDONS.md` de sysadmin: reemplazan "sin licencia" por la
  política vigente.
- **Sin cambios de comportamiento**: build, launcher y rutas de la imagen
  quedan exactamente como estaban. Los avisos de licencia viajan con el repo y
  el tarball de fuentes, no dentro de la imagen.

## [4.1.0] — 2026-10-23

### Added
- **`landlock_rosh` 1.9.0** (`src/tools/landlock_rosh`): binario estático x86_64
  que ejecuta una shell/comando en un filesystem read-only por Landlock +
  seccomp (también restringe root). Flags nuevas: `-c` (contrato de login shell),
  `--log-only` (escritura con auditoría, sin sandbox) y `--print-ssh-line`
  (genera la línea de `authorized_keys` en modo `ro`/`log`).
- **Skill `calisto-landlock`** (add-on de Calisto, no heinzel): procedimiento
  operativo para ofrecer, desplegar, verificar y respetar el acceso read-only.
  Incluye `scripts/pin-key.sh` (backup, reemplazo atómico de la línea de la
  clave y verificación).
- **`src/agents/sysadmin/ADDONS.md`**: manifiesto de add-ons custom; el
  re-vendorizado de heinzel los preserva (Paso 3b de `upgrade-heinzel.md`).
- **Imagen**: `Containerfile` copia `landlock_rosh` a `/usr/local/bin` como
  payload para servidores remotos (no se ejecuta localmente). En opencode
  tradicional se instala con `agents_update.sh --install-tools`.
- **Documentación del tool**: `src/tools/landlock/README.md`,
  `DEVELOPMENT.md`, `PROVENANCE.md`, `SHA256SUMS` y suite de regresión 1.9.0.

### Changed
- **`sysadmin` v3**: agrega la sección opcional de read-only por kernel y la
  regla de no bypass; el flujo normal no cambia y landlock no se auto-despliega.
- **`agent-builder`**: guardrail para no borrar/sobrescribir add-ons `calisto-*`
  declarados en `ADDONS.md`; checklist de vendorizado actualizado.
- **Docs**: README/AGENTS con la tabla de tools, el modo contenedor vs legacy y
  los límites reales (filesystem; daemons, señales, netlink y `utime` quedan
  fuera). `upgrade-heinzel.md` preserva el add-on y lo incluye en el gate de
  `cyberseguridad`.

### Removed
- Prototipo Python (`landlock_rosh.py`), `verify_root.py`, artefactos de
  análisis de sesiones y snapshots `.tar.gz` históricos. La fuente de verdad es
  el crate Rust en `src/tools/landlock/crate/`.
- `reports/` consolidado en `documents/reports/` (contenido idéntico): el
  histórico de auditorías queda en un solo lugar.

### Notes
- **Upgrade**: correr `src/agents_update.sh` para desplegar `sysadmin` v3 y la
  skill `calisto-landlock`. Sin ese paso la skill no se anuncia y el agente
  sigue en v2: el add-on vive en `src/agents/sysadmin/skills/` y no se
  auto-instala.
- **Imagen**: reconstruir (`--rebuild`) para hornear `landlock_rosh` en
  `/usr/local/bin`. Es payload para servidores remotos; no se ejecuta como
  sandbox local.
- **Release**: `opencode-container-src-v4.1.0.tar.gz` (raíz `src/`, sin
  `.opencode/`), SHA256 `74b3b67a03dcf40ec724cc9694e4c2307066884c364890a87ed728396c729970`.

## [4.0.0] — 2026-10-23

### Added
- **Test post-migración** (`documents/reports/test-post-migracion-agentes.md` +
  `test-agentes-hibrido.py`): verifica el registro de agentes/subagentes, skills y
  comandos sin invocar modelos; incluye `GET /api/agent/{id}` por elemento, rutas
  desplegadas, ausencia de IDs viejos y el Planning Gate del `agent-builder`.
- **Planning Gate** en `agent-builder`: `02-plan.md` obligatorio con headings, layout de
  IDs y sin `PENDIENTE`/`TBD` antes de lanzar `developer`; template incluido.

### Changed
- **BREAKING — layout de agentes**: los dueños se despliegan planos
  (`agents/<agente>.md`) y los subagentes conservan su carpeta
  (`agents/<agente>/<subagente>.md`). OpenCode V2 deriva el ID de la ruta; los IDs
  `arquitecto/arquitecto`, `developer/developer`, etc. pasan a `arquitecto`, `developer`.
- **`agents_update.sh`**: layout por rol de archivo (no por `mode:`), colisiones por ID
  final, migración de dueños anidados con backup y `REMOVE` visible en `--check`.
- **`developer` y `cyberseguridad`**: `mode: all` para usarse como primarios y como
  subagentes del `agent-builder`.
- **Prompts y docs**: `investigador` y `arquitecto` usan IDs completos de subagentes;
  `agent-builder` reemplaza `task: plan` por planning propio + gate; READMEs,
  `AGENTS.md`, `agent-architecture` y `/arquitecto` actualizados.
- **Versiones de agentes**: `investigador` 10, `arquitecto` 6, `agent-builder` 4,
  `developer` 8, `cyberseguridad` 5.

### Removed
- `task: plan` en `agent-builder` (el built-in `plan` es `mode: primary`; V2 no permite
  lanzarlo como subagente).

### Notes
- Las sesiones viejas que guardaron IDs anteriores (`arquitecto/arquitecto`, etc.)
  reciben `AgentNotFoundError` al reanudarse; hay que elegir el agente nuevo. El
  historial de la sesión no se pierde.

## [3.9.0] — 2026-10-22

### Added
- **`--pair <patrón>`**: genera links de pairing para un contenedor web usando el mismo
  resolvedor que `--kill` (nombre exacto, `tuiN`, `N`). Lee el password del contenedor
  (`podman inspect`, fallback a `podman logs`) y emite un code por origen
  (`127.0.0.1` + IPs de LAN). No acepta `--port` ni `--password`; rechaza contenedores TUI.
- **Link de acceso automático en modo web**: tras `podman run -d`, el launcher espera a
  que `/api/info` responda y pide un code a `POST /api/pair`; imprime el link
  `http://127.0.0.1:<puerto>/auth/connect/<code>` (un solo uso, 5 minutos, cookie de 30 días).
- **Password web por defecto**: `--password` > env `OPENCODE_SERVER_PASSWORD` > `opencode`;
  el launcher siempre pasa el password al contenedor y lo imprime en el arranque web.
- **Fallbacks de herramientas**: `curl` → `wget` (solo si soporta POST/auth) para la API;
  `jq` → `sed` → regex de bash para parsear el code. Si no hay herramienta HTTP, avisa y
  continúa sin link.

### Changed
- **Modo web detached**: `podman run -d` en lugar de `-it`; el contenedor sobrevive al
  cierre de la terminal y se detiene con `--kill <puerto>`. La TUI sigue en foreground.
- **Resolvedor compartido**: la lógica de `--kill` se extrajo a `resolve_opencode_container`
  y la reutiliza `--pair` (mismos patrones y mismas reglas de 0/1/varios matches).
- **Docs**: help, README, PARAMETERS y AGENTS actualizados con `--pair`, el password por
  defecto y el modo detached.
- **Salida**: línea en blanco después del link de acceso (arranque y `--pair`).

### Fixed
- **`--pair` sin ruido de IPs virtuales**: `detect_lan_ips` excluye interfaces de
  Podman/Docker (`podman`, `docker`, `veth`, `br-`, `cni`), VPN (`tun`, `tap`, `wg`,
  `tailscale`, `utun`), VMs (`virbr`, `vmnet`, `vboxnet`) y otras virtuales; solo
  imprime LAN real.
- **Nombre de contenedor en uso**: chequeo previo a `podman run` con mensaje accionable
  (`$0 --kill <puerto>` si está corriendo, `podman rm -f <nombre>` si quedó detenido)
  en lugar del error crudo de Podman.

## [3.8.1] — 2026-10-21

### Fixed
- **Modo web con opencode v2**: el launcher pasaba `opencode web` (subcomando eliminado en v2);
  ahora usa `serve` con los mismos `--port`/`--hostname`. Mismo cambio en el `CMD` del Containerfile.
  Sin esto la web no arrancaba (`Unrecognized flag: --port`).
- **Auth web documentada según v2**: el servidor exige password siempre; si no se pasa
  `--password` ni `OPENCODE_SERVER_PASSWORD`, v2 genera una aleatoria y la imprime al arrancar
  (`server password ...`). El acceso es con usuario `opencode`.

### Removed
- **`--user`**: opencode v2 fija el usuario de auth web en `opencode` (`ServerAuthConfig`) e ignora
  `OPENCODE_SERVER_USERNAME`. El flag ya no tenía efecto; ahora `error_exit` con explicación y el
  launcher deja de exportar `OPENCODE_SERVER_USERNAME` al contenedor. Docs (README, PARAMETERS,
  AGENTS) actualizadas.

## [3.8.0] — 2026-10-20

### Added
- **`--web`**: fuerza explícitamente el servidor web (modo por defecto). Mutuamente excluyente
  con `--tui`/`--no-web` (`error_exit` si se combinan).
- **Selección de interfaz vía `OPENCODE_GUI`**: la env del host (`tui`/`web`) define el modo cuando
  no se pasan flags. Precedencia: flags `--tui`/`--no-web` o `--web` > `OPENCODE_GUI` (valor inválido
  → aviso y default web) > default web. La variable se lee en el host; al contenedor llega ya
  resuelta como `OPENCODE_MODE`.
- **`--extra-ports <n>,<n>,...`**: publica puertos extra del contenedor en el host (`-p n:n`), además
  del puerto web, en **ambos modos** (web y TUI) — útil para alcanzar servicios que corran dentro del
  contenedor (p. ej. un dev server). Comas sin espacios, mínimo 1, cada puerto 1-65535, sin duplicados
  ni choque con `--port` (en modo web; mapeo `-p` duplicado). Con `--network-host` se omite con aviso.

### Changed
- **Containerfile**: el instalador de opencode pasa de `https://opencode.ai/install` a
  `https://opencode.ai/v2/install` (nuevo mecanismo oficial de instalación; descarga desde
  registry.npmjs.org, misma ubicación de binario `/root/.opencode/bin/opencode`). Requiere
  reconstruir la imagen (`--rebuild`/`--renew`).
- **Presentación HTML** (`opencode-container.html` + copia readonly): badges a v3.8.0, árbol de
  ejecución con `--tui | --web`, `--extra-ports` y precedencia `OPENCODE_GUI`; comandos de uso
  actualizados; corregido `--build` → `--rebuild` en la tarjeta de instalación; preview PNG
  regenerado.
- `opencode.sh` bumpeado a 3.8.0.

## [3.7.1] — 2026-10-02

### Fixed
- **`entrypoint.sh` — symlink de `/root/.ssh`**: se elimina `/root/.ssh` antes de recrearlo
  como symlink a `/root/.identity/ssh`. Si la imagen ya traía `/root/.ssh` como directorio,
  `ln -sf` generaba un symlink anidado (`/root/.ssh/ssh`) y git/ssh no encontraban ni las
  claves ni el `known_hosts` de la identidad del agente (el `git push` por defecto dentro
  del contenedor fallaba con "Host key verification failed" / "Permission denied").
  Requiere reconstruir la imagen.
- `opencode.sh` bumpeado a 3.7.1.

## [3.7.0] — 2026-10-02

### Added
- **Skill global `frontend-slides`** (vendorizada de `zarazhangrui/frontend-slides`, MIT): genera
  decks HTML autocontenidos con descubrimiento visual de estilo y 34 bold templates; conversión de
  PPT (`python-pptx`) y export a PDF (`playwright` + Chromium) **locales**. Vercel **excluido**
  (nada de publicación en terceros).
- **Nuevo stage `src/skills/`** en `agents_update.sh`: despliega skills globales sin agente portador
  (además de `src/agents/*/skills/`) y detecta nombres duplicados entre ambas fuentes.
- **`mermaid2png`**: vendorizada en `src/skills/mermaid2png/` (antes huérfana en la config global) y
  con dependencias horneadas en la imagen.
- **Comando `/frontend-slides`**.

### Changed
- **Imagen**: dependencias horneadas y offline (python-pptx, playwright + Chromium headless shell,
  `@mermaid-js/mermaid-cli` + Chromium del sistema, librerías de Chrome) con limpieza de cachés de
  instalación (apt/npm/pip).
- `opencode.sh` bumpeado a 3.7.0.

### Security
- Gate de ciberseguridad (auditoría + re-auditoría) sobre `frontend-slides`: servidor de export
  confinado al directorio de la presentación (anti path-traversal) y en loopback; sin carga de
  módulos/intérpretes desde variables de entorno; cachés de instalación scoped a `.deps/`.
- `skills_stage` excluye `*/.deps/*` del deploy y `.gitignore` ignora `.deps/` (evita desplegar
  o commitear venv/node_modules/browsers de una instalación local).

## [3.5.0] — 2026-09-29

### Changed
- **Agente `arquitecto` v4 → v5 — permisos por diseño + home de proyectos**:
  - `edit: allow` y `write: allow`: se eliminan los mapas de patrones del frontmatter; la restricción
    a `documents/arquitectura/**` + scratch `/tmp/opencode/arquitecto/**` pasa a sostenerse **por
    prompt** (guardrails 2 y 4). Motivo: el matcher de rutas de opencode resultó frágil entre
    versiones y profundidades de worktree; se prioriza que las herramientas dedicadas funcionen.
  - **Home del arquitecto**: `documents/arquitectura/` pasa a alojar `INDEX.md` (registro de
    proyectos: `| Proyecto | Descripción | Estado | Fecha de creación | Fecha de última
    actualización |`) y una subcarpeta `<proyecto>/` por proyecto gestionado; antes los artefactos
    vivían en la raíz del directorio. Los artefactos legacy se detectan y se relocalizan con
    consentimiento explícito.
  - `upgrade-arquitecto.md`: nueva sección **Invariantes (no re-vendorizar)** + paso de verificación,
    para que una actualización desde internet no revierta el modelo de permisos ni el layout.
- `opencode.sh` bumpeado a 3.5.0.

## [3.3.0] — 2026-09-26

### Changed
- **Agente `arquitecto` v3 → v4 — permisos usables** — se corrigen los bloqueos que obligaban
  a escribir artefactos por `bash` + heredoc (en vez de las herramientas dedicadas):
  - `bash: ask` → `bash: allow`: el `ask` pisaba el auto-approve del launcher y generaba
    prompts constantes (y auto-rechazo en ejecución no interactiva). Alineado con `developer`,
    `sysadmin`, `cyberseguridad` y `agent-builder`.
  - Scratch robusto: `edit`/`write` pasan de `../tmp/opencode/arquitecto/**` a
    `**/tmp/opencode/arquitecto/**`, que absorbe los `../` que agrega `path.relative` según la
    profundidad del worktree (`/workspace` → `../tmp/...`, `/workspace/sub` → `../../tmp/...`).
    Era el bug que denegaba el scratch en subdirectorios.
  - Bloque `write:` espejo de `edit` (defensivo: en opencode actual `edit` gobierna
    `edit`+`write`+`patch`).
  - Semántica del motor documentada en el prompt: last-match-wins, recurso relativo al worktree,
    `external_directory` absoluto y previo a `edit`.
  - Verificado T1–T6 en modo `developer` y en modo Arquitecto real (opencode 1.18.25): escritura
    en `documents/arquitectura/**` y scratch OK sin prompts; código y `.opencode/plans/**` siguen
    denegados.
- **`md2pdf` v1.3 → v1.4** — se unifica el tamaño del cuerpo de texto a **`10pt`** en los
  6 estilos (CSS embebido por defecto y `github`, `pandoc`, `newsprint`, `notion`, `paper`);
  antes el default usaba `10px` y los 5 estilos `11pt`. Sin cambios en tablas, tipografías
  ni otros estilos.
- `opencode.sh` bumpeado a 3.3.0.

## [3.1.0] — 2026-09-18

### Changed
- **Documentación general del proyecto** — revisión y actualización de la documentación
  (README y CHANGELOG) para reflejar el estado actual del launcher y de las herramientas.
- **Estilos de los informes para PDF y HTML** — las tablas pasan a **auto-layout**
  (`table-layout: auto`, columnas según el contenido), con `word-break` para tokens largos
  y sin ancho fijo para la primera columna. Aplicado al CSS embebido por defecto de `md2pdf`
  (v1.2 → v1.3) y a los 5 estilos (`github`, `pandoc`, `newsprint`, `notion`, `paper`), sin
  alterar tipografías ni el resto de cada tema.
- `opencode.sh` bumpeado a 3.1.0.

## [3.0.0] — 2026-09-08

### Changed
- **Normalización `documents/`** — carpetas de trabajo de agentes bajo `documents/`:
  `docs/arquitectura/`, `investigaciones/`, `memory/` y `reports/` se mueven a `documents/<área>/`.
  Corte limpio sin symlinks; histórico intacto.
- Agentes `arquitecto` v1→v2, `investigador` v8→v9, `sysadmin` v1→v2,
  `cyberseguridad` v3→v4, `agent-builder` v1→v2.
- `agents_update.sh`: modo exclusivo `--update-directory <dir>` (dir obligatorio; pasar el dir
  de proyecto a migrar) que mueve las carpetas legacy a `documents/`. Corte limpio, nunca sobrescribe.
- `opencode.sh` bumpeado a 3.0.0 (major por migración de layout + nuevas rutas de agentes).

### How to upgrade (manual steps)
1. Migrar cada proyecto (uno por contenedor/proyecto), primero en modo vista previa:
     ./src/agents_update.sh --update-directory /path/to/proyecto --check
     ./src/agents_update.sh --update-directory /path/to/proyecto   # confirmar Y/s
   Verificar con `ls /path/to/proyecto/documents/` (solo mueve dirs preexistentes; nunca sobrescribe).
   `<dir>` es obligatorio y debe existir. Repetir por proyecto (incluido este repo con su ruta si se desea).
2. Desplegar agentes (una vez, desde este repo):
     ./src/agents_update.sh --check
     ./src/agents_update.sh   # confirmar Y/s (sobrescribe tus copias en ~/.config/opencode)
   Verificar con `./src/agents_update.sh --check` → "up to date. Nothing to do."

## [2.9.0] — 2026-09-08

### Added
- **Agente global `arquitecto` v1** — arquitecto de software para las fases previas al desarrollo: elicitación socrática de ideas/requisitos → arquitectura documentada (canvas por módulo con contratos command/query/event, diagramas C4 en Mermaid, ADRs MADR, riesgos, auto-revisión de 8 puntos) → plan maestro con subproyectos/hitos/MoSCoW → packs de tareas por hito en `<proyecto>/docs/arquitectura/**`. No escribe código: handoff a `plan` (built-in) y `developer`. Flujo por fases con gate de aprobación humana por artefacto.
- **Skills `module-decomposition`, `architecture-decisions`, `delivery-planning`** — procedimientos on-demand del agente, construidos sobre guías verificadas en 6 idiomas (arc42, C4, Nygard/MADR, ddd-crew, superpowers, OpenSpec, WBS/DoD/MoSCoW).
- **`src/agents/arquitecto/PROVENANCE.md`** — ledger de procedencia pieza→fuente→licencia→justificación→vía de re-verificación (patrón extendido del registro upstream de sysadmin/cyberseguridad; primer agente con él). `upgrade-arquitecto.md` formaliza el re-check de piezas.
- **Comando `/arquitecto <idea>`** (`src/commands/arquitecto.md`, frontmatter `agent: arquitecto`).
- **Permisos determinísticos como primera línea**: `edit` restringido a `docs/arquitectura/**` + scratch `/tmp/opencode/arquitecto/**`, `task` allowlist (`"*": deny` primero — last-match-wins), `webfetch/websearch: deny`, `external_directory: ask` pineado, `read` con patrones `.env`. Descubrimiento documentado: los mapas de permission se evalúan findLast; el catch-all debe ir primero.
- **Auditoría del agente**: 3 pasadas `cyberseguridad` (2H/3M/5L → fixes → STOP por orden de claves → APPROVED-WITH-NOTES). Riesgo residual R1 documentado: la delegación hereda el env auto-allow del launcher (cierre total exigiría `--no-auto` o endurecer `explore`/`investigador-*`, agentes ajenos).

### Changed
- `opencode.sh` bumpeado a 2.9.0.
- `src/agents/README.md` — fila `arquitecto` en el registro; `AGENTS.md` — subsección del agente.
- `TODO.md #2` — marcado Resuelto (2026-09-04: causa raíz = contenedores no reiniciados + hint de red envuelto por AI SDK, no persistencia de models.json).

## [2.7.0-pre1] — 2026-08-30

### Added
- **Agentes/skills/commands locales** — `agent-builder` ahora pregunta **¿global o local?** (default global). Local se desarrolla igual en `/tmp` efímero y, tras aprobación, se copia a `<proyecto>/.opencode/agents/` (`/workspace/.opencode/agents/` en contenedor) + `<proyecto>/.opencode/skills/` y `<proyecto>/.opencode/commands/` si el agente los tiene. Versionado en el git del proyecto, sin pasar por `agents_update.sh`.
- Excepciones `.gitignore` para versionar locales: `!/.opencode/agents/`, `!/.opencode/agents/**`, `!/.opencode/skills/`, `!/.opencode/skills/**`, `!/.opencode/commands/`, `!/.opencode/commands/**` + creación de `<proyecto>/.opencode/{agents,skills,commands}/.gitkeep` en `setup_project_gitignore()`.

### Changed
- `opencode.sh` bumpeado a 2.7.0-pre1.
- `agent-builder` + skill `agent-architecture`: documentado flujo global vs local y checklist de deploy.

## [2.6.2-pre1] — 2026-08-30

### Changed
- `opencode.sh` bumpeado a 2.6.2-pre1.
- **Agente `developer`**: baseline de configuración ruff — `line-length = 120` (estándar del driver) e `ignore = ["I001", "RUF023"]` (isort reordena imports/normaliza líneas en blanco y `RUF023` ordena `__slots__` alfabéticamente; ambos puramente cosméticos y en conflicto con el `__slots__` semántico del driver). Aplica a `ruff.toml` y `pyproject.toml`.

## [2.6.0-pre1] — 2026-08-30

### Added
- **Agente `agent-builder` v1** — meta-orquestador creador de agentes: workflow `investigador → plan → developer → cyberseguridad` con **Regla de oro de los labs (Anthropic/OpenAI/Google): lo determinístico va a hooks (PreToolUse), lo reutilizable a skills, lo universal y corto queda en el .md** (hook emulado como bloque `## Guardrails` en opencode), efímero en `/tmp` (investigador escribe solo en `/tmp`, cleanup obligatorio con `trap`), nunca auto-vendoriza (opción `A*` pre-vendorizada solo si `>500★ + MIT` para evaluación humana), múltiples ciclos `plan↔developer` y **gate final obligatorio** con `cyberseguridad` (STOP en medio/alto con decisión humana).
- **Skill `agent-architecture`** — router de la Regla de Oro, checklist de frontmatter/permisos mínimos, plantilla de prompt y mapa de reescrituras Claude Code→opencode.
- **Auditoría `agent-builder`** — `reports/cyberseguridad-2026-08-30-agent-builder.md` (H-01 MEDIO bloqueante mitigado → `## Guardrails` verbatim) y `reports/cyberseguridad-2026-08-30-agent-builder-reaudit.md` (APROBADO).

### Changed
- `opencode.sh` bumpeado a 2.6.0-pre1.
- `src/agents/README.md` — registro de `agent-builder` v1.
- `TODO.md #7` — marcado Resuelto (2026-08-30 20:45).

## [2.5.0] — 2026-08-30

### Added
- **ruff global en la imagen**: binario estático de `astral-sh/ruff` instalado en `/usr/local/bin/ruff` vía `Containerfile` (fuera de venvs, no enmascarado por mounts).
- **Agente `developer` v7**: reglas de calidad reforzadas — ruff como linter estándar (`ruff check` antes de entregar), fallback `uvx`/`pipx`, propiedades y atributos privados en `snake_case` (`self._internal_state`), y URL del binario precompilado documentada.

### Changed
- `opencode.sh` bumpeado a 2.5.0.
- `test/test/sorted_collection.py` modernizado: `collections.abc` + sintaxis `X | None` (PEP 604), limpieza de variable no usada.

## [2.4.0] — 2026-08-24

### Added
- **`--kill-all` / `--killall`** en `opencode.sh` (mundo GESTIÓN): detiene **todos** los contenedores opencode en ejecución (web y TUI) con un solo `podman stop` (paralelo interno de Podman). Pide confirmación interactiva (procede avisando si no hay TTY) y filtra por prefijo `^opencode` para no tocar contenedores ajenos. Verificación post-stop y reporte de errores por remanente.
- **Agente `cyberseguridad`**: auditor de ciberseguridad con arquitectura **router + catálogo a demanda** — 29 metodologías vendorizadas de [`briiirussell/cybersecurity-skills`](https://github.com/briiirussell/cybersecurity-skills) (MIT) organizadas en 7 familias, cargadas solo cuando se necesitan (`references/<skill>.md`, renombradas para no escanearse como skills). Generador `build-catalog.mjs` (regeneración idempotente del vendorizado) y procedimiento `upgrade-briiirussell.md`.
- **Permisos de solo auditoría** para `cyberseguridad`: `edit` limitado a `reports/**` y `tmp/**` (matcher relativo al workspace, por eso también `../tmp/**`); `bash`/`read`/`task` habilitados; `edit` denegado en el resto.
- **Agente `sysadmin` (vendorizado heinzel)**: agente de administración de sistemas con 5 skills (`heinzel-rules`, `heinzel-housekeeping`, `heinzel-security`, `heinzel-email`, `heinzel-fleet-audit`), memoria por proyecto y procedimiento `upgrade-heinzel.md` — primera vez versionado en git.
- **Tablas en `md2pdf`**: parches en los 5 estilos CSS (`table-layout: fixed`, `overflow-wrap`, `thead` repetido, `page-break-inside`, primera columna angosta) para que las tablas anchas entren en A4 sin desbordes; verificado en los 6 estilos.
- **`BITACORA.md`**: bitácora del proyecto (hitos por timestamp).
- **`reports/`**: directorio de salida de informes del agente `cyberseguridad`.

### Changed
- `opencode.sh` bumpeado a 2.4.0.

## [2.1.0] — 2026-08-21

### Added
- **Estilos CSS para `md2pdf`** (`--style <nombre>`): `github`, `pandoc`, `newsprint`, `notion`, `paper` — CSS autocontenidos con `text-align: justify` y `@page` A4 con numeración.
- Flag `--html` en `md2pdf`: genera un HTML autocontenido en lugar de PDF.
- Flag `--custom-css <archivo.css>`: CSS personalizado con prioridad sobre `--style`.
- Flag `--list-styles` en `md2pdf`: lista los estilos detectados con su origen (no requiere dependencias).
- Stage **styles** en `agents_update.sh`: despliega `src/tools/css-styles/` → `~/.config/opencode/css-styles/` (por defecto, incluido el README; flag `--no-styles` para omitir).
- Búsqueda de estilos por precedencia: config global del usuario (`~/.config/opencode/css-styles/`, montada en el contenedor) > imagen (`/usr/local/share/md2pdf/css-styles/`) > junto al script > relativo al `.md`. Fallback al CSS embebido.

### Changed
- `md2pdf` pasa de v1.0 a v1.2; CSS default embebido con `body` a 10px y justificado.
- `agents_update.sh`: `--install-tools` ahora copia solo la raíz de `src/tools/` (únicamente `md2pdf.py`, no los estilos).
- `src/css-styles/` se reubica a `src/tools/css-styles/` (los estilos son recursos de la tool).

## [2.0.0] — 2026-08-20

### Added
- **Permisos auto-aprobados**: flags `--auto`/`--no-auto` en `opencode.sh` (default: `--auto`). El contenedor ya no pide confirmación para carpetas/herramientas (sandbox aislado).
- **Comando `/md2pdf`**: conversor de informes Markdown → PDF estilizado (comando global + tool `md2pdf.py`).
- `md2pdf` con modos `--doctor` (instrucciones de instalación por OS) e `--install` (accesible en PATH); sin fallback silencioso si faltan dependencias.
- **`agents_update.sh` rediseñado**: gestiona stages (agentes, tools, commands); las tools ya no se instalan por defecto, solo con `--install-tools [dir]` (verifica PATH).
- Agente **investigador v8**: genera la versión PDF del informe con `/md2pdf` a pedido.

### Changed
- `opencode.sh` bumpeado a 2.0.0 (major por el cambio de comportamiento en permisos).
- La env `OPENCODE_PERMISSION` del host tiene prioridad sobre `--auto`/`--no-auto` para reglas personalizadas (JSON inline).
- `Containerfile`: instala `python3-markdown` y `weasyprint`; hornea `md2pdf` en `/usr/local/bin/md2pdf`.

### Documentation
- `AGENTS.md` y `PARAMETERS.md` actualizados (permisos, stages, matriz y BNF con `--auto`).

## [1.9.5] — 2026-08-19

### Fixed
- Se agrega `.opencode/` al `.gitignore` que se completa automáticamente en los proyectos (datos internos de opencode ya no se versionan).

### Changed
- Bump de versión a 1.9.5.

## [1.9.0] — 2026-08-18

### Changed
- **Python venv-first**: se elimina `pip --user` y `PYTHONUSERBASE`. El entorno canónico es el venv del proyecto (`<proyecto>/python/`).
- `entrypoint.sh` crea el venv automáticamente en el primer arranque (si falta) y lo activa en cada arranque.
- `-config` ahora redirige solo `state/` y `data/` (ya no `python/`).
- El `.gitignore` del proyecto se completa automáticamente con `python/` (venv) + `rust/` + temporales.

## [1.8.0] — 2026-08-17

### Added
- **Agente `investigador`**: investigación web multilingüe por subagentes (`investigador-es/en/fr/de/zh/ru`), con modo simplificado (EN/ES) y extendido.
- **`agents_update.sh`**: sincroniza los agentes del repo a la config global (copia canónica en `src/agents/`, deploy preserva subcarpetas).
- **Entorno Rust** por proyecto: `CARGO_HOME`/`CARGO_TARGET_DIR` en `<proyecto>/rust/` (aislado).
- `TODO.md` con registro de pendientes.

## [1.6.0] — 2026-07-12

### Added
- **Resolución del project root**: `opencode.sh` escala hacia arriba buscando `.git` (soporta worktrees), con límite en `$HOME`.
- Anchor idempotente `opencode.jsonc` para proyectos sin `.git` ni config (fija el root dentro del contenedor).
- **Ansible** en la imagen.
- Limpieza de imagen y documentación.

## [1.5.0] — 2026-06-30

### Added
- **Mundo GESTIÓN**: `--ps`/`--ls` (lista contenedores opencode) y `--kill`/`--rm` (detiene un contenedor por patrón).
- **Versionado**: campo `VERSION`/`TAG_RELEASE` en `opencode.sh` y `--version`.

## [1.0–1.4] — 2026-06-27 a 2026-06-28

### Added
- **Launcher inicial**: `opencode.sh` ejecuta opencode en un contenedor Podman por proyecto, con aislamiento de sesiones/datos y compartición de credenciales.
- Sección de capacidades del contenedor en el README (dev Python/Rust, diagnóstico de red, DevOps, IA, Node.js, seguridad).
- `PARAMETERS.md`: referencia formal de combinaciones de parámetros (matriz, árbol, BNF).
- Se incrementa la documentación del README.

---

[2.7.0-pre1]: #270--2026-08-30
[2.6.2-pre1]: #262--2026-08-30
[2.6.0-pre1]: #260--2026-08-30
[2.5.0]: #250--2026-08-30
[2.4.0]: #240--2026-08-24
[2.1.0]: #210--2026-08-21
[2.0.0]: #200--2026-08-20
[1.9.5]: #195--2026-08-19
[1.9.0]: #190--2026-08-18
[1.8.0]: #180--2026-08-17
[1.6.0]: #160--2026-07-12
[1.5.0]: #150--2026-06-30
