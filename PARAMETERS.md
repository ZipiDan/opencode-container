<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Esquema de parámetros

> Referencia formal de combinaciones válidas. Documenta la intención de diseño que el parser de `opencode.sh` debería respetar.
>
> **Nota:** El parser actual (bloque `# Parseo de argumentos` de `opencode.sh`) NO impone totalmente este esquema — aún permite algunas combinaciones marcadas como 🔴 (silenciosamente ignoradas). Este archivo es la especificación objetivo para futuras optimizaciones del parseo.

## Filosofía: mundos separados estrictos

El launcher tiene **cuatro mundos funcionales mutuamente excluyentes**:

- **Mundo IMAGEN**: gestiona la imagen del contenedor (build/update/renew). No necesita un proyecto ni configura el runtime.
- **Mundo GESTIÓN**: opera sobre contenedores ya en ejecución (`--ps`/`--ls` para listar, `--kill`/`--rm` para detener, `--pair` para generar links de acceso). No requiere `<proyecto>`.
- **Mundo CREDENCIALES**: mantiene el `auth.json` canónico de `share/` (`--credentials-set` para alta/rotación, `--credentials-export` para promover un login de un proyecto, `--sync-credentials` para aplicarlo en un contenedor vivo). Sólo el export acepta `<proyecto>`.
- **Mundo EJECUCIÓN**: lanza un contenedor sobre un proyecto. Configura puerto, modo (TUI/web) y red.

Los flags de un mundo **no se cruzan** con los del otro. Si se mezclan, el resultado es semánticamente incorrecto (un flag se ignora o no tiene sentido) y el parser emite `error_exit`.

## Tabla única de combinaciones

```
 ┌──────────────┬──────┬────────┬───────┬─────┬───────┬───────────┬────────┬───────────┬───────┬──────────────┬──────┬──────┬──────────┬───────────┬───────┐
│              │renew│rebuild│update│--ps│--kill│<proyecto>│-config│--no-climb│--port│--extra-ports│--tui│--web│--network│--password│--auto│
 ├──────────────┼──────┼────────┼───────┼─────┼───────┼───────────┼────────┼───────────┼───────┼──────────────┼──────┼──────┼──────────┼───────────┼───────┤
│ renew        │—    │❌      │🔴     │🔴   │🔴     │🔴         │🔴      │🔴         │🔴     │🔴            │🔴    │🔴    │🔴        │🔴         │🔴     │
│ rebuild      │❌    │—      │🔴     │🔴   │🔴     │🔴         │🔴      │🔴         │🔴     │🔴            │🔴    │🔴    │🔴        │🔴         │🔴     │
│ update       │🔴    │🔴      │—     │🔴   │🔴     │🔴         │🔴      │🔴         │🔴     │🔴            │🔴    │🔴    │🔴        │🔴         │🔴     │
│ --ps         │🔴    │🔴      │🔴     │—   │❌     │🔴         │🔴      │🔴         │🔴     │🔴            │🔴    │🔴    │🔴        │🔴         │🔴     │
│ --kill       │🔴    │🔴      │🔴     │❌   │—     │🔴         │🔴      │🔴         │🔴     │🔴            │🔴    │🔴    │🔴        │🔴         │🔴     │
 ├──────────────┼──────┼────────┼───────┼─────┼───────┼───────────┼────────┼───────────┼───────┼──────────────┼──────┼──────┼──────────┼───────────┼───────┤
│ <proyecto>   │🔴    │🔴      │🔴     │🔴   │🔴     │—         │✅      │✅         │✅     │✅            │✅    │✅    │✅        │✅         │✅     │
│ -config      │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │—      │✅         │✅     │✅            │✅    │✅    │✅        │✅         │✅     │
│ --no-climb   │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │—         │✅     │✅            │✅    │✅    │✅        │✅         │✅     │
│ --port       │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │—     │✅            │🔴    │✅    │✅        │✅         │✅     │
│ --extra-ports│🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │✅     │—            │✅    │✅    │✅        │✅         │✅     │
│ --tui        │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │🔴     │✅            │—    │❌    │✅        │🔴         │✅     │
│ --web        │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │✅     │✅            │❌    │—    │✅        │✅         │✅     │
│ --network    │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │✅     │✅            │✅    │✅    │—        │✅         │✅     │
│ --password   │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │✅     │✅            │🔴    │✅    │✅        │—         │✅     │
 ├──────────────┼──────┼────────┼───────┼─────┼───────┼───────────┼────────┼───────────┼───────┼──────────────┼──────┼──────┼──────────┼───────────┼───────┤
│ --auto       │🔴    │🔴      │🔴     │🔴   │🔴     │✅         │✅      │✅         │✅     │✅            │✅    │✅    │✅        │✅         │—     │
 ├──────────────┼──────┼────────┼───────┼─────┼───────┼───────────┼────────┼───────────┼───────┼──────────────┼──────┼──────┼──────────┼───────────┼───────┤
│ -h, --help   │✅    │✅      │✅     │✅   │✅     │✅         │✅      │✅         │✅     │✅            │✅    │✅    │✅        │✅         │✅     │
│ --version    │✅    │✅      │✅     │✅   │✅     │✅         │✅      │✅         │✅     │✅            │✅    │✅    │✅        │✅         │✅     │
 └──────────────┴──────┴────────┴───────┴─────┴───────┴───────────┴────────┴───────────┴───────┴──────────────┴──────┴──────┴──────────┴───────────┴───────┘
```

