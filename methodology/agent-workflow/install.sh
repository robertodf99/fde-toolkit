#!/usr/bin/env bash
# Symlinks locales; sin flags solo muestra el plan. Requiere Python 3.9+.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
exec python3 -B - "$root" "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description="Instala agent-workflow mediante symlinks; dry-run por defecto.")
parser.add_argument("--yes", action="store_true", help="aplica el plan mostrado")
parser.add_argument("--uninstall", action="store_true", help="retira solo enlaces registrados")
parser.add_argument("--restore", action="store_true", help="restaura backups al desinstalar")
parser.add_argument("--only", choices=("claude", "codex", "hc"), help="limita el runtime")
root = Path(sys.argv[1]).resolve()
args = parser.parse_args(sys.argv[2:])
if args.restore and not args.uninstall:
    parser.error("--restore requiere --uninstall")
home = Path.home()
state_dir = home / ".local/share/agent-workflow"
state_path = state_dir / "install-manifest.json"

def exists(path):
    return os.path.lexists(path)

def owned(path, target):
    return path.is_symlink() and os.readlink(path) == target

def save(path, value):
    # Reemplazo atómico del manifiesto; no deja JSON truncado.
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)

try:
    state = json.loads(state_path.read_text()) if state_path.exists() else {"version": 1, "entries": {}}
    if state.get("version") != 1 or not isinstance(state.get("entries"), dict):
        raise ValueError("formato no admitido")
except (OSError, ValueError) as error:
    sys.exit(f"ERROR: manifiesto ilegible: {error}")
entries = state["entries"]
selected = (args.only,) if args.only else ("claude", "codex", "hc")
mappings = []
for runtime in selected:
    if runtime in ("claude", "codex"):
        mappings.append((runtime, root / "skills/agent-workflow", home / f".{runtime}/skills/agent-workflow"))
    if runtime == "claude":
        mappings.extend((runtime, p, home / ".claude/agents" / p.name) for p in sorted((root / "agents").glob("*.md")))
    elif runtime == "codex":
        mappings.extend((runtime, p, home / ".config/agent-workflow/.codex/agents" / p.name)
                        for p in sorted((root / "codex/agents").glob("*.toml")))
    else:
        mappings.extend((runtime, p, home / ".config/herdr-core/templates" / p.name)
                        for p in sorted((root / "hc/templates").glob("aw-*.md")))

try:
    common = subprocess.run(["git", "-C", str(root), "rev-parse", "--git-common-dir", "--git-dir"],
                            text=True, capture_output=True, check=False)
    lines = common.stdout.splitlines()
    if common.returncode == 0 and len(lines) == 2 and lines[0] != lines[1]:
        print("AVISO: fuente en worktree; los enlaces dependen de conservar esta ruta.")
except FileNotFoundError:
    pass
settings = home / ".claude/settings.json"
if "claude" in selected and settings.exists():
    try:
        enabled = json.loads(settings.read_text()).get("enabledPlugins", {})
        if any(key.split("@", 1)[0] == "agent-workflow" and active for key, active in enabled.items()):
            print("AVISO: plugin agent-workflow activo; skill/agentes locales pueden duplicarlo. Elige un modo de carga.")
    except (OSError, ValueError, AttributeError):
        print("AVISO: no se pudo inspeccionar settings de Claude; comprueba plugins duplicados.")
print("APLICAR" if args.yes else "DRY-RUN: no se escribe nada (usa --yes para aplicar).")

# Planifica y comprueba TODOS los conflictos antes de mutar ningún destino.
actions = []
errors = []
if args.uninstall:
    for destination, entry in entries.items():
        if entry["runtime"] not in selected:
            continue
        path = Path(destination)
        backup = Path(entry["backup"]) if entry.get("backup") else None
        if exists(path) and not owned(path, entry["target"]):
            errors.append(f"destino modificado, se conserva: {path}")
            continue
        if args.restore and backup and not exists(backup):
            errors.append(f"backup ausente, se conserva el registro: {backup}")
            continue
        if exists(path) or (args.restore and backup):
            print(f"RETIRAR {path}" + (f"; RESTAURAR {backup}" if args.restore and backup else ""))
        actions.append(("uninstall", path, entry, backup))
else:
    for runtime, source, path in mappings:
        if not source.exists():
            errors.append(f"fuente ausente: {source}")
            continue
        entry = entries.get(str(path))
        if entry and exists(path) and not owned(path, entry["target"]):
            errors.append(f"destino modificado, se conserva: {path}")
            continue
        if owned(path, str(source)) and entry:
            print(f"SIN CAMBIOS {path}")
            continue
        print(f"ENLAZAR {path} -> {source}" + (" (backup previo)" if exists(path) and not entry else ""))
        actions.append(("install", path, entry, (runtime, source)))
if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)
if not args.yes or not actions:
    sys.exit(0)

backup_dir = state_dir / "backups" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8])
backup_manifest = {"version": 1, "entries": {}}
for operation, path, entry, extra in actions:
    if operation == "install":
        runtime, source = extra
        backup = entry.get("backup") if entry else None
        if exists(path):
            if entry:
                path.unlink()  # enlace registrado comprobado durante el preflight
            else:
                backup_path = backup_dir / "files" / path.relative_to(home)
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                # Registra intención antes de mover el original para facilitar recuperación.
                backup_manifest["entries"][str(path)] = {"backup": str(backup_path), "target": str(source), "runtime": runtime}
                save(backup_dir / "manifest.json", backup_manifest)
                path.rename(backup_path)
                backup = str(backup_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        entry = {"target": str(source), "runtime": runtime, "backup": backup}
        entries[str(path)] = entry
        # Persiste antes de crear el enlace: permite reanudar si falla su creación.
        save(state_path, state)
        path.symlink_to(source, target_is_directory=source.is_dir())
    else:
        backup = extra
        if exists(path):
            path.unlink()
        if args.restore and backup:
            path.parent.mkdir(parents=True, exist_ok=True)
            backup.rename(path)
        if args.restore or not backup:
            del entries[str(path)]
        # Sin --restore se conserva el registro del backup para restaurarlo después.
        save(state_path, state)
print(f"Manifiesto: {state_path}")
PY
