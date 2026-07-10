#!/usr/bin/env bash
# CONDUCTOR --mode preset test harness (ADR-044).
# Usage: bash tools/test-install-modes.sh <tool> [base-tmp-dir]
# Exit 0 = all mode behaviors verified for the tool, 1 = a check failed, 2 = usage.
#
# Verifies, per tool:
#   full           — installs + validator passes + manifest stamps "mode": "full"
#   minimal        — rule text + docs present; NO reflector runtime (.conductor/) even
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
if bash "$T" "$d" --no-prompt --recipes=tdd,self-improvement >/dev/null 2>&1 \
   && bash tools/validate-adapter-output.sh "$d" "$TOOL" >/dev/null 2>&1 \
   && grep -q '"mode": "full"' "$d/.conductor-manifest.json"; then
  ok "full: install + validator + manifest mode stamp"
else bad "full mode"; fi

# ---- minimal ---------------------------------------------------------------
d="$BASE/minimal"; mkdir -p "$d"
bash "$T" "$d" --mode=minimal --recipes=tdd,self-improvement >/dev/null 2>&1
if have "$d/$RULE" && have "$d/docs/CURRENT_WORK.md" && [ ! -d "$d/.conductor" ]; then
  ok "minimal: rule text + docs, no Reflector runtime"
else bad "minimal mode"; fi
if [ "$TOOL" = "claude" ]; then
  { [ ! -d "$d/.claude/agents" ] && [ ! -d "$d/.claude/hooks" ]; } && ok "minimal: no agents/hooks (claude)" || bad "minimal leaked agents/hooks (claude)"
fi

# ---- strict ----------------------------------------------------------------
d="$BASE/strict-fresh"; mkdir -p "$d"
bash "$T" "$d" --mode=strict --no-prompt >/dev/null 2>&1 && have "$d/$RULE" \
  && ok "strict: fresh target installs" || bad "strict fresh install"
d="$BASE/strict-seeded"; mkdir -p "$d"
case "$TOOL" in
  cursor)  mkdir -p "$d/.cursor/rules"; echo x > "$d/.cursor/rules/mine.mdc" ;;
  copilot) mkdir -p "$d/.github"; echo MINE > "$d/.github/copilot-instructions.md" ;;
  *)       mkdir -p "$d/$(dirname "$BASELINE")" 2>/dev/null; echo MINE > "$d/$BASELINE" ;;
esac
bash "$T" "$d" --mode=strict --no-prompt >/dev/null 2>&1
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
    bash "$T" "$d" --mode=strict --no-prompt >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && [ ! -f "$d/.conductor-manifest.json" ]; then
      ok "strict: seeded secondary rules surface also aborts"
    else bad "strict secondary-surface abort (rc=$rc)"; fi
    ;;
esac

# ---- recipes-only ----------------------------------------------------------
d="$BASE/ro-noargs"; mkdir -p "$d"
bash "$T" "$d" --mode=recipes-only >/dev/null 2>&1
[ $? -eq 1 ] && ok "recipes-only: requires --recipes (errors without)" || bad "recipes-only missing-recipes guard"

d="$BASE/ro"; mkdir -p "$d"
PRE=""
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  PRE="MY EXISTING RULES"
  echo "$PRE" > "$d/$BASELINE"
fi
bash "$T" "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
art="$(recipe_artifact "$d")"
okay=true
have "$art" || okay=false
[ -d "$d/docs" ] && okay=false
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  grep -q 'conductor:block recipes' "$art" || okay=false
  grep -q "$PRE" "$art" || okay=false
else
  # per-file tools must NOT have emitted universal rules
  have "$d/$RULE" && okay=false
fi
$okay && ok "recipes-only: only recipe content landed" || bad "recipes-only emission"

bash "$T" "$d" --uninstall >/dev/null 2>&1
okay=true
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  grep -q 'conductor:block' "$art" 2>/dev/null && okay=false
  grep -q "$PRE" "$art" 2>/dev/null || okay=false
else
  have "$art" && okay=false
fi
$okay && ok "recipes-only: uninstall lossless" || bad "recipes-only uninstall"

# ---- reflector-only --------------------------------------------------------
d="$BASE/reflonly"; mkdir -p "$d"
bash "$T" "$d" --mode=reflector-only >/dev/null 2>&1
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
bash "$T" "$d" --uninstall >/dev/null 2>&1
[ ! -d "$d/.conductor" ] && ok "reflector-only: uninstall clean" || bad "reflector-only uninstall"

# ---- zero valid recipes must fail (all tools) -------------------------------
d="$BASE/ro-badname"; mkdir -p "$d"
bash "$T" "$d" --mode=recipes-only --recipes=notarealrecipe >/dev/null 2>&1
if [ $? -eq 1 ] && [ ! -f "$d/.conductor-manifest.json" ] && [ ! -f "$d/.conductor-manifest.json.staging" ]; then
  ok "recipes-only: zero valid recipes → exit 1, no manifest/staging litter"
else bad "recipes-only zero-valid-recipes guard"; fi

# ---- byte-lossless block round-trip + cross-mode (single-file tools) ---------
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  d="$BASE/lossless"; mkdir -p "$d"
  printf 'MY EXISTING RULES\n' > "$d/$BASELINE"
  before="$(/usr/bin/cksum < "$d/$BASELINE")"
  for _i in 1 2 3; do bash "$T" "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1; done
  bash "$T" "$d" --uninstall >/dev/null 2>&1
  after="$(/usr/bin/cksum < "$d/$BASELINE")"
  [ "$before" = "$after" ] && ok "block: 3x reinstall + uninstall is byte-lossless" || bad "block: reinstall/uninstall not byte-lossless"

  d="$BASE/crossmode"; mkdir -p "$d"
  printf 'BASE\n' > "$d/$BASELINE"
  bash "$T" "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  bash "$T" "$d" --mode=reflector-only >/dev/null 2>&1
  bash "$T" "$d" --uninstall >/dev/null 2>&1
  if [ "$(grep -c 'conductor:block' "$d/$BASELINE" 2>/dev/null)" -eq 0 ] && grep -q 'BASE' "$d/$BASELINE"; then
    ok "block: cross-mode (recipes-only → reflector-only) uninstall strips BOTH blocks"
  else bad "block: cross-mode uninstall left an orphaned block"; fi
fi

# ---- customized block survives uninstall (single-file tools) ----------------
if [ "$TOOL" = "gemini" ] || [ "$TOOL" = "codex" ]; then
  d="$BASE/custom"; mkdir -p "$d"
  echo "BASE" > "$d/$BASELINE"
  bash "$T" "$d" --mode=recipes-only --recipes=tdd >/dev/null 2>&1
  # mutate INSIDE the block
  /usr/bin/sed -i.bak 's/## Recipe — tdd/## Recipe — tdd (CUSTOMIZED)/' "$d/$BASELINE" && rm -f "$d/$BASELINE.bak"
  bash "$T" "$d" --uninstall >/dev/null 2>&1
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
