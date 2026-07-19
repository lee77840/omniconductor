#!/usr/bin/env bash
# CONDUCTOR --mode preset test harness (ADR-044).
# Usage: bash tools/test-install-modes.sh <tool> [base-tmp-dir]
# Exit 0 = all mode behaviors verified for the tool, 1 = a check failed, 2 = usage.
#
# Verifies, per tool:
#   full           — installs + validator passes + manifest stamps "mode": "full"
#   minimal        — rule text + docs/profile present; NO reflector runtime even
#                    with --recipes=self-improvement; tool-specific extras absent
#   strict         — fresh target installs; pre-seeded baseline ABORTS (exit 3, no writes)
#   recipes-only   — ONLY recipe content lands (file or marked block); --recipes required
#                    (error without); uninstall removes it losslessly
#   reflector-only — self-improvement text + Reflector runtime, nothing else; uninstall clean
#   block modes    — (gemini/codex) pre-existing baseline content survives append + strip;
#                    customized block is left in place on uninstall

set -u

TOOL="${1:-}"
case "$TOOL" in
  claude|cursor|copilot|gemini|codex|windsurf) : ;;
  *) echo "Usage: $0 <claude|cursor|copilot|gemini|codex|windsurf> [base-tmp-dir]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.." || exit 2
BASE="${2:-$(mktemp -d "${TMPDIR:-/tmp}/conductor-modes-$TOOL.XXXXXX")}"
T="adapters/$TOOL/transform.sh"

# Exercise the public entry point so every write also crosses the mandatory
# persisted-model-routing gate. Recommended defaults make the fixture
# deterministic while preserving the same adapter mode coverage.
run_adapter() {
  node bin/omniconductor.js init --target="$TOOL" "$@" --accept-model-defaults
}

FAIL=0
ok()   { echo "OK   [$TOOL] $1"; }
bad()  { echo "FAIL [$TOOL] $1"; FAIL=1; }
have() { [ -e "$1" ]; }

# Per-tool file map
case "$TOOL" in
  claude)   BASELINE="CLAUDE.md";                       RULE="" ;;
  cursor)   BASELINE=".cursor/rules/workflow.mdc";      RULE=".cursor/rules/workflow.mdc" ;;
  copilot)  BASELINE=".github/copilot-instructions.md"; RULE=".github/copilot-instructions.md" ;;
  gemini)   BASELINE="GEMINI.md";                       RULE="GEMINI.md" ;;
  codex)    BASELINE="AGENTS.md";                       RULE="AGENTS.md" ;;
  windsurf) BASELINE=".windsurfrules";                  RULE=".devin/rules/workflow.md" ;;
esac
# claude special-case: universal rule location
[ "$TOOL" = "claude" ] && RULE=".claude/rules/workflow.md"

recipe_artifact() { # path proving the tdd recipe landed, per tool + mode-kind (file|block)
  local d="$1"
  case "$TOOL" in
    claude)   echo "$d/.claude/rules/tdd.md" ;;
    cursor)   echo "$d/.cursor/rules/tdd.mdc" ;;
    copilot)  echo "$d/.github/instructions/tdd.instructions.md" ;;
    windsurf) echo "$d/.devin/rules/tdd.md" ;;
    gemini)   echo "$d/GEMINI.md" ;;   # block host
    codex)    echo "$d/AGENTS.md" ;;   # block host
  esac
}

# ---- full ------------------------------------------------------------------
d="$BASE/full"; mkdir -p "$d"
if run_adapter "$d" --no-prompt --recipes=tdd,self-improvement >/dev/null 2>&1 \
   && bash tools/validate-adapter-output.sh "$d" "$TOOL" >/dev/null 2>&1 \
   && grep -q '"mode": "full"' "$d/.conductor/manifests/$TOOL.json"; then
  ok "full: install + validator + manifest mode stamp"
else bad "full mode"; fi

