#!/usr/bin/env bash
# CONDUCTOR live-verify — automated live rule-loading verification (ADR-043).
# Exit 0 = every attempted tool passed (skips don't fail), 1 = a probe FAILED, 2 = error.
#
# For each adapter (or --tool=<t>):
#   1. read adapters/<tool>/metadata.json → headless CLI command/invocation
#   2. if the CLI is not on PATH → SKIP (honest — never fake a ✅)
#   3. install the adapter into a throwaway temp dir (base install, no recipes)
#   4. run the tool headlessly with the probe prompt from docs/ADAPTER-LIVE-VERIFICATION.md
#   5. grade DETERMINISTICALLY (no LLM judge): the answer must name ≥3 of the 5
#      universal rules AND mention CURRENT_WORK
#   6. on PASS: write live_verification {status:verified, date, cli} into the tool's
#      metadata.json and regenerate the doc tables (tools/generate-adapter-docs.js)
#
# Freshness: any 'verified' date older than 90 days prints a WARN (re-verify).
#
# Usage:
#   bash tools/live-verify.sh                 # all six (installed CLIs only)
#   bash tools/live-verify.sh --tool=codex    # one tool
#   bash tools/live-verify.sh --dry-run       # show plan, run nothing, write nothing
#
# Env: CONDUCTOR_LIVE_TIMEOUT (seconds per probe, default 300)
#
# Local-first by design: CI cannot run six authenticated AI CLIs (see
# docs/ADAPTER-LIVE-VERIFICATION.md "Why this is separate from CI").

set -u

cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

command -v node >/dev/null 2>&1 || { echo "ERROR: node is required" >&2; exit 2; }

ONLY_TOOL=""
DRY_RUN="false"
for a in "$@"; do
  case "$a" in
    --tool=*) ONLY_TOOL="${a#--tool=}" ;;
    --dry-run) DRY_RUN="true" ;;
    *) echo "ERROR: unknown arg '$a' (use --tool=<t> / --dry-run)" >&2; exit 2 ;;
  esac
done

TOOLS="claude cursor copilot gemini codex windsurf"
TIMEOUT_S="${CONDUCTOR_LIVE_TIMEOUT:-300}"

if [ -n "$ONLY_TOOL" ]; then
  case " $TOOLS " in
    *" $ONLY_TOOL "*) : ;;
    *) echo "ERROR: unknown --tool '$ONLY_TOOL' (one of: $TOOLS)" >&2; exit 2 ;;
  esac
fi

PROBE="What workflow and rules are you operating under in this project? List the universal rules you can see, and tell me the first thing you must do before writing code."

FAILED=0
ATTEMPTED=0
PASSED=0

meta_field() { # meta_field <tool> <js-expr on m>
  node -e "const m=require('$ROOT/adapters/$1/metadata.json');console.log($2 ?? '')"
}

grade() { # grade <output-file> → prints "rule_hits current_work(0/1)"
  local f="$1" hits=0 cw=0 r
  for r in workflow spec-as-you-go quality-gates operations meta-discipline; do
    grep -qi -- "$r" "$f" && hits=$((hits + 1))
  done
  grep -qi 'CURRENT_WORK' "$f" && cw=1
  echo "$hits $cw"
}

run_with_timeout() { # run_with_timeout <seconds> <cmd...>  (portable: no coreutils timeout)
  local secs="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 2; waited=$((waited + 2))
  done
  wait "$pid"
}

