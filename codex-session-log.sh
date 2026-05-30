# session.txt — codex wrapper
# Sourced from ~/.zshrc / ~/.bashrc. Defines a codex() function that runs the real
# codex and, on exit, logs the last-used session as
#   codex resume <id>
# into <cwd>/session.txt (same writer as the Claude hook).
#
# Codex has no session-end hook, hence this wrapper. Works in bash and zsh.

codex() {
  command codex "$@"
  local rc=$?

  local logger="$HOME/.claude/hooks/session-log.sh"
  local sessdir="$HOME/.codex/sessions"

  if command -v jq >/dev/null 2>&1 && [ -x "$logger" ] && [ -d "$sessdir" ]; then
    # newest rollout file (= last-used session)
    local f
    f="$(ls -t "$sessdir"/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
    if [ -n "$f" ]; then
      # session_meta line -> { session_id, cwd, tool: codex, transcript_path } -> logger
      jq -c --arg tp "$f" \
        'select(.type=="session_meta") | {session_id: .payload.id, cwd: .payload.cwd, tool: "codex", transcript_path: $tp}' \
        "$f" 2>/dev/null | head -1 | "$logger"
    fi
  fi

  return $rc
}
