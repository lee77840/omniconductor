#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/core/hooks/output-cap.sh.template"
fail() { echo "FAIL: $1" >&2; exit 1; }

PYTHON_BIN=""
for candidate in "${CONDUCTOR_PYTHON_BIN:-}" python3 python; do
  [ -n "$candidate" ] || continue
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import json,sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
    break
  fi
done
[ -n "$PYTHON_BIN" ] || fail "Python 3 test runtime not found (set CONDUCTOR_PYTHON_BIN)"
printf -v PYTHON_BIN_Q '%q' "$PYTHON_BIN"

# NOTE: this file runs under `set -e`, so rc is captured via `cmd || rc=$?`
# (not `cmd; rc=$?`) — the latter would let `set -e` abort the script on a
# non-zero exit before the assertion below ever runs.

# Large Claude PostToolUse result -> truncated via updatedToolOutput.
big="$(head -c 80000 /dev/zero | tr '\0' 'x')"
payload="$("$PYTHON_BIN" -c "import json,sys;print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash','tool_response':{'stdout':sys.argv[1]}}))" "$big")"
rc=0
out="$(printf '%s' "$payload" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0, got $rc"
printf '%s' "$out" | grep -q 'updatedToolOutput' || fail "large result not truncated"
printf '%s' "$out" | grep -q 'output truncated' || fail "elision marker missing"
# Shape preservation: Claude validates updatedToolOutput against the tool's own
# output schema and silently DISCARDS a mismatched replacement (claude.exe
# 2.1.215 `outputSchema.safeParse` gate). An object response MUST come back as
# the same object shape with its string leaves clipped — never as a string.
printf '%s' "$out" | "$PYTHON_BIN" -c "
import json,sys
u=json.load(sys.stdin)['hookSpecificOutput']['updatedToolOutput']
assert isinstance(u,dict), 'object response must stay an object (schema gate)'
assert set(u.keys())=={'stdout'}, 'keys must be preserved'
assert 'output truncated' in u['stdout'], 'marker must be inside the clipped leaf'
assert len(u['stdout']) < 60000, 'stdout not actually clipped'
" || fail "updatedToolOutput is not shape-preserving for an object response"

# Plain-string tool_response -> plain-string replacement (string in, string out).
payload_str="$("$PYTHON_BIN" -c "import json,sys;print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'WebFetch','tool_response':sys.argv[1]}))" "$big")"
rc=0
out_s="$(printf '%s' "$payload_str" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0 on string response, got $rc"
printf '%s' "$out_s" | "$PYTHON_BIN" -c "
import json,sys
u=json.load(sys.stdin)['hookSpecificOutput']['updatedToolOutput']
assert isinstance(u,str), 'string response must stay a string'
assert 'output truncated' in u
" || fail "string-response replacement broken"

# Many-medium-leaf (MCP-style) payload: total must land near the budget and the
# result must NEVER be larger than the input (adversarial-review regression:
# per-leaf marker overhead used to GROW such payloads and miss the budget 7x).
mcp_payload="$("$PYTHON_BIN" -c "
import json
leaves=[('段落 %d ' % i) + 'y'*300 for i in range(1000)]
print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'mcp__search','tool_response':{'content':[{'type':'text','text':t} for t in leaves]}}))")"
rc=0
out_m="$(printf '%s' "$mcp_payload" | CONDUCTOR_HOOK_DIALECT=claude bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0 on MCP-shaped payload, got $rc"
printf '%s\n%s' "${#mcp_payload}" "$out_m" | "$PYTHON_BIN" -c "
import json,sys
lines=sys.stdin.read().split('\n',1)
in_len=int(lines[0]); u=json.loads(lines[1])['hookSpecificOutput']['updatedToolOutput']
s=json.dumps(u)
assert len(s) < in_len, 'output must be smaller than input (%d vs %d)' % (len(s), in_len)
# Shape-preserving cap cannot elide JSON STRUCTURE (keys/braces), only string
# content — contract: never grow, and land within max(budget*1.15, input*0.45).
assert len(s)//4 <= max(8000*1.15, (in_len//4)*0.45), 'result not bounded: est %d (in %d)' % (len(s)//4, in_len//4)
assert isinstance(u,dict) and isinstance(u['content'],list) and len(u['content'])==1000, 'MCP shape not preserved'
" || fail "many-medium-leaf payload not bounded/shape-preserved"

# Growth guard: leaves just above MIN_KEEP must be left alone, never enlarged.
grow_payload="$("$PYTHON_BIN" -c "
import json
print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'X','tool_response':{'items':['q'*250 for _ in range(30)]}}))")"
rc=0
out_g="$(printf '%s' "$grow_payload" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=1 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0 on growth-guard payload, got $rc"
if [ -n "$out_g" ]; then
  printf '%s\n%s' "${#grow_payload}" "$out_g" | "$PYTHON_BIN" -c "
