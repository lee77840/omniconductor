#!/usr/bin/env bash
# Cross-adapter runtime/ownership regression suite (ADR-045).

set -u

cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"
BASE="${1:-$(mktemp -d "${TMPDIR:-/tmp}/conductor-multitool.XXXXXX")}"
TARGET="$BASE/project"
FAIL=0

ok() { echo "OK   [multitool] $1"; }
bad() { echo "FAIL [multitool] $1"; FAIL=1; }

manifest_count() {
  find "$1/.conductor/manifests" -type f -name '*.json' 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' '
}

doctor_fail_count() {
  local output
  output="$(node "$ROOT/bin/omniconductor.js" doctor "$1" --json 2>/dev/null || true)"
  node -e 'try { const d=JSON.parse(process.argv[1]); console.log(d.summary.FAIL); } catch { console.log(999); }' "$output"
}

projection_count() {
  node -e 'const d=require(process.argv[1]); console.log((d.installed_adapters||[]).length)' "$1/.conductor-manifest.json" 2>/dev/null || echo 999
}

ownership_digest() {
  node -e '
    const crypto=require("crypto"),fs=require("fs"),dir=process.argv[1];
    const rows=[];
    for(const f of fs.readdirSync(dir).filter(f=>f.endsWith(".json")).sort()) {
      const m=JSON.parse(fs.readFileSync(`${dir}/${f}`,"utf8"));
      for(const e of m.emitted_files) rows.push([m.adapter,e.path,e.type||"file",e.block||"",e.source||"",e.backup_path||"",e.sha256||""]);
    }
    rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
    process.stdout.write(crypto.createHash("sha256").update(JSON.stringify(rows)).digest("hex"));
  ' "$1/.conductor/manifests"
}

mkdir -p "$TARGET"
git init -q "$TARGET"

if node bin/omniconductor.js init --target=all "$TARGET" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1; then
  ok "all six adapters install in one project"
else
  bad "all-target install"
fi

[ "$(manifest_count "$TARGET")" -eq 6 ] \
  && [ "$(projection_count "$TARGET")" -eq 6 ] \
  && ok "six authoritative manifests + aggregate root projection" \
  || bad "manifest aggregation"

role_ok=true
for f in \
  .claude/agents/code-reviewer.md \
  .cursor/agents/code-reviewer.md \
  .github/agents/code-reviewer.agent.md \
  .gemini/agents/code-reviewer.md \
  .codex/agents/code-reviewer.toml \
  .windsurf/workflows/code-reviewer.md \
  .claude/agents/utility.md \
  .cursor/agents/utility.md \
  .github/agents/utility.agent.md \
  .gemini/agents/utility.md \
  .codex/agents/utility.toml \
  .windsurf/workflows/utility.md; do
  [ -s "$TARGET/$f" ] || role_ok=false
done
$role_ok && ok "every supported tool has code-review and Tier 3 utility role entries" || bad "cross-tool role emission"

# Difficulty is the cross-vendor invariant. Role sources and all compiled role
# surfaces must preserve the original 4x Tier 1 / 3x Tier 2 assignment.
tier_contract_ok=true
for role in planner reviewer code-reviewer builder; do
  /usr/bin/grep -qE '^difficulty_tier:[[:space:]]*1$' "core/roles/$role.md" || tier_contract_ok=false
done
for role in helper designer scribe; do
  /usr/bin/grep -qE '^difficulty_tier:[[:space:]]*2$' "core/roles/$role.md" || tier_contract_ok=false
