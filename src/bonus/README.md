<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# bonus — ayudas para casos puntuales

Esta carpeta guarda herramientas que **no son parte del flujo normal** del launcher: se usan sólo
cuando el entorno no cumple un prerrequisito y hay que destrabarlo a mano.

## `setup-subuid.sh`

Provisiona los rangos `subuid`/`subgid` que Podman necesita para correr contenedores rootless. Sólo
hace falta en un caso muy poco frecuente: un host donde el usuario no tiene esos rangos en
`/etc/subuid` y `/etc/subgid` (típico de equipos de dominio o de instalaciones viejas). Ahí Podman
falla al crear el namespace y el launcher no llega a arrancar.

**No es un problema de opencode ni del contenedor**: es un prerrequisito de Podman. El script es una
ayuda para crear los IDs de usuario y de grupo cuando faltan, y nada más: no corre Podman como root,
no toca los datos del proyecto y no borra nada.

```bash
sudo ./src/bonus/setup-subuid.sh <usuario>             # crea los rangos que falten
sudo ./src/bonus/setup-subuid.sh <usuario> --dry-run   # muestra qué haría, sin escribir
```

Necesita root porque escribe archivos del sistema (`/etc/subuid`, `/etc/subgid`). Si `podman` ya
funciona en el host, no lo necesitás.
