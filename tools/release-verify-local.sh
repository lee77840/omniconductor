#!/usr/bin/env bash
# Complete local release gate. It never pushes, dispatches CI, or publishes.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$ROOT/package.json")"
PREVIOUS_VERSION="${CONDUCTOR_PREVIOUS_VERSION:-}"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/conductor-release-$VERSION.XXXXXX")"
ARTIFACT_DIR="${CONDUCTOR_RELEASE_DIR:-$BASE/artifact}"
# Registry state is part of the release decision. Default to a cache scoped to this
# invocation so a prior run cannot supply an obsolete dist-tag. An explicitly supplied
# cache remains supported for controlled environments; --prefer-online below still
# forces npm to revalidate registry metadata.
CACHE="${CONDUCTOR_NPM_CACHE:-$BASE/npm-cache}"
PREVIOUS_PACKAGE="${CONDUCTOR_PREVIOUS_PACKAGE:-}"
REQUIRE_CLEAN="${CONDUCTOR_RELEASE_REQUIRE_CLEAN:-0}"
REGISTRY_LATEST="${CONDUCTOR_REGISTRY_LATEST_VERSION:-}"
REGISTRY_VERSIONS_JSON="${CONDUCTOR_REGISTRY_VERSIONS_JSON:-}"

mkdir -p "$ARTIFACT_DIR"
cd "$ROOT"

echo "[release] registry version and upgrade baseline"
if [ -z "$REGISTRY_LATEST" ]; then
  REGISTRY_LATEST="$(npm_config_cache="$CACHE" npm view omniconductor version \
    --fetch-retries=1 --fetch-retry-mintimeout=1000 \
    --fetch-retry-maxtimeout=3000 --fetch-timeout=10000 --prefer-online)"
fi
if [ -z "$REGISTRY_VERSIONS_JSON" ]; then
  REGISTRY_VERSIONS_JSON="$(npm_config_cache="$CACHE" npm view omniconductor versions --json \
    --fetch-retries=1 --fetch-retry-mintimeout=1000 \
    --fetch-retry-maxtimeout=3000 --fetch-timeout=10000 --prefer-online)"
fi
[ -n "$REGISTRY_LATEST" ] && [ -n "$REGISTRY_VERSIONS_JSON" ] || {
  echo "release gate could not establish npm registry state" >&2
  exit 1
}
node tools/check-release-version.js "$VERSION" "$REGISTRY_LATEST" "$REGISTRY_VERSIONS_JSON"
if [ -z "$PREVIOUS_VERSION" ]; then
  PREVIOUS_VERSION="$REGISTRY_LATEST"
fi

echo "[release] full local regression suite"
npm test

echo "[release] static, metadata, generated-doc, and source checks"
for required_tracked_file in \
  bin/adapter-dispatch.js bin/installer-platform.js \
  bin/claude-hookify.js bin/runtime-contract.js bin/portable-skills.js bin/hook-config.js \
  bin/assurance-coverage.js bin/evidence-contract.js bin/extension-trust.js bin/plugin-packager.js \
  bin/skill-proposals.js bin/work-contract.js bin/workspace-contract.js \
  core/hooks/registry.json core/skills/coordinate-work/SKILL.md \
  core/skills/propose-skill/SKILL.md docs/AGENT-EVAL-COVERAGE.json \
  docs/AGENT-EVAL-COVERAGE.md docs/PARALLEL-WORK.md docs/WORKSPACE-FEDERATION.md \
  docs/TOKEN-ECONOMY-KO.md docs/VERIFICATION-EVIDENCE.md \
  tools/generate-assurance-coverage.js tools/test-hook-compiler.js \
  tools/test-assurance-coverage.js tools/test-evidence-contract.js tools/test-assurance-recipes.sh tools/test-extension-trust.js \
  tools/test-plugin-packager.js tools/test-skill-proposals.js \
  tools/test-installer-platform.js tools/test-windows-installer.js \
  tools/test-work-contract.js tools/test-workspace-contract.js; do
  git ls-files --error-unmatch "$required_tracked_file" >/dev/null 2>&1 || {
    echo "release-required runtime file is not tracked by Git: $required_tracked_file" >&2
    exit 1
  }
done
bash tools/check-stale-tokens.sh
bash tools/check-adapter-metadata.sh
node tools/generate-adapter-docs.js --check
bash tools/check-framework-purity.sh
git diff --check
for file in adapters/{claude,cursor,copilot,gemini,codex,windsurf}/transform.sh \
  tools/{test-install-modes,test-multitool-runtime,test-npm-upgrade,test-assurance-recipes,live-verify}.sh \
  tools/{test-output-cap,test-doc-path-policy,manifest-safety,validate-adapter-output,check-adapter-metadata,release-verify-local}.sh \
  core/hooks/*.sh.template; do
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
for file in bin/{omniconductor,doctor,model-routing,path-safety,adapter-dispatch,installer-platform,claude-hookify,runtime-contract,portable-skills,hook-config}.js \
  bin/{assurance-coverage,evidence-contract,extension-trust,plugin-packager,skill-proposals,work-contract,workspace-contract}.js \
  tools/{test-model-routing,test-path-safety,test-installer-platform,test-windows-installer,test-hookify-posttool,test-runtime-contract,test-portable-skills,test-hook-compiler,test-release-version,check-release-version}.js \
  tools/{generate-assurance-coverage,test-assurance-coverage,test-evidence-contract,test-extension-trust,test-plugin-packager,test-skill-proposals,test-work-contract,test-workspace-contract}.js; do
  node --check "$file"
done

echo "[release] pack exact npm candidate"
PACK_OUTPUT="$(npm_config_cache="$CACHE" npm pack --pack-destination "$ARTIFACT_DIR")"
PACKAGE_NAME="$(printf '%s\n' "$PACK_OUTPUT" | /usr/bin/tail -n 1)"
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
  PREVIOUS_OUTPUT="$(npm_config_cache="$CACHE" npm pack "omniconductor@$PREVIOUS_VERSION" \
    --pack-destination "$PREVIOUS_DIR" --fetch-retries=1 \
    --fetch-retry-mintimeout=1000 --fetch-retry-maxtimeout=3000 \
    --fetch-timeout=10000)"
  PREVIOUS_NAME="$(printf '%s\n' "$PREVIOUS_OUTPUT" | /usr/bin/tail -n 1)"
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
