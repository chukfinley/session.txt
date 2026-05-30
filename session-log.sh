#!/usr/bin/env bash
# session.txt — core writer
# Called by Claude Code hooks (Stop / SessionEnd) and by the agent wrappers.
# Reads JSON from stdin:
#   { "session_id": "...", "cwd": "...", "tool": "claude|codex|opencode|pi|cursor-agent|agent",
#     "transcript_path": "...", "title": "..." }
# Writes a resume line into <cwd>/session.txt, e.g.:
#   claude --resume <id>  # <title>
#   opencode --session <id>  # <title>
# The "# <title>" part is a shell comment, so each line stays copy-paste runnable.
# Newest session is always at the BOTTOM. Each session appears once (deduped by command).
#
# Only resumable sessions are logged: if transcript_path is given but the file/dir
# does not exist, the session was never persisted -> skip it (no dead entries).

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
if [ -z "$title" ] && [ "$tool" = "claude" ] && [ -n "$transcript" ] && [ -e "$transcript" ]; then
  title="$(jq -r 'select(.type=="ai-title") | .aiTitle // empty' "$transcript" 2>/dev/null | tail -1)"
fi

# Sanitize title: single line, trimmed, capped length
title="$(printf '%s' "$title" | tr '\n\r\t' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-60)"

target="${cwd:-$(pwd)}/session.txt"

case "$tool" in
  codex)        base="codex resume ${session_id}" ;;
  opencode)     base="opencode --session ${session_id}" ;;
  pi)           base="pi --session ${session_id}" ;;
  cursor-agent) base="cursor-agent --resume=${session_id}" ;;
  agent)        base="agent --resume=${session_id}" ;;
  *)            base="claude --resume ${session_id}" ;;
esac

line="$base"
[ -n "$title" ] && line="${base}  # ${title}"

# Load existing file, drop any line whose command (ignoring "# title") equals this
# one, then append the new line at the bottom.
old=""
if [ -f "$target" ]; then
  old="$(awk -v k="$base" '{ c=$0; sub(/[ \t]*#.*$/,"",c); sub(/[ \t]+$/,"",c); if (c != k && $0 !~ /^[ \t]*$/) print }' "$target")"
fi

{
  [ -n "$old" ] && printf '%s\n' "$old"
  printf '%s\n' "$line"
} > "$target"

exit 0
