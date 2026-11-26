#!/bin/bash
# Checks local marketplace entries for any number of toolkit plugins.
# Each tool validates its own plugin's behavior separately.
set -euo pipefail
cd "$(dirname "$0")/.."

/usr/bin/python3 -I - <<'PY'
import json
from pathlib import Path
import re
import sys

failures = []

def check(ok, message):
    print(("PASS  " if ok else "FAIL  ") + message)
    if not ok:
        failures.append(message)
    return ok

def load(path):
    try:
        with path.open() as file:
            value = json.load(file)
        if not isinstance(value, dict):
            raise ValueError("expected an object")
        return value
    except (OSError, ValueError) as error:
        check(False, f"{path}: valid JSON object ({error})")
        return {}

root = Path.cwd().resolve()
market = load(Path(".claude-plugin/marketplace.json"))
check(market.get("name") == "fde-toolkit", "marketplace name is fde-toolkit")
owner = market.get("owner")
check(isinstance(owner, dict) and bool(owner.get("name")), "marketplace has an owner name")
entries = market.get("plugins")
if not check(isinstance(entries, list) and bool(entries), "marketplace lists plugins"):
    entries = []
names, sources = set(), set()
for entry in entries:
    if not check(isinstance(entry, dict), "plugin entry is an object"):
        continue
    name = entry.get("name")
    valid_name = isinstance(name, str) and re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) is not None and not name.startswith("claude")
    if not check(valid_name, f"plugin name {name!r} is kebab-case and not reserved"):
        continue
    check(name not in names, f"plugin name {name} is unique")
    names.add(name)
    source = entry.get("source")
    valid_source = isinstance(source, str) and source.startswith("./") and ".." not in Path(source).parts
    if not check(valid_source, f"{name}: source {source!r} is relative to this checkout"):
        continue
    try:
        folder = (root / source).resolve()
        local = root in folder.parents and folder.is_dir()
    except (OSError, RuntimeError):
        local = False
    if not check(local, f"{name}: source stays inside this checkout and exists"):
        continue
    check(folder not in sources, f"{name}: source is unique")
    sources.add(folder)
    manifest = load(folder / ".claude-plugin/plugin.json")
    check(manifest.get("name") == name, f"{name}: plugin name matches marketplace entry")

if failures:
    print(f"check-marketplace: {len(failures)} failed")
    sys.exit(1)
print(f"check-marketplace: all checks passed ({len(entries)} plugins)")
PY
