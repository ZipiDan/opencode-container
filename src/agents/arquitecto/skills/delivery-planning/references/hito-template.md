<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: MPL-2.0 -->

# Template de hito (con criterios de aceptación verificables)

Copiar a `documents/arquitectura/plan/PLAN.md` como sección por hito. Un hito es un
corte de integración con AC verificables, no una fecha en el calendario.

```markdown
## Hito NN — <nombre corto, un resultado>

**Objetivo (1 frase):** <qué puede hacer el sistema al cerrar este hito que
antes no podía>
**Clase MoSCoW del entregable principal:** Must | Should | Could
**Dependencias:** <hitos/ADRs/módulos que deben estar cerrados antes>

### Criterios de aceptación (AC)
- [ ] <observable: comando que pasa, demo que se muestra, métrica que se
      cumple — verificable SIN discusión, sin "está bonito">
- [ ] <cada AC se mapea a ≥1 tarea del pack>

### Criterio de salida del hito
<Todo AC verificado + los contratos de módulo tocados actualizados en su
canvas + ADRs nuevos (si hubo desviación del diseño)>

### Riesgos del hito (en Consequences, no aparte)
<qué lo puede derrubar y qué se hace al respecto>
```

## Reglas

- 3–7 AC por hito; más, y es un subproyecto disfrazado (volver al paso 2).
- AC redactados en tercera persona observable: "el endpoint responde 201 con
  id", no "el usuario queda conforme".
- Si un AC necesita leer `design.md` para entenderse, está mal escrito: el AC
  se autoexplica.
- AC ≠ DoD: el DoD vive en cada tarea del pack (ver `tarea-template.md`) y no
  se copia acá.
