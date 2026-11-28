# Validación, entrega y estado privado

Usa el worktree autorizado y la base del repo. Si hay que crearlo, confirma la
base a partir de instrucciones del proyecto, no de otro perfil. Evita colisiones
con trabajo paralelo; solo el implementador escribe. No copies .env, secretos,
credenciales ni datos reales. Toda ampliación de alcance vuelve al coordinador.

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

## PR de entrega

Todo encargo que implementa cambios termina con un PR abierto: el trabajo nunca
se queda solo en el worktree ni en la sesión del terminal. Esta regla autoriza al
coordinador a hacer push de la rama de trabajo y abrir el PR. Solo se sustituye
por un commit directo con push cuando el usuario lo pide, a la rama que indique.
Un encargo de solo planificar no abre PR.

La base es la rama menos productiva que aplique, según el trabajo en curso y cómo
esté montado el repo:

1. La rama de la feature, si el usuario trabaja con una rama por feature que
   luego integra en desarrollo.
2. La rama de desarrollo (`dev`, `develop`…), si trabaja directamente contra ella.
3. `main` (o la rama productiva), si no hay rama de desarrollo.

Las instrucciones del usuario, del repo o del perfil fijan la base y prevalecen.
Si hay varias candidatas razonables, pregunta antes de abrir el PR. Con checks
requeridos pendientes o hallazgos abiertos, el PR es draft y los enumera. El
coordinador indica en la entrega la URL del PR (o el SHA del commit directo).

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
