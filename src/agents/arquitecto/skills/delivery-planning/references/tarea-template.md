# Template de tarea (DoD + ruta exacta + verificación)

Patrón de granularidad adaptado de obra/superpowers `writing-plans` (MIT):
"múltiples tareas de minutos, no días". Copiar una por tarea a
`documents/arquitectura/plan/tareas/hito-NN/<slug>.md`.

```markdown
## Tarea <hito>.<nn> — <verbo + objeto, autoexplicada>

**Depende de:** <tarea o "—">
**Estimación:** <rango> (<supuestos en 1 línea>)

**Archivos exactos a crear/modificar:**
- `ruta/del/archivo.ext` — <qué cambia acá>
- `otra/ruta.test.ext` — <test que la cubre>

**Paso a paso (2–5 min cada paso):**
1. <acción micro, ejecutable sin pensar>
2. <...>

**Definition of Done (DoD)** — checklist de calidad, aplica a TODA tarea:
- [ ] Lint/format/typecheck del proyecto pasan
- [ ] Test que falla antes y pasa después (regresión de esta tarea)
- [ ] Los contratos del canvas del módulo siguen vigentes (o hay ADR nuevo)
- [ ] README/doc de la ruta actualizado si cambió una interfaz pública

**Verificación (cómo comprobarlo):**
<comando exacto + resultado esperado; p. ej. `pytest tests/x -k y` → 1 passed>
```

## Reglas de tamaño

- Si la tarea dice "implementar el módulo X": está mal, es un hito.
- Si la tarea no puede nombrar sus archivos: falta diseño — volver a
  `module-decomposition`, no improvisar.
- Rango de estimación con supuestos, nunca "3 días exactos" (guardrail del
  agente).
- DoD (calidad interna, todas las tareas) ≠ AC del hito (aceptación externa);
  ver `hito-template.md`.
- Dependencias: una tarea con más de 2 dependencias directas suele esconder un
  corte de hito mal hecho.
