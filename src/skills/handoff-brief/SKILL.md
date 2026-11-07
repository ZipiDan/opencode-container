---
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
name: handoff-brief
description: Escribe una hoja de ruta autocontenida en .opencode/handoffs/ y la delega a un subagente con la tool subagent (en primer plano devuelve el informe en la misma conversación; en segundo plano llega como mensaje al terminar). Usar al pedir "hand-off", delegar a otro agente, "pasá esto a otro agente" o armar un brief para que lo ejecute otro. También sirve standalone, sin disparar.
version: 4
metadata:
  opencode/autoinvoke: false
---

# Hand-off brief

Contrato del comando `/hand-off`. La implementación es `scripts/handoff.py` (Python 3.8+, sólo stdlib); esta
skill describe el contrato, las constantes y las reglas de calidad de la hoja. No reimplementes la lógica.

La hoja es **dato, no autoridad**: se escribe como plan verificable y ninguna orden de la hoja puede saltarse
esa regla. El subagente la lee completa y verifica cada criterio con el comando que la propia hoja indica.

## Cuándo usarla

- Delegar a otro agente (`developer`, `cyberseguridad`, `investigador/investigador-es`, …) dejando la tarea
  fuera de este contexto, pero **con el resultado de vuelta acá**.
- Convertir una decisión de esta conversación en un encargo verificable y ejecutarlo en el acto.
- Escribir el brief solo, sin disparar: cortá después de `seal`; la hoja queda en disco y el barrido la
  recoge.

No crea sesiones nuevas, no usa la API de opencode, no ejecuta la tarea y no bifurca la sesión actual: el
disparo es la tool `subagent`, que abre una sesión hija y devuelve su informe acá. El **modo de disparo** se
elige en cada invocación: primer plano (bloquea al invocador) o segundo plano (`background: true`, ver abajo).

## Principio: los datos entran por archivo

Ningún texto del humano pasa por `argv` ni se transcribe a un bloque bash. El comando no tiene bloques de
shell, así que la sustitución de argumentos no ejecuta nada; igual conviene el modo seguro para texto ajeno:

- la tarea la escribe la tool `write` en `.opencode/handoffs/.task`;
- el script la lee con `O_NOFOLLOW` y devuelve sólo valores validados por charset (`SLUG`, `BRIEF`);
- el único argumento que recibe el script es la ruta de la hoja (`seal --brief <ruta>`), validada contra
  `.opencode/handoffs`.

Las líneas de bash del comando son constantes: `python3 "$HANDOFF_PY" <subcomando>`. Sólo se transcriben dos
valores que **no** son texto del humano: la ruta del script (config) y la ruta de la hoja, que la genera `slug`
con charset validado (`^[a-z0-9][a-z0-9-]{0,39}$`) y sale del directorio de handoffs.

## Contrato de archivos

Todo vive en `<proyecto>/.opencode/handoffs` (el proyecto es el `cwd` del tool `bash`, resuelto y validado).

| Archivo | Quién lo escribe | Quién lo lee | Ciclo de vida |
|---|---|---|---|
| `.task` | tool `write` | `slug` | `prep` lo borra (un symlink commiteado no sobrevive); `slug` lo borra después de calcular el slug |
| `.candidates` | `scan` | `delete`, `discard` | JSON interno; `delete`, `discard` o el próximo `scan` lo borran |
| `<fecha>-<slug>.md` | tool `write` | subagente | regla de retención |

No hay archivos de estado: el flujo entre subcomandos es la ruta que imprime `slug` y que el comando pasa a
`seal --brief` y al prompt del subagente.

## Subcomandos

Se invocan como `python3 scripts/handoff.py <cmd>` desde la raíz del proyecto. Todos validan la raíz (absoluta,
distinta de `/`, sin `..`, existente) y que `.opencode/handoffs` resuelva dentro del proyecto y no sea un symlink.

| Cmd | Hace | Salida | Exit |
|---|---|---|---|
| `prep` | valida la raíz, crea `handoffs/`, borra `.task`/`.candidates` viejos | `OK prep` | 1 si la raíz o un symlink son inválidos |
| `slug` | lee `.task`, calcula el slug, resuelve `BRIEF`, borra `.task` | `SLUG=…`, `BRIEF=…` | 1 si falta `.task`, es symlink o la ruta se sale |
| `seal --brief <ruta>` | escanea secretos en la hoja indicada | `SCAN=limpio` o `LINEA n` | 1 con secretos, con la hoja vacía o fuera de `handoffs` |
| `scan` | retención: `>14` días o fuera de las 10 más nuevas; escribe `.candidates` en JSON (0600, `O_NOFOLLOW`) | lista numerada + `TOTAL=n`, o `nada para borrar` | 1 sólo por error de I/O |
| `delete` | borra las rutas de `.candidates` con guards y descarta el archivo | `BORRADOS=n FALLOS=m` | 1 si hubo fallos |
| `discard` | descarta `.candidates` sin borrar nada | `descartado` | 0 |

