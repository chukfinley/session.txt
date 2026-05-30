#!/usr/bin/env bash
# session.txt — deterministic test suite (no network).
# Exercises the writer (session-log.sh) and resume against fake session stores
# under a temporary $HOME, so every supported tool is covered end to end.
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG="$ROOT/session-log.sh"
RESUME="$ROOT/resume"

pass=0; fail=0
check() { # desc expected actual
  if [ "$2" = "$3" ]; then
    printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  \033[1;31mFAIL\033[0m %s\n' "$1"
    printf '       expected: %q\n' "$2"
    printf '       actual:   %q\n' "$3"
    fail=$((fail + 1))
  fi
}

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

tx="$WORK/tx.jsonl"
printf '%s\n' '{"type":"ai-title","aiTitle":"My Title"}' > "$tx"

echo "── writer (session-log.sh) ─────────────────────────────"

# claude + title pulled from transcript
echo "{\"session_id\":\"AAA\",\"cwd\":\"$WORK\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
check "claude line carries ai-title" "claude --resume AAA  # My Title" "$(cat session.txt)"

# transcript missing -> skipped (no dead entry)
echo "{\"session_id\":\"DEAD\",\"cwd\":\"$WORK\",\"transcript_path\":\"/no/such/file\"}" | bash "$LOG"
check "missing transcript is skipped" "claude --resume AAA  # My Title" "$(cat session.txt)"

# codex appended at the bottom (newest last)
echo "{\"session_id\":\"CDX\",\"cwd\":\"$WORK\",\"tool\":\"codex\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
check "codex appended newest-bottom" \
"claude --resume AAA  # My Title
codex resume CDX" "$(cat session.txt)"

# per-tool command mapping (incl. cursor's fused --resume= form and `agent`)
echo "{\"session_id\":\"ses_OC\",\"cwd\":\"$WORK\",\"tool\":\"opencode\",\"title\":\"OC\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
echo "{\"session_id\":\"PI1\",\"cwd\":\"$WORK\",\"tool\":\"pi\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
echo "{\"session_id\":\"CUR1\",\"cwd\":\"$WORK\",\"tool\":\"cursor-agent\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
echo "{\"session_id\":\"AGT\",\"cwd\":\"$WORK\",\"tool\":\"agent\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
echo "{\"session_id\":\"latest\",\"cwd\":\"$WORK\",\"tool\":\"gemini\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
check "all tool commands mapped" \
"claude --resume AAA  # My Title
codex resume CDX
opencode --session ses_OC  # OC
pi --session PI1
cursor-agent --resume=CUR1
agent --resume=AGT
gemini --resume latest" "$(cat session.txt)"

# dedup by command: re-logging AAA replaces old line and moves to bottom
echo "{\"session_id\":\"AAA\",\"cwd\":\"$WORK\",\"transcript_path\":\"$tx\",\"title\":\"Renamed\"}" | bash "$LOG"
check "re-log dedups by command + moves to bottom" \
"codex resume CDX
opencode --session ses_OC  # OC
pi --session PI1
cursor-agent --resume=CUR1
agent --resume=AGT
gemini --resume latest
claude --resume AAA  # Renamed" "$(cat session.txt)"

# gemini 'latest' re-log must not duplicate
echo "{\"session_id\":\"latest\",\"cwd\":\"$WORK\",\"tool\":\"gemini\",\"transcript_path\":\"$tx\"}" | bash "$LOG"
check "gemini latest stays single" "1" "$(grep -c '^gemini --resume latest$' session.txt)"

echo "── resume (liveness, prune, list, show, select) ────────"

# fake HOME with one live + matching dead store for each tool
HM="$(mktemp -d)"
md5="$(printf '%s' "$WORK" | md5sum | cut -d' ' -f1)"
sha="$(printf '%s' "$WORK" | sha256sum | cut -d' ' -f1)"
mkdir -p "$HM/.claude/projects/p" \
         "$HM/.codex/sessions/2026/05/10" \
         "$HM/.local/share/opencode" \
         "$HM/.pi/agent/sessions/x" \
         "$HM/.cursor/chats/$md5/CUR1" \
         "$HM/.cursor/chats/$md5/AGT" \
         "$HM/.gemini/tmp/$sha/chats"
: > "$HM/.claude/projects/p/AAA.jsonl"
: > "$HM/.codex/sessions/2026/05/10/rollout-2026-CDX.jsonl"
: > "$HM/.pi/agent/sessions/x/2026_PI1.jsonl"
: > "$HM/.gemini/tmp/$sha/chats/session-1.json"
# opencode keeps sessions in SQLite
sqlite3 "$HM/.local/share/opencode/opencode.db" \
  "CREATE TABLE session(id TEXT, directory TEXT, title TEXT, time_created INT, time_updated INT);
   INSERT INTO session VALUES('ses_OC','$WORK','OC',1,1);" 2>/dev/null

# session.txt: 7 live entries + 1 dead claude that must be pruned
cat > session.txt <<EOF
claude --resume AAA  # Renamed
codex resume CDX
opencode --session ses_OC  # OC
pi --session PI1
cursor-agent --resume=CUR1
agent --resume=AGT
gemini --resume latest
claude --resume GHOST  # ghost (no store)
EOF

HOME="$HM" bash "$RESUME" -l >/dev/null 2>&1   # triggers prune
check "dead entry pruned, 7 live kept" \
"claude --resume AAA  # Renamed
codex resume CDX
opencode --session ses_OC  # OC
pi --session PI1
cursor-agent --resume=CUR1
agent --resume=AGT
gemini --resume latest" "$(cat session.txt)"

# show prints the full command, no execution (covers fused --resume= parsing)
check "resume show -> newest command"       "gemini --resume latest"          "$(HOME="$HM" bash "$RESUME" show 2>/dev/null)"
check "resume 1 show -> oldest command"      "claude --resume AAA"             "$(HOME="$HM" bash "$RESUME" 1 show 2>/dev/null)"
check "resume 3 show -> opencode command"    "opencode --session ses_OC"       "$(HOME="$HM" bash "$RESUME" 3 show 2>/dev/null)"
check "resume 6 show -> agent (fused id)"    "agent --resume=AGT"              "$(HOME="$HM" bash "$RESUME" 6 show 2>/dev/null)"

# actual run replaces process with the command — stub the binaries on PATH
BIN="$WORK/bin"; mkdir -p "$BIN"
for t in claude codex opencode pi cursor-agent agent gemini; do
  printf '#!/bin/sh\necho "RAN %s $*"\n' "$t" > "$BIN/$t"; chmod +x "$BIN/$t"
done
check "resume runs newest (gemini)"  "RAN gemini --resume latest"        "$(cd "$WORK" && HOME="$HM" PATH="$BIN:$PATH" bash "$RESUME" 2>/dev/null)"
check "resume 4 runs pi"             "RAN pi --session PI1"              "$(cd "$WORK" && HOME="$HM" PATH="$BIN:$PATH" bash "$RESUME" 4 2>/dev/null)"
check "resume 6 runs agent (fused)"  "RAN agent --resume=AGT"           "$(cd "$WORK" && HOME="$HM" PATH="$BIN:$PATH" bash "$RESUME" 6 2>/dev/null)"

rm -rf "$HM"
echo "────────────────────────────────────────────────────────"
printf 'TOTAL: \033[1;32m%d passed\033[0m, \033[1;31m%d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
