#!/usr/bin/env bash
# session.txt — uninstaller
#   curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/uninstall.sh | bash
# Removes hooks, wrapper and the resume command. Existing session.txt files are kept.
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"
CMD='"$HOME/.claude/hooks/session-log.sh"'

log() { printf '\033[1;32m›\033[0m %s\n' "$*"; }

rm -f "$HOOKS_DIR/session-log.sh" "$HOOKS_DIR/codex-session-log.sh" "$BIN_DIR/resume"
log "Scripts removed"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg cmd "$CMD" '
    def strip($e):
      .hooks[$e] = ((.hooks[$e] // [])
        | map(select( ((.hooks // []) | map(.command) | index($cmd)) | not )));
    if .hooks then strip("SessionStart") | strip("Stop") | strip("SessionEnd") else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  log "Hooks removed from settings.json"
fi

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -qF "# >>> session.txt codex hook >>>" "$rc"; then
    sed -i '/# >>> session.txt codex hook >>>/,/# <<< session.txt codex hook <<</d' "$rc"
    log "codex wrapper removed from $(basename "$rc")"
  fi
done

log "Uninstalled. Your session.txt files were left untouched."