if [ "$TOOL" = "claude" ]; then
  d="$BASE/full-hookify-existing"; mkdir -p "$d/.claude"
  printf '{"customSetting":"preserve-me","hooks":{"PreToolUse":[{"matcher":"Custom","hooks":[{"type":"command","command":"custom-hook"},{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/pretool-agent-routing.sh"}]}]}}\n' > "$d/.claude/settings.json"
  before="$(/usr/bin/cksum < "$d/.claude/settings.json")"
  if run_adapter "$d" --no-prompt >/dev/null 2>&1 \
    && node -e '
      const s=require(process.argv[1]), h=require(process.argv[2]);
      const custom=s.hooks.PreToolUse.some(g=>g.hooks?.some(x=>x.command==="custom-hook"));
      process.exit(s.customSetting==="preserve-me" && custom && s.enabledPlugins?.["hookify@claude-plugins-official"]===true && h.missingCoreHooks(process.argv[1]).length===0 ? 0 : 1)
    ' "$d/.claude/settings.json" "$(pwd)/bin/claude-hookify.js" \
    && bash tools/validate-adapter-output.sh "$d" claude >/dev/null 2>&1; then
    ok "full: semantically enables Hookify without losing existing settings"
  else bad "full Hookify settings merge"; fi
  run_adapter "$d" --uninstall >/dev/null 2>&1
  after="MISSING"; [ -f "$d/.claude/settings.json" ] && after="$(/usr/bin/cksum < "$d/.claude/settings.json")"
  [ "$before" = "$after" ] \
    && ok "full: uninstall restores the exact pre-Hookify settings" \
    || bad "full Hookify settings merge was not losslessly reversible"

  d="$BASE/full-hookify-disabled-rule"; mkdir -p "$d"
  run_adapter "$d" --no-prompt >/dev/null 2>&1
  disabled_rule="$d/.claude/hookify.warn-console-direct.local.md"
  /usr/bin/sed -i.bak 's/^enabled: true$/enabled: false/' "$disabled_rule" && /bin/rm -f "$disabled_rule.bak"
  validator_output="$(bash tools/validate-adapter-output.sh "$d" claude 2>&1)"
  if [ "$?" -eq 0 ] \
    && printf '%s\n' "$validator_output" | /usr/bin/grep -q 'WARN.*valid Hookify rule intentionally disabled by adopter' \
    && printf '%s\n' "$validator_output" | /usr/bin/grep -q 'FAIL=0'; then
    ok "full: validator accepts adopter-disabled Hookify rules with a warning"
  else bad "full Hookify disabled-rule validator policy"; fi

  d="$BASE/full-hookify-optout"; mkdir -p "$d/.claude"
  printf '{"enabledPlugins":{"hookify@claude-plugins-official":false}}\n' > "$d/.claude/settings.json"
  run_adapter "$d" --no-prompt >/dev/null 2>&1
  if node -e 'const s=require(process.argv[1]); process.exit(s.enabledPlugins["hookify@claude-plugins-official"]===false ? 0 : 1)' "$d/.claude/settings.json" \
    && ! bash tools/validate-adapter-output.sh "$d" claude >/dev/null 2>&1 \
    && node bin/omniconductor.js doctor "$d" --json 2>/dev/null | node -e '
      let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
        const r=JSON.parse(s); process.exit(r.checks.some(x=>x.id==="D5"&&x.status==="FAIL"&&/Hookify/.test(x.detail))?0:1)
      })
    '; then
    ok "full: explicit Hookify opt-out is preserved and validator/doctor report degraded enforcement"
  else bad "full Hookify explicit opt-out handling"; fi

  d="$BASE/full-hookify-doctor-scope"; mkdir -p "$d/fake-bin"
  run_adapter "$d" --no-prompt >/dev/null 2>&1
  printf '%s\n' '#!/bin/sh' \
    'if [ "$1 $2 $3" = "plugin list --json" ]; then' \
    '  printf '\''[%s]\\n'\'' '\''{"id":"hookify@claude-plugins-official","scope":"user","enabled":true,"projectPath":"/tmp/not-this-checkout"}'\''' \
    '  exit 0' \
    'fi' \
    'exit 2' > "$d/fake-bin/claude"
  chmod +x "$d/fake-bin/claude"
  doctor_output="$(PATH="$d/fake-bin:$PATH" node bin/omniconductor.js doctor "$d" --json 2>/dev/null || true)"
  if printf '%s\n' "$doctor_output" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
      const r=JSON.parse(s), d5=r.checks.filter(x=>x.id==="D5");
      const mismatch=d5.some(x=>x.status==="WARN"&&/not active in this checkout/.test(x.detail));
      const summary=d5.some(x=>x.status==="OK"&&/structurally sane \([1-9][0-9]* \.json\/\.sh file\(s\) checked\)/.test(x.detail));
      process.exit(mismatch&&summary?0:1)
    })
  '; then
    ok "full: doctor rejects mismatched plugin projectPath and keeps the D5 checked-count summary"
  else bad "full Hookify live-scope/summary doctor diagnostics"; fi

  d="$BASE/full-hookify-invalid"; mkdir -p "$d/.claude"
  printf '{"enabledPlugins":[]}\n' > "$d/.claude/settings.json"
  before="$(/usr/bin/cksum < "$d/.claude/settings.json")"
  run_adapter "$d" --no-prompt >/dev/null 2>&1
  rc=$?
  after="$(/usr/bin/cksum < "$d/.claude/settings.json")"
  if [ "$rc" -eq 1 ] && [ "$before" = "$after" ] \
    && [ -z "$(find "$d/.claude" -type f ! -name settings.json -print -quit 2>/dev/null)" ]; then
    ok "full: invalid plugin settings fail before Claude runtime files are emitted"
  else bad "full invalid Hookify settings preflight (rc=$rc)"; fi

  d="$BASE/full-hookify-user-edit-settings"; mkdir -p "$d/.claude"
  printf '{"customSetting":"before"}\n' > "$d/.claude/settings.json"
  run_adapter "$d" --no-prompt >/dev/null 2>&1
  node -e '
    const fs=require("fs"), p=process.argv[1], s=JSON.parse(fs.readFileSync(p,"utf8"));
    s.customSetting="after"; fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");
  ' "$d/.claude/settings.json"
  run_adapter "$d" --uninstall >/dev/null 2>&1
  if node -e '
    const s=require(process.argv[1]);
    process.exit(s.customSetting==="after"&&s.enabledPlugins?.["hookify@claude-plugins-official"]===true?0:1)
  ' "$d/.claude/settings.json"; then
    ok "full: uninstall preserves post-install settings edits, including the merged Hookify entries"
  else bad "full Hookify user-edited settings uninstall preservation"; fi
