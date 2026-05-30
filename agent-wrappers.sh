# session.txt — agent wrappers
# Sourced from ~/.zshrc / ~/.bashrc. Wraps coding-agent CLIs that have no
# session-end hook (codex, opencode, pi, cursor-agent / agent). After each
# run the wrapper finds the session used in THIS run for the current folder and
# logs its resume command into <cwd>/session.txt (same writer as the Claude hook).
#
# Logging runs on a clean exit AND on Ctrl-C (via an INT trap), because most of
# these TUIs are quit with Ctrl-C, which would otherwise abort the function.
# Works in bash and zsh. Wrappers are always defined; each no-ops if the tool or
# its data isn't present. Double-logging (trap + clean path) is harmless: the
# writer dedups by command.

__sx_logger="$HOME/.claude/hooks/session-log.sh"

# Encode a path the way pi does: "/home/user/doc/Main" -> "--home-user-doc-Main--"
__sx_pi_enc() { printf -- '--%s--' "$(printf '%s' "$1" | sed 's#^/##; s#/#-#g')"; }

# Was the file/dir touched at or after $2 (epoch seconds, small margin)?
# Keeps stale, unrelated sessions out of the log.
__sx_fresh() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)"
  [ "$m" -ge "$(( $2 - 5 ))" ]
}

# Generic runner: run the real binary, then log on both clean exit and Ctrl-C.
#   __sx_run <command-name> <emitter-fn> <args...>
__sx_run() {
  local cmdname="$1" emit="$2"; shift 2
  local t0; t0="$(date +%s)"
  trap "$emit $t0" INT
  command "$cmdname" "$@"
  local rc=$?
  trap - INT
  "$emit" "$t0"
  return $rc
}

# --- emitters (find this run's session, gate on freshness, pipe JSON) -------
__sx_emit_codex() {
  local d="$HOME/.codex/sessions" f
  command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$d" ] || return
  f="$(ls -t "$d"/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
  [ -n "$f" ] && __sx_fresh "$f" "$1" || return
  local id cw ti
  id="$(jq -rc 'select(.type=="session_meta") | .payload.id' "$f" 2>/dev/null | head -1)"
  cw="$(jq -rc 'select(.type=="session_meta") | .payload.cwd' "$f" 2>/dev/null | head -1)"
  # title = first real user prompt (skip injected <environment_context> etc.)
  ti="$(jq -rc 'select(.type=="response_item") | .payload | select(.role=="user") | .content[]? | (.text // empty)' "$f" 2>/dev/null \
        | grep -vE '^[[:space:]]*<' | grep -vE '^[[:space:]]*$' | head -1)"
  [ -n "$id" ] && jq -nc --arg s "$id" --arg c "${cw:-$PWD}" --arg t "$ti" --arg tp "$f" \
    '{session_id:$s, cwd:$c, tool:"codex", title:$t, transcript_path:$tp}' | "$__sx_logger"
}

__sx_emit_opencode() {
  local db="$HOME/.local/share/opencode/opencode.db"
  command -v sqlite3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -f "$db" ] || return
  local p; p="${PWD//\'/\'\'}"
  local row; row="$(sqlite3 -separator $'\t' "$db" \
    "SELECT id, title, max(time_updated,time_created) FROM session WHERE directory='$p' ORDER BY max(time_updated,time_created) DESC LIMIT 1;" 2>/dev/null)"
  [ -n "$row" ] || return
  local id title newest; IFS=$'\t' read -r id title newest <<<"$row"
  [ -n "$newest" ] && [ "$newest" -ge "$(( ($1 - 5) * 1000 ))" ] || return
  jq -nc --arg s "$id" --arg c "$PWD" --arg t "$title" --arg tp "$db" \
    '{session_id:$s, cwd:$c, tool:"opencode", title:$t, transcript_path:$tp}' | "$__sx_logger"
}

__sx_emit_pi() {
  local base="$HOME/.pi/agent/sessions" dir f
  command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ] || return
  dir="$base/$(__sx_pi_enc "$PWD")"
  f="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
  [ -n "$f" ] && __sx_fresh "$f" "$1" || return
  local id cw ti
  id="$(head -1 "$f" | jq -r '.id // empty' 2>/dev/null)"
  cw="$(head -1 "$f" | jq -r '.cwd // empty' 2>/dev/null)"
  ti="$(jq -rc 'select(.type=="message" and .message.role=="user") | .message.content[]? | select(.type=="text") | .text' "$f" 2>/dev/null | head -1)"
  [ -n "$id" ] && jq -nc --arg s "$id" --arg c "${cw:-$PWD}" --arg t "$ti" --arg tp "$f" \
    '{session_id:$s, cwd:$c, tool:"pi", title:$t, transcript_path:$tp}' | "$__sx_logger"
}

# Cursor's CLI ships as both `cursor-agent` and `agent`; log the name that was used.
__sx_cursor_log() {  # $1 = command name, $2 = run start
  local base="$HOME/.cursor/chats" h d id ti=""
  command -v md5sum >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ] || return
  h="$(printf '%s' "$PWD" | md5sum | cut -d' ' -f1)"
  d="$(ls -dt "$base/$h"/*/ 2>/dev/null | head -1)"
  [ -n "$d" ] && __sx_fresh "$d" "$2" || return
  id="$(basename "$d")"
  # cursor stores the chat name in store.db meta (value = hex-encoded JSON)
  if [ -f "$d/store.db" ] && command -v sqlite3 >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ti="$(sqlite3 "$d/store.db" 'select value from meta limit 1;' 2>/dev/null | xxd -r -p 2>/dev/null | jq -r '.name // empty' 2>/dev/null)"
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg s "$id" --arg c "$PWD" --arg tl "$1" --arg t "$ti" --arg tp "$d" \
      '{session_id:$s, cwd:$c, tool:$tl, title:$t, transcript_path:$tp}' | "$__sx_logger"
  else
    printf '{"session_id":"%s","cwd":"%s","tool":"%s","transcript_path":"%s"}' "$id" "$PWD" "$1" "$d" | "$__sx_logger"
  fi
}
__sx_emit_agent()       { __sx_cursor_log agent "$1"; }
__sx_emit_cursoragent() { __sx_cursor_log cursor-agent "$1"; }

# --- wrappers ---------------------------------------------------------------
codex()        { __sx_run codex        __sx_emit_codex       "$@"; }
opencode()     { __sx_run opencode     __sx_emit_opencode    "$@"; }
pi()           { __sx_run pi           __sx_emit_pi          "$@"; }
cursor-agent() { __sx_run cursor-agent __sx_emit_cursoragent "$@"; }
agent()        { __sx_run agent        __sx_emit_agent       "$@"; }