done
/usr/bin/grep -qE '^difficulty_tier:[[:space:]]*3$' core/roles/utility.md || tier_contract_ok=false
for spec in \
  ".claude/agents/planner.md:1" ".claude/agents/helper.md:2" \
  ".cursor/agents/planner.md:1" ".cursor/agents/helper.md:2" \
  ".github/agents/planner.agent.md:1" ".github/agents/helper.agent.md:2" \
  ".gemini/agents/planner.md:1" ".gemini/agents/helper.md:2" \
  ".codex/agents/planner.toml:1" ".codex/agents/helper.toml:2" \
  ".windsurf/workflows/planner.md:1" ".windsurf/workflows/helper.md:2"; do
  path="${spec%:*}"; tier="${spec##*:}"
  /usr/bin/grep -qE "CONDUCTOR difficulty contract:.*Tier ${tier}([^0-9]|$)" "$TARGET/$path" || tier_contract_ok=false
done
for path in \
  .claude/agents/utility.md .cursor/agents/utility.md \
  .github/agents/utility.agent.md .gemini/agents/utility.md \
  .codex/agents/utility.toml .windsurf/workflows/utility.md; do
  /usr/bin/grep -qE 'CONDUCTOR difficulty contract:.*Tier 3([^0-9]|$)' "$TARGET/$path" || tier_contract_ok=false
done
if $tier_contract_ok \
  && /usr/bin/grep -qF 'model_reasoning_effort = "high"' "$TARGET/.codex/agents/planner.toml" \
  && /usr/bin/grep -qF 'model_reasoning_effort = "medium"' "$TARGET/.codex/agents/scribe.toml" \
  && /usr/bin/grep -qF 'model_reasoning_effort = "low"' "$TARGET/.codex/agents/utility.toml"; then
  ok "portable difficulty tiers compile without changing the declared role difficulty"
else
  bad "difficulty tier drift across role sources or adapters"
fi

# Vendor model families must not leak into another vendor's role profiles.
if ! find "$TARGET/.cursor" "$TARGET/.github" "$TARGET/.gemini" "$TARGET/.codex" \
  "$TARGET/.devin" "$TARGET/.windsurf" -type f -print0 \
  | xargs -0 /usr/bin/grep -Eiq '(^|[^A-Za-z])(Opus|Sonnet|Haiku)([^A-Za-z]|$)' \
  && ! /usr/bin/grep -Eiq '(^|[^A-Za-z])(Opus|Sonnet|Haiku)([^A-Za-z]|$)' "$TARGET/GEMINI.md" "$TARGET/AGENTS.md" "$TARGET/.windsurfrules" \
  && /usr/bin/grep -qF 'model: gpt-5.6-sol' "$TARGET/.cursor/agents/planner.md" \
  && /usr/bin/grep -qF 'model: pro' "$TARGET/.gemini/agents/planner.md" \
  && /usr/bin/grep -qF 'model: gpt-5.6-sol' "$TARGET/.github/agents/planner.agent.md" \
  && /usr/bin/grep -qF 'model = "gpt-5.6-sol"' "$TARGET/.codex/agents/planner.toml" \
  && /usr/bin/grep -qF 'select **Adaptive**' "$TARGET/.windsurf/workflows/planner.md"; then
  ok "non-Claude adapters compile saved native Tier mappings without Claude model leakage"
else
  bad "cross-vendor model leakage or saved-routing compilation regression"
fi

