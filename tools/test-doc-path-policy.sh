#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

primary_surface() {
  case "$1" in
    claude) echo "CLAUDE.md" ;;
    cursor) echo ".cursor/rules/workflow.mdc" ;;
    copilot) echo ".github/copilot-instructions.md" ;;
    gemini) echo "GEMINI.md" ;;
    codex) echo "AGENTS.md" ;;
    windsurf) echo ".windsurfrules" ;;
    opencode) echo ".opencode/rules/workflow.md" ;;
  esac
}

for adapter in claude cursor copilot gemini codex windsurf opencode; do
  target="$TMP/$adapter"
  mkdir -p "$target"
  node "$ROOT/bin/omniconductor.js" init --target="$adapter" "$target" \
    --no-prompt --accept-model-defaults >/dev/null

  for rel in docs/plans/README.md docs/architecture/README.md docs/research/README.md; do
    [ -s "$target/$rel" ] || fail "$adapter did not emit $rel"
  done
  grep -qF 'docs/plans/YYYY-MM-DD-<topic>.md' "$target/docs/INDEX.md" \
    || fail "$adapter INDEX lacks the implementation-plan default"
  grep -qF 'Existing files or plugin-created' "$target/docs/INDEX.md" \
    || fail "$adapter INDEX lacks the precedence rule"

  primary="$(primary_surface "$adapter")"
  grep -qF 'docs/plans/YYYY-MM-DD-<topic>.md' "$target/$primary" \
    || fail "$adapter primary instruction surface lacks the canonical plan path"
  grep -Eq 'not (a )?policy' "$target/$primary" \
    || fail "$adapter primary instruction surface lacks the legacy-precedent rule"

  bash "$ROOT/tools/validate-adapter-output.sh" "$target" "$adapter" >/dev/null \
    || fail "$adapter validator rejected canonical docs"
done

# A pre-ADR-052 adopter INDEX is preserved on upgrade. The validator must make
# that visible without failing an otherwise safe, lossless upgrade; fresh
# installs above still fail closed on the exact current template contract.
upgrade_like="$TMP/upgrade-like"
/bin/cp -R "$TMP/claude" "$upgrade_like"
printf '# Existing adopter index\n' > "$upgrade_like/docs/INDEX.md"
bash "$ROOT/tools/validate-adapter-output.sh" "$upgrade_like" claude \
  > "$TMP/upgrade-like-validator.txt" \
  || fail "validator rejected a preserved pre-ADR-052 adopter INDEX"
grep -qF 'WARN  docs/INDEX.md' "$TMP/upgrade-like-validator.txt" \
  || fail "validator hid preserved INDEX drift during upgrade"

# Existing adopter conflict: warn while preserving files. An explicit INDEX
# declaration converts the same path from accidental precedent to project policy.
legacy="$TMP/claude"
mkdir -p "$legacy/docs/superpowers/plans"
printf '# Legacy plan\n' > "$legacy/docs/superpowers/plans/old.md"
node "$ROOT/bin/omniconductor.js" doctor "$legacy" --json > "$TMP/doctor-legacy.json" || true
node -e '
  const r=require(process.argv[1]);
  if(!r.checks.some(x=>x.id==="D12" && x.status==="WARN" && x.detail.includes("docs/superpowers/plans"))) process.exit(1)
' "$TMP/doctor-legacy.json" || fail "doctor did not warn on an undeclared legacy plan root"

printf '\n| Legacy implementation-plan override | `docs/superpowers/plans/` |\n' \
  >> "$legacy/docs/INDEX.md"
node "$ROOT/bin/omniconductor.js" doctor "$legacy" --json > "$TMP/doctor-override.json" || true
node -e '
  const r=require(process.argv[1]);
  if(r.checks.some(x=>x.id==="D12" && x.status==="WARN" && x.detail.includes("docs/superpowers/plans"))) process.exit(1)
' "$TMP/doctor-override.json" || fail "doctor ignored the explicit docs/INDEX.md override"

# The stock `docs/plans/` and `docs/specs/` rows must not accidentally declare
# the unrelated top-level `plans/` and `specs/` legacy roots.
root_legacy="$TMP/codex"
mkdir -p "$root_legacy/plans" "$root_legacy/specs"
printf '# Legacy root plan\n' > "$root_legacy/plans/roadmap.md"
printf '# Legacy root spec\n' > "$root_legacy/specs/domain.md"
node "$ROOT/bin/omniconductor.js" doctor "$root_legacy" --json \
  > "$TMP/doctor-root-legacy.json" || true
node -e '
  const r=require(process.argv[1]);
  const warning=r.checks.find(x=>x.id==="D12" && x.status==="WARN");
  if(!warning || !warning.detail.includes("plans") || !warning.detail.includes("specs")) process.exit(1)
' "$TMP/doctor-root-legacy.json" \
  || fail "doctor let stock docs/plans or docs/specs rows hide top-level legacy roots"

printf '\n| Legacy plan override | `plans/` |\n| Legacy spec override | `specs/` |\n' \
  >> "$root_legacy/docs/INDEX.md"
node "$ROOT/bin/omniconductor.js" doctor "$root_legacy" --json \
  > "$TMP/doctor-root-override.json" || true
node -e '
  const r=require(process.argv[1]);
  if(r.checks.some(x=>x.id==="D12" && x.status==="WARN"
    && (x.detail.includes("plans") || x.detail.includes("specs")))) process.exit(1)
' "$TMP/doctor-root-override.json" \
  || fail "doctor ignored exact top-level plans/specs override declarations"

# The policy must remain scoped to recognized CONDUCTOR artifact classes.
grep -qF 'not a ban on other documentation' "$ROOT/core/universal-rules/workflow.md" \
  || fail "workflow lost the ordinary-document allowance"

echo "PASS: canonical document paths across all seven adapters"
echo "PASS: preserved pre-ADR-052 INDEX is a visible non-failing upgrade warning"
echo "PASS: doctor distinguishes accidental precedent from explicit override"
echo "PASS: stock docs/* paths cannot mask top-level plans/specs legacy roots"
