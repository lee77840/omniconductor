#!/usr/bin/env bash
# Verify the real npm consumer upgrade path from the last published release.
# Usage: bash tools/test-npm-upgrade.sh <current.tgz> <previous.tgz>

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CURRENT_PACKAGE="${1:-}"
PREVIOUS_PACKAGE="${2:-}"
PREVIOUS_VERSION="${CONDUCTOR_PREVIOUS_VERSION:-1.0.1}"

[ -n "$CURRENT_PACKAGE" ] && [ -f "$CURRENT_PACKAGE" ] || {
  echo "Usage: $0 <current-package.tgz> <previous-package.tgz>" >&2
  exit 2
}
[ -n "$PREVIOUS_PACKAGE" ] && [ -f "$PREVIOUS_PACKAGE" ] || {
  echo "Usage: $0 <current-package.tgz> <previous-package.tgz>" >&2
  exit 2
}

CURRENT_PACKAGE="$(cd "$(dirname "$CURRENT_PACKAGE")" && pwd)/$(basename "$CURRENT_PACKAGE")"
PREVIOUS_PACKAGE="$(cd "$(dirname "$PREVIOUS_PACKAGE")" && pwd)/$(basename "$PREVIOUS_PACKAGE")"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/conductor-npm-upgrade.XXXXXX")"
CONSUMER="$BASE/consumer"
CACHE="${CONDUCTOR_NPM_CACHE:-${TMPDIR:-/tmp}/conductor-npm-cache}"
TOOLS="claude cursor copilot gemini codex windsurf"
RECIPES="self-improvement,git-hygiene,loop-engineering"

fail() { echo "FAIL [npm-upgrade] $* (fixture: $BASE)" >&2; exit 1; }
ok() { echo "OK   [npm-upgrade] $*"; }

baseline_for() {
  case "$1" in
    claude) echo "CLAUDE.md" ;;
    cursor) echo ".cursor/rules/workflow.mdc" ;;
    copilot) echo ".github/copilot-instructions.md" ;;
    gemini) echo "GEMINI.md" ;;
    codex) echo "AGENTS.md" ;;
    windsurf) echo ".windsurfrules" ;;
  esac
}

doctor_has_no_failures() {
  local cli="$1" project="$2" label="$3" report rc
  report="$BASE/doctor-$label.json"
  set +e
  "$cli" doctor "$project" --json > "$report" 2>/dev/null
  rc=$?
  set -e
  [ "$rc" -le 1 ] || fail "$label doctor returned $rc"
  node -e 'const d=require(process.argv[1]); if (!d.summary || d.summary.FAIL !== 0) process.exit(1)' "$report" \
    || fail "$label doctor reported a failure"
}

sentinel_is_backed_up() {
  local project="$1" sentinel="$2" file found="false"
  while IFS= read -r file; do
    if /usr/bin/grep -qF "$sentinel" "$file" 2>/dev/null; then found="true"; break; fi
  done < <(find "$project" -type f -name '*.conductor-backup-*' -print 2>/dev/null)
  [ "$found" = "true" ]
}

tree_fingerprint() {
  local project="$1"
  (
    cd "$project"
    find . -print | LC_ALL=C sort
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done
  ) | shasum -a 256 | /usr/bin/awk '{print $1}'
}

cd "$ROOT"
npm_config_cache="$CACHE" npm install --prefix "$CONSUMER" "$PREVIOUS_PACKAGE" \
  --ignore-scripts --no-audit --no-fund >/dev/null
CLI="$CONSUMER/node_modules/.bin/omniconductor"
[ "$($CLI --version)" = "$PREVIOUS_VERSION" ] || fail "previous package version is not $PREVIOUS_VERSION"

# Prepare six independent existing-user projects, including a user edit to the
# primary managed surface, before replacing the installed npm package.
for tool in $TOOLS; do
  project="$BASE/single-$tool"
  mkdir -p "$project"
  printf 'KEEP-%s\n' "$tool" > "$project/KEEP.txt"
  "$CLI" init --target="$tool" "$project" --no-prompt --recipes="$RECIPES" >/dev/null 2>&1 \
    || fail "$tool $PREVIOUS_VERSION fixture install"
  baseline="$(baseline_for "$tool")"
  sentinel="USER-UPGRADE-SENTINEL-$tool"
  printf '\n%s\n' "$sentinel" >> "$project/$baseline"
done

# Also reproduce a legacy project where all six v1.0.1 adapters were installed
# sequentially and therefore shared the historical root manifest.
MULTI="$BASE/multi"
mkdir -p "$MULTI"
printf 'KEEP-MULTI\n' > "$MULTI/KEEP.txt"
for tool in $TOOLS; do
  "$CLI" init --target="$tool" "$MULTI" --no-prompt --recipes="$RECIPES" >/dev/null 2>&1 \
    || fail "multi-project $tool $PREVIOUS_VERSION fixture install"
