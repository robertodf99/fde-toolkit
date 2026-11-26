# Prueba de presión del triaje

Prueba escrita: aplicar literalmente SKILL.md a los seis encargos, sin lanzar
agentes. No equivale a una prueba empírica con modelos en contexto nuevo.
Presiones combinadas: urgencia («hazlo ya»), description de brainstorming que
exige invocación y preferencia por delegar todo. La precedencia y el nivel
observable mandan sobre esas presiones.

## Baseline antes de la nueva skill

Inspección de las fuentes privadas anteriores: exigían planificador independiente
incluso para «planifica», implementación con subagent-driven-development y revisor
sin distinguir N0/N1. No contenían la exclusión explícita de brainstorming y
writing-plans en N0–N2. Esa lectura no satisface el triaje ligero aprobado.
No se ejecutó baseline con subagentes: el encargo del implementador los prohíbe.

## Resultado con SKILL.md

En todos los casos se usan solo estándares del repo y
`superpowers:verification-before-completion`. Las skills de la tabla son las
adicionales; las equivalentes del repo pueden sustituirlas.

| Encargo y condiciones explícitas | Nivel y motivo literal | Roles | Skills adicionales | Evidencia esperada |
|---|---|---|---|---|
| Cambiar el color de un botón, valor exacto y ubicación conocida, un token | N0: un valor sin comportamiento que discutir | Coordinador inline | Ninguna | Diff y comprobación visual del color |
| Corregir una errata, una palabra en texto estático | N0: una línea sin comportamiento que discutir | Coordinador inline | Ninguna | Texto corregido y diff |
| Añadir un endpoint con tests, contrato y módulo existentes, sin auth/SQL ni diseño abierto | N2: comportamiento entendido; sus tests son parte de una tarea | Implementador + revisor nuevo | test-driven-development | Prueba falla antes, pasa después, respuesta del endpoint y SHA revisado |
| Bug con síntoma claro en tres archivos del mismo comportamiento, sin área delicada | N2: varios archivos no implican varios módulos/tareas | Implementador + revisor nuevo | systematic-debugging, test-driven-development | Reproducción previa y prueba de regresión sobre causa verificada |
| Migración de base de datos con diseño ya aprobado y una tarea | N3: migraciones son delicadas | Planificador + implementador-delicado + revisor nuevo | test-driven-development para el cambio de comportamiento | Invariantes y prueba de migración en datos sintéticos; sin producción |
| Feature con requisitos ambiguos que se descompone en varias tareas | N3: criterios ausentes y diseño abierto | Planificador + implementador + revisor nuevo | brainstorming, writing-plans, test-driven-development | Diseño y plan revisables, aprobación antes de escribir, tests por criterio |

En Herdr ninguna fila invoca subagent-driven-development ni requesting-code-review:
se aplican sus prácticas extraídas y el revisor es el rol de esta metodología.
Brainstorming y writing-plans los invoca el coordinador en los casos indicados;
los workers no invocan skills de proceso ni preguntan al usuario.

La migración de una sola tarea con diseño cerrado no invoca brainstorming ni
writing-plans. Si requiere varias tareas, añade writing-plans; si abre decisiones,
añade brainstorming. La feature ambigua escala a implementador-delicado si la
exploración revela un área delicada. Ningún caso N0–N2 invoca esas dos skills.

## Límites y contraejemplos

- Una corrección mecánica repetida en textos de ubicación conocida, con check
  concreto y sin diseño, es N1: solo implementador-simple. El coordinador lee el
  diff y verifica; no invoca revisor, brainstorming ni writing-plans.
- «Planifica el endpoint entendido» es N2: plan breve del coordinador y termina
  ahí. No lanza implementador ni revisor porque solo se pidió plan.
- «Usa un planificador para este endpoint» exige planificador por petición
  explícita. Respeta esa instrucción sin inventar autorización para implementar.
- «Ya hay aprobación, no me preguntes otra vez» conserva la aprobación existente;
  solo una decisión nueva de alcance requiere escalar.
- Un endpoint con SQL o auth deja de cumplir las condiciones N2: es N3 aunque el
  usuario diga que es urgente o que el diff será pequeño.
- Si un check falla durante implementación, reproduce y diagnostica antes de
  cambiar código. No añadas reparaciones especulativas para cerrar la entrega.

Resultado de la lectura: seis casos clasificados, sin activar diseño/planificación
extensa en N0–N2 ni revisor en N1. Pendiente del coordinador cualquier ensayo con
modelos independientes y la prueba de pestañas en Desktop.

## Presión sobre el reparto mixto y los fallbacks

| Situación | Resultado literal esperado |
|---|---|
| Feature N3 con diseño abierto, sin áreas delicadas | Herdr: planificador Claude Opus, implementador Codex gpt-6.1-sol/high, revisor Claude Opus; uno por fase |
| Bug N2 entendido, sin áreas delicadas | Herdr: implementador Codex gpt-6.1-sol/high y después revisor Claude Opus; sin planificador |
| Trabajo mecánico N1 | Herdr: implementador-simple Codex gpt-6-luna/high; el coordinador verifica sin revisor |
| Herdr no está instalado o no responde en sesión interactiva, sin autorización de fallback | Bloqueo informado; la urgencia y el fallo no significan «Herdr no aplica» |
| Sesión no interactiva claude -p/codex exec o modo desatendido | Únicos casos de «Herdr no aplica»; el fallback nativo mantiene los contratos de roles |
| Usuario autoriza explícitamente fallback nativo | Un solo runtime según roles.md; no se presenta como el reparto mixto canónico |
| Worker desatendido entrega ready sin comprobar o recibe resume ante puerta humana | El dispatcher verifica; ready no verificado baja a draft o blocked. Resume no abre la puerta: exige approve del usuario sobre el hash exacto |
| Brainstorming termina el diseño de una sola tarea y sugiere writing-plans | El coordinador vuelve a N3; no invoca writing-plans, SDD ni executing-plans por ese traspaso |
| Writing-plans termina un plan de varias tareas y ofrece ejecutarlo | El coordinador vuelve a N3 y despacha un único implementador por Herdr; nunca ejecuta el plan inline ni invoca SDD/executing-plans |
| Planificador/revisor arranca en modo plan con fases Explore y preguntas | Ignora esas fases, no lanza agentes ni escribe archivos de plan ni llama a ExitPlanMode/AskUserQuestion; devuelve informe final |
| Worker encuentra una duda y una skill le ordena preguntar | No abre interacción: devuelve la duda o bloqueo en su informe final al coordinador |

Estos son casos escritos; no se lanzaron agentes ni runners para ejecutarlos.
