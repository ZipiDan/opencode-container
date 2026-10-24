<!-- SPDX-FileCopyrightText: ddd-crew -->
<!-- SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto) -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Vocabulario de relaciones entre módulos

Aclaración: esta referencia usa **solo los NOMBRES** de los patrones de
relación (para etiquetar aristas del mapa C4); las descripciones son propias,
en español, no traducciones de ningún póster o texto ajeno.

Fuente de los nombres: https://github.com/ddd-crew/context-mapping (CC BY-SA
4.0) · https://martinfowler.com/bliki/BoundedContext.html (referencia).

| Nombre | Cuándo va sobre la arista A → B |
|--------|---------------------------------|
| Partnership | Ambos co-diseñan el contrato: éxito compartido, cambios coordinados. |
| Shared Kernel | Fragmento chico del modelo compartido y versionado en conjunto; lo mínimo indispensable. |
| Customer-Supplier | A necesita a B y puede influir en su roadmap (negociado); B prioriza. |
| Conformist | A no puede influir en B y adopta su modelo tal cual (API de un SaaS). |
| Anticorruption Layer (ACL) | A traduce el modelo de B a su lenguaje antes de usarlo; protege al core. |
| Open Host Service (OHS) | B expone un protocolo común para cualquier consumidor, sin trato uno-a-uno. |
| Published Language | El OHS habla un lenguaje estándar documentado que A consume sin traducir. |

## Reglas de uso

- Toda arista entre módulos del mapa C4 lleva UN nombre de esta lista. Si
  ninguna calza, o falta un patrón (raro) o el modelo está mal: abrir ADR.
- Conformist implica deuda: se anota en los riesgos/consecuencias de
  `design.md`. Las opciones sanas frente a sistemas externos son ACL o
  OHS+Published Language.
- El nombre implica esfuerzo: ACL y OHS cuestan más que Conformist — que el
  ranking de atributos de calidad justifique el gasto.
- En el diagrama, el nombre va sobre la flecha (p. ej.
  `Facturación -->|ACL| Legado`).

## Ejemplo de lectura

"Ventas → Inventario: Customer-Supplier" significa que Ventas negocia cambios
de contrato con Inventario y este prioriza sus requests; si la arista dijera
"Conformist", Inventario manda y Ventas se adapta — anótalo como riesgo.
