# Prueba escrita del triaje

En todos los casos se usa verification-before-completion. Las skills del repo
pueden sustituir prácticas equivalentes. No se han lanzado agentes para esta prueba.

| Encargo y condiciones explícitas | Nivel y motivo literal | Roles | Skills adicionales | Evidencia esperada |
|---|---|---|---|---|
| Cambiar el color de un botón, valor exacto y ubicación conocida, un token | N0: un valor sin comportamiento que discutir | Coordinador inline | Ninguna | Diff y comprobación visual del color |
| Corregir una errata, una palabra en texto estático | N0: una línea sin comportamiento que discutir | Coordinador inline | Ninguna | Texto corregido y diff |
| Añadir un endpoint con tests, contrato y módulo existentes, sin auth/SQL ni diseño abierto | N2: comportamiento entendido; sus tests son parte de una tarea | Implementador + revisor nuevo | test-driven-development | Prueba falla antes, pasa después, respuesta del endpoint y SHA revisado |
| Bug con síntoma claro en tres archivos del mismo comportamiento, sin área delicada | N2: varios archivos no implican varios módulos/tareas | Implementador + revisor nuevo | systematic-debugging, test-driven-development | Reproducción previa y prueba de regresión sobre causa verificada |
| Migración de base de datos con diseño ya aprobado y una tarea | N3: migraciones son delicadas | Planificador + implementador-delicado + revisor nuevo | test-driven-development para el cambio de comportamiento | Invariantes y prueba de migración en datos sintéticos; sin producción |
| Feature con requisitos ambiguos que se descompone en varias tareas | N3: criterios ausentes y diseño abierto | Planificador + implementador + revisor nuevo | brainstorming, writing-plans, test-driven-development | Diseño y plan revisables, aprobación antes de escribir, tests por criterio |
