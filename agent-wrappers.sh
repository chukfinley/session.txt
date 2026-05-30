# session.txt — agent wrappers
# Sourced from ~/.zshrc / ~/.bashrc. Wraps coding-agent CLIs that have no
# session-end hook (codex, opencode, pi, cursor-agent, gemini). After each run
# the wrapper finds the last-used session for the current folder and logs its
# resume command into <cwd>/session.txt (same writer as the Claude hook).
# Works in bash and zsh. Wrappers are always defined (so installing a tool later
# just works); each one no-ops if the tool or its data isn't present.

__sx_logger="$HOME/.claude/hooks/session-log.sh"

# Encode a path the way pi does: "/home/user/doc/Main" -> "--home-user-doc-Main--"
__sx_pi_enc() { printf -- '--%s--' "$(printf '%s' "$1" | sed 's#^/##; s#/#-#g')"; }

# --- codex ------------------------------------------------------------------
codex() {
  command codex "$@"; local rc=$?
  local d="$HOME/.codex/sessions" f
  if command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$d" ]; then
    f="$(ls -t "$d"/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
    [ -n "$f" ] && jq -c --arg tp "$f" \
      'select(.type=="session_meta") | {session_id:.payload.id, cwd:.payload.cwd, tool:"codex", transcript_path:$tp}' \
      "$f" 2>/dev/null | head -1 | "$__sx_logger"
  fi
  return $rc
}

# --- opencode ---------------------------------------------------------------
opencode() {
  command opencode "$@"; local rc=$?
  local d="$HOME/.local/share/opencode/storage/session" f
  if command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$d" ]; then
    # newest session (by time.updated) whose .directory == current folder
    f="$(jq -rc --arg p "$PWD" 'select(.directory==$p) | "\(.time.updated // 0)\t\(input_filename)"' \
          "$d"/*/ses_*.json 2>/dev/null | sort -rn | head -1 | cut -f2)"
    [ -n "$f" ] && jq -c '{session_id:.id, cwd:.directory, tool:"opencode", title:(.title // ""), transcript_path:input_filename}' \
      "$f" 2>/dev/null | head -1 | "$__sx_logger"
  fi
  return $rc
}

# --- pi ---------------------------------------------------------------------
pi() {
  command pi "$@"; local rc=$?
  local base="$HOME/.pi/agent/sessions" dir f
  if command -v jq >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ]; then
    dir="$base/$(__sx_pi_enc "$PWD")"
    f="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
    if [ -n "$f" ]; then
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
  command cursor-agent "$@"; local rc=$?
  local base="$HOME/.cursor/chats" h d id
  if command -v md5sum >/dev/null 2>&1 && [ -x "$__sx_logger" ] && [ -d "$base" ]; then
    h="$(printf '%s' "$PWD" | md5sum | cut -d' ' -f1)"
    d="$(ls -dt "$base/$h"/*/ 2>/dev/null | head -1)"
    if [ -n "$d" ]; then
      id="$(basename "$d")"
      printf '{"session_id":"%s","cwd":"%s","tool":"cursor-agent","transcript_path":"%s"}' "$id" "$PWD" "$d" | "$__sx_logger"
    fi
  fi
  return $rc
}

# --- gemini -----------------------------------------------------------------
# Gemini resumes by index/"latest", not a stable id, so we log `--resume latest`.
gemini() {
  command gemini "$@"; local rc=$?
  local h cd f
  if command -v sha256sum >/dev/null 2>&1 && [ -x "$__sx_logger" ]; then
    h="$(printf '%s' "$PWD" | sha256sum | cut -d' ' -f1)"
    cd="$HOME/.gemini/tmp/$h/chats"
    f="$(ls -t "$cd"/session-*.json 2>/dev/null | head -1)"
    [ -n "$f" ] && printf '{"session_id":"latest","cwd":"%s","tool":"gemini","transcript_path":"%s"}' "$PWD" "$f" | "$__sx_logger"
  fi
  return $rc
}
