#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
from pathlib import Path
import re
import shlex
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
for language, base in (("es", root), ("en", root / "en")):
    print(f"Idioma: {language}")
    for folder, suffix, names in (
            ("agents", ".md", set(roles)),
            ("codex/agents", ".toml", {role.replace("-", "_") for role in roles}),
            ("hc/templates", ".md", {f"aw-{role}" for role in roles})):
        check({p.stem for p in (base / folder).glob(f"*{suffix}")} == names,
              f"{folder}: exactamente los cinco roles previstos")
    for role in roles:
        try:
            native = markdown(base / f"agents/{role}.md")
            hc_path = base / f"hc/templates/aw-{role}.md"
            hc = markdown(hc_path)
            toml = (base / f"codex/agents/{role.replace('-', '_')}.toml").read_text()
            body = re.search(r'developer_instructions = """\n(.*?)\n"""', toml, re.S)
            check(body is not None and native == hc == body[1].strip(), f"{role}: paridad de cuerpo en tres runtimes")
            if role.startswith("implementador"):
                command = hc_path.read_text().split("command: ", 1)[1].splitlines()[0]
                check("--sandbox danger-full-access" in command and "--no-daemon" in command
                      and '-c approval_policy="never"' in command,
                      f"{role}: permisos de git, sin daemon ni aprobaciones invisibles")
            if role in ("planificador", "revisor"):
                command = hc_path.read_text().split("command: ", 1)[1].splitlines()[0]
                argv = shlex.split(command)
                check(command.endswith(" --"), f"{role}: separador final protege el prompt de tab.new")
                flags = {flag: argv[argv.index(flag) + 1] for flag in
                         ("--model", "--permission-mode", "--allowedTools", "--disallowedTools") if flag in argv}
                check(flags.get("--model") == "opus" and flags.get("--permission-mode") == "dontAsk",
                      f"{role}: Claude Opus sin modo plan ni preguntas de permisos")
                check(set(flags.get("--allowedTools", "").split(",")) == {"Bash", "Read", "Grep", "Glob", "WebFetch", "WebSearch"}
                      and set(flags.get("--disallowedTools", "").split(",")) == {"Edit", "Write", "NotebookEdit", "Agent", "Skill", "AskUserQuestion", "ExitPlanMode", "Workflow", "Artifact", "SendMessage"},
                      f"{role}: herramientas de lectura y límites de escritura/despacho")
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
instructions = [repo / "AGENTS.md", repo / "CLAUDE.md", repo / "INSTALL.md", repo / "scripts/check-setup.sh"]
for path in instructions:
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
precedence = [re.search(r"^\s*line\s*=\s*'([^']+)'$", path.read_text(), re.M)
              for path in (repo / "INSTALL.md", repo / "scripts/check-setup.sh")]
check(all(precedence) and precedence[0][1] == precedence[1][1], "misma línea de precedencia en guía y verificador")
def settings(path):
    text = path.read_text()
    if path.suffix == ".toml":
        text = text.split('developer_instructions = """', 1)[0]
        return dict(re.findall(r"^(\w+) = (.+)$", text, re.M))
    return dict(re.findall(r"^(\w+): (.+)$", text.split("---", 2)[1], re.M))

es_files = {p.relative_to(root / "skills/agent-workflow") for p in (root / "skills/agent-workflow").rglob("*") if p.is_file()}
en_files = {p.relative_to(root / "en/skills/agent-workflow") for p in (root / "en/skills/agent-workflow").rglob("*") if p.is_file()}
check(es_files == en_files, "es/en: mismos archivos relativos de skill")
for relative in [Path("skills/agent-workflow/SKILL.md")] + [
        Path(folder) / name for role in roles for folder, name in (
            ("agents", role + ".md"),
            ("codex/agents", role.replace("-", "_") + ".toml"),
            ("hc/templates", "aw-" + role + ".md"))]:
    try:
        es, en = settings(root / relative), settings(root / "en" / relative)
        same_keys = es.keys() == en.keys()
        es.pop("description", None)
        en.pop("description", None)
        check(same_keys and es == en, f"es/en: metadatos idénticos salvo description: {relative}")
    except (OSError, IndexError) as error:
        check(False, f"es/en: {relative}: {error}")
for language, base in (("es", root), ("en", root / "en")):
    skill = base / "skills/agent-workflow/SKILL.md"
    if check(skill.is_file(), f"{language}: SKILL.md presente"):
        check(len(skill.read_text().splitlines()) <= 120, f"{language}: SKILL.md de hasta 120 líneas")
        check(bool(re.search(r"^description: Use when", skill.read_text(), re.M)), f"{language}: description descubrible")
    paths = [skill, base / "skills/agent-workflow/references/delivery.md"] + [
        base / folder / name for role in roles for folder, name in (
            ("agents", role + ".md"),
            ("codex/agents", role.replace("-", "_") + ".toml"),
            ("hc/templates", "aw-" + role + ".md"))]
    for path in paths:
        content = path.read_text() if path.is_file() else ""
        paragraph = next((part for part in re.split(r"\n\s*\n", content) if "`language`" in part), "")
        paragraph = " ".join(paragraph.split())
        ordered = ("AGENTS.md / CLAUDE.md", "`language`", "commits", "español" if language == "es" else "Spanish")
        position = 0
        for fragment in ordered:
            position = paragraph.find(fragment, position)
            if position < 0:
                break
            position += len(fragment)
        check(position >= 0 and all(word in content for word in ("PRs", "tickets", "es|en")),
              f"{language}: regla de idioma en {path.relative_to(base)}")
if failures:
    sys.exit(1)
print("check-roles: todos los checks pasan")
PY