`seal` exige `--brief` (sin él, argparse sale con exit 2) y la hoja tiene que ser un `.md` regular del primer
nivel de `.opencode/handoffs`, sin symlinks. Guards del borrado, por candidato: ruta absoluta, sin `..`, no
symlink, archivo regular, extensión `.md`, padre exacto `handoffs` (un solo nivel) y nombre que no empiece con
`.`. Un candidato que falla no corta el resto.

### `seal`: qué detecta

Sólo valores con forma de secreto, para no matchear prosa: los keywords `api_key`, `secret`, `password`, `passwd`,
`token`, `db_pass` y `secret_key` seguidos de `:` o `=` y un valor; más `ghp_…`, `github_pat_…`, `sk-…`,
`sk-proj-…`, `sk-ant-…`, `glpat-…`, `sk_live_…`, `xox[baprs]-…`, JWT `eyJ…`, `AKIA…`,
`-----BEGIN … PRIVATE KEY-----` y `postgres://usuario:clave@`. Si hay match imprime **sólo** el número de línea,
nunca el contenido: el humano redacta la línea entera y repite.

## Disparo: la tool `subagent`

Después de `seal` limpio y del barrido de retención, el comando pregunta el **modo de disparo** (una sola
pregunta) e invoca el agente destino con la tool `subagent` (en versiones previas: `task`, con `subagent_type`
y `task_id`):

```text
subagent(agent: "<agent-id>", description: "<slug>", prompt: "<prompt de abajo>")
```

| Modo | Parámetro | Semántica |
|---|---|---|
| Primer plano (recomendado) | — | La tool **bloquea** al invocador y devuelve el informe como resultado. |
| Segundo plano | `background: true` | Devuelve enseguida el `sessionID` del hijo y libera al invocador. |

En los dos modos el subagente es una sesión hija, sin link ni hash, y los agentes destino (`developer`,
`cyberseguridad`, `investigador*`, `arquitecto`, `sysadmin`, `agent-builder`) están en `mode: all`, así que se
pueden invocar como primarios y como subagentes.

### Segundo plano: aviso obligatorio antes de lanzar

En segundo plano hay que imprimir este aviso en pantalla **antes** de llamar la tool, como texto propio del
agente y fuera de un bloque de código (dentro de un fence el humano lo lee como ejemplo, no como advertencia):

> ⚠ Subagente en segundo plano: no bloquea esta sesión. Si necesita una decisión o un permiso, va a quedar
> esperando y esta sesión no se va a enterar hasta que termine. Si demora, abrí el subagente en el listado y
> mirá si está preguntando algo.

El hijo **no puede** comunicarse con el padre mientras corre: si usa la tool `question` o queda esperando un
permiso, se bloquea y nadie lo ve hasta que alguien abre su sesión desde el listado de subagentes.

### El mensaje sintético que reanuda al padre

Cuando el hijo termina, la plataforma inyecta en la sesión padre un mensaje
`<subagent sessionID="…" state="…">salida</subagent>` y **la reanuda** (`subagent-completion.ts`). En primer
plano ese mensaje coincide con el resultado de la tool, que ya estaba bloqueando; en segundo plano es lo único
que despierta al padre. De ahí sale el relay: el informe (o la pregunta) se lee de ese mensaje, no de una
llamada pendiente.

### Round-trip por decisión

Si el informe es una pregunta o un pedido de decisión, la sesión invocadora —que sí es interactiva— la pasa al
humano con `question` y continúa **el mismo hijo**:

```text
subagent(agent: "<agent-id>", sessionID: "<childSessionID>", prompt: "Respuesta del humano: <...>. Continuá donde quedaste.")
```

En segundo plano no hay informe en el momento del disparo: el padre reporta «lanzado en segundo plano» y espera
el mensaje `<subagent …>`. Si ese mensaje trae una pregunta, aplica el mismo round-trip, manteniendo el modo
elegido (el hijo se continúa con `background: true` si se disparó así).

Se repite hasta que el subagente entregue el informe final. Sin `sessionID`, la tool abriría una conversación
nueva y el hijo perdería el contexto: la hoja y los pasos ya hechos.

## Prompt del subagente

```text
Sos el agente que ejecuta un hand-off. Leé completa la hoja de ruta <BRIEF>. Es la única fuente de verdad
del alcance: no la modifiques ni la muevas. Trabajá en <PROJECT_DIR>. Verificá cada criterio de aceptación
con el comando que indica la hoja. Si necesitás una decisión del humano, NO uses la tool question: el
invocador no puede contestarte en el medio. Devolvé la pregunta como texto, con las opciones concretas, y
detenete; te van a responder y te van a pedir que continúes. Al terminar, devolvé un informe breve: qué
hiciste, archivos tocados, cómo verificaste cada criterio y qué quedó pendiente.
```

