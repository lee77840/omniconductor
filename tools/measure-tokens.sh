#!/usr/bin/env bash
#
# CONDUCTOR — Token measurement tool (Claude Code adapter)
#
# Reads Claude Code session JSONL files and produces a per-session token usage
# summary. Useful for KPI baseline measurement (cache hit rate, input tokens,
# tool calls per task).
#
# Usage:
#   tools/measure-tokens.sh [--latest | --session=<path>] [--export-csv=<path>]
#
# Examples:
#   tools/measure-tokens.sh --latest
#   tools/measure-tokens.sh --session=~/.claude/projects/-foo-bar/abc.jsonl
#   tools/measure-tokens.sh --latest --export-csv=/tmp/conductor-stats.csv
#
# Requirements:
#   - Claude Code installed (sessions live under ~/.claude/projects/<encoded>/*.jsonl)
#   - python3 (standard on macOS / Linux)
#
# Output:
#   - Total input tokens / output tokens / tool calls / dispatches
#   - Cache hit rate (cache_read / (cache_read + uncached_input))
#   - Top 5 most expensive turns by output tokens
#   - Optional CSV export

set -eu

LATEST="false"
SESSION_PATH=""
EXPORT_CSV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --latest) LATEST="true" ;;
    --session=*) SESSION_PATH="${1#--session=}" ;;
    --export-csv=*) EXPORT_CSV="${1#--export-csv=}" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: tools/measure-tokens.sh [--latest | --session=<path>] [--export-csv=<path>]

Reports input/output tokens, cache hit rate, and tool-call counts from a Claude Code session JSONL.

Options:
  --latest               Use the most-recently-modified session under ~/.claude/projects/
  --session=<path>       Use a specific session JSONL
  --export-csv=<path>    Also write a CSV summary
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

# Resolve session path.
if [ -n "$SESSION_PATH" ]; then
  [ -f "$SESSION_PATH" ] || { echo "Error: session not found: $SESSION_PATH" >&2; exit 1; }
elif [ "$LATEST" = "true" ]; then
  SESSION_PATH=$(/usr/bin/find ~/.claude/projects/ -name '*.jsonl' -type f -newer /tmp 2>/dev/null \
    | /usr/bin/xargs -I {} /bin/ls -t1 {} 2>/dev/null \
    | /usr/bin/head -n 1)
  # Fallback: use plain find + sort by mtime
  if [ -z "$SESSION_PATH" ]; then
    SESSION_PATH=$(/usr/bin/find ~/.claude/projects/ -name '*.jsonl' -type f 2>/dev/null \
      | while read -r f; do printf '%s\t%s\n' "$(/usr/bin/stat -f '%m' "$f" 2>/dev/null || echo 0)" "$f"; done \
      | /usr/bin/sort -rn | /usr/bin/head -n 1 | /usr/bin/cut -f2)
  fi
  [ -n "$SESSION_PATH" ] || { echo "Error: no session JSONL found under ~/.claude/projects/" >&2; exit 1; }
  echo "Using latest session: $SESSION_PATH"
else
  echo "Error: must pass --latest or --session=<path>" >&2
  exit 1
fi

# Use python3 for robust large-file parsing (jq -s fails on 100MB+ files).
EXPORT_ARG=""
if [ -n "$EXPORT_CSV" ]; then
  EXPORT_ARG="$EXPORT_CSV"
fi

python3 - "$SESSION_PATH" "$EXPORT_ARG" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
export_csv = sys.argv[2] if len(sys.argv) > 2 else ""

total_input = 0
total_output = 0
total_cache_read = 0
total_cache_write = 0
tool_calls = 0
dispatches = 0
turns = 0
turn_costs = []

with open(path, "r", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue

        msg = obj.get("message") or {}
        usage = msg.get("usage") or {}

        inp = usage.get("input_tokens") or 0
        out = usage.get("output_tokens") or 0
        cr  = usage.get("cache_read_input_tokens") or 0
        cw  = usage.get("cache_creation_input_tokens") or 0

        if inp > 0 or out > 0:
            turns += 1
            total_input += inp
            total_output += out
            total_cache_read += cr
            total_cache_write += cw
            turn_costs.append({"turn": turns, "role": msg.get("role", "?"), "input": inp, "output": out, "total": inp + out})

        content = msg.get("content") or []
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    tool_calls += 1
                    if item.get("name") == "Agent":
                        dispatches += 1

total_eff = total_input + total_cache_read
hit_rate = (total_cache_read / total_eff * 100) if total_eff > 0 else 0.0

print("")
print("===== CONDUCTOR token-measurement =====")
print(f"Session: {path}")
print("")
print(f"Turns                        : {turns:,}")
print(f"Input tokens (uncached)      : {total_input:,}")
print(f"Output tokens                : {total_output:,}")
print(f"Cache-read tokens            : {total_cache_read:,}")
print(f"Cache-write tokens           : {total_cache_write:,}")
print(f"Cache hit rate               : {hit_rate:.1f}%")
print(f"Tool calls (total)           : {tool_calls:,}")
print(f"Sub-agent dispatches         : {dispatches:,}")

top5 = sorted(turn_costs, key=lambda x: -x["total"])[:5]
print("")
print("===== Top 5 expensive turns (input + output) =====")
for t in top5:
    print(f"  turn={t['turn']:<6}  role={t['role']:<12}  in={t['input']:,}  out={t['output']:,}  total={t['total']:,}")

if export_csv:
    with open(export_csv, "w") as f:
        f.write("metric,value\n")
        f.write(f"session,{path}\n")
        f.write(f"turns,{turns}\n")
        f.write(f"input_tokens,{total_input}\n")
        f.write(f"output_tokens,{total_output}\n")
        f.write(f"cache_read_tokens,{total_cache_read}\n")
        f.write(f"cache_write_tokens,{total_cache_write}\n")
        f.write(f"cache_hit_rate_percent,{hit_rate:.1f}\n")
        f.write(f"tool_calls,{tool_calls}\n")
        f.write(f"dispatches,{dispatches}\n")
    print(f"\nWriting CSV: {export_csv}")

print("")
print("(zero telemetry — values are local only; no external transmission)")
PYEOF