import json,sys
lines=sys.stdin.read().split('\n',1)
in_len=int(lines[0]); u=json.loads(lines[1])['hookSpecificOutput']['updatedToolOutput']
assert len(json.dumps(u)) <= in_len, 'clipping GREW the payload'
" || fail "growth guard violated (output larger than input)"
fi

# Large 5000-leaf payload (~1.6MB): must complete quickly and shrink (was a 27s
# O(n^2) hang that returned a LARGER payload).
big_start=$(date +%s)
big_payload_file="$(mktemp)"
"$PYTHON_BIN" -c "
import json
leaves=['y'*300 for _ in range(5000)]
open('$big_payload_file','w').write(json.dumps({'hook_event_name':'PostToolUse','tool_name':'mcp__big','tool_response':{'content':[{'type':'text','text':t} for t in leaves]}}))"
rc=0
out_b="$(CONDUCTOR_HOOK_DIALECT=claude bash "$HOOK" < "$big_payload_file")" || rc=$?
big_secs=$(( $(date +%s) - big_start ))
[ "$rc" -eq 0 ] || fail "hook must exit 0 on 5000-leaf payload, got $rc"
[ "$big_secs" -le 10 ] || fail "5000-leaf payload took ${big_secs}s (O(n^2) regression)"
in_b=$(wc -c < "$big_payload_file")
printf '%s\n%s' "$in_b" "$out_b" | "$PYTHON_BIN" -c "
import json,sys
lines=sys.stdin.read().split('\n',1)
in_len=int(lines[0]); u=json.loads(lines[1])['hookSpecificOutput']['updatedToolOutput']
s=json.dumps(u)
assert len(s) < in_len, '5000-leaf output not smaller than input'
assert len(s)//4 <= max(8000*1.15, (in_len//4)*0.45), '5000-leaf result not bounded: est %d (in %d)' % (len(s)//4, in_len//4)
" || fail "5000-leaf payload not bounded"
rm -f "$big_payload_file"

# Small result -> no output (untouched).
small="$("$PYTHON_BIN" -c "import json;print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash','tool_response':{'stdout':'hello'}}))")"
rc=0
out2="$(printf '%s' "$small" | CONDUCTOR_HOOK_DIALECT=claude bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0, got $rc"
[ -z "$out2" ] || fail "small result should be untouched (got output)"

# Opt-out -> no output even when large.
rc=0
out3="$(printf '%s' "$payload" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_SKIP_OUTPUT_CAP=1 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0, got $rc"
[ -z "$out3" ] || fail "opt-out not honored"

# tool_result fallback key -> also truncated.
payload_tr="$("$PYTHON_BIN" -c "import json,sys;print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash','tool_result':{'stdout':sys.argv[1]}}))" "$big")"
rc=0
out4="$(printf '%s' "$payload_tr" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0, got $rc"
printf '%s' "$out4" | grep -q 'updatedToolOutput' || fail "tool_result fallback key not truncated"
printf '%s' "$out4" | grep -q 'output truncated' || fail "tool_result fallback elision marker missing"

# Malformed non-JSON stdin -> no output, rc 0.
malformed="$(head -c 80000 /dev/zero | tr '\0' 'z')not-json-at-all"
rc=0
out5="$(printf '%s' "$malformed" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0 on malformed input, got $rc"
[ -z "$out5" ] || fail "malformed input should produce no output"

# Non-numeric token budget -> clamps to default (8000), does not error.
rc=0
out6="$(printf '%s' "$payload" | CONDUCTOR_HOOK_DIALECT=claude CONDUCTOR_OUTPUT_CAP_TOKENS=abc bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "hook must exit 0 with non-numeric budget, got $rc"

# Claude install emits + makes executable the hook, and registers it.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
node "$ROOT/bin/omniconductor.js" init --target=claude "$TMP" --no-prompt --accept-model-defaults >/dev/null 2>&1 || true
[ -x "$TMP/.claude/hooks/output-cap.sh" ] || fail "claude hook not emitted/executable"
grep -q 'output-cap.sh' "$TMP/.claude/settings.json" || fail "claude settings missing output-cap"

CX="$(mktemp -d)"
node "$ROOT/bin/omniconductor.js" init --target=codex "$CX" --no-prompt --accept-model-defaults >/dev/null 2>&1 || true
grep -q '^tool_output_token_limit = 8000' "$CX/.codex/config.toml" || fail "codex tool_output_token_limit not emitted"
rm -rf "$CX"

