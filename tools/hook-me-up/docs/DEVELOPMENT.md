# Building from source

Requires Xcode 16 or later (Swift 6). From the repository root, first run
`cd tools/hook-me-up` (or use `make -C tools/hook-me-up <target>`).

```sh
make            # build the hook, the installer CLI and the agent
make test       # unit tests
make lint       # swift format lint (make format to apply)
make app        # .build/HookMeUp.app (with the editor extension in Contents/Resources)
make vsix       # the editor extension alone: .build/hook-me-up.vsix
make install    # package this checkout and run install.sh with it
make uninstall  # run uninstall.sh
make dist VERSION=1.2.3 UNIVERSAL=1   # .build/dist/hook-me-up-1.2.3-macos.zip and .sha256
```

[TESTING.md](TESTING.md) lists the automated checks and a manual end-to-end
checklist. Pushing a `hook-me-up-v*` tag publishes a release with GitHub Actions.

## How it works

```
Claude Code ──hook──▶ hook-me-up ──Unix socket──▶ Hook Me Up (menu-bar agent)
     ▲                    │                              │
     └──── decision ◀─────┘ ◀──────── your answer ◀──── native notification
```

Claude Code runs the `hook-me-up` command for `PermissionRequest`, `Notification`,
`Stop`, `UserPromptSubmit` and `SessionEnd`. For a permission request, the hook asks
the agent over a local socket and waits; the agent shows a notification and sends back
your decision, and the hook prints it for Claude Code. If there is no decision (the
agent isn't running, notifications are off, the agent is paused, something fails, or
the request times out), the hook prints nothing and Claude Code shows its own terminal
dialog. You can always answer in the terminal instead; the notification then goes
away when the session finishes its turn or you send the next prompt. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the details.
