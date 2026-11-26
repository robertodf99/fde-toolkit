#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
roles = ("planificador", "implementador-simple", "implementador", "implementador-delicado", "revisor")
failures = []
def check(ok, message):
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)
    return ok
def markdown(path):
    return path.read_text().split("---", 2)[2].strip()
for folder, suffix, names in (
        ("agents", ".md", set(roles)),
        ("codex/agents", ".toml", {role.replace("-", "_") for role in roles}),
        ("hc/templates", ".md", {f"aw-{role}" for role in roles})):
    check({p.stem for p in (root / folder).glob(f"*{suffix}")} == names,
          f"{folder}: exactamente los cinco roles previstos")
for role in roles:
    try:
        native = markdown(root / f"agents/{role}.md")
        hc_path = root / f"hc/templates/aw-{role}.md"
        hc = markdown(hc_path)
        toml = (root / f"codex/agents/{role.replace('-', '_')}.toml").read_text()
        body = re.search(r'developer_instructions = """\n(.*?)\n"""', toml, re.S)
        check(body is not None and native == hc == body[1].strip(), f"{role}: paridad de cuerpo en tres runtimes")
        if role.startswith("implementador"):
            command = hc_path.read_text().split("command: ", 1)[1].splitlines()[0]
            check("--sandbox danger-full-access" in command and "--no-daemon" in command,
                  f"{role}: permisos de git y modo Codex de Herdr")
        if role in ("planificador", "revisor"):
            command = hc_path.read_text().split("command: ", 1)[1].splitlines()[0]
            check(command == "claude --model opus --permission-mode plan",
                  f"{role}: Claude Opus en Herdr")
    except (OSError, IndexError) as error:
        check(False, f"{role}: {error}")
patterns = [("ruta personal", re.compile(r"/" + r"Users/")),
            ("email", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
            ("ticket", re.compile(r"\b[A-Z]{2,5}-[0-9]+\b"))]
private = Path.home() / ".config/agent-workflow/private-terms.txt"
terms = []
if private.is_file():
    terms = [line.strip() for line in private.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
repo = root.parent.parent
instructions = [repo / "AGENTS.md", repo / "CLAUDE.md"]
for path in instructions + [root / "skills/agent-workflow/references/unattended.md"]:
    check(path.is_file(), f"{path.relative_to(repo)} presente")
for path in sorted(list(root.rglob("*")) + instructions):
    if not path.is_file():
        continue
    content = path.read_text()
    for label, pattern in patterns:
        # El comprobador define los patrones; no contiene ejemplos privados.
        if pattern.search(content):
            check(False, f"privacidad ({label}): {path.relative_to(repo)}")
    if any(term.casefold() in content.casefold() for term in terms):
        check(False, f"privacidad (término privado, valor oculto): {path.relative_to(repo)}")
check(not failures, "privacidad genérica y términos privados locales")
skill = root / "skills/agent-workflow/SKILL.md"
if check(skill.is_file(), "SKILL.md presente"):
    check(len(skill.read_text().splitlines()) <= 120, "SKILL.md de hasta 120 líneas")
    check(bool(re.search(r"^description: Use when", skill.read_text(), re.M)), "description descubrible")
if failures:
    sys.exit(1)
print("check-roles: todos los checks pasan")
PY
