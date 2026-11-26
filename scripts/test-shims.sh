#!/bin/bash
# Exercises both root entry points with fake curl and payloads; never installs anything.
set -euo pipefail
cd "$(dirname "$0")/.."

/usr/bin/python3 -I - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile

root = Path.cwd()
with tempfile.TemporaryDirectory(prefix="fde-shims-", dir=os.environ.get("TMPDIR")) as temporary:
    work = Path(temporary)
    bindir = work / "bin"
    bindir.mkdir()
    curl = bindir / "curl"
    curl.write_text('''#!/bin/bash
printf '%s\\n' "$@" >"$CURL_TRACE"
cat "$PAYLOAD"
exit "${CURL_STATUS:-0}"
''')
    curl.chmod(0o755)
    payload = '''#!/bin/bash
printf '%s\\n' "$HOME" "$HOOK_ME_UP_VERSION" "$HOOK_ME_UP_REF" "$HOOK_ME_UP_ZIP" \\
  "$HOOK_ME_UP_YES" "$HOOK_ME_UP_NO_TTY" "$HOOK_ME_UP_DRY_LAUNCH" "$SENTINEL" "$#" "$@" >"$TRACE"
exit "${TARGET_STATUS:-0}"
'''
    home = work / "home"
    home.mkdir()
    arguments = ["value with spaces", "literal $(no-command) *"]
    for name in ("install.sh", "uninstall.sh"):
        original = root / name
        assert original.is_file(), f"missing root shim: {name}"
        checkout = work / name.removesuffix(".sh")
        target = checkout / "tools/hook-me-up" / name
        target.parent.mkdir(parents=True)
        target.write_text(payload)
        target.chmod(0o644)
        local = checkout / name
        local.write_bytes(original.read_bytes())
        remote = work / ("remote-" + name)
        remote.write_bytes(original.read_bytes())
        downloaded = work / "payload"
        downloaded.write_text(payload)
        trace, curl_trace = work / "trace", work / "curl-trace"
        env = dict(os.environ, HOME=str(home), PATH=str(bindir) + ":/usr/bin:/bin:/usr/sbin:/sbin",
                   HOOK_ME_UP_VERSION="hook-me-up-v0.5.0-rc.1", HOOK_ME_UP_REF="review/test",
                   HOOK_ME_UP_ZIP="/fixture/a zip.zip", HOOK_ME_UP_YES="1", HOOK_ME_UP_NO_TTY="1",
                   HOOK_ME_UP_DRY_LAUNCH="1", SENTINEL="a value\nsecond line", TRACE=str(trace),
                   CURL_TRACE=str(curl_trace), PAYLOAD=str(downloaded), CURL_STATUS="0", TARGET_STATUS="0")
        expected = "\n".join([env[key] for key in ("HOME", "HOOK_ME_UP_VERSION", "HOOK_ME_UP_REF",
                             "HOOK_ME_UP_ZIP", "HOOK_ME_UP_YES", "HOOK_ME_UP_NO_TTY", "HOOK_ME_UP_DRY_LAUNCH",
                             "SENTINEL")] + ["2"] + arguments) + "\n"

        def run(script, stdin=None, cwd=work, **changes):
            trace.unlink(missing_ok=True)
            curl_trace.unlink(missing_ok=True)
            command = ["/bin/bash", str(script)] if script else ["/bin/bash", "-s", "--"]
            return subprocess.run(command + arguments, input=stdin, text=True, cwd=cwd,
                                  env=dict(env, **changes), capture_output=True)

        result = run(local)
        assert result.returncode == 0 and trace.read_text() == expected, (name, "checkout", result.stderr)
        assert not curl_trace.exists(), (name, "checkout must not download")
        print(f"PASS  {name}: checkout delegates from another working directory; environment and args intact")

        for script, stdin, cwd in ((remote, None, work), (None, original.read_text(), work),
                                   (None, original.read_text(), root)):
            result = run(script, stdin, cwd)
            assert result.returncode == 0 and trace.read_text() == expected, (name, "download", result.stderr)
            assert curl_trace.read_text().splitlines() == ["-fsSL", f"https://raw.githubusercontent.com/robertodf99/fde-toolkit/review/test/tools/hook-me-up/{name}"]
        result = run(remote, HOOK_ME_UP_REF="")
        assert result.returncode == 0 and "/main/tools/" in curl_trace.read_text(), (name, "default ref")
        print(f"PASS  {name}: standalone and piped download; explicit/default ref, environment and args intact")

        for script, stdin in ((local, None), (None, original.read_text())):
            result = run(script, stdin, TARGET_STATUS="7")
            assert result.returncode == 7, (name, "target exit code", result)
        print(f"PASS  {name}: target exit status is preserved in both modes")

        result = run(remote, CURL_STATUS="22")
        assert result.returncode == 22 and not trace.exists(), (name, "failed download was executed")
        print(f"PASS  {name}: a failed curl never executes its partial output")

        lines = original.read_text().splitlines(keepends=True)
        for count in (len(lines) // 2, len(lines) * 3 // 4, len(lines) - 1):
            result = run(None, "".join(lines[:count]))
            assert not trace.exists() and not curl_trace.exists(), (name, "truncated shim executed")
        # Use the real target without its final main call: it must do nothing too.
        downloaded.write_text("\n".join((root / "tools/hook-me-up" / name).read_text().splitlines()[:-1]) + "\n")
        result = run(remote)
        assert result.returncode == 0 and not trace.exists(), (name, "truncated real script executed", result.stderr)
        print(f"PASS  {name}: truncated shim and target run nothing")
print("test-shims: all checks passed")
PY
