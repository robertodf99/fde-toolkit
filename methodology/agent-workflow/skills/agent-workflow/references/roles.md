# Roles y contratos

Los modelos son preferencias de despacho, no promesas de coste o calidad.
Comprueba el catálogo y esquema del runtime; registra por separado modelo
solicitado y confirmado. Si falta una capacidad requerida, informa bloqueo.
No cambies configuración global para forzarla.

| Rol | Claude nativo | Codex nativo (esfuerzo) | Herdr (CLI, modelo) |
|---|---|---|---|
| planificador | opus, high | gpt-6.1-sol, high | Claude opus, plan |
| implementador-simple | sonnet, high | gpt-6-luna, high | Codex gpt-6-luna, high |
| implementador | opus, high | gpt-6.1-sol, high | Codex gpt-6.1-sol, high |
| implementador-delicado | opus, xhigh | gpt-6.1-sol, xhigh | Codex gpt-6.1-sol, xhigh |
| revisor | opus, high | gpt-6.1-sol, high | Claude sonnet, plan |

La diferencia **intencionada** del revisor es Opus en el agente nativo de Claude
y Sonnet en Herdr. No normalices esa diferencia al sincronizar cuerpos.
Los nombres públicos usan guiones; los archivos/nombres TOML de Codex usan
`implementador_simple` e `implementador_delicado` por compatibilidad local.
Los tres formatos conservan el mismo cuerpo, comprobado por `tests/check-roles.sh`.

## Contratos

- Planificador: solo inspección; comportamiento actual, reproducción, nivel
  N0–N3 y motivos, criterios, exclusiones, pasos, validación y bloqueos.
- Implementadores: único escritor en el worktree indicado; SHA, archivos,
  evidencia por criterio, checks ejecutados/omitidos y riesgos. El delicado
  incluye invariantes. Cada hallazgo recibido lleva disposición y evidencia.
- Revisor: contexto nuevo; SHA final revisado, veredicto, hallazgos con prioridad,
  archivo/línea, consecuencia y reproducción o razonamiento; criterios sin
  probar y limitaciones. Solo estándares vinculantes del repo.

Ningún rol crea agentes, publica, cambia el tracker ni hace merge. El coordinador
conserva la sesión del implementador para dos rondas de reparación como máximo;
planificador y revisores se retiran tras registrar sus informes.

## Áreas delicadas y permisos

Lee AGENTS.md / CLAUDE.md para áreas del dominio. Autenticación, SQL, migraciones,
seguridad, arquitectura crítica, cambios irreversibles y despliegue requieren
escalar. Si implementador-simple los descubre, detiene escrituras y devuelve el
encargo al coordinador; no decide un diseño por su cuenta.

Claude nativo deshabilita edición en planificador/revisor, pero Bash y MCP siguen
sujetos al contrato de solo lectura; no constituyen aislamiento técnico.
Codex nativo no ofrece sandbox por agente en la API descrita aquí; el TOML es
fuente de instrucciones, no garantía de permisos. En Herdr los implementadores
usan `--sandbox danger-full-access`: `workspace-write` deja `.git` en solo lectura
en este flujo y bloquea commits. El contrato limita sus acciones al encargo.
`--no-daemon` es obligatorio para Codex dentro de hc.
