# Despacho nativo en Codex

Si las instrucciones piden Herdr, usa herdr-hc.md en su lugar.
Lee explícitamente el TOML de `codex/agents/` de esta fuente (instalado en
`~/.config/agent-workflow/.codex/agents/`). No se carga por nombrar el rol.

1. Comprueba esquema de spawn, catálogo y modelos/esfuerzos admitidos.
2. Lee `developer_instructions`, `model` y `model_reasoning_effort` del TOML.
   Incluye el cuerpo en el mensaje autosuficiente junto al brief: ruta absoluta,
   AGENTS.md, base, criterios, plan aprobado, límites y formato de entrega.
3. Usa `spawn_agent` con `fork_turns="none"`, `model` y `reasoning_effort` de
   roles.md. Esta metodología autoriza esos overrides. No asumas soporte de
   `agent_type` ni sandbox por agente; solo lectura es contrato, no aislamiento.
4. Registra el ID y la confirmación efectiva del modelo si existe. El catálogo
   o la solicitud no demuestran qué modelo ejecutó la inferencia.
5. Conserva al implementador; usa followup/resume para cada reparación en su
   misma sesión. Revisor siempre nuevo, con contexto limpio, base y SHA final.
6. Aplica N0 inline y N1 sin revisor; no despaches roles que el nivel no pide.

No edites configuración global. Si falta una capacidad, informa bloqueo. Nunca
sustituyas revisión independiente por la autoevaluación del implementador.