fi

# ---- manifest safety: repeat install + user edits -------------------------
# Re-running a full install must retain the original pre-CONDUCTOR baseline
# for uninstall, and uninstall must never delete a post-install user edit.
d="$BASE/full-reinstall"; mkdir -p "$d/$(dirname "$BASELINE")"
printf 'ORIGINAL-USER-BASELINE-%s\n' "$TOOL" > "$d/$BASELINE"
before="$(/usr/bin/cksum < "$d/$BASELINE")"
run_adapter "$d" --no-prompt >/dev/null 2>&1 \
  && run_adapter "$d" --no-prompt >/dev/null 2>&1 \
  && run_adapter "$d" --uninstall >/dev/null 2>&1
after="MISSING"; [ -f "$d/$BASELINE" ] && after="$(/usr/bin/cksum < "$d/$BASELINE")"
[ "$before" = "$after" ] && ok "full: re-install + uninstall restores original baseline" || bad "full re-install lost original baseline"

d="$BASE/full-customized"; mkdir -p "$d"
run_adapter "$d" --no-prompt >/dev/null 2>&1
printf '\nUSER-CUSTOMIZATION-MUST-SURVIVE\n' >> "$d/$BASELINE"
run_adapter "$d" --uninstall >/dev/null 2>&1
grep -q 'USER-CUSTOMIZATION-MUST-SURVIVE' "$d/$BASELINE" 2>/dev/null \
  && ok "full: uninstall preserves user-modified emitted file" \
  || bad "full uninstall deleted user customization"

d="$BASE/full-edit-then-update"; mkdir -p "$d"
run_adapter "$d" --no-prompt >/dev/null 2>&1
printf '\nUSER-EDIT-BEFORE-UPDATE\n' >> "$d/$BASELINE"
run_adapter "$d" --no-prompt >/dev/null 2>&1
run_adapter "$d" --uninstall >/dev/null 2>&1
grep -q 'USER-EDIT-BEFORE-UPDATE' "$d/$BASELINE" 2>/dev/null \
  && ok "full: update snapshots a user edit before replacement" \
  || bad "full update lost user edit"