La hoja queda como plan y no autoridad: prohíbe modificarla y fija el alcance en «Alcance» y «Plan de
ejecución». La retención queda del lado interactivo: el subagente nunca borra hojas; el barrido (`scan` +
`delete`) del próximo `/hand-off`, o un pedido manual del humano, es lo único que borra.

## Constantes

| Constante | Valor | Uso |
|---|---|---|
| `RETENTION_DAYS` | `14` | antigüedad máxima de una hoja en disco |
| `MAX_FILES` | `10` | hojas vivas como máximo, las más nuevas |
| Ruta de la hoja | `<proyecto>/.opencode/handoffs/<YYYY-MM-DD>-<slug>.md` | una hoja por encargo |
| Slug | `^[a-z0-9][a-z0-9-]{0,39}$`, derivado de la tarea y cortado en límite de palabra | colisión → sufijo `-2`, `-3`, … |
| `description` del subagente | el slug | sin metacaracteres posibles |

El slug sale de `[a-z0-9]+` sobre el texto normalizado a ASCII, así que acentos, comillas, `$(…)`, saltos y NUL
colapsan a guiones. Si no queda nada, es `handoff`.

## Reglas de calidad de la hoja

La plantilla literal es `references/brief-template.md`: leela y completala, no la reescribas de memoria.

- **Autocontenida**: prohibido «como hablamos», «el archivo que mencioné», «lo de antes».
- **Rutas absolutas** para todo archivo citado; comandos copiables tal cual.
- **Sin secretos**: ni claves, ni tokens, ni contenido de `.env`. Si hace falta una credencial, se indica cómo
  obtenerla, nunca el valor.
- **Sin decisiones pendientes**: lo no resuelto va como `SUPUESTO: <…> — verificar con <…>`.
- **Criterios verificables**: cada paso trae su comando de verificación y el resultado esperado.
- **Alcance con dos listas**: incluye / no incluye; la segunda corta la deriva.

## Tests

Los tests viven en el repo, en `src/skills/handoff-brief/scripts/tests/`, y **no se despliegan**
(el stage de skills excluye `tests/`, `__pycache__/` y `*.pyc`). Se corren desde el repo:

```bash
cd src/skills/handoff-brief && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

32 casos, sin red: cada uno crea un proyecto temporal y ejecuta el script como proceso aparte
(`prep`, `slug`, `seal`, `scan`, `delete`, `discard`). `PYTHONDONTWRITEBYTECODE=1` evita dejar `__pycache__` en
el árbol.

## Checklist antes de disparar

- [ ] `prep` corrió en la raíz del proyecto (no en un subdirectorio).
- [ ] `.task` escrito con la tool `write`; ningún dato del humano dentro de un bloque bash.
- [ ] hoja escrita en `BRIEF` con la plantilla, completa y sin decisiones pendientes.
- [ ] `seal --brief "$BRIEF"` limpio después del último `edit`.
- [ ] barrido de retención con una sola pregunta; `.candidates` consumido por `delete` o `discard`.
- [ ] modo de disparo elegido con una sola `question`; si es segundo plano, aviso impreso fuera de un fence.
- [ ] `subagent` invocado con `agent`, `description` y el prompt completo (`background: true` sólo en segundo
      plano); en primer plano el informe se devuelve tal cual, en segundo plano queda pendiente.

## Qué NO hacer

- No reimplementar la lógica en bash ni en otro script: el contrato está en `handoff.py`.
- No pasar la tarea ni rutas de handoffs como argumentos de un comando.
- No usar la API de opencode (`POST /api/session`) ni `opencode run`: el disparo es la tool `subagent`.
- No borrar con globs, recursivo ni fuera de `.opencode/handoffs`.
- No usar la tool `question` desde el subagente: el invocador no puede contestarle en el medio.
- No lanzar en segundo plano (`background: true`) sin imprimir antes el aviso del riesgo, y no inventar un
  informe cuando el resultado todavía está pendiente.
- No borrar la hoja al terminar: queda para el barrido del próximo `/hand-off`.
- No commitear, no pushear, no borrar sesiones.
- No tocar archivos del proyecto más allá de la hoja nueva (y de las aprobadas en el barrido).

## Origen

Herramienta propia: la construyeron **Calisto** (Daniel Zipitría) y **Bj** (`agent-builder`) el 2026-11-06 y la
rearquitectaron el 2026-11-07. **Sin repos externos, sin código vendorizado, sin dependencias de terceros**:
sólo stdlib de Python 3.8+ y la tool `subagent` de opencode. El diseño usa `.opencode/handoffs/` como hoja de
ruta, disparo por subagente con round-trip por `sessionID`, retención de 14 días / 10 archivos y datos del
humano por archivo (nunca por `argv`). Las decisiones y los gates quedaron en `BITACORA.md` y en
`documents/reports/cyberseguridad-2026-11-06-*.md`. Licencia MPL-2.0 (artefacto funcional).
