#!/usr/bin/env bash
#
# CONDUCTOR — weekly Reflector runner (portable).
# Register this with a scheduler (cron / launchd / a tool's native scheduler) to
# run the Reflector on a cadence. See .conductor/reflect/SCHEDULING.md.
#
# It runs the reflect brief NON-INTERACTIVELY with the first supported CLI found on
# PATH. Local trajectory files under .conductor/ are read directly, so the scheduler
# MUST run locally (OS cron/launchd, Claude Desktop task, or Codex app automation) —
# a cloud scheduler runs on a fresh clone and cannot see un-committed .conductor/.
#
# Env:
#   CONDUCTOR_REFLECT_CLI   force a CLI (claude|codex|gemini|cursor-agent|copilot|devin|opencode)
#   CONDUCTOR_REFLECT_DRYRUN=1  print the chosen CLI + exit (do not run)
set -u

# Anchor to project root: this script lives at .conductor/reflect/, so ../.. is root.
_self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 1
case "$_self" in
  */.conductor/reflect) cd "$_self/../.." 2>/dev/null || exit 1 ;;
esac

# Resolve the CLI first, so a dry-run can confirm wiring even before any trajectory.
CLI="${CONDUCTOR_REFLECT_CLI:-}"
if [ -n "$CLI" ]; then
  command -v "$CLI" >/dev/null 2>&1 || { echo "conductor-reflect: CONDUCTOR_REFLECT_CLI='$CLI' is not on PATH" >&2; exit 0; }
else
  for c in claude codex gemini cursor-agent copilot devin opencode; do
    if command -v "$c" >/dev/null 2>&1; then CLI="$c"; break; fi
  done
fi
[ -n "$CLI" ] || { echo "conductor-reflect: no supported CLI on PATH (set CONDUCTOR_REFLECT_CLI)" >&2; exit 0; }

if [ "${CONDUCTOR_REFLECT_DRYRUN:-}" = "1" ]; then
  echo "conductor-reflect: would run reflect via '$CLI'"
  exit 0
fi

# Real run: nothing to reflect on yet → no-op (not an error).
[ -s .conductor/trajectories/index.jsonl ] || { echo "conductor-reflect: no trajectories yet"; exit 0; }

PROMPT="$(/bin/cat "$_self/reflect-brief.md" 2>/dev/null || true)"
[ -n "$PROMPT" ] || { echo "conductor-reflect: reflect-brief.md missing" >&2; exit 0; }

# The model is an analyzer, never a writer. Each supported invocation below has
# a verified native read-only contract. Its stdout is untrusted data; only the
# deterministic writer may append the one proposal target afterward.
OUT="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/conductor-reflect-output.XXXXXX")" || exit 1
trap '/bin/rm -f "$OUT"' EXIT INT TERM
BEFORE=""
CHECK_GIT="false"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CHECK_GIT="true"
  BEFORE="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null || true)"
fi

case "$CLI" in
  claude)
    claude -p "$PROMPT" --output-format text --permission-mode plan \
      --disallowedTools Edit Write NotebookEdit >"$OUT" ;;
  codex)
    codex exec --sandbox read-only "$PROMPT" >"$OUT" ;;
  gemini)
    gemini --approval-mode=plan -p "$PROMPT" --output-format text >"$OUT" ;;
  cursor-agent)
    cursor-agent -p --mode=ask --output-format text "$PROMPT" >"$OUT" ;;
  copilot)
    copilot -p "$PROMPT" --available-tools=view,grep,glob \
      --deny-tool=write,memory,shell,url --no-ask-user >"$OUT" ;;
  opencode)
    opencode run --agent reflector "$PROMPT" >"$OUT" ;;
  devin)
    echo "conductor-reflect: devin has no verified headless read-only contract; run the installed manual /reflect workflow instead" >&2
    exit 2 ;;
  *)
    echo "conductor-reflect: unknown CLI '$CLI'" >&2
    exit 2 ;;
esac
MODEL_RC=$?
[ "$MODEL_RC" -eq 0 ] || { echo "conductor-reflect: analyzer failed (exit $MODEL_RC); no proposal was written" >&2; exit "$MODEL_RC"; }

if [ "$CHECK_GIT" = "true" ]; then
  AFTER="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null || true)"
  [ "$BEFORE" = "$AFTER" ] || {
    echo "conductor-reflect: analyzer changed the worktree despite its read-only contract; refusing proposal import" >&2
    exit 2
  }
fi

WRITER="$_self/reflection-proposals.js"
[ -f "$WRITER" ] || { echo "conductor-reflect: trusted proposal writer missing" >&2; exit 2; }
node "$WRITER" --from="$OUT" --target=docs/REFLECTION-PROPOSALS.md