# ---- minimal ---------------------------------------------------------------
d="$BASE/minimal"; mkdir -p "$d"
minimal_install_ok=false
run_adapter "$d" --mode=minimal --recipes=tdd,self-improvement >/dev/null 2>&1 && minimal_install_ok=true
if $minimal_install_ok && have "$d/$RULE" && have "$d/docs/CURRENT_WORK.md" && have "$d/.conductor/project.json" && [ ! -d "$d/.conductor/reflect" ]; then
  ok "minimal: rule text + docs, no Reflector runtime"
else bad "minimal mode"; fi
if [ "$TOOL" = "claude" ]; then
  { $minimal_install_ok && [ ! -d "$d/.claude/agents" ] && [ ! -d "$d/.claude/hooks" ] \
    && have "$d/CLAUDE.md" && ! /usr/bin/grep -q '{{CLAUDE_TIER_' "$d/CLAUDE.md"; } \
    && ok "minimal: no agents/hooks and dynamic model aliases resolved (claude)" \
    || bad "minimal leaked agents/hooks or unresolved model aliases (claude)"
fi

# ---- strict ----------------------------------------------------------------
d="$BASE/strict-fresh"; mkdir -p "$d"
run_adapter "$d" --mode=strict --no-prompt >/dev/null 2>&1 && have "$d/$RULE" \
  && ok "strict: fresh target installs" || bad "strict fresh install"
d="$BASE/strict-seeded"; mkdir -p "$d"
case "$TOOL" in
  cursor)  mkdir -p "$d/.cursor/rules"; echo x > "$d/.cursor/rules/mine.mdc" ;;
  copilot) mkdir -p "$d/.github"; echo MINE > "$d/.github/copilot-instructions.md" ;;
  *)       mkdir -p "$d/$(dirname "$BASELINE")" 2>/dev/null; echo MINE > "$d/$BASELINE" ;;
esac
run_adapter "$d" --mode=strict --no-prompt >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ] && [ ! -f "$d/.conductor-manifest.json" ]; then
  ok "strict: seeded baseline aborts (exit 3, no manifest)"
else bad "strict seeded abort (rc=$rc)"; fi

# Multi-surface tools: seeding ONLY the secondary rules surface must also abort.
case "$TOOL" in
  claude|copilot|gemini|windsurf)
    d="$BASE/strict-seeded2"; mkdir -p "$d"
    case "$TOOL" in
      claude)   mkdir -p "$d/.claude/rules";        echo x > "$d/.claude/rules/mine.md" ;;
      copilot)  mkdir -p "$d/.github/instructions"; echo x > "$d/.github/instructions/mine.instructions.md" ;;
      gemini)   mkdir -p "$d/.gemini";              echo x > "$d/.gemini/styleguide.md" ;;
      windsurf) mkdir -p "$d/.devin/rules";         echo x > "$d/.devin/rules/mine.md" ;;
    esac
    run_adapter "$d" --mode=strict --no-prompt >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && [ ! -f "$d/.conductor-manifest.json" ]; then
      ok "strict: seeded secondary rules surface also aborts"
    else bad "strict secondary-surface abort (rc=$rc)"; fi
    ;;
esac

# ---- recipes-only ----------------------------------------------------------
d="$BASE/ro-noargs"; mkdir -p "$d"
run_adapter "$d" --mode=recipes-only >/dev/null 2>&1
[ $? -eq 1 ] && ok "recipes-only: requires --recipes (errors without)" || bad "recipes-only missing-recipes guard"

d="$BASE/ro"; mkdir -p "$d"
PRE=""
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  PRE="MY EXISTING RULES"
  echo "$PRE" > "$d/$BASELINE"
fi
run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
art="$(recipe_artifact "$d")"
okay=true
have "$art" || okay=false
[ -d "$d/docs" ] && okay=false
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  grep -q 'conductor:block recipes' "$art" || okay=false
  grep -q "$PRE" "$art" || okay=false
  if [ "$TOOL" = "codex" ]; then
    have "$d/.codex/conductor/recipes/tdd.md" || okay=false
  fi
