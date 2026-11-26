# Modo desatendido

Solo trabaja tickets habilitados explícitamente por el usuario, uno a la vez por perfil.
Cada trabajo usa worktree propio; workers Codex o un runner equivalente con `claude -p`.
El dispatcher verifica el recibo del worker contra git y gh; ready no verificado baja a draft o blocked.
Una puerta humana termina blocked con artifact revisable y su hash.
Solo se reabre con aprobación explícita del usuario sobre el hash exacto de ese artifact.
Enqueue y resume no son aprobación; el worker no se aprueba a sí mismo.
Nunca se arranca, encola, aprueba ni ejecuta trabajo por iniciativa propia.
La implementación y los perfiles viven en la configuración privada `~/.config/agent-workflow`.
