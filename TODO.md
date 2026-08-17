# TODO — opencode.sh

Registro de problemas y nuevas características a incorporar al launcher.

**Formato**: `tipo | título | detalle | estado | fecha_ingreso | fecha_cierre`
**Estado**: `Pendiente` | `En progreso` | `Resuelto` | `Cancelado`
**Fecha ingreso**: `YYYY-MM-DD HH:MM` — alta de la tarea en el TODO.
**Fecha cierre**: `YYYY-MM-DD HH:MM` — fecha en que la tarea se resolvió o se canceló.

## Pendientes

| # | Tipo | Título | Detalle | Estado | Fecha ingreso | Fecha cierre |
|---|------|--------|---------|--------|---------------|--------------|
| 1 | Feature | Soporte de `OPENCODE_SERVER_PASSWORD` | Permitir setear una contraseña para el servidor web de opencode (solo entorno web, no TUI). Implementado con `--password`/`--user` en `opencode.sh` (precedencia flag > env del host). | Resuelto | 2026-08-10 17:55 | 2026-08-10 18:42 |
| 2 | Bug | Modelos desactualizados (models.json cacheado) | Bajo ciertas circunstancias, tanto la interfaz TUI como la web tienen problemas para actualizar los modelos existentes cuando cambian en opencode. Solución manual encontrada: `rm -f /root/.cache/opencode/models.json /root/.cache/opencode/models.json.*.tmp` y rearrancar el contenedor. Lo extraño: al arrancar un contenedor nuevo, `/root` no se persiste (se limpia en teoría), pero aparecen unos modelos en algunos proyectos y otros en otros, lo cual es raro. | Pendiente | 2026-08-10 17:55 | — |