# Advanced adopters may save exact models per Tier without editing role sources.
# A saved choice changes only the native translation, never the difficulty.
MODEL_OVERRIDE="$BASE/model-overrides"
mkdir -p "$MODEL_OVERRIDE"
if node -e '
    const path=require("path"),r=require("./bin/model-routing.js"),target=path.resolve(process.argv[1]);
    const choices={
      claude:{1:"claude-exact-tier-1",2:"claude-exact-tier-2",3:"haiku"},
      codex:{1:"gpt-5.6-sol",2:"gpt-5.6-terra",3:"gpt-5.6-luna"},
      gemini:{1:"gemini-exact-tier-1",2:"gemini-exact-tier-2",3:"gemini-exact-tier-3"}
    };
    (async()=>{for(const tool of Object.keys(choices)) await r.configure({targetAbs:target,targets:[tool],choices:{[tool]:choices[tool]},generatorVersion:"1.1.0"});})().catch(e=>{console.error(e.message);process.exit(1)});
  ' "$MODEL_OVERRIDE" >/dev/null 2>&1 \
  && node bin/omniconductor.js init --target=claude "$MODEL_OVERRIDE" --no-prompt --accept-model-defaults >/dev/null 2>&1 \
  && node bin/omniconductor.js init --target=codex "$MODEL_OVERRIDE" --no-prompt --accept-model-defaults >/dev/null 2>&1 \
  && node bin/omniconductor.js init --target=gemini "$MODEL_OVERRIDE" --no-prompt --accept-model-defaults >/dev/null 2>&1 \
  && /usr/bin/grep -qF 'model: claude-exact-tier-1' "$MODEL_OVERRIDE/.claude/agents/planner.md" \
  && /usr/bin/grep -qF 'model: claude-exact-tier-2' "$MODEL_OVERRIDE/.claude/agents/scribe.md" \
  && /usr/bin/grep -qF 'model = "gpt-5.6-sol"' "$MODEL_OVERRIDE/.codex/agents/planner.toml" \
  && /usr/bin/grep -qF 'model_reasoning_effort = "medium"' "$MODEL_OVERRIDE/.codex/agents/scribe.toml" \
  && /usr/bin/grep -qF 'model: gemini-exact-tier-1' "$MODEL_OVERRIDE/.gemini/agents/planner.md" \
  && /usr/bin/grep -qF 'CONDUCTOR difficulty contract: **Tier 2' "$MODEL_OVERRIDE/.gemini/agents/scribe.md"; then
  ok "saved Tier-specific exact models compile without changing difficulty"
else
  bad "saved Tier-specific exact-model contract"
fi

# Runtime environment variables are no longer an authority boundary. Even a
# hostile inherited value must be replaced by the validated saved mapping.
ENV_OVERRIDE="$BASE/untrusted-env-override"
mkdir -p "$ENV_OVERRIDE"
if CONDUCTOR_CLAUDE_MODEL_TIER_1='invalid/model' \
    node bin/omniconductor.js init --target=claude "$ENV_OVERRIDE" --no-prompt --accept-model-defaults >/dev/null 2>&1 \
  && /usr/bin/grep -qF 'model: opus' "$ENV_OVERRIDE/.claude/agents/planner.md" \
  && ! /usr/bin/grep -RqF 'invalid/model' "$ENV_OVERRIDE/.claude"; then
  ok "untrusted runtime model overrides cannot replace saved routing"
else
  bad "runtime environment replaced or bypassed saved model routing"
fi

codex_kernel_bytes="$(/usr/bin/wc -c < "$TARGET/AGENTS.md" | /usr/bin/tr -d ' ')"
codex_refs=true
for f in workflow spec-as-you-go quality-gates operations meta-discipline; do
  [ -s "$TARGET/.codex/conductor/rules/$f.md" ] || codex_refs=false
done
if [ "$codex_kernel_bytes" -le 24576 ] \
  && /usr/bin/grep -qF 'CONDUCTOR_KERNEL_END' "$TARGET/AGENTS.md" \
  && $codex_refs \
  && [ -s "$TARGET/.codex/conductor/recipes/loop-engineering.md" ]; then
  ok "Codex always-loaded kernel is bounded and complete references are preserved on demand"
else
  bad "Codex project instructions exceed budget or omit detailed references"
fi

# Current Codex output must never describe hooks that it actually installs as
# Claude-only. This catches stale universal prose even when runtime validators
# correctly see the files and hook registrations.
codex_claims="$TARGET/.codex/conductor"
if ! /usr/bin/grep -RIEi \
    '(stop-session-log-check|stop-r6-review-check|stop-git-hygiene-guard|pretool-loop-guard|stop-trajectory-log).{0,100}Claude[- ]only|Claude[- ]only.{0,100}(stop-session-log-check|stop-r6-review-check|stop-git-hygiene-guard|pretool-loop-guard|stop-trajectory-log)' \
    "$codex_claims" >/dev/null 2>&1; then
  ok "Codex output has no Claude-only claims for hooks it emits"
