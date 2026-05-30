# session.txt

Never lose an AI coding session again. Drops a `session.txt` into every folder you work in, listing the **resume commands** for your Claude Code and OpenAI Codex sessions — newest at the bottom, deduplicated, one line each.

```text
claude --resume 2e3204d9-fac4-4fa4-b578-09a5b1c6bfba
codex resume 019e12e7-6090-7372-95e0-5098aa1d98c0
claude --resume 6b2a13c9-344c-4053-8d19-53930f371e9b   ← newest
```

No more guessing which session belonged to which folder, or hunting through `claude --resume` pickers. Just open the folder, read the file, copy a line — or run `resume`.

## Why

`claude -c` continues the *last* session, but only if you remember which directory you were in, and it forgets across crashes. Codex has no session-end hook at all. This tool writes the resume command to disk **at session start** (crash-safe) and **at session end** (cleanup), so the ID is always on disk.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/install.sh | bash
```

Requirements: `jq`, `curl`. (`sudo apt install jq` / `brew install jq`)

The installer:
- adds a Claude Code `SessionStart` + `SessionEnd` hook to `~/.claude/settings.json` (merged, existing settings untouched)
- sources a `codex` wrapper from `~/.zshrc` / `~/.bashrc`
- installs the `resume` command to `~/.local/bin`

Open a new terminal (or `source ~/.zshrc`) afterwards so the codex wrapper loads.

## Usage

It runs itself. Use Claude or Codex normally — each session appends its resume command to `session.txt` in the folder you launched from.

To jump back in:

```bash
resume          # start the newest session in ./session.txt
resume -l       # numbered list (1 = oldest, at top)
resume N        # start entry N  (e.g. resume 1 = oldest)
```

`resume` runs whatever the line says, so it resumes Claude *and* Codex sessions transparently.

## How it works

| Tool | Mechanism |
|------|-----------|
| **Claude Code** | `SessionStart`/`SessionEnd` hooks call `session-log.sh` with the session JSON. |
| **Codex** | A shell function wraps `codex`; on exit it reads the newest rollout file in `~/.codex/sessions`, extracts the session id + cwd, and logs it. |

Both feed the same writer (`session-log.sh`), which writes `<cwd>/session.txt`: removes any existing line for that session, then appends it at the bottom (newest last).

- Session **start** writes the ID immediately → survives crashes / `kill` / no clean exit.
- Session **end** confirms it / moves it to the bottom.
- A start-written ID whose conversation never persisted (abandoned before the first turn) will not resume — just use the next line.

## Files

| File | Location after install |
|------|------------------------|
| `session-log.sh` | `~/.claude/hooks/session-log.sh` |
| `codex-session-log.sh` | `~/.claude/hooks/codex-session-log.sh` |
| `resume` | `~/.local/bin/resume` |

## Ignore session.txt globally (optional)

To keep `session.txt` out of your git repos:

```bash
git config --global core.excludesFile ~/.config/git/ignore
echo 'session.txt' >> ~/.config/git/ignore
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/uninstall.sh | bash
```

Removes hooks, wrapper, and the `resume` command. Existing `session.txt` files are left alone.

## License

MIT
