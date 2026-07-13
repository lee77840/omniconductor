#!/usr/bin/env bash
# Complete local release gate. It never pushes, dispatches CI, or publishes.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$ROOT/package.json")"
PREVIOUS_VERSION="${CONDUCTOR_PREVIOUS_VERSION:-1.0.1}"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/conductor-release-$VERSION.XXXXXX")"
ARTIFACT_DIR="${CONDUCTOR_RELEASE_DIR:-$BASE/artifact}"
CACHE="${CONDUCTOR_NPM_CACHE:-${TMPDIR:-/tmp}/conductor-npm-cache}"
PREVIOUS_PACKAGE="${CONDUCTOR_PREVIOUS_PACKAGE:-}"
REQUIRE_CLEAN="${CONDUCTOR_RELEASE_REQUIRE_CLEAN:-0}"

mkdir -p "$ARTIFACT_DIR"
cd "$ROOT"

echo "[release] full local regression suite"
npm test

echo "[release] static, metadata, generated-doc, and source checks"
bash tools/check-stale-tokens.sh
bash tools/check-adapter-metadata.sh
node tools/generate-adapter-docs.js --check
bash tools/check-framework-purity.sh
git diff --check
for file in adapters/{claude,cursor,copilot,gemini,codex,windsurf}/transform.sh \
  tools/{test-install-modes,test-multitool-runtime,test-npm-upgrade,live-verify}.sh; do
  bash -n "$file"
done

if [ -z "$(git status --porcelain --untracked-files=all)" ]; then
  echo "[release] committed public-snapshot boundary"
  bash scripts/sync-public.sh HEAD --check
  SNAPSHOT_STATUS="PASS (HEAD)"
else
  if [ "$REQUIRE_CLEAN" = "1" ]; then
    echo "release gate requires a clean committed tree so the exact public snapshot can be verified" >&2
    exit 1
  fi
  echo "[release] public-snapshot boundary deferred: working tree is not committed"
  echo "          rerun with CONDUCTOR_RELEASE_REQUIRE_CLEAN=1 after the release commit"
  SNAPSHOT_STATUS="DEFERRED (uncommitted working tree)"
fi
for file in bin/{omniconductor,doctor,model-routing,path-safety}.js \
  tools/{test-model-routing,test-path-safety}.js; do
  node --check "$file"
done

echo "[release] pack exact npm candidate"
PACKAGE_NAME="$(npm_config_cache="$CACHE" npm pack --pack-destination "$ARTIFACT_DIR" | /usr/bin/tail -n 1)"
CURRENT_PACKAGE="$ARTIFACT_DIR/$PACKAGE_NAME"
[ -f "$CURRENT_PACKAGE" ] || { echo "release artifact missing: $CURRENT_PACKAGE" >&2; exit 1; }

echo "[release] fresh six-tool consumer install"
FRESH="$BASE/fresh"
mkdir -p "$FRESH/project"
npm_config_cache="$CACHE" npm install --prefix "$FRESH/consumer" "$CURRENT_PACKAGE" \
  --ignore-scripts --no-audit --no-fund >/dev/null
CLI="$FRESH/consumer/node_modules/.bin/omniconductor"
PKG="$FRESH/consumer/node_modules/omniconductor"
"$CLI" init --target=all "$FRESH/project" --no-prompt --accept-model-defaults \
  --recipes=self-improvement,git-hygiene,loop-engineering >/dev/null 2>&1
for tool in claude cursor copilot gemini codex windsurf; do
  bash "$PKG/tools/validate-adapter-output.sh" "$FRESH/project" "$tool" >/dev/null
done
set +e
"$CLI" doctor "$FRESH/project" --json > "$BASE/fresh-doctor.json" 2>/dev/null
DOCTOR_RC=$?
set -e
[ "$DOCTOR_RC" -le 1 ] || { echo "fresh consumer doctor failed" >&2; exit 1; }
node -e 'const d=require(process.argv[1]); if (!d.summary || d.summary.FAIL !== 0) process.exit(1)' \
  "$BASE/fresh-doctor.json"
"$CLI" init --target=all "$FRESH/project" --uninstall >/dev/null 2>&1
[ "$(find "$FRESH/project" -type f ! -path '*/.conductor/model-routing.json' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq 0 ]
[ -s "$FRESH/project/.conductor/model-routing.json" ]

if [ -z "$PREVIOUS_PACKAGE" ]; then
  PREVIOUS_DIR="$BASE/previous"
  mkdir -p "$PREVIOUS_DIR"
  echo "[release] fetch published omniconductor@$PREVIOUS_VERSION for upgrade verification"
  PREVIOUS_NAME="$(npm_config_cache="$CACHE" npm pack "omniconductor@$PREVIOUS_VERSION" \
    --pack-destination "$PREVIOUS_DIR" | /usr/bin/tail -n 1)"
  PREVIOUS_PACKAGE="$PREVIOUS_DIR/$PREVIOUS_NAME"
fi

echo "[release] published-version npm upgrade matrix"
CONDUCTOR_PREVIOUS_VERSION="$PREVIOUS_VERSION" \
  bash tools/test-npm-upgrade.sh "$CURRENT_PACKAGE" "$PREVIOUS_PACKAGE"

echo "[release] npm publish dry run"
npm_config_cache="$CACHE" npm publish --dry-run --ignore-scripts "$CURRENT_PACKAGE" >/dev/null

SHA256="$(shasum -a 256 "$CURRENT_PACKAGE" | /usr/bin/awk '{print $1}')"
echo "local release gate: PASS"
echo "artifact: $CURRENT_PACKAGE"
echo "sha256: $SHA256"
echo "public snapshot: $SNAPSHOT_STATUS"
echo "note: GitHub Actions were not invoked; publication was a dry run only."
