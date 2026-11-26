#!/usr/bin/env bash
# Solo HOME falso; nunca instala en la configuración real.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 -B - "$root" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
count = 0
with tempfile.TemporaryDirectory(prefix="aw-test-") as temporary:
    home = Path(temporary) / "home con espacios"
    home.mkdir()
    env = dict(os.environ, HOME=str(home))
    def run(*args, ok=True, extra_env=None):
        global count
        result = subprocess.run(["bash", str(root / "install.sh"), *args],
                                env=dict(env, **(extra_env or {})), text=True, capture_output=True)
        assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
        assert "Traceback" not in result.stderr, result.stderr
        count += 1
        return result.stdout + result.stderr
    def snapshot():
        return sorted(str(p.relative_to(home)) for p in home.rglob("*"))
    state = home / ".local/share/agent-workflow/install-manifest.json"
    skill = home / ".claude/skills/agent-workflow"
    codex = home / ".codex/skills/agent-workflow"
    agent = home / ".claude/agents/implementador.md"
    assert "DRY-RUN" in run() and snapshot() == []
    skill.mkdir(parents=True)
    (skill / "original.txt").write_text("original")
    agent.parent.mkdir(parents=True)
    agent.symlink_to("original-inexistente")
    before = snapshot()
    run("--only", "claude")
    assert snapshot() == before
    run("--yes", "--only", "claude")
    assert len(json.loads(state.read_text())["entries"]) == 6 and not codex.exists()
    assert skill.resolve() == root / "skills/agent-workflow"
    assert not list((state.parent / "backups").rglob("manifest.json")), "Solo debe haber un manifiesto principal"
    before, manifest = snapshot(), state.read_text()
    run("--yes", "--only", "claude")
    assert snapshot() == before and state.read_text() == manifest
    run("--yes")
    assert len(json.loads(state.read_text())["entries"]) == 17
    before, manifest = snapshot(), state.read_text()
    run("--uninstall")
    assert snapshot() == before and state.read_text() == manifest
    # Un enlace reemplazado por el usuario nunca se sigue ni se borra.
    foreign = home / "archivo-ajeno"
    foreign.write_text("conservar")
    codex.unlink()
    codex.symlink_to(foreign)
    replaced = agent  # También debe conservar el backup original de este destino.
    replaced.unlink()
    replaced.write_text("archivo del usuario")
    assert "--uninstall" not in run("--yes", "--only", "codex", ok=False)
    output = run("--yes", "--uninstall")
    assert "AVISO:" in output and "destino ajeno" in output
    assert codex.is_symlink() and codex.resolve() == foreign.resolve() and foreign.read_text() == "conservar"
    assert replaced.read_text() == "archivo del usuario"
    assert (skill / "original.txt").read_text() == "original", "El resto debe desinstalarse"
    assert set(json.loads(state.read_text())["entries"]) == {str(codex), str(replaced)}
    for path in (codex, replaced):  # El fixture revierte los cambios ajenos.
        path.unlink()
        path.symlink_to(json.loads(manifest)["entries"][str(path)]["target"])
    run("--yes", "--uninstall")
    assert (skill / "original.txt").read_text() == "original"
    assert agent.is_symlink() and os.readlink(agent) == "original-inexistente"
    assert json.loads(state.read_text())["entries"] == {}
    # Backup ausente: avisa, retira el enlace propio y procesa los demás destinos.
    run("--yes", "--only", "claude")
    backup = Path(json.loads(state.read_text())["entries"][str(skill)]["backup"])
    parked = backup.with_name("original-apartado")
    backup.rename(parked)
    before, manifest = snapshot(), state.read_text()
    assert "backup ausente" in run("--uninstall")
    assert snapshot() == before and state.read_text() == manifest
    output = run("--yes", "--uninstall")
    assert "AVISO:" in output and "backup ausente" in output
    assert not os.path.lexists(skill), "El enlace propio sí debe retirarse"
    assert set(json.loads(state.read_text())["entries"]) == {str(skill)}
    assert agent.is_symlink() and os.readlink(agent) == "original-inexistente"
    parked.rename(backup)
    run("--yes", "--uninstall")
    assert (skill / "original.txt").read_text() == "original"
    assert json.loads(state.read_text())["entries"] == {}
    # Fallos antes y después de mover el original: el único manifiesto basta.
    injection = Path(temporary) / "inject"
    injection.mkdir()
    (injection / "sitecustomize.py").write_text('''import errno
import os
from pathlib import Path
rename, symlink = Path.rename, Path.symlink_to
def fail_rename(self, target):
    if str(self) == os.environ["AW_TEST_PATH"] and os.environ["AW_TEST_FAIL"] == "move":
        raise OSError(errno.EXDEV, "EXDEV simulado")
    return rename(self, target)
def fail_symlink(self, target, **kwargs):
    if str(self) == os.environ["AW_TEST_PATH"]:
        raise OSError(errno.EIO, "fallo de enlace simulado")
    return symlink(self, target, **kwargs)
Path.rename, Path.symlink_to = fail_rename, fail_symlink
''')
    for failure in ("move", "link"):
        output = run("--yes", "--only", "claude", ok=False, extra_env={
            "PYTHONPATH": str(injection), "AW_TEST_PATH": str(skill), "AW_TEST_FAIL": failure})
        assert "ERROR:" in output and (failure != "move" or "EXDEV" in output)
        entry = json.loads(state.read_text())["entries"][str(skill)]
        original = skill if failure == "move" else Path(entry["backup"])
        assert (original / "original.txt").read_text() == "original"
        run("--yes", "--uninstall")
        assert (skill / "original.txt").read_text() == "original"
        assert json.loads(state.read_text())["entries"] == {}
    settings = home / ".claude/settings.json"
    settings.write_text(json.dumps({"enabledPlugins": {"agent-workflow@fde-toolkit": True}}))
    assert "duplic" in run("--only", "claude").lower()
    state.write_text('{"version": 1, "entries": {"invalid": {"target": 123}}}')
    assert "manifiesto" in run("--yes", ok=False)
print(f"test-install: {count} invocaciones verificadas en HOME falso")
PY
