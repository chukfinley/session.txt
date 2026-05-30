#!/usr/bin/env bash
# session.txt — uninstaller
#   curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/uninstall.sh | bash
# Entfernt Hooks, Wrapper und resume-Command. Vorhandene session.txt-Dateien bleiben.
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"
CMD='"$HOME/.claude/hooks/session-log.sh"'

log() { printf '\033[1;32m›\033[0m %s\n' "$*"; }

rm -f "$HOOKS_DIR/session-log.sh" "$HOOKS_DIR/codex-session-log.sh" "$BIN_DIR/resume"
log "Skripte entfernt"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg cmd "$CMD" '
    def strip($event):
      .hooks[$event] = ((.hooks[$event] // [])
        | map(select( ((.hooks // []) | map(.command) | index($cmd)) | not )));
    if .hooks then strip("SessionStart") | strip("SessionEnd") else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  log "Hooks aus settings.json entfernt"
fi

# codex-Wrapper-Block aus RCs loeschen
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -qF "# >>> session.txt codex hook >>>" "$rc"; then
    sed -i '/# >>> session.txt codex hook >>>/,/# <<< session.txt codex hook <<</d' "$rc"
    log "codex-Wrapper aus $(basename "$rc") entfernt"
  fi
done

log "Deinstalliert. session.txt-Dateien wurden nicht angefasst."
