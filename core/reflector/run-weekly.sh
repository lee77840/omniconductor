#!/usr/bin/env bash
# Portable opt-in Reflector entry point. Node owns bounded execution.
set -u
_self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 1
case "$_self" in */.conductor/reflect) cd "$_self/../.." || exit 1 ;; esac
CLI="${CONDUCTOR_REFLECT_CLI:-}"
if [ -z "$CLI" ]; then
  for c in claude codex gemini cursor-agent copilot devin opencode; do
    if command -v "$c" >/dev/null 2>&1; then CLI="$c"; break; fi
  done
fi
case "$CLI" in claude|codex|gemini|cursor-agent|copilot|devin|opencode) ;; *) echo 'conductor-reflect: no supported CLI selected' >&2; exit 2 ;; esac
command -v "$CLI" >/dev/null 2>&1 || { echo "conductor-reflect: '$CLI' is not on PATH" >&2; exit 2; }
if [ "${CONDUCTOR_REFLECT_DRYRUN:-}" = 1 ]; then
  echo "conductor-reflect: would run reflect via '$CLI' (wiring only; no model call)"
  exit 0
fi
CONDUCTOR_REFLECT_BASH="$BASH"
if command -v cygpath >/dev/null 2>&1; then CONDUCTOR_REFLECT_BASH="$(cygpath -w "$BASH")"; fi
export CONDUCTOR_REFLECT_BASH
exec node "$_self/runner.js" "$CLI"