else
  bad "Codex output contradicts its emitted hook runtime"
fi

if [ "$(doctor_fail_count "$TARGET")" -eq 0 ]; then
  ok "doctor reports zero failures after multi-tool install"
else
  bad "doctor after multi-tool install"
fi

hook_exec_ok=true
while IFS= read -r hook; do
  hook_output="$(cd "$TARGET" && printf '%s' '{}' | bash "$hook" 2>/dev/null)" || hook_exec_ok=false
  if [ -n "$hook_output" ] && ! printf '%s' "$hook_output" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{try{JSON.parse(s)}catch{process.exit(1)}})
  '; then
    hook_exec_ok=false
  fi
done < <(find "$TARGET/.claude/hooks" "$TARGET/.codex/hooks" -type f -name '*.sh' | sort)
$hook_exec_ok \
  && ok "all emitted Claude/Codex hook scripts execute benign input and return valid JSON" \
  || bad "emitted hook behavioral smoke"

backup_count="$(find "$TARGET/.conductor/reflect" -type f -name '*.conductor-backup-*' 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[ "$backup_count" -eq 0 ] && ok "identical shared runtime files are reused without backup chains" || bad "shared runtime created $backup_count redundant backup(s)"

ownership_before_repeat="$(ownership_digest "$TARGET")"
if node bin/omniconductor.js init --target=all "$TARGET" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1 \
  && [ "$(doctor_fail_count "$TARGET")" -eq 0 ] \
  && [ "$ownership_before_repeat" = "$(ownership_digest "$TARGET")" ]; then
  ok "repeat all-target install preserves the complete ownership ledger"
else
  bad "repeat all-target install changed or lost ownership"
fi

# Shared files must have an owner regardless of removal order, and local
# trajectory data must be ignored without mutating a user's top-level file.
ORDERED="$BASE/ordered-uninstall"
mkdir -p "$ORDERED"
git init -q "$ORDERED"
printf 'user-ignore\n' > "$ORDERED/.gitignore"
printf 'keep\n' > "$ORDERED/KEEP.txt"
ordered_ignore_before="$(/usr/bin/cksum < "$ORDERED/.gitignore")"
node bin/omniconductor.js init --target=all "$ORDERED" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1
ordered_ok=true
for tool in claude cursor copilot gemini codex windsurf; do
  bash "adapters/$tool/transform.sh" "$ORDERED" --uninstall >/dev/null 2>&1 || ordered_ok=false
done
ordered_ignore_after="$(/usr/bin/cksum < "$ORDERED/.gitignore")"
ordered_residual="$(find "$ORDERED" -type f ! -path "$ORDERED/.git/*" ! -name KEEP.txt ! -name .gitignore ! -path '*/.conductor/model-routing.json' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
if $ordered_ok && [ "$ordered_residual" -eq 0 ] \
  && [ "$ordered_ignore_before" = "$ordered_ignore_after" ] \
  && [ "$(/bin/cat "$ORDERED/KEEP.txt")" = "keep" ]; then
  ok "forward-order uninstall leaves zero managed files and preserves user ignore/data"
else
  bad "forward-order uninstall leaked ownership or changed user files"
fi