else
  # per-file tools must NOT have emitted universal rules
  have "$d/$RULE" && okay=false
fi
$okay && ok "recipes-only: only recipe content landed" || bad "recipes-only emission"

run_adapter "$d" --uninstall >/dev/null 2>&1
okay=true
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  grep -q 'conductor:block' "$art" 2>/dev/null && okay=false
  grep -q "$PRE" "$art" 2>/dev/null || okay=false
  if [ "$TOOL" = "codex" ]; then
    have "$d/.codex/conductor/recipes/tdd.md" && okay=false
  fi
else
  have "$art" && okay=false
fi
$okay && ok "recipes-only: uninstall lossless" || bad "recipes-only uninstall"

# ---- reflector-only --------------------------------------------------------
d="$BASE/reflonly"; mkdir -p "$d"
run_adapter "$d" --mode=reflector-only >/dev/null 2>&1
okay=true
if [ "$TOOL" = "claude" ]; then
  # Claude's trajectory logger is the Stop hook, not the portable stdin logger.
  [ -x "$d/.claude/hooks/stop-trajectory-log.sh" ] || okay=false
  [ -d "$d/.conductor/reflect" ] || okay=false
else
  [ -x "$d/.conductor/reflect/trajectory-log.sh" ] || okay=false
fi
[ -d "$d/docs" ] && okay=false
case "$TOOL" in
  claude)   { have "$d/.claude/rules/self-improvement.md" && have "$d/.claude/agents/reflector.md" && have "$d/.claude/hooks/stop-trajectory-log.sh" && have "$d/.claude/settings.json" && [ ! -f "$d/CLAUDE.md" ]; } || okay=false ;;
  cursor)   { have "$d/.cursor/rules/self-improvement.mdc" && have "$d/.cursor/hooks.json" && [ ! -f "$d/.cursor/rules/workflow.mdc" ]; } || okay=false ;;
  copilot)  { have "$d/.github/instructions/self-improvement.instructions.md" && have "$d/.github/hooks/conductor-reflect.json" && [ ! -f "$d/.github/copilot-instructions.md" ]; } || okay=false ;;
  gemini)   { grep -q 'conductor:block reflector' "$d/GEMINI.md" && have "$d/.gemini/settings.json"; } || okay=false ;;
  codex)    { grep -q 'conductor:block reflector' "$d/AGENTS.md" && have "$d/.codex/hooks.json"; } || okay=false ;;
  windsurf) { have "$d/.devin/rules/self-improvement.md" && have "$d/.windsurf/hooks.json" && [ ! -f "$d/.windsurfrules" ]; } || okay=false ;;
esac
$okay && ok "reflector-only: loop artifacts only" || bad "reflector-only emission"
run_adapter "$d" --uninstall >/dev/null 2>&1
if [ ! -d "$d/.conductor" ] || [ -z "$(find "$d/.conductor" -type f ! -path "$d/.conductor/model-routing.json" -print -quit 2>/dev/null)" ]; then
  ok "reflector-only: uninstall clean"
else
  bad "reflector-only uninstall"
fi

# ---- zero valid recipes must fail (all tools) -------------------------------
d="$BASE/ro-badname"; mkdir -p "$d"
run_adapter "$d" --mode=recipes-only --recipes=notarealrecipe >/dev/null 2>&1
if [ $? -eq 1 ] && [ ! -f "$d/.conductor-manifest.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json.staging" ]; then
  ok "recipes-only: zero valid recipes → exit 1, no manifest/staging litter"
else bad "recipes-only zero-valid-recipes guard"; fi