Leyenda:

| Marca | Significado |
|-------|-------------|
| ✅ | Combinación válida |
| ❌ | Prohibido: el script tira `error_exit` |
| 🔴 | Sin sentido: un flag se ignora o cruza mundos |
| — | Diagonal, no se compara consigo mismo |

> `--pair` y `--kill-all` no figuran como columnas en la tabla (se agregaron después): son acciones del mundo GESTIÓN, mutuamente excluyentes con `--ps`/`--kill` y con los mundos IMAGEN/EJECUCIÓN. `--pair` además rechaza `--port` y `--password`.
>
> `--credentials-set`, `--credentials-export`, `--sync-credentials` y `--no-credentials-seed` tampoco figuran en la tabla (v4.2.0): los tres primeros forman el mundo CREDENCIALES, mutuamente excluyentes entre sí y con los otros mundos; `--no-credentials-seed` es un flag del mundo EJECUCIÓN (se combina con `<proyecto>`).

## Árbol de combinaciones de parámetros

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
│       Patrón puede ser:
│         nombre exacto (opencode-tui2, opencode-4096)
│         o forma corta (tui2, 2, 4096)
│       Si el patrón no matchea o matchea varios, no se actúa.
│
├── --pair <patrón>                  genera links de pairing para un contenedor web
│       Mismo patrón que --kill. No acepta --port ni --password:
│       el puerto y el password se leen del contenedor resuelto.
│       Un link por origen (127.0.0.1 + LAN real; sin interfaces virtuales).
│
├── --credentials-set <integración>  escribe la API key en share/auth.json (0600)
│       La key se pide sin eco (o se lee de stdin si no hay TTY).
│
├── --credentials-export <proyecto>  vuelca las API keys del proyecto al canónico
│       Acepta también -config y --no-climb (resuelve las rutas igual que la
│       ejecución). Exporta sólo credenciales de tipo API key, no OAuth.
│
├── --sync-credentials <patrón>      aplica el canónico en un contenedor vivo
│       Mismo patrón que --kill. No acepta <proyecto> ni -config.
│
└── <proyecto>                       lanza opencode en el proyecto
    │
    ├── --no-climb                   desactiva la búsqueda de .git hacia atrás
    │                                (también: --no-search-git)
    │
    ├── --auto | --no-auto           auto-aprueba permisos de opencode
    │                                (default: --auto; --no-auto vuelve a pedir)
    │
    ├── --no-credentials-seed        no siembra auth.json al arrancar
    │
    ├── --tui                        arranca terminal interactiva
    │   ├── -config <ruta>
    │   ├── --network-host
    │   └── --extra-ports <n>,<n>,...   publica puertos extra host→contenedor
    │
    └── web (default)                arranca servidor web
        ├── --web                    fuerza modo web (gana a OPENCODE_GUI)
        ├── --port <1-65535>
        │   └── default: 4096
        ├── --extra-ports <n>,<n>,...   publica puertos extra host→contenedor
        ├── --password <pwd>         activa auth básica web (usuario: opencode)
        ├── -config <ruta>
        └── --network-host
```

Reglas de lectura:

- **Nivel 1** (hijos de `parámetros`): hermanos mutuamente excluyentes. Se elige UNO.
- **Nivel 2 y siguientes**: hermanos del mismo nivel son excluyentes entre sí; hijos de una rama extienden el camino del padre.
- Un camino completo del root a una hoja equivale a una invocación válida.

## Sintaxis formal (BNF simplificada)

```
invocacion       ::= mundo_imagen | mundo_gestion | mundo_credenciales
                     | mundo_ejecucion | "--help" | "--version"

mundo_imagen     ::= ("--renew" | "--rebuild" | "--update") ["--help"]
mundo_gestion    ::= ( "--ps" | "--ls"
                     | "--kill" <patrón> | "--rm" <patrón>
                     | "--pair" <patrón>
                     ) ["--help"]
