#!/usr/bin/env bash
# session.txt — core writer
# Wird von Claude Code (SessionStart/SessionEnd hook) und vom codex-Wrapper aufgerufen.
# Liest JSON von stdin: { "session_id": "...", "cwd": "...", "tool": "claude|codex" }
# Schreibt eine resume-Zeile in <cwd>/session.txt:
#   claude --resume <id>      (tool=claude, default)
#   codex resume <id>         (tool=codex)
# Neueste Session steht immer UNTEN. Jede Session nur einmal (Duplikate werden entfernt).

input="$(cat)"

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
tool="$(printf '%s' "$input" | jq -r '.tool // "claude"')"

# Ohne Session-ID: nichts tun
[ -z "$session_id" ] && exit 0

target="${cwd:-$(pwd)}/session.txt"

case "$tool" in
  codex) line="codex resume ${session_id}" ;;
  *)     line="claude --resume ${session_id}" ;;
esac

# Bestehende Datei laden, gleiche Zeile entfernen, neue Zeile unten anhaengen.
old=""
[ -f "$target" ] && old="$(grep -vxF "$line" "$target" 2>/dev/null)"

{
  [ -n "$old" ] && printf '%s\n' "$old"
  printf '%s\n' "$line"
} > "$target"

exit 0
