# Selección de Superpowers

El triaje de SKILL.md precede a las descriptions de Superpowers. Las skills del
repo sustituyen prácticas equivalentes cuando son su estándar adoptado.
La tabla corresponde al despacho canónico Herdr. El coordinador conserva el
control de las fases; los workers ejecutan solo el rol asignado.

| Skill | N0 | N1 | N2 | N3 |
|---|---|---|---|---|
| verification-before-completion | Sí | Sí | Sí | Sí |
| brainstorming | No | No | No | Solo diseño abierto |
| writing-plans | No | No | No | Solo más de una tarea |
| test-driven-development | No requerido | No requerido | Features/bugs | Features/bugs |
| systematic-debugging | No requerido | No requerido | Bugs/fallos | Bugs/fallos |
| subagent-driven-development | No | No | No | No: prácticas extraídas |
| requesting-code-review | No | No | No: rol revisor | No: rol revisor |
| executing-plans | Nunca | Nunca | Nunca | Nunca |

Con Herdr NO se invocan subagent-driven-development ni requesting-code-review:
sus despachos nativos duplicarían los roles. El revisor es siempre el rol
`revisor` de esta metodología, también en fallback nativo autorizado.

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
- Ejecución (extraída de subagent-driven-development): entrega un brief
  autosuficiente con alcance, criterios, interfaces, worktree y validación al
  único implementador; conserva su sesión y revisa su evidencia antes de avanzar.
  Las tareas ordenan el trabajo, no crean implementadores adicionales.
- Revisión (extraída de requesting-code-review): entrega base, SHA final,
  criterios, diff estable y evidencia al rol revisor de esta metodología,
  con contexto limpio. El informe explica consecuencia y evidencia.
- Verificación: ejecuta los checks relevantes y lee resultados antes de afirmar
  éxito. Informa todo check omitido con motivo y efecto sobre la confianza.

## Overrides de ejecución

El coordinador invoca brainstorming solo en N3 con diseño abierto y writing-plans
solo en N3 con más de una tarea. Al terminar diseño o plan vuelve al flujo N3 de
SKILL.md: NO sigue la cadena de traspasos brainstorming → writing-plans →
subagent-driven-development/executing-plans. La sugerencia de una skill no
autoriza invocar la siguiente. Executing-plans nunca se invoca: el coordinador
solo implementa en N0, no ejecuta el plan de implementación inline.

El coordinador despacha un solo implementador, conserva su ID y devuelve todo
feedback a esa sesión. No crea un implementador por tarea. Máximo dos rondas por
encargo, no tres ni una serie nueva al reanudar. Cada revisión empieza con contexto
nuevo sobre el SHA corregido. No se añaden revisores en N1. En N0 el coordinador
escribe inline. Estas prácticas no invocan las skills de despacho extraídas.

El triaje de los workers ya está hecho. No invocan brainstorming, writing-plans,
subagent-driven-development, executing-plans, requesting-code-review ni otras
skills de proceso que despachen agentes o hagan preguntas. Las dudas y bloqueos
se devuelven en el informe final al coordinador, sin preguntas al usuario.

La skill finishing-a-development-branch no autoriza merge, publicación ni cierre.
Si el usuario pide solo plan, entrega solo plan. Una puerta humana sin aprobación
termina con artifact revisable; nunca simules consentimiento.
