# Despacho nativo en Claude Code

Si las instrucciones piden Herdr, usa herdr-hc.md en su lugar.
Comprueba que los agentes estén disponibles en `claude agents` y que el runtime
admita el modelo solicitado. En plugin usa el nombre expuesto por ese plugin;
en instalación local usa el nombre del archivo de `~/.claude/agents/`.

1. Resuelve base y worktree; usa EnterWorktree si corresponde y está disponible.
   No copies .env ni heredes datos de otro entorno.
2. Prepara un brief autosuficiente: rol, ruta absoluta, instrucciones aplicables,
   alcance, base, criterios, plan aprobado, validación, límites y entrega.
3. Para planificador/revisor haz una llamada nueva a Agent con `subagent_type`
   del rol y `model` explícito según roles.md. No uses fork ni una sesión previa.
4. Guarda el ID del implementador. El feedback va con SendMessage al mismo ID;
   máximo dos rondas. Revisor nuevo para cada SHA estable tras reparaciones.
5. En N1 el coordinador lee diff y verifica, sin lanzar revisor. N0 es inline.
6. Archiva informes y modelos solicitados/confirmados en estado privado.

Si falta Agent o el modelo, declara la limitación y no presentes una lectura
inline como revisión independiente. La puerta humana se presenta con artifact
revisable solo si falta aprobación; conserva todas las aprobaciones vigentes.
