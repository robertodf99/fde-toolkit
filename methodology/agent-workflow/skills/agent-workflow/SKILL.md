---
name: agent-workflow
description: Use when el usuario pide planificar o ejecutar desarrollo con la metodología multiagente, o se recibe un encargo de uno de sus roles.
---

# Metodología multiagente

Escala el proceso al alcance y las consecuencias. La misma fuente sirve para
Claude Code, Codex y Herdr Core. Si el primer mensaje asigna un rol, ejecuta solo
ese rol y devuelve su contrato de entrega; no orquestes agentes.
## Reparto por defecto

El coordinador es la sesión del usuario. Planificador y revisor usan **Claude
Opus**; los implementadores usan **Codex**: gpt-6-luna/high para mecánico,
gpt-6.1-sol/high para normal y gpt-6.1-sol/xhigh para delicado.
El despacho canónico es [Herdr](references/herdr-hc.md): ejecuta en orden los
roles que pide el triaje, uno por fase, esperando su resultado antes de la siguiente.
El despacho nativo usa un solo runtime como fallback no interactivo:
`claude -p`, `codex exec` o modo desatendido («Herdr no aplica»).
En sesión interactiva, Herdr no instalado o sin respuesta = bloqueo informado,
sin fallback automático.
## Precedencia y selección de skills

Instrucciones del usuario > AGENTS.md / CLAUDE.md del repo > esta skill >
Superpowers. Esta skill decide qué Superpowers aplican. En N0–N2 **NO invoques
brainstorming ni writing-plans**, aunque sus descriptions exijan invocarlas.
Las skills propias del repo para diagnóstico, pruebas o validación prevalecen.
Respeta el nivel fijado por el usuario y las aprobaciones vigentes.
## Triaje del coordinador

Lee primero el encargo y las instrucciones del repo. Clasifica por criterios
observables, no por número de líneas ni estimación del tracker:

| Nivel | Condición | Ejecución |
|---|---|---|
| N0 | Una línea o valor, sin cambio de comportamiento que discutir | Coordinador inline |
| N1 | Requisito completo, ubicación conocida, efecto local, sin diseño ni áreas delicadas, check concreto | Solo implementador-simple |
| N2 | Comportamiento entendido o bug con síntoma claro, sin diseño abierto ni áreas delicadas | Implementador + revisor |
| N3 | Área delicada, diseños abiertos, varios módulos o tareas independientes, criterios ausentes, o petición explícita de planificador | Planificador + implementador o implementador-delicado + revisor |

Un cambio entendido repartido en varios archivos del mismo comportamiento no
implica varios módulos ni tareas. Pruebas de un endpoint son parte de su tarea.
«Planifica» en N1/N2 significa plan breve del coordinador, sin planificador
independiente. Solo «usa un planificador» exige ese rol fuera de N3.
Ante duda elige el nivel inferior, salvo área delicada; una vez fijado, solo
escala hacia arriba. Autenticación, SQL, migraciones, seguridad, operaciones
irreversibles y despliegue son delicados, además de lo que marque el repo.
## Flujo por nivel

- **N0:** edita inline y verifica el efecto concreto.
- **N1:** el coordinador prepara un brief con criterio y check; despacha a
  implementador-simple. Sin revisor: el coordinador lee el diff y verifica.
- **N2:** brief y plan breve del coordinador, implementador, reproducción antes
  de corregir bugs, pruebas de comportamiento y revisor con contexto nuevo
  sobre el SHA final. No se requiere planificador independiente.
- **N3:** planificador independiente. El coordinador usa brainstorming **solo**
  con diseño abierto y writing-plans **solo** si hay más de una tarea. Al acabar
  diseño o plan vuelve a este flujo N3: **NO sigue la cadena de traspasos**
  brainstorming → writing-plans → SDD/executing-plans. Presenta artifact si falta
  aprobación; conserva las vigentes. Implementador-delicado en áreas delicadas,
  implementador en los demás casos. Revisor nuevo sobre cada SHA corregido.

En «planifica» entrega el plan y termina sin implementar, sea cual sea el nivel.
Usa verification-before-completion siempre. En N2/N3 usa test-driven-development
para features/bugs y systematic-debugging para bugs o fallos inesperados.
Con Herdr **NO invoques subagent-driven-development ni requesting-code-review**;
usa sus [prácticas extraídas](references/superpowers.md). El revisor es siempre el
rol revisor de esta metodología. **Executing-plans nunca**: el coordinador solo
implementa en N0.
## Límites de ejecución

Un solo implementador escribe; conserva su sesión para el feedback. Máximo dos
rondas de reparación por encargo, persistidas al reanudar. Cada revisión usa
contexto nuevo y diff estable; no revises mientras cambia el código. No reemplaces
al implementador ni reinicies rondas para eludir el límite. Al agotarlo, escala
los hallazgos pendientes con evidencia y disposición individual.

Los roles no crean agentes, publican, modifican el tracker ni hacen merge.
El coordinador tampoco hace merge, deploy, release ni cierre por iniciativa propia.
No selecciones tickets ni colas automáticamente. No inventes aprobaciones:
una puerta pendiente deja artifact y estado bloqueado. No copies .env ni uses
datos o credenciales reales. Escala alcance nuevo y áreas delicadas antes de editar.

## Contexto y despacho

Identifica el repo por el worktree y sus instrucciones. Resuelve la rama base
antes de crear worktree o PR. Un perfil privado en
`~/.config/agent-workflow/profiles/` es opcional; si contradice al repo, aclara
antes de escribir. Sin perfil, el encargo basta. No heredes arquitectura,
negocio, estándares, estados ni prefijos de otros proyectos.

Idioma del proyecto: AGENTS.md / CLAUDE.md del repo → campo opcional `language`
(`es|en`) del perfil privado → idioma predominante de commits y docs existentes
→ español. El coordinador indica el idioma en el encargo; si falta, los roles aplican esta regla.

Con ticket, lee criterios, relaciones y bloqueadores del tracker vía MCP
(p. ej. Linear) y verifica identidad del proyecto. Cambios del tracker requieren
instrucción del usuario o regla explícita del repo y los ejecuta el coordinador.

Lee [roles.md](references/roles.md) para modelos, contratos y permisos. En sesiones
interactivas sigue [Herdr](references/herdr-hc.md) y los overrides opcionales de
`~/.config/agent-workflow/HERDR.md`. Cada rol aparece bajo su padre en la lista
de agentes de la barra lateral; puede inspeccionarse con `terminal.peek` y
convertirse en pestaña con `terminal.keep` si se solicita. Si falta Herdr
requerido, informa bloqueo, sin sustitución nativa.

Referencias nativas: [Claude Code](references/claude-code.md) y [Codex](references/codex.md).
Esta metodología autoriza los modelos de roles.md para ese despacho.
Si no puedes delegar, declara la limitación; una revisión inline no es independiente.

## Entrega y registro

Commits, PRs, tickets, planes, revisiones, comentarios de código e informes de roles
usan el idioma del proyecto resuelto arriba.
Sigue [delivery.md](references/delivery.md): SHA, archivos, evidencia por criterio,
checks reales y omitidos, riesgos, rondas y disposición de cada hallazgo.
El coordinador verifica por su cuenta SHA, diff, estado del worktree y evidencia.
Registra IDs, modelos solicitados/confirmados y aprobaciones sin secretos en
estado privado, nunca en el repo público.
Modo desatendido opcional y privado: [contrato y aprobaciones](references/unattended.md).
