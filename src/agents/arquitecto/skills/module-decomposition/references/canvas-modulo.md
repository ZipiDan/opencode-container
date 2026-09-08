# Canvas de módulo (una página por módulo)

Adaptado de: ddd-crew/bounded-context-canvas (CC BY-SA 4.0),
https://github.com/ddd-crew/bounded-context-canvas — campos reformulados con
criterio propio en español; NO es texto verbatim del póster original.

Uso: copiar la plantilla a `docs/arquitectura/modulos/<slug>.md` y completarla.
Un módulo sin canvas no entra al diagrama C4 ni al plan de tareas.

## Plantilla

```markdown
# <Nombre del módulo>

Propósito (1 frase): <qué valor entrega, en términos del negocio>
Clasificación: core | supporting | generic

## Mensajes entrantes (contrato de entrada)
| Mensaje | Tipo (command/query/event) | Emisor | Qué espera |
|---------|--------------------------------|--------|------------|

## Mensajes salientes (contrato de salida)
| Mensaje | Tipo (command/query/event) | Receptor | Qué entrega |
|---------|------------------------------|----------|-------------|

## Lenguaje ubicuo
| Término | Definición (1 línea) | Colisiona con <módulo> si... |
|---------|----------------------|------------------------------|

## Reglas del módulo (máx. 5)
- <invariante que este módulo garantiza, solo este módulo>

## Supuestos
- <qué se asume del entorno y de otros módulos; si se rompe, reabrir ADR>

## Métricas de salud
- <cómo se sabe que el módulo va bien: latencia p95, tasa de error, lead time...>
```

## Notas de llenado

- Mensajes in/out = **el contrato**: cambiar uno es cambiar la arquitectura →
  ADR o nueva versión del contrato; nunca edición silenciosa del canvas de un
  módulo ya aprobado.
- Clasificación: `core` = ventaja competitiva (acá se invierte); `supporting` =
  necesario sin diferenciación; `generic` = comprable — no construirlo.
- En Lenguaje ubicuo anotá explícitamente las palabras que significan distinto
  en otro módulo (esa columna alimenta el diagrama de relaciones).
- Máximo 5 reglas: si necesitás más, el módulo esconde un corte pendiente
  (volver al paso 2 de la skill).