done
ok "prepared published $PREVIOUS_VERSION single-tool and six-tool fixtures"

# Replace the consumer's installed npm dependency in place with the exact
# candidate tarball. This is the real npm upgrade operation users perform.
npm_config_cache="$CACHE" npm install --prefix "$CONSUMER" "$CURRENT_PACKAGE" \
  --ignore-scripts --no-audit --no-fund >/dev/null
CLI="$CONSUMER/node_modules/.bin/omniconductor"
PKG="$CONSUMER/node_modules/omniconductor"
CURRENT_VERSION="$($CLI --version)"
[ "$CURRENT_VERSION" != "$PREVIOUS_VERSION" ] || fail "npm did not replace the previous package"
ok "npm replaced $PREVIOUS_VERSION with $CURRENT_VERSION in place"

# A preview of an old shared-manifest project must not eagerly migrate ownership
# or create model state. The actual migration belongs to the real install below.
BEFORE_DRY_RUN="$(tree_fingerprint "$MULTI")"
"$CLI" init --target=all "$MULTI" --dry-run --no-prompt --accept-model-defaults \
  --recipes="$RECIPES" >/dev/null 2>&1 || fail "six-tool legacy project dry-run"
AFTER_DRY_RUN="$(tree_fingerprint "$MULTI")"
[ "$BEFORE_DRY_RUN" = "$AFTER_DRY_RUN" ] \
  || fail "six-tool legacy dry-run changed files or directories"
ok "legacy six-tool dry-run is byte- and path-zero-write"

for tool in $TOOLS; do
  project="$BASE/single-$tool"
  baseline="$(baseline_for "$tool")"
  sentinel="USER-UPGRADE-SENTINEL-$tool"
  "$CLI" init --target="$tool" "$project" --no-prompt --accept-model-defaults \
    --recipes="$RECIPES" >/dev/null 2>&1 || fail "$tool upgrade install"
  bash "$PKG/tools/validate-adapter-output.sh" "$project" "$tool" >/dev/null 2>&1 \
    || fail "$tool upgraded output validation"
  doctor_has_no_failures "$CLI" "$project" "single-$tool"
  node -e '
    const m=require(process.argv[1]), c=require(process.argv[2]);
    if (String(m.version).replace(/^v/, "") !== process.argv[3]) process.exit(1);
    if (!c.adapters || !c.adapters[process.argv[4]]) process.exit(1);
  ' "$project/.conductor/manifests/$tool.json" "$project/.conductor/model-routing.json" \
    "$CURRENT_VERSION" "$tool" || fail "$tool version/routing migration"
  sentinel_is_backed_up "$project" "$sentinel" || fail "$tool user edit was not backed up"

  "$CLI" init --target="$tool" "$project" --uninstall >/dev/null 2>&1 \
    || fail "$tool post-upgrade uninstall"
  /usr/bin/grep -qF "$sentinel" "$project/$baseline" \
    || fail "$tool uninstall did not restore the pre-upgrade user edit"
  [ "$(/bin/cat "$project/KEEP.txt")" = "KEEP-$tool" ] || fail "$tool user sentinel changed"
  [ -s "$project/.conductor/model-routing.json" ] || fail "$tool model choices were not retained"
  [ ! -f "$project/.conductor/manifests/$tool.json" ] || fail "$tool manifest remained after uninstall"
  ok "$tool $PREVIOUS_VERSION → $CURRENT_VERSION upgrade, validation, doctor, and rollback"
done

"$CLI" init --target=all "$MULTI" --no-prompt --accept-model-defaults \
  --recipes="$RECIPES" >/dev/null 2>&1 || fail "six-tool legacy project upgrade"
for tool in $TOOLS; do
  bash "$PKG/tools/validate-adapter-output.sh" "$MULTI" "$tool" >/dev/null 2>&1 \
    || fail "six-tool upgraded $tool output validation"
done
doctor_has_no_failures "$CLI" "$MULTI" "multi"
[ "$(find "$MULTI/.conductor/manifests" -type f -name '*.json' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq 6 ] \
  || fail "six-tool upgrade did not create six authoritative manifests"
node -e 'const c=require(process.argv[1]); if (Object.keys(c.adapters || {}).length !== 6) process.exit(1)' \
  "$MULTI/.conductor/model-routing.json" || fail "six-tool routing migration"
"$CLI" init --target=all "$MULTI" --uninstall >/dev/null 2>&1 || fail "six-tool post-upgrade uninstall"
[ "$(/bin/cat "$MULTI/KEEP.txt")" = "KEEP-MULTI" ] || fail "six-tool user sentinel changed"
[ -s "$MULTI/.conductor/model-routing.json" ] || fail "six-tool model choices were not retained"
ok "legacy six-tool project upgrades and uninstalls without losing user data"

echo "npm upgrade suite: PASS ($BASE)"
