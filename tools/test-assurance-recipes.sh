#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/conductor-assurance-recipes.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

RECIPES="database-change-assurance,non-vacuous-testing,visual-baseline-integrity,release-provenance"
RECIPE_NAMES="database-change-assurance non-vacuous-testing visual-baseline-integrity release-provenance"
PASS=0
FAIL=0

ok() { echo "OK   [assurance-recipes] $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL [assurance-recipes] $1" >&2; FAIL=$((FAIL + 1)); }

recipe_file() {
  tool="$1" target="$2" recipe="$3"
  case "$tool" in
    claude) echo "$target/.claude/rules/$recipe.md" ;;
    cursor) echo "$target/.cursor/rules/$recipe.mdc" ;;
    copilot) echo "$target/.github/instructions/$recipe.instructions.md" ;;
    codex) echo "$target/.codex/conductor/recipes/$recipe.md" ;;
    windsurf) echo "$target/.devin/rules/$recipe.md" ;;
    gemini) echo "$target/GEMINI.md" ;;
    opencode) echo "$target/.opencode/rules/recipes/$recipe.md" ;;
  esac
}

cd "$ROOT"

for tool in claude cursor copilot gemini codex windsurf opencode; do
  target="$TMP/$tool"
  mkdir -p "$target"
  printf 'USER-DATA-%s\n' "$tool" > "$target/user.keep"
  if ! node bin/omniconductor.js init --target="$tool" "$target" \
    --mode=recipes-only --recipes="$RECIPES" >/dev/null 2>&1; then
    bad "$tool installs the four assurance recipes"
    continue
  fi

  installed=true
  for recipe in $RECIPE_NAMES; do
    file="$(recipe_file "$tool" "$target" "$recipe")"
    [ -s "$file" ] || installed=false
    /usr/bin/grep -Eq '^#{1,2} Recipe' "$file" 2>/dev/null || installed=false
    /usr/bin/grep -q "$recipe" "$target/.conductor/manifests/$tool.json" 2>/dev/null \
      || installed=false
  done
  if $installed; then
    ok "$tool emits and manifests all four opt-in recipes"
  else
    bad "$tool recipe output or ownership"
  fi

  if node bin/omniconductor.js init --target="$tool" "$target" --uninstall >/dev/null 2>&1 \
    && [ "$(/bin/cat "$target/user.keep")" = "USER-DATA-$tool" ]; then
    removed=true
    for recipe in $RECIPE_NAMES; do
      file="$(recipe_file "$tool" "$target" "$recipe")"
      if [ "$tool" = "gemini" ]; then
        /usr/bin/grep -q "$recipe" "$file" 2>/dev/null && removed=false
      else
        [ ! -e "$file" ] || removed=false
      fi
    done
    if $removed; then
      ok "$tool uninstall removes only managed assurance recipes"
    else
      bad "$tool assurance recipe uninstall"
    fi
  else
    bad "$tool uninstall or user-data preservation"
  fi
done

node bin/omniconductor.js eval coverage --json > "$TMP/coverage.json"
if node - "$TMP/coverage.json" <<'NODE'
const report = require(process.argv[2]);
const required = new Set([
  'recipe:database-change-assurance',
  'recipe:non-vacuous-testing',
  'recipe:visual-baseline-integrity',
  'recipe:release-provenance',
]);
for (const record of report.records) required.delete(record.id);
process.exit(required.size ? 1 : 0);
NODE
then
  ok "assurance coverage discovers all four recipes"
else
  bad "assurance coverage recipe discovery"
fi

[ "$FAIL" -eq 0 ] || exit 1
echo "OK — assurance recipe tests: $PASS/$PASS"
