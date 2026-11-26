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

Requisitos para el reparto mixto por defecto: Claude Code, Codex CLI, Herdr
Desktop y Herdr Core 0.1.22, Superpowers instalado, Bash y Python 3.9+.
Comprueba que los CLIs admitan los modelos y flags de
[roles.md](skills/agent-workflow/references/roles.md).

```sh
git clone https://github.com/robertodf99/fde-toolkit
cd fde-toolkit
bash methodology/agent-workflow/install.sh        # dry-run
bash methodology/agent-workflow/install.sh --yes  # aplica tras revisar el plan
```

Conserva este checkout en una ruta estable. Abre una sesión del agente en
cualquier proyecto y di «usa la metodología agent-workflow» o invoca
`$agent-workflow`. Sin instalación, indica la ruta del checkout y pide «usa la
metodología de este repo»: el agente debe leer su SKILL.md y referencias.
El coordinador es tu sesión; Herdr lanza los roles que exige el triaje en orden,
uno por fase: Claude Opus para planificar/revisar y Codex para implementar según
complejidad. El despacho nativo de un solo runtime es un fallback únicamente
autorizado por el usuario o cuando Herdr no aplica.

Alternativa para cargar la skill y agentes en Claude Code:

```text
/plugin marketplace add robertodf99/fde-toolkit
/plugin install agent-workflow@fde-toolkit
```

Para añadir las plantillas de Herdr y los roles de Codex, desde la raíz del checkout:

```sh
bash methodology/agent-workflow/install.sh --yes --only hc
bash methodology/agent-workflow/install.sh --yes --only codex
```

Evita duplicar la carga local y por plugin.

Recomendado: añade a tu CLAUDE.md / AGENTS.md personal esta línea de precedencia:

> Para trabajo de desarrollo usa la skill agent-workflow; su triaje decide qué skills de Superpowers aplican.

`using-superpowers` puede enrutar antes de cargar la skill; esta instrucción
personal hace explícita la precedencia desde el inicio de cualquier proyecto.
El instalador no modifica esos archivos por ti.

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
bash methodology/agent-workflow/install.sh --uninstall --restore  # dry-run
bash methodology/agent-workflow/install.sh --yes --uninstall --restore
```

`--only claude|codex|hc` limita instalación y desinstalación. Sin `--yes` no crea
ni modifica archivos. Con `--yes` crea estos symlinks:

- Claude: `~/.claude/skills/agent-workflow` y cinco `~/.claude/agents/*.md`.
- Codex: `~/.codex/skills/agent-workflow` y cinco TOML en
  `~/.config/agent-workflow/.codex/agents/` (no modifica config global).
- Herdr: cinco `~/.config/herdr-core/templates/aw-*.md`.

Los originales se mueven, incluidos directorios y symlinks rotos, a
`~/.local/share/agent-workflow/backups/<fecha-id>/files/`, con `manifest.json`.
El registro activo es `~/.local/share/agent-workflow/install-manifest.json`.
Repetir la instalación es idempotente. Si el usuario reemplaza un enlace
registrado, se bloquea la operación antes de escribir y conserva ese archivo.
Desinstalar retira solo enlaces registrados; `--restore` recupera originales.
Sin `--restore`, conserva backups y registro para restaurarlos más tarde.
No borra las carpetas de backups ni archivos ajenos.
Un manifiesto inválido se rechaza antes de actuar. Los movimientos entre volúmenes
(EXDEV) se rechazan con un mensaje claro: el original permanece en su ubicación
de origen. Corrige la ubicación de los volúmenes y reintenta; si falló una
restauración, el registro y el backup se conservan para volver a restaurar.

Mantén la ruta del checkout: borrar un worktree rompe los enlaces. El instalador
avisa de fuentes en worktree y de un plugin activo en settings de Claude.
Usa una sola forma de cargar la skill en Claude para evitar duplicados.
Los manifiestos son estado local: no los edites ni borres mientras dependas de
los backups. No ejecutes dos instalaciones a la vez.

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

El protocolo [Herdr](skills/agent-workflow/references/herdr-hc.md) resuelve el
espacio antes de cada lanzamiento, abre una pestaña por rol con `tab.new`, verifica
la recepción y conserva sesiones. La alternativa `hc run` requiere comprobación
y `terminal.keep` por el coordinador si falta pestaña; no garantiza el espacio
resultante de ese comando. No se pide al usuario que ejecute keep manualmente.

## Validación

```sh
bash methodology/agent-workflow/tests/check-roles.sh
bash methodology/agent-workflow/tests/test-install.sh
bash scripts/check-marketplace.sh
```

Los tests del instalador usan exclusivamente un HOME temporal. El check de roles
comprueba paridad, modelos y flags de Herdr, y privacidad genérica en este paquete
(incluido el [contrato desatendido](skills/agent-workflow/references/unattended.md))
y en AGENTS.md / CLAUDE.md de la raíz. Si existe
`~/.config/agent-workflow/private-terms.txt`, añade sus términos (una cadena por
línea, comentarios con `#`) al barrido local sin imprimirlos. No se crea ese archivo.
La [prueba de triaje](tests/triage-cases.md) es una lectura escrita, no un ensayo
con agentes independientes ni una prueba viva de Herdr Desktop.
