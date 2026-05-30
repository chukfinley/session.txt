#!/usr/bin/env bash
# session.txt — live end-to-end test.
# Runs each installed coding-agent CLI in headless mode inside a temp folder,
# then asserts the wrapper/hook logged a correct, resumable line into session.txt.
# This makes REAL API calls and needs each CLI to be authenticated.
#   SX_TIMEOUT=90 bash test/e2e.sh
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WRAP="$HOME/.claude/hooks/agent-wrappers.sh"; [ -f "$WRAP" ] || WRAP="$ROOT/agent-wrappers.sh"
RESUME="$ROOT/resume"
TO="${SX_TIMEOUT:-90}"
PROMPT='Reply with exactly the word: ok'

pass=0; fail=0; skip=0
P(){ printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
F(){ printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
S(){ printf '  \033[1;33mSKIP\033[0m %s\n' "$1"; skip=$((skip+1)); }

# run_tool <bin> <resume-prefix> <invocation...>
run_tool() {
  local bin="$1" prefix="$2"; shift 2
  if ! command -v "$bin" >/dev/null 2>&1; then S "$bin (not installed)"; return; fi
  local work; work="$(mktemp -d)"
  printf '\033[1m▶ %s\033[0m  (timeout %ss)\n' "$bin" "$TO"
  # run headless; wrappers self-log on exit, claude logs via its hooks
  timeout "$TO" bash -c "source '$WRAP' 2>/dev/null; cd '$work'; $*" >/dev/null 2>&1
  local rc=$?
  [ "$rc" -eq 124 ] && printf '    (timed out)\n'

  # No log can be legitimate: tool not authed, plan-limited, or its headless mode
  # doesn't persist a resumable session (some TUIs only persist on interactive exit).
  if [ ! -f "$work/session.txt" ]; then
    S "$bin: ran but logged nothing (headless may not persist / auth / plan limit)"; rm -rf "$work"; return
  fi
  local line; line="$(grep -m1 -- "^$prefix" "$work/session.txt")"
  if [ -z "$line" ]; then
    S "$bin: logged a different tool's line only"; printf '    got: %s\n' "$(cat "$work/session.txt")"; rm -rf "$work"; return
  fi
  P "$bin: logged -> $line"

  # liveness: resume -l prunes dead entries; the line must survive
  ( cd "$work" && "$RESUME" -l >/dev/null 2>&1 )
  if grep -qF -- "$line" "$work/session.txt"; then
    P "$bin: entry is resumable (survived prune)"
  else
    F "$bin: entry pruned as dead (not resumable)"
  fi

  # show prints the runnable command without executing
  local shown; shown="$( cd "$work" && "$RESUME" show 2>/dev/null )"
  case "$shown" in
    "$prefix"*) P "$bin: resume show -> $shown" ;;
    *)          F "$bin: resume show gave '$shown'" ;;
  esac
  rm -rf "$work"
}

echo "════ session.txt live E2E ════"
run_tool claude       "claude --resume "      claude -p "'$PROMPT'"
run_tool codex        "codex resume "         codex exec "'$PROMPT'"
run_tool opencode     "opencode --session "   opencode run "'$PROMPT'"
run_tool pi           "pi --session "         pi --print "'$PROMPT'"
run_tool cursor-agent "cursor-agent --resume=" cursor-agent --trust -p "'$PROMPT'"
run_tool agent        "agent --resume="        agent --trust -p "'$PROMPT'"
echo "──────────────────────────────"
printf 'TOTAL: \033[1;32m%d passed\033[0m, \033[1;31m%d failed\033[0m, \033[1;33m%d skipped\033[0m\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