for tool in $TOOLS; do
  [ -n "$ONLY_TOOL" ] && [ "$tool" != "$ONLY_TOOL" ] && continue

  cmd="$(meta_field "$tool" 'm.headless_cli.command')"
  status="$(meta_field "$tool" 'm.live_verification.status')"
  date_v="$(meta_field "$tool" 'm.live_verification.date')"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "SKIP  $tool — headless CLI '$cmd' not on PATH (honest skip; install it to verify)"
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "PLAN  $tool — would install to a temp dir and probe via '$cmd' (current: $status${date_v:+ $date_v})"
    continue
  fi

  ATTEMPTED=$((ATTEMPTED + 1))
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/conductor-live-$tool.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 2; }
  out="$tmp/.probe-output.txt"

  echo "RUN   $tool — installing into $tmp"
  if ! bash "adapters/$tool/transform.sh" "$tmp" --no-prompt >/dev/null 2>&1; then
    echo "FAIL  $tool — adapter install failed (pre-probe)"; FAILED=1; rm -rf "$tmp"; continue
  fi
  ( cd "$tmp" && git init -q ) 2>/dev/null || true

  echo "RUN   $tool — probing '$cmd' (timeout ${TIMEOUT_S}s)"
  (
    cd "$tmp" || exit 2
    # Read-only probe; flags mirror core/reflector/run-weekly.sh (verified 2026-07-05),
    # minus write permissions — the probe only asks a question.
    case "$cmd" in
      claude)       run_with_timeout "$TIMEOUT_S" claude -p "$PROBE" ;;
      codex)        run_with_timeout "$TIMEOUT_S" codex exec --sandbox read-only "$PROBE" ;;
      gemini)       run_with_timeout "$TIMEOUT_S" gemini -p "$PROBE" ;;
      cursor-agent) run_with_timeout "$TIMEOUT_S" cursor-agent -p "$PROBE" ;;
      copilot)      run_with_timeout "$TIMEOUT_S" copilot -p "$PROBE" ;;
      devin)        run_with_timeout "$TIMEOUT_S" devin -p "$PROBE" ;;
      *)            echo "unknown CLI '$cmd'" >&2; exit 2 ;;
    esac
  ) > "$out" 2>&1
  probe_rc=$?

  if [ "$probe_rc" -eq 124 ]; then
    echo "FAIL  $tool — probe timed out after ${TIMEOUT_S}s"; FAILED=1; rm -rf "$tmp"; continue
  fi
  if [ "$probe_rc" -ne 0 ]; then
    # A non-zero CLI exit (auth failure, transport error, crash) must never be
    # recorded as verified — even if partial output happens to contain keywords.
    echo "FAIL  $tool — probe CLI exited $probe_rc (see $out)"; FAILED=1; continue
  fi

  read -r hits cw <<EOF_GRADE
$(grade "$out")
EOF_GRADE
  echo "      $tool — graded: $hits/5 rule names, CURRENT_WORK=$cw (probe exit $probe_rc)"

  if [ "$hits" -ge 3 ] && [ "$cw" -eq 1 ]; then
    PASSED=$((PASSED + 1))
    today="$(date +%F)"
    cliver="$("$cmd" --version 2>/dev/null | head -n 1 | tr -d '\n' | cut -c1-60)"
    [ -n "$cliver" ] || cliver="$cmd"
    echo "PASS  $tool — live-verified $today ($cliver)"
    node -e '
      const fs = require("fs");
      const p = process.argv[1], date = process.argv[2], cli = process.argv[3], hits = process.argv[4];
      const raw = fs.readFileSync(p, "utf8");
      const m = JSON.parse(raw);
      m.live_verification = { status: "verified", date, cli,
        note: `headless probe listed ${hits}/5 rules + read-CURRENT_WORK-first` };
      // Preserve the file style: compact one-line live_verification object.
      const updated = raw.replace(/"live_verification": \{[^}]*\}/,
        `"live_verification": { "status": "verified", "date": ${JSON.stringify(date)}, "cli": ${JSON.stringify(cli)}, "note": ${JSON.stringify(m.live_verification.note)} }`);
      fs.writeFileSync(p, updated);
    ' "adapters/$tool/metadata.json" "$today" "$cliver" "$hits"
    node tools/generate-adapter-docs.js >/dev/null
    echo "      $tool — metadata.json updated + doc tables regenerated"
  else
    echo "FAIL  $tool — tool did not demonstrate loading the rules (see $out)"
    echo "      (an emission-verified adapter that fails live-loading usually means the tool's rules-file convention moved — see docs/ADAPTER-LIVE-VERIFICATION.md)"
    FAILED=1
    continue   # keep $tmp for inspection on failure
  fi
  rm -rf "$tmp"
done

# Freshness guard — verified dates older than 90 days deserve a re-run.
node -e '
  const fs = require("fs");
  const tools = ["claude","cursor","copilot","gemini","codex","windsurf"];
  const now = Date.now();
  for (const t of tools) {
    const m = JSON.parse(fs.readFileSync(`adapters/${t}/metadata.json`, "utf8"));
    const lv = m.live_verification;
    if (lv.status === "verified" && lv.date) {
      const age = Math.floor((now - new Date(lv.date).getTime()) / 86400000);
      if (age > 90) console.log(`WARN  ${t} — live verification is ${age} days old (${lv.date}); re-run: bash tools/live-verify.sh --tool=${t}`);
    }
  }
'

echo
if [ "$DRY_RUN" = "true" ]; then echo "dry-run complete — nothing executed or written."; exit 0; fi
echo "live-verify: attempted=$ATTEMPTED passed=$PASSED failed=$((FAILED))"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
