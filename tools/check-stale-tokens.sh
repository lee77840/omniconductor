#!/usr/bin/env bash
# CONDUCTOR stale-token + version-stamp check (ADR-039).
# Exit 0 = clean, 1 = stale claim or stamp drift found, 2 = checker error.
#
# Two check classes:
#   A. Version stamps — mechanizes the R7 release checklist items that drifted twice:
#      A1: README.md has EXACTLY ONE status line, and it stamps the CURRENT
#          package.json version (policy: re-stamped on EVERY release, patches
#          included — ADR-039).
#      A2: CHANGELOG.md has a section for the current version.
#   B. Stale-claim tokens — known-false claims (data-driven from tools/stale-tokens.txt).
#      A line matching a token fails UNLESS its CONTENT (not its file path) matches the
#      token's allow_regex (legacy/historical qualifiers) or carries an inline waiver
#      `stale-ok: <why>`.
#
# Scanned paths (living public surface — what an adopter reads as CURRENT truth):
#   README.md / VISION.md / ROADMAP.md
#   docs/*.md            (top level only)
#   core/                (all rule/template text)
#   adapters/            (READMEs, specs, transform.sh emitted text, templates)
#
# Excluded (frozen history / private / machine data / self):
#   CHANGELOG.md, docs/DESIGN-DECISIONS.md (ADRs), docs/audits|plans|specs|data/,
#   docs/KPI.md, docs/GO-TO-MARKET.md, docs/LAUNCH-*.md, docs/CONDUCTOR-V0.2-DESIGN.md,
#   CLAUDE.md / CURRENT_WORK.md / SESSION_HANDOFF.md (private session docs),
#   adapters/*/metadata.json (machine data — its legacy_paths MUST name legacy tokens;
#   checked by tools/check-adapter-metadata.sh instead), archive/, tools/ (this checker
#   + its data file), scripts/, phase-2/ (frozen scaffold).
#
# See docs/DESIGN-DECISIONS.md ADR-026 (frozen-history carve-outs) + ADR-039 (this policy).

set -u

cd "$(dirname "$0")/.." || exit 2

TOKENS_FILE="tools/stale-tokens.txt"
[ -f "$TOKENS_FILE" ] || { echo "ERROR: $TOKENS_FILE not found" >&2; exit 2; }

FAIL=0

# --------------------------------------------------------------------------
# Class A — version stamps
# --------------------------------------------------------------------------
PKG_VERSION="$(sed -n -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' package.json 2>/dev/null | head -n 1)"
if [ -z "$PKG_VERSION" ]; then
  echo "ERROR: cannot read version from package.json" >&2
  exit 2
fi

STATUS_LINES="$(grep -cE '^> \*\*Status' README.md || true)"
if [ "$STATUS_LINES" -ne 1 ]; then
  echo "FAIL[A1] README.md must have exactly ONE '> **Status' line (found ${STATUS_LINES}) — a leftover stamp from a previous release is itself drift (ADR-039)"
  grep -nE '^> \*\*Status' README.md | head -4
  FAIL=1
elif grep -E '^> \*\*Status' README.md | grep -qF "v${PKG_VERSION}"; then
  echo "OK  [A1] README.md status line stamps v${PKG_VERSION}"
else
  echo "FAIL[A1] README.md status line does not stamp v${PKG_VERSION} (package.json is the single source; re-stamp on EVERY release, patches included — ADR-039)"
  grep -nE '^> \*\*Status' README.md | head -2
  FAIL=1
fi

if grep -qF "## [${PKG_VERSION}]" CHANGELOG.md; then
  echo "OK  [A2] CHANGELOG.md has a [${PKG_VERSION}] section"
else
  echo "FAIL[A2] CHANGELOG.md has no section for [${PKG_VERSION}] (R7 checklist: [Unreleased] -> [${PKG_VERSION}] — <date>)"
  FAIL=1
fi

# A3 (advisory, never fails the check): npm registry lag. The docs say "published to
# npm"; if the registry is behind package.json, `npm publish` is the missing R7 step.
# Skipped silently when npm/network is unavailable (CI-safe).
if command -v npm >/dev/null 2>&1; then
  REG_VERSION="$(npm view omniconductor version 2>/dev/null || true)"
  if [ -n "$REG_VERSION" ] && [ "$REG_VERSION" != "$PKG_VERSION" ]; then
    echo "WARN[A3] npm registry serves omniconductor@${REG_VERSION} but package.json is ${PKG_VERSION} — run \`npm publish\` (advisory only)"
  fi
fi

# --------------------------------------------------------------------------
# Class B — stale-claim tokens
# --------------------------------------------------------------------------
# Build the scan file list.
SCAN_FILES=()
for f in README.md VISION.md ROADMAP.md; do
  [ -f "$f" ] && SCAN_FILES+=("$f")
done
while IFS= read -r f; do
  case "$(basename "$f")" in
    DESIGN-DECISIONS.md|KPI.md|GO-TO-MARKET.md|CONDUCTOR-V0.2-DESIGN.md|LAUNCH-*.md) continue ;;
  esac
  SCAN_FILES+=("$f")
done < <(find docs -maxdepth 1 -type f -name '*.md' | sort)
while IFS= read -r f; do
  SCAN_FILES+=("$f")
done < <(find core adapters -type f \( -name '*.md' -o -name '*.sh' -o -name '*.template' -o -name '*.json' \) ! -name 'metadata.json' | sort)

TOTAL_HITS=0
while IFS=$'\t' read -r pattern reason hint allow_regex || [ -n "${pattern:-}" ]; do
  # Strip CR from every field (CRLF-saved data file must not corrupt the last column).
  pattern="${pattern%$'\r'}"; reason="${reason-}"; hint="${hint-}"; allow_regex="${allow_regex-}"
  reason="${reason%$'\r'}"; hint="${hint%$'\r'}"; allow_regex="${allow_regex%$'\r'}"
  case "$pattern" in ''|'#'*) continue ;; esac
  matches="$(grep -FIn -- "$pattern" "${SCAN_FILES[@]}" 2>/dev/null | grep -v 'stale-ok:' || true)"
  if [ -n "$matches" ] && [ -n "$allow_regex" ]; then
    # Apply allow_regex to the line CONTENT only — never to the "file:line:" prefix,
    # so a file path containing e.g. "legacy" cannot waive hits inside it.
    matches="$(printf '%s\n' "$matches" | grep -Ev -- "^[^:]*:[0-9]+:.*(${allow_regex})" || true)"
  fi
  if [ -n "$matches" ]; then
    count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
    echo "FAIL[B]  stale claim '$pattern' — $count line(s)"
    echo "         why stale : $reason"
    echo "         fix       : $hint"
    printf '%s\n' "$matches" | head -8 | sed 's/^/         /'
    echo
    FAIL=1
    TOTAL_HITS=$((TOTAL_HITS + count))
  fi
done < "$TOKENS_FILE"

if [ "$FAIL" -eq 0 ]; then
  echo "OK — no stale claims on living surfaces; version stamps consistent (v${PKG_VERSION})."
  exit 0
fi

echo "FAIL — stale-token check found problems (stale lines: ${TOTAL_HITS})."
echo "Fix the claim, add a legacy qualifier matching the token's allow_regex,"
echo "or (rarely) add an inline 'stale-ok: <why>' waiver. Policy: ADR-039."
exit 1
