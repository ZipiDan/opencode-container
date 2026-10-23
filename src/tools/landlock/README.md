# Landlock read-only shell — `landlock_rosh` 1.9.0

Launcher que ejecuta una shell o un comando **dentro de una jaula read-only
impuesta por el kernel** (Landlock + seccomp). Es un binario estático
`x86_64-unknown-linux-musl` (~590 KB), sin dependencias en el servidor. Corre
como root o como usuario normal y **también restringe a root**: una vez sellado,
el proceso y todos sus hijos no pueden escribir fuera de los paths permitidos.

> **Alcance real:** es una barrera de **filesystem**. Bloquea escrituras,
> borrados, `chmod`/`chown`/`setxattr` y `truncate` directos. **No** bloquea
> cambios mediados por daemons (`systemctl`, `docker`, `gluster`, `virsh`),
> señales (`kill`), netlink (`ip`, `iptables`), `utime` (`touch -m`) ni
> escrituras en `/tmp`/`/var/tmp`. Ver [Límites](#límites-y-modelo-de-amenaza).

> **Uso en el contenedor:** el binario se hornea en la imagen solo como
> *payload* para copiarlo a servidores remotos. No se ejecuta localmente como
> sandbox ni genera log local; solo se usan `--version`/`--print-ssh-line` como
> helpers del controlador y tests de build. La auditoría y el sandbox viven en
> el target remoto.

---

## Requisitos

- Linux con Landlock ABI ≥ 1 (kernel ≥ 5.13).
- Para bloquear `IOCTL_DEV` hace falta ABI ≥ 5 (kernel ≥ 6.2).
- Kernel < 5.13: fallback automático a **bubblewrap** (`bwrap`) con mounts
  read-only. Requiere `bwrap` instalado en el target.
- Arquitectura: **x86_64**. No hay binarios aarch64 en v1.

Verificación rápida en el target:

```bash
uname -r
cat /proc/sys/kernel/osrelease
python3 -c "import ctypes; print('Landlock ABI:', ctypes.CDLL(None).syscall(444,0,0,1))"
cat /sys/kernel/security/lsm    # debe listar landlock
```

---

## Uso

```bash
# Shell interactiva read-only (prompt con "(rosh)")
landlock_rosh

# Comando puntual; `-c` gana sobre SSH_ORIGINAL_COMMAND
landlock_rosh -c "df -h"

# El caso del agente: sshd pone el comando en SSH_ORIGINAL_COMMAND
SSH_ORIGINAL_COMMAND="gluster volume status" landlock_rosh

# Solo auditoría: SIN sandbox (permite escribir), deja traza en el log
landlock_rosh --log-only -c "systemctl restart nginx"

# Deshabilitar auditoría en esta invocación
landlock_rosh --no-log -c "uptime"
```

`--log-only` y `--no-log` son incompatibles.

### `-c` vs `SSH_ORIGINAL_COMMAND`

`-c "comando"` existe para el contrato estándar de shell (`shell -c`) y para la
invocación manual. Precedencia:

1. `-c "comando"` (argumento).
2. `SSH_ORIGINAL_COMMAND` (lo setea sshd en el modo `command=`).
3. Shell interactiva.

Sin `-c`, un usuario cuyo login shell es `landlock_rosh` no podía ejecutar
comandos no interactivos (`ssh host "df -h"` abría una shell interactiva y el
comando se perdía). Con `-c` funciona.

---

## Integración por SSH

### Escenario 1 — login shell del usuario

El binario es el shell de login de un usuario (recomendado: un usuario UID 0
dedicado, para lectura privilegiada sin `sudo`):

```bash
# En el target, como root
landlock_rosh --install-shell          # copia a /usr/local/bin + /etc/shells
useradd -m -s /usr/local/bin/landlock_rosh rosh
usermod -o -u 0 -g 0 rosh              # UID/GID 0, sin duplicar la cuenta root
passwd rosh

# Clave del agente en /home/rosh/.ssh/authorized_keys (sin command=;
# el login shell ya impone la jaula)
```

`ssh rosh@host "df -h"` ejecuta `landlock_rosh -c "df -h"` y el comando corre
bajo la jaula. `ssh -t rosh@host` da una shell interactiva read-only.

> `--install-shell` también crea `/usr/local/bin/landlock_rosh-nolog`, un
> wrapper que invoca `--no-log`. Si no querés ofrecer esa variante, borralo o
> dejalo en modo `0700`.

### Escenario 2 — `command=` en `authorized_keys` (agente de IA)

Es el modo que **no puede evitar el cliente**: sshd ignora el comando pedido y
ejecuta siempre el launcher; el comando original llega en
`SSH_ORIGINAL_COMMAND`.

```bash
# Generar la línea para la clave del agente (no toca nada)
landlock_rosh --print-ssh-line --pubkey ~/.ssh/id_ed25519.pub
# restrict,no-pty,...,command="/usr/local/bin/landlock_rosh" ssh-ed25519 AAAA... usuario@host

# Variante solo auditoría (permite escribir, deja traza)
landlock_rosh --print-ssh-line --mode log --pubkey ~/.ssh/id_ed25519.pub
# restrict,no-pty,...,command="/usr/local/bin/landlock_rosh --log-only" ssh-ed25519 AAAA... usuario@host
```

Agregar la línea a `~/.ssh/authorized_keys` del usuario del agente. Si la misma
clave ya estaba autorizada **sin** `command=`, hay que **reemplazar** esa línea,
no agregar otra: sshd usa la primera coincidencia y la clave sin restringir
seguiría funcionando. El script `pin-key.sh` de la skill `calisto-landlock`
hace ese reemplazo con backup y verificación.

`--install-ssh` (root) instala el shell y deja un **placeholder comentado** en
`/root/.ssh/authorized_keys`; no fija ninguna clave. Es solo una ayuda visual.

> **Consecuencia:** con `command=` la clave no puede usar `scp`, `sftp` ni
> `rsync` (el subsistema se reemplaza por el launcher). Para descargar archivos
> usar `ssh host 'cat /ruta'`; para subir, un canal de provisioning separado.

---

## Auditoría de comandos

Cada ejecución deja una entrada `start` + `end` (con exit code) en el backend
que se detecte:

| Orden | Artefacto | Backend |
|---|---|---|
| 1 | `/run/systemd/journal/socket` | **journald** (campos estructurados) |
| 2 | `/etc/logrotate.d/landlock_rosh` + `/var/log/landlock_rosh/` | **archivo** (texto + rotación) |
| 3 | ninguno | desactivado (silencioso) |

```bash
# Instalar el backend de archivo si no hay journald (root, sin sandbox)
landlock_rosh --install-log
landlock_rosh --uninstall-log      # idempotente; preserva logs históricos

# Consultar journald
journalctl -t landlock_rosh --since today
journalctl -t landlock_rosh LANDLOCK_SRC=10.1.0.5 LANDLOCK_EXIT!=0
```

Formato del backend archivo:

```
2026-08-24 14:03:22-03:00 | host | user(uid) | src=10.1.0.5:52234 | mode=landlock-abi6 | start | cmd="gluster volume status"
2026-08-24 14:03:22-03:00 | host | user(uid) | src=10.1.0.5:52234 | mode=landlock-abi6 | end | cmd="gluster volume status" | exit=0
```

- `src=` sale de `SSH_CONNECTION`; `src=local` en TTY/consola.
- Los comandos se sanitizan (newlines escapadas) y se recortan a 8 KB.
- El fd del log se abre **antes** del sandbox; el usuario encerrado solo puede
  hacer append. `truncate(2)`/`ftruncate(2)` están bloqueados por seccomp.
- **`--log-only` no es una barrera:** no hay sandbox, el proceso puede escribir
  el log o `authorized_keys`. Es una traza, no un control.

### Desactivar auditoría

- Por invocación: `--no-log` o `LANDLOCK_NO_LOG=1`.
- Permanente por clave: `command="/usr/local/bin/landlock_rosh --no-log"`.
- Login shell: wrapper `landlock_rosh-nolog`.

### Rotación (backend archivo)

`--install-log` escribe `/etc/logrotate.d/landlock_rosh`: `daily` o
`maxsize 20M` (lo primero), `rotate 31`, `compress`. Valida con `logrotate -d`.

---

## Paths escribibles

La jaula permite escritura **solo** en:

```text
/tmp
/var/tmp
/dev/null  /dev/zero  /dev/tty   (solo write/truncate, no create/remove)
```

Override opcional sin recompilar (separado por `:`):

```bash
LANDLOCK_WRITABLE_PATHS=/srv/tmp landlock_rosh -c "..."
LANDLOCK_WRITABLE_NODES=/dev/null:/dev/tty landlock_rosh -c "..."
```

En el modo `command=` de `authorized_keys`, las variables se pueden fijar en la
propia línea:

```
command="LANDLOCK_WRITABLE_PATHS=/srv/tmp /usr/local/bin/landlock_rosh" ...
```

---

## Límites y modelo de amenaza

Landlock es un LSM de **filesystem**. Lo que **sí** bloquea (probado en kernel
6.12 / ABI 6):

- `open` para escritura, `creat`, `mkdir`, `mknod`, `symlink`, `rename`,
  `unlink`, `truncate` por path, fuera de los paths permitidos.
- `chmod`, `fchmod`, `fchmodat`, `chown`, `fchown`, `lchown`, `fchownat`,
  `setxattr`, `lsetxattr`, `fsetxattr` (seccomp, porque Landlock no los cubre).
- `truncate(2)`/`ftruncate(2)` (seccomp; también dentro de `/tmp`).
- Escrituras en `procfs`/`sysfs` (Landlock las media como filesystem).
- `ioctl` sobre dispositivos de bloque/carácter en ABI ≥ 5 (por eso
  `smartctl`, `storcli`, `nvme` pueden fallar; es intencional).

Lo que **no** bloquea:

| Vector | Por qué | Riesgo |
|---|---|---|
| `systemctl`, `docker`, `podman`, `virsh`, `gluster` | Hablan con daemons por sockets; el daemon escribe fuera del sandbox | Cambios de servicio, reboots |
| `kill`, `pkill` | Señales fuera del alcance de Landlock | Detener procesos |
| `ip`, `iptables`, `nft` | Netlink no es filesystem | Cambios de red/firewall |
| `touch -m` | `utime` no está en seccomp y Landlock no lo cubre | Cambio de mtime |
| `/tmp`, `/var/tmp` | Escribibles por diseño | Estado efímero, no persistente |
| `--log-only` | Sin sandbox | Cualquier cambio; log tamperable |

**Conclusión:** usar `landlock_rosh` cuando el objetivo es que el agente **no
escriba archivos** ni edite configuración. No alcanza para impedir que un
agente deliberado reinicie un servicio o toque la red. Para eso hace falta una
allowlist de comandos o un modo write-guarded (no incluido en 1.9.0).

---

## Kernel < 5.13: fallback bubblewrap

Si Landlock no existe (ENOSYS), el binario usa `bwrap` con mounts read-only:

| Montaje | Modo |
|---|---|
| `/` | read-only |
| `/dev` | tmpfs propio; `/dev/null` y `/dev/zero` escribibles |
| discos reales (`/dev/sdX`, `/dev/nvme*`, megaraid) | bind read-only (para `smartctl`/`storcli`) |
| `/sys` | read-only |
| `/proc` | procfs |
| `/tmp`, `/var/tmp` | tmpfs writable efímero |

Namespaces: `--unshare-user --unshare-ipc`. No se aísla pid, net ni uts.
`LANDLOCK_FORCE_BWRAP=1` fuerza el modo para testing.

Instalación de `bwrap` por distro: Debian/Ubuntu `apt-get install -y
bubblewrap`; Fedora `dnf install -y bubblewrap`; RHEL/Rocky/Alma
`dnf install -y epel-release && dnf install -y bubblewrap`; SUSE `zypper
install -y bubblewrap`; Arch `pacman -S --noconfirm bubblewrap`; Alpine `apk add
--no-cache bubblewrap`; Gentoo `emerge --ask=n sys-apps/bubblewrap`.

Limitaciones del modo bwrap: la protección es por VFS read-only, no por LSM;
no bloquea ioctls ni sockets de servicios; `/dev/tty` solo existe con TTY real;
job control desactivado en la shell interactiva (`--new-session`).

---

## Compilar

El crate vive en `crate/`; el binario empaquetable sale a `../landlock_rosh`
(`src/tools/landlock_rosh`):

```bash
cd crate
./build_static.sh
# OK -> /.../src/tools/landlock_rosh (ELF static-pie x86_64)
```

Prerequisitos: Rust estable + `rustup target add x86_64-unknown-linux-musl` +
`musl-tools` (provee `musl-gcc`).

## Tests

```bash
cd crate
cargo test          # unitarios (20)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
bash tests/regresion.sh   # requiere root, logrotate y bubblewrap
```

La suite cubre modo comando, `-c`, `--log-only`, `--print-ssh-line`, sandbox,
inyección de log, bwrap, interactivo y `--install-shell`/`--install-ssh`.
Checksum del binario:

```bash
cd src/tools/landlock && sha256sum -c SHA256SUMS
```

## Documentación relacionada

- `DEVELOPMENT.md` — arquitectura, invariantes y guía para agregar features.
- `PROVENANCE.md` — origen, versiones, build y checksum.
