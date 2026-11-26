#!/usr/bin/env bash
# Read-only, offline setup check. Bash 3.2; Python is also needed by the installer.
command -v python3 >/dev/null 2>&1 || { printf '✗ python3 — install Python 3.9+ (INSTALL.md, step 1)\n'; exit 1; }
exec python3 -B - <<'PY'
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

home = Path.home()
failed = False
roles = ('planificador', 'implementador-simple', 'implementador', 'implementador-delicado', 'revisor')
def report(ready, label, action):
    global failed
    print(('✓ ' if ready else '✗ ') + label + ('' if ready else ' — ' + action), flush=True)
    failed = failed or not ready

def read_command(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None

report(sys.version_info >= (3, 9), 'Python 3.9+', 'See INSTALL.md, step 1')
for tool in ('git', 'claude', 'codex', 'herdr-app', 'herdr-core', 'jq'):
    report(bool(shutil.which(tool)), tool + ' on PATH', 'Install it or fix PATH; see INSTALL.md, step 1')
for runtime in ('claude', 'codex'):
    cache = home / ('.' + runtime) / 'plugins/cache'
    found = any(p.is_file() for p in cache.glob('*/superpowers/*/skills/using-superpowers/SKILL.md'))
    report(found, 'Superpowers files detectable for ' + runtime, 'Install/enable the plugin; see INSTALL.md, step 1')

if platform.system() == 'Darwin':
    major = platform.mac_ver()[0].split('.')[0]
    report(major.isdigit() and int(major) >= 14, 'macOS 14+', 'Upgrade macOS to use Hook Me Up')
    doctor = home / 'Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup'
    result = read_command(str(doctor), 'doctor') if os.access(doctor, os.X_OK) else None
    report(result is not None and result.returncode == 0, 'Hook Me Up doctor', 'Run its doctor directly; see INSTALL.md, step 3')
else:
    print('⚠ Hook Me Up skipped: requires macOS 14+; methodology checks continue')

skill = home / '.codex/skills/agent-workflow'
target = skill.resolve()
checkout = target.parents[3] if len(target.parents) > 3 else target
package = checkout / 'methodology/agent-workflow'
links = [(home / ('.' + runtime) / 'skills/agent-workflow', package / 'skills/agent-workflow') for runtime in ('claude', 'codex')]
for destination, source, files in (
    ('.claude/agents', 'agents', [r + '.md' for r in roles]),
    ('.config/agent-workflow/.codex/agents', 'codex/agents', [r.replace('-', '_') + '.toml' for r in roles]),
    ('.config/herdr-core/templates', 'hc/templates', ['aw-' + r + '.md' for r in roles]),
):
    links += [(home / destination / name, package / source / name) for name in files]
temporary = ('/tmp/', '/private/tmp/', '/var/tmp/', '/private/var/tmp/', '/var/folders/', '/private/var/folders/')
stable = (checkout / '.git').is_dir() and not str(checkout).startswith(temporary)
linked = stable and all(link.is_symlink() and source.exists() and link.resolve() == source.resolve() for link, source in links)
report(linked, 'Methodology links (17, same stable checkout)', 'Run the methodology installer from a stable clone, not /tmp or a worktree')

result = read_command('herdr-core', 'templates', '--json')
try:
    names = {t['name'] for t in json.loads(result.stdout)['templates']} if result and result.returncode == 0 else set()
except (ValueError, KeyError, TypeError):
    names = set()
report(all('aw-' + r in names for r in roles), 'Five aw-* templates visible', 'Run install.sh --only hc after reviewing its dry-run')
line = 'Para trabajo de desarrollo usa la skill agent-workflow; su triaje decide qué skills de Superpowers aplican.'
for name in ('.claude/CLAUDE.md', '.codex/AGENTS.md'):
    try:
        present = line in (home / name).read_text().splitlines()
    except OSError:
        present = False
    report(present, 'Precedence in ~/' + name, 'Ask permission to add the line in INSTALL.md, step 5')
result = read_command('herdr-core', 'server', 'status')
report(result is not None and result.returncode == 0, 'Herdr Core server responding', 'Open Herdr Desktop; see INSTALL.md, step 6')
result = read_command('herdr-app', 'ls')
report(result is not None and result.returncode == 0, 'Herdr Desktop window responding', 'Open Herdr Desktop; see INSTALL.md, step 6')
print('Detection only: confirm Superpowers is enabled in both plugin menus; no login or agent was started.')
sys.exit(1 if failed else 0)
PY
