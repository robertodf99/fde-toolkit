# Selección de Superpowers

El triaje de SKILL.md precede a las descriptions de Superpowers. Las skills del
repo sustituyen prácticas equivalentes cuando son su estándar adoptado.

| Skill | N0 | N1 | N2 | N3 |
|---|---|---|---|---|
| verification-before-completion | Sí | Sí | Sí | Sí |
| brainstorming | No | No | No | Solo diseño abierto |
| writing-plans | No | No | No | Solo más de una tarea |
| test-driven-development | No requerido | No requerido | Features/bugs | Features/bugs |
| systematic-debugging | No requerido | No requerido | Bugs/fallos | Bugs/fallos |
| subagent-driven-development | No | No | No | Sí, con overrides |
| requesting-code-review | No | No | Sí | Sí |

## Prácticas extraídas

- Diagnóstico: reproduce el síntoma, recoge evidencia, formula una hipótesis y
  prueba la causa antes de corregir. Un fallo inesperado durante validación
  requiere diagnóstico; no encadenes parches especulativos.
- TDD: para features/bugs desde N2, observa una prueba de comportamiento fallar
  por el motivo esperado, implementa lo mínimo y vuelve a probar. Tipos y build
  no prueban el efecto. No añadas tests que solo repitan la implementación.
- Brainstorming: en N3 con diseño abierto explora restricciones y alternativas,
  concreta criterios y presenta diseño revisable. No reabras diseño ya aprobado.
- Writing-plans: en N3 con varias tareas ordena dependencias, alcance y validación
  por criterio en un artifact. Un brief N1/N2 lo redacta el coordinador.
- Revisión: entrega base, SHA final, criterios, diff estable y evidencia al
  revisor con contexto limpio. El informe explica consecuencia y evidencia.
- Verificación: ejecuta los checks relevantes y lee resultados antes de afirmar
  éxito. Informa todo check omitido con motivo y efecto sobre la confianza.

## Overrides de ejecución

El coordinador despacha un solo implementador, conserva su ID y devuelve todo
feedback a esa sesión. No crea un implementador por tarea. Máximo dos rondas por
encargo, no tres ni una serie nueva al reanudar. Cada revisión empieza con contexto
nuevo sobre el SHA corregido. No se añaden revisores en N1. En N0 el coordinador
escribe inline. Estos límites prevalecen sobre subagent-driven-development.

La skill finishing-a-development-branch no autoriza merge, publicación ni cierre.
Si el usuario pide solo plan, entrega solo plan. Una puerta humana sin aprobación
termina con artifact revisable; nunca simules consentimiento.
