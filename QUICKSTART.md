<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# QUICKSTART — opencode-container

Guía rápida: de cero a opencode corriendo en contenedor en unos minutos.
El detalle completo está en [`README.md`](README.md); la gramática de flags, en
[`PARAMETERS.md`](PARAMETERS.md).

## 1. ¿Qué es?

- Launcher que corre [opencode](https://opencode.ai) dentro de un contenedor
  Debian aislado por proyecto (Podman), con toolchains y agentes ya dispuestos.
- No reemplaza a opencode: lo acompaña. Tu proyecto se monta en `/workspace`.

¿Preferís una vista en imágenes? **[Presentación del proyecto](https://www.cilan.com.uy/blog/opencode-container)**.

## 2. Prerrequisitos

- [Podman](https://podman.io/) instalado → `podman --version`
- Linux o macOS

## 3. Instalación (30 segundos)

```bash
git clone https://gitlab.com/dzipitria/opencode-container.git
cd opencode-container/src
chmod +x ./opencode.sh
# opcional recomendado: lanzarlo desde cualquier carpeta
ln -s "opencode.sh" ~/.local/bin/opencode.sh  # O una carpeta que este en tu Path
```
*Nota*: Si la imagen no está creada en la primera ejecucución genera la imagen.
      Pero yo tengo la mala costumbre de generarla a mano.

## 4. Construir la imagen del contenedor

La primera vez tarda unos minutos (Debian + toolchains + opencode + tools).

```bash
./opencode.sh --rebuild        # build con caché (reutiliza capas)
```

- Alternativas: `--update` (desde cero + pull de la base) y `--renew` (desde
  cero, reemplaza la imagen anterior sólo si el build es exitoso).
  `--renew` y `--rebuild` son mutuamente excluyentes.
- Atajo: si la imagen no existe, el primer arranque la construye solo
  (`check_image`); igual conviene hacerlo explícito para no mezclar "esperar el
  build" con "entrar a opencode".
- Verificación: `podman images | grep opencode`

## 5. Desplegar agentes, skills, estilos y comandos

El código vive en el repo; para que opencode los vea hay que copiarlos a la
config global (`~/.config/opencode/`), que el contenedor monta y que también
lee un opencode tradicional.

```bash
./agents_update.sh --check   # ver qué cambiaría, sin escribir nada
./agents_update.sh           # aplicar (pide confirmación por etapa)
```

Reiniciá opencode después. 

**Sólo opencode tradicional** (no el contenedor):
las tools (`md2pdf`, `landlock_rosh`) se instalan aparte con

`./agents_update.sh --install-tools`.

*Nota*: Cuando usas el contenedor esas herramientas ya vienen incluidas.

## 6. Credenciales (API key opcional)

```bash
./src/opencode.sh --credentials-set opencode-go   # prompt oculto; escribe
                                                  # share/auth.json (0600)
```

- La key canónica se siembra en cada proyecto al arrancar; las OAuth no se
  comparten (sus refresh tokens rotan).
- ¿Ya tenés un login hecho en la TUI de un proyecto y querés compartirlo?
  `./src/opencode.sh --credentials-export /ruta/al/proyecto`.

## 7. Primer arranque

Si has creado el link de acceso en el path último paso del paso 3
```bash
opencode.sh /ruta/a/tu/proyecto           # web, puerto 4096 (default)
opencode.sh /ruta/a/tu/proyecto --tui     # terminal interactiva
```

- Es **obligatorio** pasarle una carpeta local: el contenedor monta tu
  directorio y trabaja sobre él (como `/workspace`).
- Modo web: corre detached, imprime el password (usuario `opencode`) y un link
  de pairing de un solo uso. Abrí `http://127.0.0.1:4096`.
- Detener: `./src/opencode.sh --kill 4096`. Logs: `podman logs -f opencode-4096`.

### Entorno por defecto: web o TUI (`OPENCODE_GUI`)

En vez de pasar `--tui` o `--web` en cada arranque, podés fijar en tu máquina
qué entorno de trabajo querés usar, con la variable de entorno `OPENCODE_GUI`
(los flags `--tui`/`--web` siguen ganando si los pasás en un arranque puntual):

```bash
OPENCODE_GUI=tui  opencode.sh /ruta/a/tu/proyecto   # ese arranque, en TUI
OPENCODE_GUI=web  opencode.sh /ruta/a/tu/proyecto   # ese arranque, en web
export OPENCODE_GUI=tui                             # valor por defecto de tu shell
```

Valores válidos: `tui` o `web`. Default: `web` (un valor inválido avisa y usa `web`).

**Para hacerla permanente**, agregá el `export` al archivo de configuración de
tu shell y volvé a abrirla (o hacé `source` del archivo):

| Shell | Archivo | Línea a agregar |
|-------|---------|-----------------|
| bash | `~/.bashrc` | `export OPENCODE_GUI=tui` |
| zsh | `~/.zshrc` | `export OPENCODE_GUI=tui` |
| fish | `~/.config/fish/config.fish` | `set -gx OPENCODE_GUI tui` |

Verificá que quedó seteada con `echo "$OPENCODE_GUI"`.

## 8. Dos ajustes únicos de la web

Son molestias del cliente web de opencode (no del launcher); la TUI no las
tiene. Se resuelven una sola vez por puerto:

1. **La carpeta del proyecto no aparece** → ícono de proyectos → *Proyectos* →
   agregar uno nuevo → escribí `/workspace` (la ruta *dentro* del contenedor) →
   *Seleccionar carpeta*.
2. **No se ve el selector de agentes** → *Ajustes* → activar **Mostrar agente**.
   Mientras esté apagada, todo corre con `build` y los agentes instalados
   parecen no existir.

¿Querés verlo de forma gráfica, con capturas de cada clic? Está explicado con
imágenes en el README, sección **[Problemas conocidos](README.md#problemas-conocidos)**.

## 9. Comandos del día a día

| Acción | Comando |
|--------|---------|
| Listar contenedores | `opencode.sh --ps` |
| Detener un contenedor | `opencode.sh --kill 4096` |
| Links de acceso nuevos | `opencode.sh --pair 4096` |
| Reconstruir imagen (caché) | `opencode.sh --rebuild` |
| Actualizar imagen | `opencode.sh --renew` |
| Sincronizar credenciales en un contenedor vivo | `opencode.sh --sync-credentials 4096` |
| Sync de agentes/skills/comandos | `./agents_update.sh` |

## 10. Problemas típicos

- **Puerto ocupado** → `opencode.sh /ruta/proyecto --port 4097`.
- **El contenedor no ve un servicio del host en `127.0.0.1`** (BD local, proxy
  LLM) → agregar `--network-host`. Rompe el aislamiento de red: úsalo sólo si
  hace falta.
- **Puertos extra** (dev server dentro del contenedor) →
  `--extra-ports 3000,8080` (aplica en web y TUI).
- **Logs** → `podman logs -f opencode-<puerto>`; contenedores →
  `opencode.sh --ps`.
- **Imagen rota/desactualizada** → `cd <carpete_donde_clonaste>/src; ./opencode.sh --renew`.
- **Quiero una versión nueva de opencode** → `cd <carpete_donde_clonaste>/src; ./opencode.sh --renew`.

## 11. Siguientes pasos

- [`README.md`](README.md) — especificaciones técnicas, montajes, variables.
- [`PARAMETERS.md`](PARAMETERS.md) — referencia formal de los parámetros.
- [`CHANGELOG.md`](CHANGELOG.md) — qué cambió en cada versión.
- [`src/agents/README.md`](src/agents/README.md) — registro y actualización de
  los agentes personalizados.
