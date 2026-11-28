#!/usr/bin/env bash
# Symlinks locales; dry-run por defecto. Requiere Python 3.9+.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
exec python3 -B - "$root" "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import errno
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description="Instala agent-workflow; dry-run por defecto.")
parser.add_argument("--yes", action="store_true", help="aplica el plan")
parser.add_argument("--uninstall", action="store_true", help="retira enlaces propios y restaura originales")
parser.add_argument("--only", choices=("claude", "codex", "hc"), help="limita el runtime")
parser.add_argument("--lang", choices=("es", "en"), default="es", help="idioma de las fuentes (defecto: es)")
root = Path(sys.argv[1]).resolve()
args = parser.parse_args(sys.argv[2:])
base = root / "en" if args.lang == "en" else root
home = Path.home()
state_dir = home / ".local/share/agent-workflow"
state_path = state_dir / "install-manifest.json"

def exists(path):
    return os.path.lexists(path)

def owned(path, entry):
    return entry is not None and path.is_symlink() and os.readlink(path) == entry["target"]

def save():
    state_dir.mkdir(parents=True, exist_ok=True)
    temporary = state_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(state_path)

try:
    state = json.loads(state_path.read_text()) if state_path.exists() else {"version": 1, "entries": {}}
    if not isinstance(state, dict) or type(state.get("version")) is not int or state["version"] != 1 or not isinstance(state.get("entries"), dict):
        raise ValueError("versión o tipo no admitido")
    for entry in state["entries"].values():
        if (not isinstance(entry, dict) or not isinstance(entry.get("runtime"), str)
                or not isinstance(entry.get("target"), str)
                or not isinstance(entry.get("backup"), (str, type(None)))
                or not isinstance(entry.get("pending", False), bool)):
            raise ValueError("tipos de entrada inválidos")
except (OSError, ValueError) as error:
    sys.exit(f"ERROR: manifiesto ilegible: {error}")
entries = state["entries"]
selected = (args.only,) if args.only else ("claude", "codex", "hc")
if args.only and not args.uninstall:
    for entry in entries.values():
        target = Path(entry["target"])
        depth = 2 if target.parent.name == "templates" or target.suffix == ".toml" else 1
        installed_base = target.parents[depth] if len(target.parents) > depth else target
        language = "en" if installed_base.name == "en" else "es"
        if entry["runtime"] not in selected and language != args.lang:
            print("AVISO: otros runtimes están instalados en otro idioma; repite sin --only para unificarlos.")
            break
mappings = []
for runtime in selected:
    if runtime in ("claude", "codex"):
        mappings.append((runtime, base / "skills/agent-workflow", home / f".{runtime}/skills/agent-workflow"))
    folder, destination, pattern = {
        "claude": ("agents", ".claude/agents", "*.md"),
        "codex": ("codex/agents", ".config/agent-workflow/.codex/agents", "*.toml"),
        "hc": ("hc/templates", ".config/herdr-core/templates", "aw-*.md"),
    }[runtime]
    mappings.extend((runtime, source, home / destination / source.name) for source in sorted((base / folder).glob(pattern)))

try:
    git = subprocess.run(["git", "-C", str(root), "rev-parse", "--git-common-dir", "--git-dir"], capture_output=True, text=True)
    if git.returncode == 0 and len(set(git.stdout.splitlines())) == 2:
        print("AVISO: fuente en worktree; conserva esta ruta mientras uses sus enlaces.")
except FileNotFoundError:
    pass
settings = home / ".claude/settings.json"
if "claude" in selected and settings.exists():
    try:
        enabled = json.loads(settings.read_text()).get("enabledPlugins", {})
        if any(key.split("@", 1)[0] == "agent-workflow" and active for key, active in enabled.items()):
            print("AVISO: plugin agent-workflow activo; evita duplicar la carga local y por plugin.")
    except (OSError, ValueError, AttributeError):
        print("AVISO: no se pudo inspeccionar settings; comprueba plugins duplicados.")
print("APLICAR" if args.yes else "DRY-RUN: no se escribe nada (usa --yes).")
backup_dir = state_dir / "backups" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8])
actions, errors = [], []
if args.uninstall:
    for destination, entry in entries.items():
        if entry["runtime"] not in selected:
            continue
        path = Path(destination)
        backup = Path(entry["backup"]) if entry.get("backup") else None
        intact = entry.get("pending") and backup and not exists(backup) and exists(path) and not owned(path, entry)
        if exists(path) and not owned(path, entry) and not intact:
            print(f"AVISO: destino ajeno, se conserva junto a su registro: {path}")
            continue
        if backup and not exists(backup) and not intact:
            print(f"AVISO: backup ausente: {backup}; se retira solo el enlace propio y se conserva el registro de {path}")
        else:
            print(f"RECUPERAR {path}" if intact else f"RETIRAR {path}; RESTAURAR su original si existe")
        actions.append((path, dict(entry), None))
else:
    for runtime, source, path in mappings:
        entry = entries.get(str(path))
        if not source.exists():
            errors.append(f"fuente ausente: {source}")
        elif entry and exists(path) and not owned(path, entry):
            errors.append(f"destino ajeno, se conserva: {path}; revisa el conflicto antes de instalar")
        elif owned(path, entry) and entry["target"] == str(source) and not entry.get("pending"):
            print(f"SIN CAMBIOS {path}")
        else:
            entry = dict(entry) if entry else {"runtime": runtime, "target": str(source),
                    "backup": str(backup_dir / "files" / path.relative_to(home)) if exists(path) else None}
            print(f"ENLAZAR {path} -> {source}")
            actions.append((path, entry, source))
if errors:
    sys.exit("ERROR: " + "\nERROR: ".join(errors))
if not args.yes or not actions:
    sys.exit(0)

try:
    for path, entry, source in actions:
        previous = entries.get(str(path))
        backup = Path(entry["backup"]) if entry.get("backup") else None
        if source is None and backup and not exists(backup):
            if entry.get("pending") and exists(path) and not owned(path, entry):
                del entries[str(path)]  # Original intacto tras un movimiento fallido o una restauración.
            elif owned(path, entry):
                path.unlink()  # Backup ausente: retira solo el enlace propio; conserva el registro.
            save()
            continue
        entry["pending"] = True
        entries[str(path)] = entry
        save()  # Siempre ANTES de mover el original o retirar el enlace.
        if exists(path):
            if owned(path, previous):
                path.unlink()
            elif previous:
                raise FileExistsError(f"destino ajeno, se conserva: {path}")
            else:
                backup.parent.mkdir(parents=True, exist_ok=True)
                path.rename(backup)  # Mueve el propio symlink, nunca su destino.
        path.parent.mkdir(parents=True, exist_ok=True)
        if source is None:
            if backup:
                backup.rename(path)
            del entries[str(path)]
        else:
            entry["target"] = str(source)
            save()
            path.symlink_to(source, target_is_directory=source.is_dir())
            entry.pop("pending", None)
        save()
except OSError as error:
    reason = f"EXDEV (volúmenes diferentes): {error}" if error.errno == errno.EXDEV else str(error)
    sys.exit(f"ERROR: {reason}. Original y backup se conservan; usa --uninstall para recuperar.")
print(f"Manifiesto: {state_path}")
PY