# Gemini dialect: rewrite run_shell_command to append a truncator, as a clean success.
gp="$("$PYTHON_BIN" -c "import json;print(json.dumps({'hook_event_name':'BeforeTool','tool_name':'run_shell_command','tool_input':{'command':'printf \"AAAA\\n\"'}}))")"
rc=0
gout="$(printf '%s' "$gp" | CONDUCTOR_HOOK_DIALECT=gemini CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "gemini hook must exit 0, got $rc"
printf '%s' "$gout" | grep -q '"tool_input"' || fail "gemini did not rewrite tool_input"
printf '%s' "$gout" | grep -q 'awk' || fail "gemini truncator not appended"
printf '%s' "$gout" | grep -q 'BeforeTool' || fail "gemini hookEventName wrong"

# Helper: feed an arbitrary original command through the gemini dialect and
# print the rewritten command (passed via argv, not interpolated into the
# python source, so quoting in the original command is never a hazard).
gemini_rewrite_cmd() {
  "$PYTHON_BIN" -c "import json,sys;print(json.dumps({'hook_event_name':'BeforeTool','tool_name':'run_shell_command','tool_input':{'command':sys.argv[1]}}))" "$1" \
    | CONDUCTOR_HOOK_DIALECT=gemini CONDUCTOR_OUTPUT_CAP_TOKENS=1000 bash "$HOOK" \
    | "$PYTHON_BIN" -c "import json,sys;print(json.loads(sys.stdin.read())['hookSpecificOutput']['tool_input']['command'])"
}

# The rewritten command must be VALID shell that truncates: run it (as a whole,
# not a hand-extracted awk fragment) against a large-output original command.
newcmd="$(gemini_rewrite_cmd 'yes x | head -c 40000')"
rc=0; capped="$(bash -c "$newcmd")" || rc=$?
[ "$rc" -eq 0 ] || fail "rewritten command for a succeeding large-output original must still exit 0, got $rc"
printf '%s' "$capped" | grep -q 'output truncated' || fail "awk cap did not emit the marker on large input"
[ "$(printf '%s' "$capped" | wc -c)" -lt 20000 ] || fail "awk cap did not actually bound the output"

# CRITICAL: exit-status masking regression. A pipeline's status is normally its
# LAST stage (awk, ~always 0), so a FAILING original command whose output gets
# capped must still surface its real non-zero exit code to the agent — not a
# false-success 0. `sh -c '...; exit 3'` fails after producing large output.
newcmd_fail="$(gemini_rewrite_cmd "sh -c 'yes x | head -c 40000; exit 3'")"
rc=0; capped_fail="$(bash -c "$newcmd_fail")" || rc=$?
[ "$rc" -eq 3 ] || fail "rewritten command must preserve the original non-zero exit code (3), got $rc"
printf '%s' "$capped_fail" | grep -q 'output truncated' || fail "failing large command still needs the truncation marker"

# Regression: stderr must pass through the same cap. Previously, a command
# could emit an arbitrarily large error log while stdout stayed empty.
newcmd_stderr="$(gemini_rewrite_cmd "$PYTHON_BIN_Q -c 'import sys; sys.stderr.write(\"E\"*40000)'")"
rc=0; capped_stderr="$(bash -c "$newcmd_stderr")" || rc=$?
[ "$rc" -eq 0 ] || fail "rewritten stderr-only command must preserve success, got $rc"
printf '%s' "$capped_stderr" | grep -q 'output truncated' || fail "large stderr did not pass through the cap"
[ "$(printf '%s' "$capped_stderr" | wc -c)" -lt 20000 ] || fail "stderr cap did not actually bound the output"

# Mixed stdout+stderr uses one bounded stream and still preserves failure.
newcmd_mixed="$(gemini_rewrite_cmd "$PYTHON_BIN_Q -c 'import sys; print(\"O\"*25000); sys.stderr.write(\"E\"*25000); sys.exit(7)'")"
rc=0; capped_mixed="$(bash -c "$newcmd_mixed")" || rc=$?
[ "$rc" -eq 7 ] || fail "rewritten mixed-output command must preserve exit 7, got $rc"
printf '%s' "$capped_mixed" | grep -q 'output truncated' || fail "mixed stdout/stderr did not emit the cap marker"
[ "$(printf '%s' "$capped_mixed" | wc -c)" -lt 20000 ] || fail "mixed stream was not bounded"

