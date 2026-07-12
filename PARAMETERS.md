# Esquema de parámetros

> Referencia formal de combinaciones válidas. Documenta la intención de diseño que el parser de `opencode.sh` debería respetar.
>
> **Nota:** El parser actual (líneas 328-394 de `opencode.sh`) NO impone totalmente este esquema — aún permite algunas combinaciones marcadas como 🔴 (silenciosamente ignoradas). Este archivo es la especificación objetivo para futuras optimizaciones del parseo.

## Filosofía: mundos separados estrictos

El launcher tiene **tres mundos funcionales mutuamente excluyentes**:

- **Mundo IMAGEN**: gestiona la imagen del contenedor (build/update/renew). No necesita un proyecto ni configura el runtime.
- **Mundo GESTIÓN**: opera sobre contenedores ya en ejecución (`--ps`/`--ls` para listar, `--kill`/`--rm` para detener). No requiere `<proyecto>`.
- **Mundo EJECUCIÓN**: lanza un contenedor sobre un proyecto. Configura puerto, modo (TUI/web) y red.

Los flags de un mundo **no se cruzan** con los del otro. Si se mezclan, el resultado es semánticamente incorrecto (un flag se ignora o no tiene sentido) y el parser emite `error_exit`.

## Tabla única de combinaciones

```
                  MUNDO IMAGEN              MUNDO GESTIÓN            MUNDO EJECUCIÓN
               ┌──────┬──────┬──────┬──────┬──────────┬─────────┬──────┬──────────┬───────┬──────┬─────────┐
               │renew │rebuild│update│--ps  │ --kill   │<proyecto>│-config│--no-climb│--port│--tui│--network│
┌──────────────┼──────┼──────┼──────┼──────┼──────────┼─────────┼──────┼──────────┼───────┼──────┼─────────┤
│ --renew      │  —   │  ❌  │  🔴  │  🔴  │   🔴    │   🔴   │  🔴  │    🔴    │  🔴  │  🔴  │   🔴   │
│ --rebuild    │  ❌  │  —   │  🔴  │  🔴  │   🔴    │   🔴   │  🔴  │    🔴    │  🔴  │  🔴  │   🔴   │
│ --update     │  🔴  │  🔴  │  —   │  🔴  │   🔴    │   🔴   │  🔴  │    🔴    │  🔴  │  🔴  │   🔴   │
│ --ps         │  🔴  │  🔴  │  🔴  │  —   │   ❌    │   🔴   │  🔴  │    🔴    │  🔴  │  🔴  │   🔴   │
│ --kill       │  🔴  │  🔴  │  🔴  │  ❌  │   —     │   🔴   │  🔴  │    🔴    │  🔴  │  🔴  │   🔴   │
├──────────────┼──────┼──────┼──────┼──────┼──────────┼─────────┼──────┼──────────┼───────┼──────┼─────────┤
│ <proyecto>   │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   —    │  ✅  │    ✅    │  ✅  │  ✅  │   ✅   │
│ -config      │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   ✅   │  —   │    ✅    │  ✅  │  ✅  │   ✅   │
│ --no-climb   │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   ✅   │  ✅  │    —     │  ✅  │  ✅  │   ✅   │
│ --port       │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   ✅   │  ✅  │    ✅    │  —   │  🔴  │   ✅   │
│ --tui        │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   ✅   │  ✅  │    ✅    │  🔴  │  —   │   ✅   │
│ --network    │  🔴  │  🔴  │  🔴  │  🔴  │   🔴    │   ✅   │  ✅  │    ✅    │  ✅  │  ✅  │   —    │
│ -h, --help   │  ✅  │  ✅  │  ✅  │  ✅  │   ✅    │   ✅   │  ✅  │    ✅    │  ✅  │  ✅  │   ✅   │
│ --version    │  ✅  │  ✅  │  ✅  │  ✅  │   ✅    │   ✅   │  ✅  │    ✅    │  ✅  │  ✅  │   ✅   │
└──────────────┴──────┴──────┴──────┴──────┴──────────┴─────────┴──────┴──────────┴───────┴──────┴─────────┘
```

Leyenda:

| Marca | Significado |
|-------|-------------|
| ✅ | Combinación válida |
| ❌ | Prohibido: el script tira `error_exit` |
| 🔴 | Sin sentido: un flag se ignora o cruza mundos |
| — | Diagonal, no se compara consigo mismo |

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

Reglas de lectura:

