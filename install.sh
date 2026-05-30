#!/usr/bin/env bash
# session.txt — installer (also updater: re-run this any time)
#   curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/install.sh | bash
#
# Installs / updates:
#   - Claude Code hooks (Stop + SessionEnd) -> log resume command to ./session.txt
#   - codex wrapper (zsh/bash) -> same, for OpenAI Codex
#   - `resume` command -> relaunch the newest session from ./session.txt
set -euo pipefail

RAW="https://raw.githubusercontent.com/chukfinley/session.txt/main"
HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

log()  { printf '\033[1;32m›\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v jq   >/dev/null 2>&1 || die "jq is required. Install: sudo apt install jq  (or brew install jq)"
command -v curl >/dev/null 2>&1 || die "curl is required."

mkdir -p "$HOOKS_DIR" "$BIN_DIR" "$(dirname "$SETTINGS")"

log "Downloading files from $RAW"
curl -fsSL "$RAW/session-log.sh"    -o "$HOOKS_DIR/session-log.sh"
curl -fsSL "$RAW/agent-wrappers.sh" -o "$HOOKS_DIR/agent-wrappers.sh"
curl -fsSL "$RAW/resume"            -o "$BIN_DIR/resume"
chmod +x "$HOOKS_DIR/session-log.sh" "$BIN_DIR/resume"
# remove the old codex-only wrapper from earlier versions
rm -f "$HOOKS_DIR/codex-session-log.sh"

# --- merge Claude Code hooks into settings.json (idempotent) ----------------
log "Registering Claude Code hooks in $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
CMD='"$HOME/.claude/hooks/session-log.sh"'
tmp="$(mktemp)"
jq --arg cmd "$CMD" '
  # remove our command from an event list
  def strip($e):
    .hooks[$e] = ((.hooks[$e] // [])
      | map(select( ((.hooks // []) | map(.command) | index($cmd)) | not )));
  # ensure our command is present once in an event list
  def add($e):
    strip($e) | .hooks[$e] = ((.hooks[$e] // []) + [ { hooks: [ { type: "command", command: $cmd } ] } ]);
  .hooks = (.hooks // {})
  | strip("SessionStart")          # remove old placement from earlier versions
  | add("Stop")                    # log after each turn (crash-safe)
  | add("SessionEnd")              # log on clean exit
  | (if (.hooks.SessionStart // []) == [] then del(.hooks.SessionStart) else . end)
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# --- source agent wrappers from shell rc files (idempotent + updatable) -----
MARK_OPEN="# >>> session.txt agent wrappers >>>"
MARK_CLOSE="# <<< session.txt agent wrappers <<<"
SRC='[ -f "$HOME/.claude/hooks/agent-wrappers.sh" ] && . "$HOME/.claude/hooks/agent-wrappers.sh"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  # drop any previous block (old codex-only marker included), then append fresh
  sed -i '/# >>> session.txt codex hook >>>/,/# <<< session.txt codex hook <<</d' "$rc"
  sed -i "\#$MARK_OPEN#,\#$MARK_CLOSE#d" "$rc"
  printf '\n%s\n%s\n%s\n' "$MARK_OPEN" "$SRC" "$MARK_CLOSE" >> "$rc"
  log "agent wrappers sourced from $(basename "$rc")"
done

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on PATH. Add: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
log "Done."
echo "  • Claude logs via hooks. Codex / opencode / pi / cursor-agent / gemini log via wrappers."
echo "  • Open a new terminal (or: source ~/.zshrc) so the wrappers load."
echo "  • resume        start the newest session from ./session.txt"
echo "  • resume -l     list with titles   |   resume N   start entry N"
echo "  • resume N show print the full command instead of running it"
