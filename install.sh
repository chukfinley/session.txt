#!/usr/bin/env bash
# session.txt — installer
#   curl -fsSL https://raw.githubusercontent.com/chukfinley/session.txt/main/install.sh | bash
#
# Installiert:
#   - Claude Code Hook (SessionStart + SessionEnd) -> schreibt resume-Command in ./session.txt
#   - codex-Wrapper (zsh/bash) -> dito fuer OpenAI Codex
#   - `resume` Command -> startet die neueste Session aus ./session.txt
set -euo pipefail

RAW="https://raw.githubusercontent.com/chukfinley/session.txt/main"
HOOKS_DIR="$HOME/.claude/hooks"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

log() { printf '\033[1;32m›\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v jq  >/dev/null 2>&1 || die "jq fehlt. Installieren: sudo apt install jq (oder brew install jq)"
command -v curl >/dev/null 2>&1 || die "curl fehlt."

mkdir -p "$HOOKS_DIR" "$BIN_DIR" "$(dirname "$SETTINGS")"

log "Lade Dateien von $RAW"
curl -fsSL "$RAW/session-log.sh"        -o "$HOOKS_DIR/session-log.sh"
curl -fsSL "$RAW/codex-session-log.sh"  -o "$HOOKS_DIR/codex-session-log.sh"
curl -fsSL "$RAW/resume"                -o "$BIN_DIR/resume"
chmod +x "$HOOKS_DIR/session-log.sh" "$BIN_DIR/resume"

# --- Claude Code Hooks in settings.json mergen (idempotent) -----------------
log "Registriere Claude Code Hooks in $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
CMD='"$HOME/.claude/hooks/session-log.sh"'
tmp="$(mktemp)"
jq --arg cmd "$CMD" '
  def addhook($event):
    .hooks[$event] = (
      ((.hooks[$event] // [])
        | map(select( ((.hooks // []) | map(.command) | index($cmd)) | not )))
      + [ { hooks: [ { type: "command", command: $cmd } ] } ]
    );
  .hooks = (.hooks // {})
  | addhook("SessionStart")
  | addhook("SessionEnd")
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# --- codex-Wrapper in Shell-RCs sourcen (idempotent) ------------------------
MARK="# >>> session.txt codex hook >>>"
SRC='[ -f "$HOME/.claude/hooks/codex-session-log.sh" ] && . "$HOME/.claude/hooks/codex-session-log.sh"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -qF "$MARK" "$rc"; then
    log "codex-Wrapper schon in $(basename "$rc")"
  else
    printf '\n%s\n%s\n# <<< session.txt codex hook <<<\n' "$MARK" "$SRC" >> "$rc"
    log "codex-Wrapper in $(basename "$rc") eingetragen"
  fi
done

# --- PATH-Hinweis -----------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR ist nicht im PATH. Fuege hinzu: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
log "Fertig."
echo "  • Claude: neue Session -> ./session.txt wird automatisch geschrieben."
echo "  • Codex:  neues Terminal oeffnen (oder: source ~/.zshrc), dann codex nutzen."
echo "  • resume        startet neueste Session aus ./session.txt"
echo "  • resume -l     Liste   |   resume N   Eintrag N"
