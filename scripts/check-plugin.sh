#!/bin/bash
# Checks the Claude Code plugin files without the claude CLI (which CI doesn't have):
# the marketplace and plugin manifests parse as JSON, names and paths line up, the
# plugin declares no hooks (they would run in addition to the ones in settings.json),
# and every skill has a name, a description and disable-model-invocation: true.
# With the claude CLI, `claude plugin validate .` checks more.
set -euo pipefail
cd "$(dirname "$0")/.."

/usr/bin/python3 -I - <<'PY'
import json, os, re, sys

failures = []
def check(ok, message):
    print(("PASS  " if ok else "FAIL  ") + message)
    if not ok:
        failures.append(message)

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as error:
        check(False, f"{path} is valid JSON ({error})")
        sys.exit(1)

market = load(".claude-plugin/marketplace.json")
check(True, ".claude-plugin/marketplace.json is valid JSON")
check(market.get("name") == "hook-me-up", "marketplace name is hook-me-up")
check(bool(market.get("owner", {}).get("name")), "marketplace has an owner name")
plugins = market.get("plugins", [])
check(len(plugins) == 1, "marketplace lists one plugin")
entry = plugins[0] if plugins else {}
source = entry.get("source", "")
check(source.startswith("./") and ".." not in source and os.path.isdir(source), f"plugin source {source} is a folder here")

manifest_path = os.path.join(source, ".claude-plugin/plugin.json")
manifest = load(manifest_path)
check(True, f"{manifest_path} is valid JSON")
name = manifest.get("name", "")
check(name == entry.get("name"), "plugin name matches its marketplace entry")
check(re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) is not None and not name.startswith("claude"), f"plugin name {name} is kebab-case and not reserved")
check("version" not in manifest, "plugin.json pins no version")
check("hooks" not in manifest and "hooks" not in entry and not os.path.exists(os.path.join(source, "hooks")), "the plugin declares no hooks")

skills = os.path.join(source, "skills")
names = sorted(os.listdir(skills)) if os.path.isdir(skills) else []
check(names == ["doctor", "install", "uninstall"], f"skills: {', '.join(names)}")
for skill in names:
    path = os.path.join(skills, skill, "SKILL.md")
    text = open(path).read()
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    fields = dict(line.split(": ", 1) for line in match.group(1).splitlines()) if match else {}
    check(fields.get("name") == skill, f"{path}: name {skill}")
    check(bool(fields.get("description")), f"{path}: has a description")
    check(fields.get("disable-model-invocation") == "true", f"{path}: runs only when asked")

if failures:
    print(f"check-plugin: {len(failures)} failed")
    sys.exit(1)
print("check-plugin: all checks passed")
PY
