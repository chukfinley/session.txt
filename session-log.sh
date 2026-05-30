#!/usr/bin/env bash
# session.txt — core writer
# Called by Claude Code (Stop / SessionEnd hook) and by the codex wrapper.
# Reads JSON from stdin:
#   { "session_id": "...", "cwd": "...", "tool": "claude|codex",
#     "transcript_path": "...", "title": "..." }
# Writes a resume line into <cwd>/session.txt:
#   claude --resume <id>  # <title>
#   codex resume <id>  # <title>
# The "# <title>" part is a shell comment, so each line stays copy-paste runnable.
# Newest session is always at the BOTTOM. Each session appears once (deduped by id).
#
# Only resumable sessions are logged: if transcript_path is given but the file does
# not exist, the session was never persisted -> skip it (no dead ids in the list).

input="$(cat)"

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
tool="$(printf '%s' "$input" | jq -r '.tool // "claude"')"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
title="$(printf '%s' "$input" | jq -r '.title // empty')"

# No session id: do nothing
[ -z "$session_id" ] && exit 0

# Transcript path known but missing on disk -> not resumable yet -> skip
if [ -n "$transcript" ] && [ ! -e "$transcript" ]; then
  exit 0
fi

# For Claude, derive the session title from the transcript (Claude writes ai-title).
if [ -z "$title" ] && [ "$tool" != "codex" ] && [ -n "$transcript" ] && [ -e "$transcript" ]; then
  title="$(jq -r 'select(.type=="ai-title") | .aiTitle // empty' "$transcript" 2>/dev/null | tail -1)"
fi

# Sanitize title: single line, no leading/trailing space, capped length
title="$(printf '%s' "$title" | tr '\n\r\t' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-60)"

target="${cwd:-$(pwd)}/session.txt"

case "$tool" in
  codex) line="codex resume ${session_id}" ;;
  *)     line="claude --resume ${session_id}" ;;
esac
[ -n "$title" ] && line="${line}  # ${title}"

# Load existing file, drop any line for this session id, append the new line at bottom.
old=""
[ -f "$target" ] && old="$(grep -vF "$session_id" "$target" 2>/dev/null)"

{
  [ -n "$old" ] && printf '%s\n' "$old"
  printf '%s\n' "$line"
} > "$target"

exit 0
