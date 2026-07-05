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
#   CONDUCTOR_REFLECT_CLI   force a CLI (claude|codex|gemini|cursor-agent|copilot|devin)
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
  for c in claude codex gemini cursor-agent copilot devin; do
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

# Headless, non-interactive invocation per tool (flags verified 2026-07-05).
case "$CLI" in
  claude)       exec claude -p "$PROMPT" --permission-mode acceptEdits ;;
  codex)        exec codex exec --sandbox workspace-write "$PROMPT" ;;
  gemini)       exec gemini -p "$PROMPT" ;;
  cursor-agent) exec cursor-agent -p --force "$PROMPT" ;;
  copilot)      exec copilot -p "$PROMPT" --allow-tool=write --no-ask-user ;;
  devin)        exec devin -p "$PROMPT" ;;
  *)            echo "conductor-reflect: unknown CLI '$CLI'" >&2; exit 0 ;;
esac
