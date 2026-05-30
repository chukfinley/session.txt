# session.txt — codex wrapper
# In ~/.zshrc / ~/.bashrc gesourced. Definiert eine codex()-Funktion, die das echte
# codex aufruft und beim Beenden die zuletzt benutzte Session als
#   codex resume <id>
# in <cwd>/session.txt schreibt (gleiche Logik wie der Claude-Hook).
#
# Codex hat keinen Session-End-Hook, darum dieser Wrapper. Funktioniert in bash und zsh.

codex() {
  command codex "$@"
  local rc=$?

  local logger="$HOME/.claude/hooks/session-log.sh"
  local sessdir="$HOME/.codex/sessions"

  if command -v jq >/dev/null 2>&1 && [ -x "$logger" ] && [ -d "$sessdir" ]; then
    # Neueste Rollout-Datei (= zuletzt benutzte Session) finden
    local f
    f="$(ls -t "$sessdir"/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
    if [ -n "$f" ]; then
      # session_meta-Zeile -> { session_id, cwd, tool: codex } -> logger
      jq -c 'select(.type=="session_meta") | {session_id: .payload.id, cwd: .payload.cwd, tool: "codex"}' "$f" 2>/dev/null \
        | head -1 \
        | "$logger"
    fi
  fi

  return $rc
}