# run_shell_command with the marker already present -> idempotent no-op (no double-wrap).
gp2="$("$PYTHON_BIN" -c "import json;print(json.dumps({'hook_event_name':'BeforeTool','tool_name':'run_shell_command','tool_input':{'command':'echo hi | awk 1 #…[CONDUCTOR]'}}))")"
rc=0; gout2="$(printf '%s' "$gp2" | CONDUCTOR_HOOK_DIALECT=gemini bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "gemini idempotency case must exit 0"
[ -z "$gout2" ] || fail "gemini should not re-wrap an already-capped command"
# Non-shell tool -> no-op.
gp3="$("$PYTHON_BIN" -c "import json;print(json.dumps({'hook_event_name':'BeforeTool','tool_name':'read_file','tool_input':{'path':'x'}}))")"
rc=0; gout3="$(printf '%s' "$gp3" | CONDUCTOR_HOOK_DIALECT=gemini bash "$HOOK")" || rc=$?
[ "$rc" -eq 0 ] || fail "gemini non-shell case must exit 0"
[ -z "$gout3" ] || fail "gemini should not touch non-shell tools"
# Gemini install emits the hook + a BeforeTool settings entry (full mode).
GEM="$(mktemp -d)"
node "$ROOT/bin/omniconductor.js" init --target=gemini "$GEM" --no-prompt --accept-model-defaults >/dev/null 2>&1 || true
[ -x "$GEM/.gemini/hooks/output-cap.sh" ] || fail "gemini hook not emitted/executable"
grep -q 'BeforeTool' "$GEM/.gemini/settings.json" || fail "gemini settings missing BeforeTool"
"$PYTHON_BIN" -c "import json;json.load(open('$GEM/.gemini/settings.json'))" || fail "gemini settings.json is not valid JSON"
rm -rf "$GEM"

# Task 6: validator + doctor accept the new surfaces on a fresh full-mode
# install, for every tool that actually emits an output-cap surface.
# NOTE: `bin/doctor.js` has no CLI entry point of its own (module.exports only,
# no `require.main` dispatch) — it is invoked through `bin/omniconductor.js
# doctor`, exactly as every other suite in this repo does
# (tools/test-multitool-runtime.sh's doctor_fail_count, tools/test-install-modes.sh).
for a in claude codex gemini; do
  T6="$(mktemp -d)"
  VALIDATE_LOG="$(mktemp)"
  DOCTOR_LOG="$(mktemp)"
  node "$ROOT/bin/omniconductor.js" init --target="$a" "$T6" --no-prompt --accept-model-defaults >/dev/null 2>&1 || true

  rc=0
  bash "$ROOT/tools/validate-adapter-output.sh" "$T6" "$a" >"$VALIDATE_LOG" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "validate-adapter-output.sh must exit 0 for $a with output-cap surfaces present, got $rc (see $VALIDATE_LOG)"

  rc=0
  node "$ROOT/bin/omniconductor.js" doctor "$T6" >"$DOCTOR_LOG" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || fail "doctor must exit 0 or 1 (WARN allowed) for $a, never 2 (FAIL), got $rc (see $DOCTOR_LOG)"

  rm -rf "$T6" "$VALIDATE_LOG" "$DOCTOR_LOG"
done

# Effective-activation regression: a valid full-mode install can still lack the
# cap when a user-owned Codex config predates the feature. The validator keeps
# preserving that config, but doctor must now distinguish preservation from
# activation and fail with an actionable branch-local reinstall message.
CAP_GAP="$(mktemp -d)"
/bin/mkdir -p "$CAP_GAP/.codex"
printf 'model = "example"\n' > "$CAP_GAP/.codex/config.toml"
node "$ROOT/bin/omniconductor.js" init --target=codex "$CAP_GAP" --no-prompt --accept-model-defaults >/dev/null 2>&1 || true
if grep -q '^tool_output_token_limit' "$CAP_GAP/.codex/config.toml"; then
  fail "pre-existing Codex config fixture unexpectedly gained an output cap"
fi
CAP_GAP_LOG="$(mktemp)"
rc=0
node "$ROOT/bin/omniconductor.js" doctor "$CAP_GAP" >"$CAP_GAP_LOG" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "doctor must fail a full Codex install whose preserved config has no effective cap (got $rc)"
grep -q 'codex full/strict install has no effective output cap' "$CAP_GAP_LOG" \
  || fail "doctor did not explain the effective Codex cap gap"
rm -rf "$CAP_GAP" "$CAP_GAP_LOG"

# Documentation reach is derived from the current adapter inventory so adding
# an eighth adapter cannot silently leave another stale "3/7" claim behind.
adapter_total="$(find "$ROOT/adapters" -mindepth 2 -maxdepth 2 -name metadata.json -type f | wc -l | tr -d ' ')"
[ "$adapter_total" -ge 3 ] || fail "adapter metadata inventory is unexpectedly small"
grep -q "3/$adapter_total" "$ROOT/docs/COMPATIBILITY-MATRIX.md" \
  || fail "compatibility matrix output-cap reach is not 3/$adapter_total"

echo "PASS: output-cap Claude dialect"
echo "PASS: output-cap Gemini dialect"
echo "PASS: output-cap validator + doctor verify effective claude/codex/gemini activation"
