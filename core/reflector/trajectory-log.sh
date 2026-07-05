#!/usr/bin/env bash
#
# CONDUCTOR — portable trajectory logger for non-Claude adapters.
# Wired to a tool's session-end hook. Reads the hook's stdin JSON, extracts the
# transcript path + a session id + cwd, and UPSERTS one pointer record per session
# into .conductor/trajectories/index.jsonl for the Reflector to consume.
#
# Upsert (not blind append) because some tools' nearest "session-end" event is
# turn-scoped (Codex Stop) or response-scoped (Windsurf post_cascade_response),
# so the same session would otherwise be logged many times.
#
# Opt-in gated on .conductor/reflect/ (created only by the self-improvement recipe).
# Fail-open, non-blocking. Env: CONDUCTOR_TRAJ_DIR, CONDUCTOR_REFLECT_DIR,
# CONDUCTOR_SKIP_TRAJLOG=1 to disable.
set -u

[ "$(/usr/bin/printenv CONDUCTOR_SKIP_TRAJLOG 2>/dev/null || true)" = "1" ] && exit 0

# Anchor to project root: when installed, this script lives at .conductor/reflect/,
# so ../.. is root. Only re-anchor in that case (running from core/ keeps the cwd).
_self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _self=""
case "$_self" in
  */.conductor/reflect) _root="$(cd "$_self/../.." 2>/dev/null && pwd)"; [ -n "$_root" ] && cd "$_root" 2>/dev/null || true ;;
esac

TRAJ_DIR="${CONDUCTOR_TRAJ_DIR:-.conductor/trajectories}"
REFLECT_DIR="${CONDUCTOR_REFLECT_DIR:-.conductor/reflect}"
[ -d "$REFLECT_DIR" ] || exit 0          # opt-in gate

# Manual invocation without piped stdin → no-op (hooks always pipe JSON).
[ -t 0 ] && exit 0
INPUT="$(/bin/cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# Tolerant flat-JSON string extraction (handles snake/camel + nested tool_info).
jval() { printf '%s' "$1" | /usr/bin/grep -oE "\"($2)\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | /usr/bin/head -n1 | /usr/bin/sed -E 's/^.*:[[:space:]]*"([^"]*)"$/\1/'; }
TRANSCRIPT="$(jval "$INPUT" 'transcript_path|transcriptPath')"
SESSION="$(jval "$INPUT" 'session_id|sessionId|conversation_id|trajectory_id')"
[ -n "$SESSION" ] || SESSION="unknown"

/bin/mkdir -p "$TRAJ_DIR" 2>/dev/null || exit 0
TS="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
GIT_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
CWD="$(pwd)"
esc() { printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'; }
LINE="$(printf '{"ts":"%s","session":"%s","transcript":"%s","git_head":"%s","cwd":"%s"}' "$TS" "$(esc "$SESSION")" "$(esc "$TRANSCRIPT")" "$GIT_HEAD" "$(esc "$CWD")")"

IDX="$TRAJ_DIR/index.jsonl"
if [ -f "$IDX" ]; then
  _tmp="$IDX.$$.tmp"                        # PID-unique: avoid a race on concurrent hook fires
  /usr/bin/grep -vF "\"session\":\"$(esc "$SESSION")\"" "$IDX" > "$_tmp" 2>/dev/null || : > "$_tmp"
  /bin/mv "$_tmp" "$IDX" 2>/dev/null || true
fi
printf '%s\n' "$LINE" >> "$IDX"
exit 0
