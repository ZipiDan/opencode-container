# Esquema de parámetros

> Referencia formal de combinaciones válidas. Documenta la intención de diseño que el parser de `opencode.sh` debería respetar.
>
> **Nota:** El parser actual (líneas 328-394 de `opencode.sh`) NO impone totalmente este esquema — aún permite algunas combinaciones marcadas como 🔴 (silenciosamente ignoradas). Este archivo es la especificación objetivo para futuras optimizaciones del parseo.

## Filosofía: mundos separados estrictos

El launcher tiene **dos mundos funcionales mutuamente excluyentes**:

- **Mundo IMAGEN**: gestiona la imagen del contenedor (build/update/renew). No necesita un proyecto ni configura el runtime.
- **Mundo EJECUCIÓN**: lanza un contenedor sobre un proyecto. Configura puerto, modo (TUI/web) y red.

Los flags de un mundo **no se cruzan** con los del otro. Si se mezclan, el resultado es semánticamente incorrecto (un flag se ignora o no tiene sentido).

## Tabla única de combinaciones

```
                  MUNDO IMAGEN                  MUNDO EJECUCIÓN
               ┌──────┬──────┬──────┬─────────┬──────┬───────┬──────┬──────┐
               │renew │rebuild│update│<proyecto>│-config│--port│--tui│--network│
┌──────────────┼──────┼──────┼──────┼─────────┼──────┼───────┼──────┼─────────┤
│ --renew      │  —   │  ❌  │  🔴  │   🔴   │  🔴  │  🔴   │  🔴  │   🔴   │
│ --rebuild    │  ❌  │  —   │  🔴  │   🔴   │  🔴  │  🔴   │  🔴  │   🔴   │
│ --update     │  🔴  │  🔴  │  —   │   🔴   │  🔴  │  🔴   │  🔴  │   🔴   │
├──────────────┼──────┼──────┼──────┼─────────┼──────┼───────┼──────┼─────────┤
│ <proyecto>   │  🔴  │  🔴  │  🔴  │   —    │  ✅  │  ✅   │  ✅  │   ✅   │
│ -config      │  🔴  │  🔴  │  🔴  │   ✅   │  —   │  ✅   │  ✅  │   ✅   │
│ --port       │  🔴  │  🔴  │  🔴  │   ✅   │  ✅  │   —   │  🔴  │   ✅   │
│ --tui        │  🔴  │  🔴  │  🔴  │   ✅   │  ✅  │  🔴   │  —   │   ✅   │
│ --network    │  🔴  │  🔴  │  🔴  │   ✅   │  ✅  │  ✅   │  ✅  │   —    │
│ -h, --help   │  ✅  │  ✅  │  ✅  │   ✅   │  ✅  │  ✅   │  ✅  │   ✅   │
└──────────────┴──────┴──────┴──────┴─────────┴──────┴───────┴──────┴─────────┘
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

parámetros
│
├── --renew                          reconstruye imagen atómicamente
│
├── --rebuild                        reconstruye imagen usando caché
│
├── --update                         actualiza imagen desde cero
│
└── <proyecto>                       lanza opencode en el proyecto
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
invocacion     ::= mundo_imagen | mundo_ejecucion | "--help"

mundo_imagen   ::= ("--renew" | "--rebuild" | "--update") ["--help"]
mundo_ejecucion ::= "<proyecto>" (modo_tui | modo_web) ["--help"]

modo_tui       ::= "--tui" *tui_option
tui_option     ::= "-config" "<ruta>" | "--network-host" | "--network_host"

modo_web       ::= *web_option
web_option     ::= "--port" "<1-65535>"
                 | "-config" "<ruta>"
                 | "--network-host"
                 | "--network_host"
```

Restricciones adicionales:

- `--renew` y `--rebuild` son **mutuamente excluyentes** (error de sintaxis en el parser).
- `--tui` **excluye** el uso de `--port` (no hay servidor).
- En `modo_web`, `--network-host` suppress explicitamente el flag `-p` de `podman run` (podman lo ignora con `--network host` y emite warning).

## Estado del parser actual vs. el esquema

Estado de cada regla en el parser actual de `opencode.sh`:

| Regla del esquema | Parser actual | Acción requerida |
|-------------------|---------------|-------------------|
| `--renew` ❌ `--rebuild` | ✅ ya lo impone | Ninguna |
| `--renew` + `<proyecto>` should be 🔴 | ⚠️ Lo permite y ejecuta | Endurecer |
| `--renew` + `--tui` should be 🔴 | ⚠️ Lo permite (ignora `--tui` en flujo rápido) | Endurecer |
| `--tui` ignora `--port` | ⚠️ No lo valida, solo lo silencia al armar `PORT_ARGS` | Validar y advertir |
| `--network-host` omite `-p` en web | ✅ Ya lo hace | Ninguna |
| Sin `<proyecto>` + flags runtime | ⚠️ Los parsea pero los descarta al salir temprano | Endurecer o advertir |

## Optimizaciones sugeridas para el parser

1. **Validación temprana de mundos**: después del `while` de parseo, verificar que ningún flag IMAGEN coexista con flags RUNTIME (esto es lo único que validar que daba error temprano).
2. **Advertir en lugar de callar**: si se usan flags que van a ser ignorados (ej: `--port` con `--tui`), emitir un `warning` en lugar de callar la elección.
3. **Conjuntos explícitos**: definir dos arrays en bash (`IMAGE_FLAGS`, `RUNTIME_FLAGS`) para validar combinaciones con `comm`/arrays en lugar de if-then dispersos.
4. **`--tui` vs `web` como booleano único**: hoy `TUI_MODE` decide; en el esquema es una decisión de primer nivel. Documentarlo.
5. **Mensaje de error con sugerencia**: si una combinación es 🔴, sugerir el comando equivalente válido (ej: "para renovar la imagen, ejecute `./opencode.sh --renew` sin <proyecto>").

Discrepancias entre este esquema y el código actual son deliberadas: el parser es permisivo por compatibilidad histórica con versiones anteriores (iteraciones 9-11), donde las combinaciones entre mundos estaban permitidas. Endurecer el parser constituye un cambio de behavior y debe tratarse como breaking change en una iteración futura.