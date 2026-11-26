# agent-workflow

Metodología multiagente en español para Claude Code, Codex y Herdr Core.
La fuente común es [SKILL.md](skills/agent-workflow/SKILL.md); los cinco roles
mantienen el mismo cuerpo en los tres formatos.

| Nivel | Flujo |
|---|---|
| N0 | Coordinador inline |
| N1 | Implementador-simple; el coordinador revisa y verifica |
| N2 | Implementador y revisor independiente |
| N3 | Planificador, implementador o implementador-delicado y revisor |

En N0–N2 no se invocan brainstorming ni writing-plans. En N3 se activan solo
con diseño abierto o más de una tarea, respectivamente. Superpowers debe estar
instalado para las prácticas seleccionadas; este paquete no lo descarga ni copia.

## Quick start

Sigue [INSTALL.md](../../INSTALL.md) para preparar herramientas, dependencias,
permisos y precedencia desde un terminal, y comprobar el entorno con un comando.
Después, en cualquier proyecto, pide «usa la metodología agent-workflow» o invoca
`$agent-workflow`. El detalle de instalación y restauración está a continuación.

## Instalación local

Requiere Bash y Python 3.9+, disponibles en macOS/Linux. Para Herdr, Core 0.1.22
(`hc`) y Desktop (`herdr-app`); Claude Code/Codex deben admitir los modelos y flags
indicados en [roles.md](skills/agent-workflow/references/roles.md).
Desde un checkout estable, ejecuta:

```sh
bash methodology/agent-workflow/install.sh                 # dry-run
bash methodology/agent-workflow/install.sh --yes           # aplica
bash methodology/agent-workflow/install.sh --only codex    # solo muestra Codex
bash methodology/agent-workflow/install.sh --yes --only hc
bash methodology/agent-workflow/install.sh --uninstall  # dry-run
bash methodology/agent-workflow/install.sh --yes --uninstall
```

`--only claude|codex|hc` limita instalación y desinstalación. Sin `--yes` no crea
ni modifica archivos. Con `--yes` crea estos symlinks:

- Claude: `~/.claude/skills/agent-workflow` y cinco `~/.claude/agents/*.md`.
- Codex: `~/.codex/skills/agent-workflow` y cinco TOML en
  `~/.config/agent-workflow/.codex/agents/` (no modifica config global).
- Herdr: cinco `~/.config/herdr-core/templates/aw-*.md`.

Los originales quedan en `~/.local/share/agent-workflow/backups/`; el manifiesto
principal está en `~/.local/share/agent-workflow/install-manifest.json`.
Repetir la instalación es idempotente; desinstalar restaura siempre los originales.
Nunca sigue ni borra enlaces ajenos; ante fallos, conserva originales y backups.

Mantén la ruta del checkout: borrar un worktree rompe los enlaces. El instalador
avisa de fuentes en worktree y de un plugin activo en settings de Claude.
Usa una sola forma de cargar la skill en Claude para evitar duplicados.
No ejecutes dos instalaciones a la vez.

## Plugin Claude Code

Desde el marketplace `fde-toolkit`, instala `agent-workflow@fde-toolkit`.
Con el marketplace ya añadido:

```text
/plugin install agent-workflow@fde-toolkit
```

El plugin expone `skills/` y `agents/`; para Codex/Herdr usa el instalador local.
No combina automáticamente perfil privado, punteros ni configuración global.

## Estado privado y despacho

Perfiles, runners y overrides siguen fuera del repositorio en
`~/.config/agent-workflow`; informes y estado en `~/.local/share/agent-workflow`.
No se necesitan perfiles ni tracker para un encargo explícito. Un tracker se
consulta vía MCP (p. ej. Linear). Los punteros personales de AGENTS.md / CLAUDE.md
se mantienen aparte.

## Validación

```sh
bash methodology/agent-workflow/tests/check-roles.sh
bash methodology/agent-workflow/tests/test-install.sh
bash scripts/check-marketplace.sh
```

Los tests del instalador usan exclusivamente un HOME temporal. El check de roles
comprueba paridad, modelos y flags de Herdr, y privacidad genérica en este paquete
(incluido el [contrato desatendido](skills/agent-workflow/references/unattended.md))
y en AGENTS.md / CLAUDE.md, INSTALL.md y el verificador de setup de la raíz. Si existe
`~/.config/agent-workflow/private-terms.txt`, añade sus términos (una cadena por
línea, comentarios con `#`) al barrido local sin imprimirlos. No se crea ese archivo.
La [prueba de triaje](tests/triage-cases.md) es una lectura escrita, no un ensayo
con agentes independientes ni una prueba viva de Herdr Desktop.
