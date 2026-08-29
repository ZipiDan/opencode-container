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
| 3 | Feature | Deploy de estilos CSS de `md2pdf` | Resuelto: los estilos viven en `src/tools/css-styles/`, se hornean en la imagen (`/usr/local/share/md2pdf/css-styles/`) y se despliegan a la config global (`~/.config/opencode/css-styles/`) con el nuevo stage `styles` de `agents_update.sh` (por defecto, `--no-styles` para omitir). Precedencia: config global del usuario > imagen. `md2pdf --list-styles` lista los detectados. | Resuelto | 2026-08-21 09:33 | 2026-08-21 17:05 |
| 4 | Feature | Proceso de auditoría de seguridad pre-vendorización de agentes | Crear un proceso del agente `cyberseguridad` que audite los repositorios descargados de internet **antes** de vendorizar el conocimiento a los agentes `sysadmin` y `cyberseguridad` (`src/agents/sysadmin/upgrade-heinzel.md`, `src/agents/cyberseguridad/upgrade-briiirussell.md`), chequeando exclusivamente código malicioso (prompt injection, comandos exfiltradores, ofuscación), con foco en los archivos `.md`/skills (patrón ToxicSkills/ClawHavoc), emitiendo un reporte de hallazgos y bloqueando/gateando la actualización de los agentes personalizados hasta que el operador decida. | Pendiente | 2026-08-24 13:13 | — |
| 5 | Review | Comandos taboo de opencode vs Landlock/Landlock_ROSH | Revisar la lista de comandos "taboo" que opencode maneja por defecto (restricciones de shell). Evaluar si realmente son efectivos o si es una lista incompleta/fragil. Explorar `landlock_rosh` (https://github.com/niclas3640/landlock_rosh) como mecanismo de sandboxing basado en Landlock LSM como alternativa más robusta y eficaz a la lista taboo — aislamiento a nivel kernel vs lista de strings. | Pendiente | 2026-08-24 14:00 | — |
| 6 | Bug | Web UI no arranca en /workspace por defecto | La interfaz web de opencode no se posiciona por defecto en `/workspace` al iniciar. El usuario debe navegar manualmente hasta esa carpeta en la interfaz web. Verificar si es issue de CWD en entrypoint.sh, de la config de opencode web, o del launch command. Afecta solo modo web, TUI funciona correctamente. | Pendiente | 2026-08-24 14:00 | — |
