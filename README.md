# FDE Toolkit

Tools for my daily work as a Forward Deployed Engineer.

Setting up with an agent? Point it to [INSTALL.md](INSTALL.md).

| Tool | What it does |
|---|---|
| [Hook Me Up](tools/hook-me-up/) | Answer Claude Code from native macOS notifications. |
| [agent-workflow](methodology/agent-workflow/) | Multiagent development methodology for Claude Code, Codex and Herdr Core. |

## Install Hook Me Up

Requires macOS 14 or later and Claude Code. The installer shows the settings diff
and asks before adding hooks.

```sh
curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | bash
```

Or use the Claude Code plugin:

```text
/plugin marketplace add robertodf99/fde-toolkit
/plugin install hook-me-up@fde-toolkit
```

See [Hook Me Up](tools/hook-me-up/README.md) for configuration, uninstalling and
building from source. From a checkout, `make` builds Hook Me Up; tool targets can
also be run with `make -C tools/hook-me-up <target>`.

## License

[MIT](LICENSE).