REVERSE="$BASE/reverse-uninstall"
mkdir -p "$REVERSE"
git init -q "$REVERSE"
printf 'keep\n' > "$REVERSE/KEEP.txt"
if node bin/omniconductor.js init --target=all "$REVERSE" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1 \
  && node bin/omniconductor.js init --target=all "$REVERSE" --uninstall >/dev/null 2>&1 \
  && [ "$(find "$REVERSE" -type f ! -path "$REVERSE/.git/*" ! -name KEEP.txt ! -path '*/.conductor/model-routing.json' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq 0 ] \
  && [ -s "$REVERSE/.conductor/model-routing.json" ]; then
  ok "all-target reverse uninstall removes managed runtime and retains adopter model choices"
else
  bad "all-target reverse uninstall left managed residue"
fi

if bash adapters/codex/transform.sh "$TARGET" --uninstall >/dev/null 2>&1 \
  && [ "$(manifest_count "$TARGET")" -eq 5 ] \
  && [ "$(projection_count "$TARGET")" -eq 5 ] \
  && [ -s "$TARGET/.claude/rules/workflow.md" ] \
  && [ -s "$TARGET/docs/CURRENT_WORK.md" ]; then
  ok "uninstalling one adapter preserves the other five and shared docs"
else
  bad "scoped uninstall isolation"
fi

if CONDUCTOR_CLI_DISPATCH=0 bash adapters/codex/transform.sh "$TARGET" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1 \
  && [ "$(manifest_count "$TARGET")" -eq 6 ] \
  && [ "$(doctor_fail_count "$TARGET")" -eq 0 ]; then
  ok "removed adapter can be reinstalled without ownership drift"
else
  bad "scoped adapter reinstall"
fi

# A user-owned hook registry must not be overwritten by first install.
OWNED="$BASE/user-owned-hooks"
mkdir -p "$OWNED/.codex"
printf '{"hooks":{"Stop":[]},"owner":"user"}\n' > "$OWNED/.codex/hooks.json"
before="$(/usr/bin/cksum < "$OWNED/.codex/hooks.json")"
bash adapters/codex/transform.sh "$OWNED" --no-prompt --accept-model-defaults >/dev/null 2>&1
after="$(/usr/bin/cksum < "$OWNED/.codex/hooks.json")"
if [ "$before" = "$after" ] \
  && bash tools/validate-adapter-output.sh "$OWNED" codex >/dev/null 2>&1; then
  ok "user-owned Codex hooks.json is preserved and not misclassified as generated output"
else
  bad "user-owned hook registry overwritten or misclassified by validator"
fi

# Codex soft warnings must use model-visible context, never the unsupported
# permissionDecision:ask contract. Exercise the installed script, not just text.
DIALECT="$BASE/codex-dialect"
mkdir -p "$DIALECT"
git init -q "$DIALECT"
bash adapters/codex/transform.sh "$DIALECT" --no-prompt --accept-model-defaults >/dev/null 2>&1
printf 'a\n' > "$DIALECT/a.ts"; printf 'b\n' > "$DIALECT/b.ts"; printf 'c\n' > "$DIALECT/c.ts"
git -C "$DIALECT" add a.ts b.ts c.ts
codex_output="$(cd "$DIALECT" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | bash .codex/hooks/pretool-commit-current-work-check.sh)"
if printf '%s' "$codex_output" | /usr/bin/grep -q 'additionalContext' \
  && ! printf '%s' "$codex_output" | /usr/bin/grep -q 'permissionDecision.*ask'; then
  ok "Codex PreToolUse soft warning uses additionalContext, not ask"
else
  bad "Codex PreToolUse emitted an unsupported soft-warning contract"
fi

# Portability regressions from the adopter audit: no third-argument awk match,
# and zero counters normalize to exactly one integer on both BSD and GNU awk.
if ! /usr/bin/grep -qE 'match\([^)]*,[^)]*,' core/hooks/stop-r6-review-check.sh.template \
  && [ "$(printf '' | /usr/bin/awk '{n++} END{print n+0}')" = "0" ] \
  && ! /usr/bin/grep -qE 'grep -c[^\n]*\|\|[[:space:]]*echo 0' core/hooks/stop-session-log-check.sh.template; then
  ok "portable awk extraction and single-zero counter contract"
else
  bad "BSD/GNU awk or zero-counter portability regression"
fi

# Negative fixture: removing the compiled dialect pin exposes an unsupported
# ask branch and doctor must fail it deterministically.
ASK="$BASE/ask-fixture"
mkdir -p "$ASK"
bash adapters/codex/transform.sh "$ASK" --no-prompt --accept-model-defaults >/dev/null 2>&1
/usr/bin/sed -i.bak '/^export CONDUCTOR_HOOK_DIALECT=codex$/d' "$ASK/.codex/hooks/pretool-commit-current-work-check.sh"
/bin/rm -f "$ASK/.codex/hooks/pretool-commit-current-work-check.sh.bak"
if [ "$(doctor_fail_count "$ASK")" -gt 0 ]; then
  ok "doctor rejects an unpinned Codex ask contract"
else
  bad "doctor accepted unsupported Codex ask contract"
fi

# Negative fixture: existence-only role checks miss malformed TOML and accidental
# write access on reviewers. Doctor must validate the emitted native contract.
BAD_AGENT="$BASE/bad-codex-agent"
mkdir -p "$BAD_AGENT"
bash adapters/codex/transform.sh "$BAD_AGENT" --no-prompt --accept-model-defaults >/dev/null 2>&1
printf '\ninvalid = [\n' >> "$BAD_AGENT/.codex/agents/planner.toml"
if [ "$(doctor_fail_count "$BAD_AGENT")" -gt 0 ]; then
  ok "doctor rejects malformed Codex agent TOML contracts"
else
  bad "doctor accepted malformed Codex agent TOML"
fi

# Negative fixture: an oversized AGENTS.md is accepted by the filesystem but
# truncated by Codex's default project instruction loader. Doctor must fail it.
OVERSIZE="$BASE/oversize-agents"
mkdir -p "$OVERSIZE"
bash adapters/codex/transform.sh "$OVERSIZE" --no-prompt --accept-model-defaults >/dev/null 2>&1
/usr/bin/awk 'BEGIN { for (i=0; i<40000; i++) printf "x"; print "" }' >> "$OVERSIZE/AGENTS.md"
if [ "$(doctor_fail_count "$OVERSIZE")" -gt 0 ]; then
  ok "doctor rejects AGENTS.md beyond the Codex project-instruction budget"
else
  bad "doctor accepted an AGENTS.md that Codex will truncate"
fi

# Negative fixture: structured work-state must disagree loudly with Git.
git -C "$TARGET" add . >/dev/null 2>&1
git -C "$TARGET" -c user.name=CONDUCTOR -c user.email=conductor@example.invalid commit -qm baseline
/usr/bin/sed -E -i.bak 's/^- \*\*active_branch\*\*:.*/active_branch: definitely-wrong-branch/' "$TARGET/docs/CURRENT_WORK.md"
/bin/rm -f "$TARGET/docs/CURRENT_WORK.md.bak"
if [ "$(doctor_fail_count "$TARGET")" -gt 0 ]; then
  ok "doctor rejects structured CURRENT_WORK/Git branch drift"
else
  bad "doctor accepted structured work-state drift"
fi

# The optional registry advisory must never make deterministic validation wait
# on an unavailable network. Offline mode must skip npm entirely, while the live
# path remains explicitly retry/time bounded.
FAKE_BIN="$BASE/fake-bin"
NPM_CALLED="$BASE/npm-called"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nprintf called > %s\nexit 99\n' "$NPM_CALLED" > "$FAKE_BIN/npm"
chmod +x "$FAKE_BIN/npm"
if PATH="$FAKE_BIN:$PATH" CONDUCTOR_SKIP_REGISTRY_CHECK=1 bash tools/check-stale-tokens.sh >/dev/null 2>&1 \
  && [ ! -e "$NPM_CALLED" ] \
  && /usr/bin/grep -q -- '--fetch-retries=0' tools/check-stale-tokens.sh \
  && /usr/bin/grep -q -- '--fetch-timeout=3000' tools/check-stale-tokens.sh; then
  ok "offline stale-token validation skips npm and live advisory is time-bounded"
else
  bad "stale-token registry advisory can block deterministic validation"
fi

echo
[ "$FAIL" -eq 0 ] && echo "multitool runtime suite: PASS ($BASE)" || echo "multitool runtime suite: FAIL ($BASE)"
exit "$FAIL"