# ---- byte-lossless block round-trip + cross-mode (single-file tools) ---------
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  # A user-owned marker (including a malformed one) must never be treated as
  # an existing CONDUCTOR block. Refuse without touching the host file.
  d="$BASE/marker-collision"; mkdir -p "$d"
  printf 'USER PREFIX\n<!-- conductor:block recipes -->\nUSER CONTENT AFTER MARKER\n' > "$d/$BASELINE"
  before="$(/usr/bin/cksum < "$d/$BASELINE")"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  rc=$?
  after="$(/usr/bin/cksum < "$d/$BASELINE")"
  if [ "$rc" -eq 1 ] && [ "$before" = "$after" ] && [ ! -f "$d/.conductor-manifest.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json.staging" ]; then
    ok "block: foreign/unpaired marker aborts without data loss"
  else bad "block: foreign marker collision (rc=$rc)"; fi

  d="$BASE/marker-foreign-paired"; mkdir -p "$d"
  printf 'USER PREFIX\n<!-- conductor:block recipes -->\nUSER BLOCK\n<!-- /conductor:block recipes -->\nUSER SUFFIX\n' > "$d/$BASELINE"
  before="$(/usr/bin/cksum < "$d/$BASELINE")"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  rc=$?
  after="$(/usr/bin/cksum < "$d/$BASELINE")"
  if [ "$rc" -eq 1 ] && [ "$before" = "$after" ] && [ ! -f "$d/.conductor-manifest.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json.staging" ]; then
    ok "block: foreign paired marker aborts without data loss"
  else bad "block: foreign paired-marker collision (rc=$rc)"; fi

  d="$BASE/marker-custom-reinstall"; mkdir -p "$d"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  if [ "$TOOL" = "codex" ]; then
    /usr/bin/sed -i.bak 's/`tdd`/`tdd-CUSTOMIZED`/' "$d/$BASELINE"
  else
    /usr/bin/sed -i.bak 's/## Recipe — tdd/## Recipe — tdd (CUSTOMIZED)/' "$d/$BASELINE"
  fi
  rm -f "$d/$BASELINE.bak"
  before="$(/usr/bin/cksum < "$d/$BASELINE")"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  rc=$?
  after="$(/usr/bin/cksum < "$d/$BASELINE")"
  if [ "$rc" -eq 1 ] && [ "$before" = "$after" ] && [ ! -f "$d/.conductor/manifests/$TOOL.json.staging" ]; then
    ok "block: customized managed block is not overwritten on re-install"
  else bad "block: customized managed block overwritten (rc=$rc)"; fi

  d="$BASE/lossless"; mkdir -p "$d"
  printf 'MY EXISTING RULES\n' > "$d/$BASELINE"
  before="$(/usr/bin/cksum < "$d/$BASELINE")"
  for _i in 1 2 3; do run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1; done
  run_adapter "$d" --uninstall >/dev/null 2>&1
  after="$(/usr/bin/cksum < "$d/$BASELINE")"
  [ "$before" = "$after" ] && ok "block: 3x reinstall + uninstall is byte-lossless" || bad "block: reinstall/uninstall not byte-lossless"

  d="$BASE/crossmode"; mkdir -p "$d"
  printf 'BASE\n' > "$d/$BASELINE"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  run_adapter "$d" --mode=reflector-only >/dev/null 2>&1
  run_adapter "$d" --uninstall >/dev/null 2>&1
  if [ "$(grep -c 'conductor:block' "$d/$BASELINE" 2>/dev/null)" -eq 0 ] && grep -q 'BASE' "$d/$BASELINE"; then
    ok "block: cross-mode (recipes-only → reflector-only) uninstall strips BOTH blocks"
  else bad "block: cross-mode uninstall left an orphaned block"; fi
fi

# ---- customized block survives uninstall (single-file tools) ----------------
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  d="$BASE/custom"; mkdir -p "$d"
  echo "BASE" > "$d/$BASELINE"
  run_adapter "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  # mutate INSIDE the block
  if [ "$TOOL" = "codex" ]; then
    /usr/bin/sed -i.bak 's/`tdd`/`tdd-CUSTOMIZED`/' "$d/$BASELINE"
  else
    /usr/bin/sed -i.bak 's/## Recipe — tdd/## Recipe — tdd (CUSTOMIZED)/' "$d/$BASELINE"
  fi
  rm -f "$d/$BASELINE.bak"
  run_adapter "$d" --uninstall >/dev/null 2>&1
  if grep -q 'CUSTOMIZED' "$d/$BASELINE"; then
    ok "block: customized block left in place on uninstall"
  else bad "block: customized block was destroyed"; fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK — all --mode behaviors verified for $TOOL ($BASE)"
  exit 0
fi
echo "FAIL — mode behavior broken for $TOOL (workdirs kept at $BASE)"
exit 1