mundo_credenciales ::= "--credentials-set" <integración> ["--help"]
                     | "--credentials-export" "<proyecto>"
                       ["-config" "<ruta>"] ["--no-climb"] ["--help"]
                     | "--sync-credentials" <patrón> ["--help"]
mundo_ejecucion  ::= "<proyecto>" ["--no-climb"] ["--auto" | "--no-auto"]
                     ["--no-credentials-seed"]
                     (modo_tui | modo_web) ["--help"]

modo_tui         ::= ("--tui" | "--no-web") *tui_option
tui_option       ::= "-config" "<ruta>" | "--network-host" | "--network_host"
                   | "--extra-ports" "<lista_puertos>"

modo_web         ::= ["--web"] *web_option
web_option       ::= "--port" "<1-65535>"
                   | "--extra-ports" "<lista_puertos>"
                   | "--password" "<pwd>"
                   | "-config" "<ruta>"
                   | "--network-host"
                   | "--network_host"

lista_puertos    ::= <1-65535> ("," <1-65535>)*
```

Restricciones adicionales:

- `--renew` y `--rebuild` son **mutuamente excluyentes** (error de sintaxis en el parser).
- `--tui`/`--no-web` y `--web` son **mutuamente excluyentes** (error de sintaxis en el parser).
- Selección de modo (precedencia): flags `--tui`/`--no-web` o `--web` > env `OPENCODE_GUI` del host (`tui`|`web`; valor inválido → aviso y default) > default web.
- `--extra-ports <lista_puertos>`: comas sin espacios, mínimo 1, cada puerto 1-65535 y sin duplicados (error de sintaxis en el parser). En modo web no puede chocar con `--port` (error: mapeo `-p` duplicado).
- `--extra-ports` publica `-p n:n` por cada puerto en **ambos modos** (web y TUI); con `--network-host` se omite con aviso (podman descarta `-p` en red del host).
- `--ps`/`--ls`, `--kill`/`--rm`, `--pair` y `--kill-all` son **mutuamente excluyentes** (error de sintaxis en el parser).
- `--pair <patrón>` usa el mismo resolvedor que `--kill` (nombre exacto, `tuiN`, `N`; 0 matches → aviso, >1 → error). No acepta `--port` ni `--password`: el puerto y el password se leen del contenedor resuelto.
- `--pair` solo opera sobre contenedores web (`opencode-<puerto>`); un contenedor TUI produce `error_exit`.
- Cualquier flag IMAGEN con cualquier flag GESTIÓN o EJECUCIÓN es **error de sintaxis**.
- Cualquier flag GESTIÓN con cualquier flag IMAGEN o EJECUCIÓN es **error de sintaxis**.
- `--credentials-set`, `--credentials-export` y `--sync-credentials` son **mutuamente excluyentes** entre sí y con los mundos IMAGEN/GESTIÓN/EJECUCIÓN (error de sintaxis en el parser).
- `--credentials-set` y `--sync-credentials` **no aceptan** `<proyecto>`, `-config`, `--no-climb` ni flags de ejecución (`--port`, `--tui`, `--web`, `--password`, `--extra-ports`, `--network-host`, `--auto`).
- `--credentials-export` **requiere** `<proyecto>` y acepta `-config` y `--no-climb`; rechaza los flags de ejecución. Falla si el proyecto no tiene `data/opencode.db`.
- `--no-credentials-seed` sólo aplica con `<proyecto>`; combinarlo con los comandos de credenciales es **error de sintaxis**.
- `--tui` **excluye** el uso de `--port` (no hay servidor).
- `--tui` **excluye** `--password` (la auth básica es solo web; se avisa y se ignora).
- `--password` tiene prioridad sobre la env var `OPENCODE_SERVER_PASSWORD` del host; si no se pasa el flag ni existe la env, se usa el default `opencode`. El password se imprime en el arranque web.
- `--user` **se eliminó**: opencode v2 fija el usuario de auth web en `opencode` (hardcodeado en `ServerAuthConfig`; ignora `OPENCODE_SERVER_USERNAME`). Pasarlo produce `error_exit`.
- `--no-climb` (alias `--no-search-git`) solo aplica con `<proyecto>`; en otros mundos se ignora o produce error de sintaxis.
- `--auto`/`--no-auto` solo aplican con `<proyecto>`; en otros mundos se ignoran o producen error de sintaxis. Default: `--auto` (el contenedor auto-aprueba permisos). La env var `OPENCODE_PERMISSION` del host tiene prioridad sobre ambos flags.
- En `modo_web`, `--network-host` omite el flag `-p` de `podman run` (podman lo ignora con `--network host` y emite warning).
- Contenedores TUI: nombre `opencode-tuiN` con N = `max(existentes) + 1` (no rellena huecos).
- Contenedores web: nombre `opencode-<puerto>`.

## Estado del parser actual vs. el esquema

Estado de cada regla en el parser actual de `opencode.sh`:

| Regla del esquema | Parser actual | Acción requerida |
|-------------------|---------------|-------------------|
| `--renew` ❌ `--rebuild` | ✅ ya lo impone | Ninguna |
| Mundo GESTIÓN (--ps/--kill/--pair) excluye IMAGEN y EJECUCIÓN | ✅ ya lo impone (error_exit) | Ninguna |
| `--ps` ❌ `--kill` ❌ `--pair` | ✅ ya lo impone (error_exit) | Ninguna |
| `--kill <patrón>` match flexible | ✅ Implementado (1 match → stop, 0 o >1 → no actúa) | Ninguna |
| `--pair <patrón>` usa el mismo match que `--kill` | ✅ Implementado (resolvedor compartido) | Ninguna |
| `--pair` lee puerto/password del contenedor, sin `--password` | ✅ Implementado (inspect + fallback logs) | Ninguna |
| `--pair` rechaza contenedores TUI | ✅ `error_exit` si no hay puerto web | Ninguna |
| `--password` default `opencode` + impresión en arranque | ✅ Implementado (flag > env > default) | Ninguna |
| `--ps` lista contenedores con formato extendido | ✅ Implementado | Ninguna |
| Contenedores TUI: nombre `opencode-tuiN` con N=max+1 | ✅ Implementado | Ninguna |
| `--tui` ignora `--port` | ⚠️ No lo valida, solo lo silencia al armar `PORT_ARGS` | Validar y advertir |
| `--tui` ❌ `--web` | ✅ ya lo impone (error_exit) | Ninguna |
| Selección de modo: flags > `OPENCODE_GUI` > default | ✅ Implementado (env del host; valor inválido → aviso y default web) | Ninguna |
| `--extra-ports`: lista válida + sin choque con `--port` | ✅ Implementado (error_exit) | Ninguna |
| `--extra-ports` omitido con `--network-host` | ✅ Implementado (aviso, sin `-p`) | Ninguna |
| `--password` solo en web | ✅ Avisa en TUI y lo ignora (no pasa env var de auth) | Ninguna |
| `--password` prioridad sobre env del host | ✅ Implementado (flag > env) | Ninguna |
| `--user` eliminado (usuario fijo `opencode` en v2) | ✅ `error_exit` con explicación | Ninguna |
| `--network-host` omite `-p` en web | ✅ Ya lo hace | Ninguna |
| `--auto`/`--no-auto` (auto-aprueba permisos) | ✅ Implementado; default `--auto`; env `OPENCODE_PERMISSION` del host tiene prioridad | Ninguna |
| Mundo CREDENCIALES (`--credentials-set`/`--credentials-export`/`--sync-credentials`) excluye los otros tres mundos | ✅ ya lo impone (error_exit) | Ninguna |
| Los tres comandos de credenciales son mutuamente excluyentes | ✅ ya lo impone (error_exit) | Ninguna |
| `--credentials-set`/`--sync-credentials` rechazan proyecto, `-config` y flags de ejecución | ✅ ya lo impone (error_exit) | Ninguna |
| `--credentials-export` requiere `<proyecto>` y acepta `-config`/`--no-climb` | ✅ ya lo impone (error_exit) | Ninguna |
| `--no-credentials-seed` sólo con `<proyecto>` | ✅ ya lo impone (error_exit si se mezcla con credenciales) | Ninguna |

## Optimizaciones sugeridas para el parser

1. **Validación temprana de mundos**: después del `while` de parseo, verificar que ningún flag IMAGEN coexista con flags RUNTIME (esto es lo único que validar que daba error temprano).
2. **Advertir en lugar de callar**: si se usan flags que van a ser ignorados (ej: `--port` con `--tui`), emitir un `warning` en lugar de callar la elección.
3. **Conjuntos explícitos**: definir dos arrays en bash (`IMAGE_FLAGS`, `RUNTIME_FLAGS`) para validar combinaciones con `comm`/arrays en lugar de if-then dispersos.
4. **`--tui` vs `web` como booleano único**: hoy `TUI_MODE` decide; en el esquema es una decisión de primer nivel. Documentarlo.
5. **Mensaje de error con sugerencia**: si una combinación es 🔴, sugerir el comando equivalente válido (ej: "para renovar la imagen, ejecute `./opencode.sh --renew` sin <proyecto>").

Discrepancias entre este esquema y el código actual son deliberadas: el parser es permisivo por compatibilidad histórica con versiones anteriores (iteraciones 9-11), donde las combinaciones entre mundos estaban permitidas. Endurecer el parser constituye un cambio de behavior y debe tratarse como breaking change en una iteración futura.
