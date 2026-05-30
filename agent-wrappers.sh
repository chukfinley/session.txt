# session.txt — agent wrappers
# Sourced from ~/.zshrc / ~/.bashrc. Wraps coding-agent CLIs that have no
# session-end hook (codex, opencode, pi, cursor-agent, gemini). After each run
# the wrapper finds the session that was actually used in THIS run for the current
# folder and logs its resume command into <cwd>/session.txt (same writer as the
# Claude hook). Works in bash and zsh. Wrappers are always defined (so installing a
# tool later just works); each one no-ops if the tool or its data isn't present.

__sx_logger="$HOME/.claude/hooks/session-log.sh"

# Encode a path the way pi does: "/home/user/doc/Main" -> "--home-user-doc-Main--"
__sx_pi_enc() { printf -- '--%s--' "$(printf '%s' "$1" | sed 's#^/##; s#/#-#g')"; }

# Was the file/dir touched at or after $2 (epoch seconds, with a small margin)?
# This is what keeps stale, unrelated sessions out of the log: only a session
# created or updated during this run is logged.
__sx_fresh() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)"
  [ "$m" -ge "$(( $2 - 5 ))" ]
}

# --- codex ------------------------------------------------------------------
codex() {
  local t0; t0="$(date +%s)"
  command codex "$@"; local rc=$?
  local d="$HOME/.codex/sessions" f
  if command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$d" ]; then
    f="$(ls -t "$d"/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
    if [ -n "$f" ] && __sx_fresh "$f" "$t0"; then
      jq -c --arg tp "$f" \
        'select(.type=="session_meta") | {session_id:.payload.id, cwd:.payload.cwd, tool:"codex", transcript_path:$tp}' \
        "$f" 2>/dev/null | head -1 | "$__sx_logger"
    fi
  fi
  return $rc
}

# --- opencode ---------------------------------------------------------------
# opencode (>=1.x) keeps sessions in a SQLite DB, not JSON files.
opencode() {
  local t0; t0="$(date +%s)"
  command opencode "$@"; local rc=$?
  local db="$HOME/.local/share/opencode/opencode.db"
  if command -v sqlite3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -f "$db" ]; then
    local p; p="${PWD//\'/\'\'}"
    local row
    row="$(sqlite3 -separator $'\t' "$db" \
      "SELECT id, title, max(time_updated,time_created) FROM session WHERE directory='$p' ORDER BY max(time_updated,time_created) DESC LIMIT 1;" 2>/dev/null)"
    if [ -n "$row" ]; then
      local id title newest
      IFS=$'\t' read -r id title newest <<<"$row"
      # only log if this session was touched during this run (time in ms)
      if [ -n "$newest" ] && [ "$newest" -ge "$(( (t0 - 5) * 1000 ))" ]; then
        jq -nc --arg s "$id" --arg c "$PWD" --arg t "$title" --arg tp "$db" \
          '{session_id:$s, cwd:$c, tool:"opencode", title:$t, transcript_path:$tp}' | "$__sx_logger"
      fi
    fi
  fi
  return $rc
}

# --- pi ---------------------------------------------------------------------
pi() {
  local t0; t0="$(date +%s)"
  command pi "$@"; local rc=$?
  local base="$HOME/.pi/agent/sessions" dir f
  if command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ]; then
    dir="$base/$(__sx_pi_enc "$PWD")"
    f="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
    if [ -n "$f" ] && __sx_fresh "$f" "$t0"; then
      local id cw ti
      id="$(head -1 "$f" | jq -r '.id // empty' 2>/dev/null)"
      cw="$(head -1 "$f" | jq -r '.cwd // empty' 2>/dev/null)"
      ti="$(jq -rc 'select(.type=="message" and .message.role=="user") | .message.content[]? | select(.type=="text") | .text' "$f" 2>/dev/null | head -1)"
      [ -n "$id" ] && jq -nc --arg s "$id" --arg c "${cw:-$PWD}" --arg t "$ti" --arg tp "$f" \
        '{session_id:$s, cwd:$c, tool:"pi", title:$t, transcript_path:$tp}' | "$__sx_logger"
    fi
  fi
  return $rc
}

# --- cursor-agent -----------------------------------------------------------
cursor-agent() {
  local t0; t0="$(date +%s)"
  command cursor-agent "$@"; local rc=$?
  local base="$HOME/.cursor/chats" h d id
  if command -v md5sum >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ]; then
    h="$(printf '%s' "$PWD" | md5sum | cut -d' ' -f1)"
    d="$(ls -dt "$base/$h"/*/ 2>/dev/null | head -1)"
    if [ -n "$d" ] && __sx_fresh "$d" "$t0"; then
      id="$(basename "$d")"
      printf '{"session_id":"%s","cwd":"%s","tool":"cursor-agent","transcript_path":"%s"}' "$id" "$PWD" "$d" | "$__sx_logger"
    fi
  fi
  return $rc
}

# --- gemini -----------------------------------------------------------------
# Gemini resumes by index/"latest", not a stable id, so we log `--resume latest`.
gemini() {
  local t0; t0="$(date +%s)"
  command gemini "$@"; local rc=$?
  local h cd f
  if command -v sha256sum >/dev/null 2>&1 && [ -x "$__sx_logger" ]; then
    h="$(printf '%s' "$PWD" | sha256sum | cut -d' ' -f1)"
    cd="$HOME/.gemini/tmp/$h/chats"
    f="$(ls -t "$cd"/session-*.json 2>/dev/null | head -1)"
    if [ -n "$f" ] && __sx_fresh "$f" "$t0"; then
      printf '{"session_id":"latest","cwd":"%s","tool":"gemini","transcript_path":"%s"}' "$PWD" "$f" | "$__sx_logger"
    fi
  fi
  return $rc
}
