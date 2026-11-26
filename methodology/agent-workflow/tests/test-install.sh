#!/usr/bin/env bash
# Todas las mutaciones del instalador se ejecutan en HOME temporales.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
count = 0
with tempfile.TemporaryDirectory(prefix="aw-test-") as temporary:
    home = Path(temporary) / "home con espacios"
    home.mkdir()
    env = dict(os.environ, HOME=str(home))
    def run(*args, ok=True, source=root, extra_env=None):
        global count
        result = subprocess.run(["bash", str(source / "install.sh"), *args],
                                env=dict(env, **(extra_env or {})), text=True, capture_output=True)
        assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
        count += 1
        return result.stdout + result.stderr
    def snapshot():
        return sorted(str(p.relative_to(home)) for p in home.rglob("*"))
    def links():
        return [p for p in home.rglob("*") if p.is_symlink()]
    skill = home / ".claude/skills/agent-workflow"
    codex = home / ".codex/skills/agent-workflow"
    assert "DRY-RUN" in run()
    assert snapshot() == [], "dry-run escribió en HOME"
    run("--restore", ok=False)
    run("--only", "otro", ok=False)
    assert snapshot() == []
    skill.mkdir(parents=True)
    (skill / "original.txt").write_text("original")
    agent = home / ".claude/agents/implementador.md"
    agent.parent.mkdir(parents=True)
    agent.symlink_to("no-existe")
    before = snapshot()
    run("--only", "claude")
    assert snapshot() == before and not skill.is_symlink()
    run("--yes", "--only", "claude")
    assert len(links()) == 7  # seis instalados y el symlink original respaldado
    assert skill.resolve() == root / "skills/agent-workflow"
    assert not codex.exists()
    state = home / ".local/share/agent-workflow/install-manifest.json"
    manifest = json.loads(state.read_text())
    assert len(manifest["entries"]) == 6
    backup_dirs = list((home / ".local/share/agent-workflow/backups").iterdir())
    assert len(backup_dirs) == 1
    assert (backup_dirs[0] / "manifest.json").is_file()
    run("--yes", "--only", "claude")
    assert len(list((home / ".local/share/agent-workflow/backups").iterdir())) == 1
    run("--yes", "--only", "codex")
    run("--yes", "--only", "hc")
    assert len(json.loads(state.read_text())["entries"]) == 17
    assert len(list((home / ".config/herdr-core/templates").glob("aw-*.md"))) == 5
    before = snapshot()
    run("--uninstall", "--restore")
    assert snapshot() == before
    # Uninstall respeta la selección; sin restore conserva backups recuperables.
    run("--yes", "--uninstall", "--only", "claude")
    assert not skill.exists() and codex.is_symlink()
    run("--yes", "--uninstall", "--restore", "--only", "claude")
    assert (skill / "original.txt").read_text() == "original"
    assert agent.is_symlink() and os.readlink(agent) == "no-existe"
    # No elimina ni pisa un archivo del usuario que reemplaza un enlace instalado.
    codex.unlink()
    codex.mkdir()
    (codex / "nuevo.txt").write_text("conservar")
    before = snapshot()
    run("--yes", "--only", "codex", ok=False)
    run("--yes", "--uninstall", "--restore", "--only", "codex", ok=False)
    assert snapshot() == before, "un conflicto debe bloquear la operación completa"
    assert (codex / "nuevo.txt").read_text() == "conservar"
    (codex / "nuevo.txt").unlink()
    codex.rmdir()
    run("--yes", "--uninstall", "--restore")
    assert (skill / "original.txt").read_text() == "original"
    assert not links() or links() == [agent]
    run("--yes", "--uninstall", "--restore")
    # Reinstala sobre una restauración y recupera otra vez el mismo original.
    run("--yes", "--only", "claude")
    run("--yes", "--uninstall", "--restore", "--only", "claude")
    assert (skill / "original.txt").read_text() == "original"
    settings = home / ".claude/settings.json"
    settings.write_text(json.dumps({"enabledPlugins": {"agent-workflow@fde-toolkit": True}}))
    assert "duplic" in run("--only", "claude").lower()
    settings.write_text("malformed")
    assert "settings" in run("--only", "claude").lower()
    # Instalación completa y cambio de checkout: actualiza enlaces propios y
    # mantiene el backup original. La fuente también tiene espacios en su ruta.
    relocated = Path(temporary).resolve() / "otra fuente"
    shutil.copytree(root, relocated)
    run("--yes")
    assert len(json.loads(state.read_text())["entries"]) == 17
    run("--yes", source=relocated)
    assert skill.resolve() == relocated / "skills/agent-workflow"
    assert codex.resolve() == relocated / "skills/agent-workflow"
    # Una fuente ausente bloquea instalación sin tocar nada; desinstalación
    # aún retira enlaces rotos y restaura el original.
    shutil.rmtree(relocated / "skills/agent-workflow")
    before = snapshot()
    run("--yes", source=relocated, ok=False)
    assert snapshot() == before
    run("--yes", "--uninstall", "--restore", source=relocated)
    assert (skill / "original.txt").read_text() == "original"
    assert agent.is_symlink() and os.readlink(agent) == "no-existe"
    # Un manifiesto corrupto se rechaza sin traza ni mutaciones, incluso con --yes.
    valid_manifest = state.read_text()
    invalid_manifests = [
        [],
        {"version": 1, "entries": {str(skill): {}}},
        {"version": 1, "entries": {str(skill): {"runtime": "otro", "target": str(root), "backup": None}}},
        {"version": 1, "entries": {str(skill): {"runtime": "claude", "target": 123, "backup": None}}},
        {"version": 1, "entries": {str(skill): {"runtime": "claude", "target": str(root), "backup": []}}},
    ]
    for invalid in invalid_manifests:
        encoded = json.dumps(invalid)
        state.write_text(encoded)
        before = snapshot()
        output = run("--yes", "--uninstall", ok=False)
        assert "ERROR:" in output and "manifiesto" in output and "Traceback" not in output, output
        assert snapshot() == before and state.read_text() == encoded
        assert (skill / "original.txt").read_text() == "original"
    state.write_text(valid_manifest)
    # EXDEV se inyecta en Path.rename: no requiere montar un segundo volumen.
    injection = Path(temporary) / "inject-exdev"
    injection.mkdir()
    (injection / "sitecustomize.py").write_text('''import errno
import os
from pathlib import Path
original_rename = Path.rename
def rename(self, target):
    if str(self) == os.environ["AW_TEST_EXDEV_SOURCE"]:
        raise OSError(errno.EXDEV, "fallo entre volúmenes simulado")
    return original_rename(self, target)
Path.rename = rename
''')
    injected_env = {"PYTHONPATH": str(injection), "AW_TEST_EXDEV_SOURCE": str(skill),
                    "PYTHONDONTWRITEBYTECODE": "1"}
    output = run("--yes", "--only", "claude", ok=False, extra_env=injected_env)
    assert "ERROR:" in output and "volúmenes" in output and "Traceback" not in output, output
    assert (skill / "original.txt").read_text() == "original"
    assert state.read_text() == valid_manifest
    run("--yes", "--only", "claude")
    installed_manifest = state.read_text()
    backup = Path(json.loads(installed_manifest)["entries"][str(skill)]["backup"])
    injected_env["AW_TEST_EXDEV_SOURCE"] = str(backup)
    output = run("--yes", "--uninstall", "--restore", "--only", "claude", ok=False, extra_env=injected_env)
    assert "ERROR:" in output and "volúmenes" in output and "Traceback" not in output, output
    assert (backup / "original.txt").read_text() == "original"
    assert state.read_text() == installed_manifest
    run("--yes", "--uninstall", "--restore", "--only", "claude")
    assert (skill / "original.txt").read_text() == "original"
print(f"test-install: {count} invocaciones verificadas en HOME falso")
PY
