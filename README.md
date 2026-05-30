# session.txt

Never lose an AI coding session again. Drops a `session.txt` into every folder you work in, listing the **resume commands** for your Claude Code and OpenAI Codex sessions — newest at the bottom, deduplicated, one line each.

```text
claude --resume 2e3204d9-fac4-4fa4-b578-09a5b1c6bfba  # Fix auth middleware
codex resume 019e12e7-6090-7372-95e0-5098aa1d98c0  # Refactor renderer
claude --resume 6b2a13c9-344c-4053-8d19-53930f371e9b  # Explore repository   ← newest
```

Each line is a runnable command; the `# title` is a shell comment (Claude's own auto-generated session title), so you can paste the whole line and it just works. No more guessing which session belonged to which folder, or hunting through `claude --resume` pickers. Just run `resume`.

## Why

`claude -c` continues the *last* session, but only if you remember which directory you were in. Codex has no session-end hook at all. This tool logs the resume command to disk **after every turn** (crash-safe) and **on exit**, and only ever records sessions that actually persisted — so the IDs in `session.txt` are always resumable.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/install.sh | bash
```

Requirements: `jq`, `curl`. (`sudo apt install jq` / `brew install jq`)

The installer:
- adds Claude Code `Stop` + `SessionEnd` hooks to `~/.claude/settings.json` (merged, existing settings untouched)
- sources a `codex` wrapper from `~/.zshrc` / `~/.bashrc`
- installs the `resume` command to `~/.local/bin`

Open a new terminal (or `source ~/.zshrc`) afterwards so the codex wrapper loads.

### Update

Re-run the same command — it is idempotent and cleans up older versions:

```bash
curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/install.sh | bash
```

## Usage

It runs itself. Use Claude or Codex normally — each session appends its resume command to `session.txt` in the folder you launched from.

To jump back in:

```bash
resume          # start the newest session in ./session.txt
resume -l       # numbered list with titles (1 = oldest, at top)
resume N        # start entry N  (e.g. resume 1 = oldest)
```

`resume -l` prints something human-friendly instead of raw UUIDs:

```text
 1  claude  6b2a13c9  Explore repository contents
 2  codex   019e12e7  Refactor renderer
 3  claude  2e3204d9  Fix auth middleware
```

`resume` runs whatever the line says, so it resumes Claude *and* Codex sessions transparently. On every run it also **self-cleans**: any entry whose session no longer exists on disk is dropped from `session.txt`.

## How it works

| Tool | Mechanism |
|------|-----------|
| **Claude Code** | `Stop` (after each turn) + `SessionEnd` hooks call `session-log.sh` with the session JSON. The session title comes from Claude's own `ai-title`. |
| **Codex** | A shell function wraps `codex`; on exit it reads the newest rollout file in `~/.codex/sessions`, extracts the session id + cwd, and logs it. |

Both feed the same writer (`session-log.sh`), which writes `<cwd>/session.txt`: removes any existing line for that session id, then appends it at the bottom (newest last) with a `# title` comment.

- It only logs sessions whose transcript actually exists on disk, so the list never fills with non-resumable IDs.
- Logging after every turn means a hard crash (no clean exit) still leaves a resumable entry behind.

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
