# Hook Me Up for VS Code

Part of [Hook Me Up](https://github.com/robertodf99/hook-me-up), which answers Claude Code
from native macOS notifications. With this extension, clicking a session's notification
also shows that session's integrated terminal, even when the window has several.

Hook Me Up's installer adds it to VS Code, VS Code Insiders, Cursor and Windsurf (skip that
with `HOOK_ME_UP_NO_EDITOR_EXTENSION=1`); its uninstaller removes it.

How it works: on a click, the Hook Me Up agent writes a small request (a request id, the
time and the session's process ids; no paths, titles or commands) to
`~/Library/Application Support/hook-me-up/editor-focus-request.json`. Every editor window
watches that file; the one with a terminal whose process is one of those ids shows it, and
the others do nothing. Requests are checked strictly (a file of yours, in a folder only you
can reach, at most 4 KiB, less than 5 seconds old, each acted on once). The extension never
writes or removes the file, has no dependencies, logs nothing and sends nothing anywhere.

Windows that were already open may need a reload (Developer: Reload Window) after the
extension is installed or updated.
