# Validación, entrega y estado privado

Usa el worktree autorizado y la base del repo. Si hay que crearlo, confirma la
base a partir de instrucciones del proyecto, no de otro perfil. Evita colisiones
con trabajo paralelo; solo el implementador escribe. No copies .env, secretos,
credenciales ni datos reales. Toda ampliación de alcance vuelve al coordinador.

## Idioma de los entregables

Commits, PRs, tickets, planes, revisiones, comentarios de código e informes de roles
usan el idioma del proyecto: AGENTS.md / CLAUDE.md del repo → campo opcional
`language` (`es|en`) del perfil privado → idioma predominante de commits y docs
existentes → español. El coordinador indica el idioma en el encargo; los roles
lo usan y, si falta, aplican esta regla.

## Evidencia mínima

- SHA(s), HEAD, base y archivos cambiados.
- Criterios e invariantes con comportamiento observado y evidencia concreta.
- Checks ejecutados con resultado y checks omitidos con motivo. Tipos, lint y
  build no equivalen a E2E; configura pruebas de navegador según el proyecto.
- Cada hallazgo recibido: corregido, rebatido con evidencia o pendiente escalado.
- Riesgos, bloqueos, decisiones pendientes y número de rondas consumidas.

El coordinador ejecuta `git rev-parse HEAD`, inspecciona `git diff <base> HEAD`
y `git status --short`; contrasta evidencia y SHA revisado. El estado «terminado»
del terminal no demuestra criterios. No afirma que una revisión previa a cambios
cubra el SHA corregido. Checks requeridos pendientes dejan entrega draft.
Si está autorizado crear un PR y quedan checks/hallazgos abiertos, debe ser draft;
no crees PR ni publiques sin autorización aplicable.

## Estado y puertas humanas

Usa el estado del perfil privado, o sin perfil
`~/.local/share/agent-workflow/interactive/<repo>/<trabajo>/`, con identificadores
que eviten colisiones. Registra plan, aprobaciones vigentes, base, SHAs, IDs,
modelos solicitados y confirmados, informes, checks, rondas y pendientes.
No guardes datos personales ni secretos. Los perfiles y runners permanecen en
`~/.config/agent-workflow`; los punteros personales de AGENTS.md / CLAUDE.md se
editan aparte, nunca se copian al repo compartido.

Al faltar aprobación, entrega un artifact revisable y declara bloqueo; una
reanudación o mensaje de un rol no concede autorización. Conserva aprobaciones
previas. Sin merge, deploy, release ni cierre automático por iniciativa propia.
