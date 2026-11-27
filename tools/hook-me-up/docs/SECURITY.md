# Security model

- **Fail-open.** The hook outputs a decision only when you made one. Errors never turn
  into an approval or a denial.
- **Local, same-user socket.** The socket lives in a private folder (`0700`, socket
  `0600`) and both sides check that the peer runs as the same user (`getpeereid`).
- **One answer per request.** Every request has its own id; the agent answers only on
  that request's connection, at most once, and the hook ignores any answer for another
  id. An action only counts if it belongs to the notification currently shown.
- **The hook builds the output.** Answers never carry tool input from the agent: the
  hook builds `updatedInput` from its own `tool_input`.
- **Session-only rules.** "Approve for session" keeps only rule and directory
  suggestions and always scopes them to the session; it never writes to your settings.
- **Unlocked Mac only** for every answering action.
- **Clicks reach only the session's own terminal.** For Ghostty, the title marker is
  written only to the session's tty, and only while the session runs and that tty is
  still its controlling terminal (a character device of yours with the same device
  number, opened without following links); the marker is random, goes to Ghostty's
  AppleScript as an argument (never as script text), and the title written back has no
  control characters. The editor extension acts only on a request that is exactly what
  the agent writes: a file of yours in your private support folder, not a link, at most
  4 KiB, less than 5 seconds old, each id once, 1 to 16 process ids; it never writes the
  file, logs nothing and sends nothing anywhere.
- **Careful installer.** It verifies the package checksum, shows the settings diff and
  asks first, backs up, writes atomically, and refuses to write if the file changed
  meanwhile.
- **No content in logs.** `~/Library/Logs/hook-me-up.log` and the unified log (subsystem
  `io.github.robertodf99.hook-me-up`) hold event kinds and short ids only.

## Why macOS says "unidentified developer"

Hook Me Up is signed ad-hoc: it has no Apple Developer ID and is not notarized. A
Developer ID is a paid Apple membership, and this project won't buy one. What you see
because of that:

- System Settings → General → Login Items (Login Items & Extensions on newer macOS)
  lists Hook Me Up under **Allow in the Background**, marked as from an unidentified
  developer.
- When the installer starts the agent, macOS may show a notice that Hook Me Up added
  an item that can run in the background. That is the LaunchAgent that starts the
  agent at login.
- `codesign -dv ~/Applications/"Hook Me Up.app"` shows `Signature=adhoc`.

**Why the install isn't blocked.** Gatekeeper checks apps that carry the quarantine
flag (`com.apple.quarantine`), which browsers and other apps add to what they download.
`curl` doesn't add it, so the app the installer unpacks opens normally. The same zip
downloaded with a browser would be quarantined, and Gatekeeper would block the app from
opening.

**What to do.** Keep the Login Items entry enabled: turning it off stops the agent from
starting at login, and requests then go to the terminal dialog. Install with the script
rather than by downloading the zip in a browser. Or build it yourself from this
repository ([Building from source](DEVELOPMENT.md#building-from-source)).

**How to check what you installed.**

- `codesign --verify --strict --deep ~/Applications/"Hook Me Up.app"` checks that no
  file changed since the package was signed. An ad-hoc signature can't tell you who
  signed it.
- The installer compares the zip with the `.sha256` file published in the same
  release. That catches a corrupted or cut-short download. It doesn't protect against
  a compromised account or release: whoever can replace the zip can replace its
  checksum too.
- Releases carry a GitHub build provenance attestation, which ties the
  zip to the workflow run and the commit that built it:

  ```sh
  version=0.5.0
  gh release download "hook-me-up-v$version" --repo robertodf99/fde-toolkit --pattern '*.zip'
  gh attestation verify "hook-me-up-$version-macos.zip" --owner robertodf99 \
    --signer-workflow robertodf99/fde-toolkit/.github/workflows/release.yml
  # Compare it with the installed app:
  ditto -x -k "hook-me-up-$version-macos.zip" unpacked
  diff -r unpacked/HookMeUp.app ~/Applications/"Hook Me Up.app"
  ```

  This shows the zip was built by this repository's release workflow from that
  commit. It says nothing about what the code at that commit does: reading the source,
  or building it yourself, is still the strongest check.
