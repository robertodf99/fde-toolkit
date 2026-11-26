# Contrato del modo desatendido

Modo opcional para un dispatcher con workers Codex o un runner equivalente de
Claude en modo `claude -p`. Este documento define el contrato, sin implementar
servicios ni configurar proyectos. La implementación concreta, perfiles, estados
y reglas de habilitación viven en la configuración privada
`~/.config/agent-workflow`.

## Entrada y aislamiento

Solo se trabajan tickets habilitados explícitamente por el usuario y dentro del
perfil correspondiente. Un ticket a la vez por perfil; el dispatcher impide
procesamiento simultáneo y duplicados al reanudar. Cada trabajo usa worktree
propio, base identificada e instrucciones del repositorio. No se copian .env ni
se usan datos o credenciales reales. Se mantienen el único escritor, la revisión
independiente cuando el nivel la pide y el límite de dos rondas de reparación.

Nunca se arranca, encola, aprueba ni ejecuta trabajo por iniciativa propia.
La disponibilidad de un ticket o de un perfil no es un encargo. El worker no
amplía su alcance ni registra aprobaciones en nombre del usuario.

## Recibo del worker y verificación

El worker entrega un recibo estructurado con estos campos obligatorios:

| Campo | Evidencia |
|---|---|
| Identidad | Ticket habilitado, perfil y ruta del worktree |
| Revisión | Base, HEAD, commits y SHA revisado cuando corresponde |
| Resultado | Estado propuesto: ready, draft o blocked, y motivo |
| Criterios | Evidencia por criterio e invariante; archivos afectados |
| Validación | Checks ejecutados, resultados y omisiones justificadas |
| Hallazgos | Disposición individual, riesgos y rondas consumidas |
| Puertas | Artifact y hash exacto; aprobación explícita asociada, si existe |

El dispatcher contrasta el recibo con git y gh: identidad del repo, base, SHA,
diff, estado del worktree y, cuando existan, PR, checks y revisión remotos.
Comprueba que la evidencia corresponde al SHA entregado y al alcance autorizado.
Un ready sin verificación baja a draft; una puerta humana, contradicción o
capacidad necesaria ausente deja blocked con motivo. Un recibo o un estado de
terminal nunca sustituyen la comprobación. Ready no autoriza merge, publicación,
despliegue ni cierre.

## Puertas humanas y reanudación

Una puerta humana termina en **blocked**, con artifact revisable y su hash.
Solo se reabre con **approve explícito del usuario sobre ese hash exacto**.
El dispatcher verifica identidad, alcance y hash de la aprobación antes de
reanudar trabajo dependiente; el worker no puede aprobarse a sí mismo.
Si cambia el artifact, la aprobación anterior no cubre el hash nuevo.

Enqueue y resume no son aprobación. Reintentos, mensajes de otros roles o una
aprobación para otro artifact tampoco abren la puerta. Conserva las aprobaciones
vigentes para su hash y alcance; no vuelvas a pedirlas sin un cambio relevante.
Registra recibos, verificaciones, rondas y aprobaciones en estado privado,
sin secretos ni datos de clientes.