- **Nivel 1** (hijos de `parámetros`): hermanos mutuamente excluyentes. Se elige UNO.
- **Nivel 2 y siguientes**: hermanos del mismo nivel son excluyentes entre sí; hijos de una rama extienden el camino del padre.
- Un camino completo del root a una hoja equivale a una invocación válida.

## Sintaxis formal (BNF simplificada)

```
invocacion       ::= mundo_imagen | mundo_gestion | mundo_ejecucion | "--help" | "--version"

mundo_imagen     ::= ("--renew" | "--rebuild" | "--update") ["--help"]
mundo_gestion    ::= ( "--ps" | "--ls"
                     | "--kill" <patrón> | "--rm" <patrón>
                     ) ["--help"]
mundo_ejecucion  ::= "<proyecto>" ["--no-climb"] (modo_tui | modo_web) ["--help"]

modo_tui         ::= "--tui" *tui_option
tui_option       ::= "-config" "<ruta>" | "--network-host" | "--network_host"

modo_web         ::= *web_option
web_option       ::= "--port" "<1-65535>"
                   | "-config" "<ruta>"
                   | "--network-host"
                   | "--network_host"
```

Restricciones adicionales:

- `--renew` y `--rebuild` son **mutuamente excluyentes** (error de sintaxis en el parser).
- `--ps`/`--ls` y `--kill`/`--rm` son **mutuamente excluyentes** (error de sintaxis en el parser).
- Cualquier flag IMAGEN con cualquier flag GESTIÓN o EJECUCIÓN es **error de sintaxis**.
- Cualquier flag GESTIÓN con cualquier flag IMAGEN o EJECUCIÓN es **error de sintaxis**.
- `--tui` **excluye** el uso de `--port` (no hay servidor).
- `--no-climb` (alias `--no-search-git`) solo aplica con `<proyecto>`; en otros mundos se ignora o produce error de sintaxis.
- En `modo_web`, `--network-host` omite el flag `-p` de `podman run` (podman lo ignora con `--network host` y emite warning).
- Contenedores TUI: nombre `opencode-tuiN` con N = `max(existentes) + 1` (no rellena huecos).
- Contenedores web: nombre `opencode-<puerto>`.

## Estado del parser actual vs. el esquema

Estado de cada regla en el parser actual de `opencode.sh`:

| Regla del esquema | Parser actual | Acción requerida |
|-------------------|---------------|-------------------|
| `--renew` ❌ `--rebuild` | ✅ ya lo impone | Ninguna |
| Mundo GESTIÓN (--ps/--kill) excluye IMAGEN y EJECUCIÓN | ✅ ya lo impone (error_exit) | Ninguna |
| `--ps` ❌ `--kill` | ✅ ya lo impone (error_exit) | Ninguna |
| `--kill <patrón>` match flexible | ✅ Implementado (1 match → stop, 0 o >1 → no actúa) | Ninguna |
| `--ps` lista contenedores con formato extendido | ✅ Implementado | Ninguna |
| Contenedores TUI: nombre `opencode-tuiN` con N=max+1 | ✅ Implementado | Ninguna |
| `--tui` ignora `--port` | ⚠️ No lo valida, solo lo silencia al armar `PORT_ARGS` | Validar y advertir |
| `--network-host` omite `-p` en web | ✅ Ya lo hace | Ninguna |

## Optimizaciones sugeridas para el parser

1. **Validación temprana de mundos**: después del `while` de parseo, verificar que ningún flag IMAGEN coexista con flags RUNTIME (esto es lo único que validar que daba error temprano).
2. **Advertir en lugar de callar**: si se usan flags que van a ser ignorados (ej: `--port` con `--tui`), emitir un `warning` en lugar de callar la elección.
3. **Conjuntos explícitos**: definir dos arrays en bash (`IMAGE_FLAGS`, `RUNTIME_FLAGS`) para validar combinaciones con `comm`/arrays en lugar de if-then dispersos.
4. **`--tui` vs `web` como booleano único**: hoy `TUI_MODE` decide; en el esquema es una decisión de primer nivel. Documentarlo.
5. **Mensaje de error con sugerencia**: si una combinación es 🔴, sugerir el comando equivalente válido (ej: "para renovar la imagen, ejecute `./opencode.sh --renew` sin <proyecto>").

Discrepancias entre este esquema y el código actual son deliberadas: el parser es permisivo por compatibilidad histórica con versiones anteriores (iteraciones 9-11), donde las combinaciones entre mundos estaban permitidas. Endurecer el parser constituye un cambio de behavior y debe tratarse como breaking change en una iteración futura.