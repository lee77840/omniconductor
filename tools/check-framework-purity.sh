#!/usr/bin/env bash
# Conductor framework purity check — ban reference-adopter-specific tokens in framework body.
# Exit 0 = clean, 1 = leak detected.
#
# Scanned paths (framework body — adopters read these and must not see specifics):
#   core/                                      — universal rules / recipes / templates
#   adapters/<tool>/hookify-templates/         — runtime hook templates
#   docs/MANUAL-INSTALL.md                     — install guide
#   README.md                                  — top-level intro
#   phase-2/                                   — VSCode extension scaffolding
#
# Excluded (frozen history — intentional named references OK):
#   docs/DESIGN-DECISIONS.md                   — ADR archive
#   docs/audits/                               — competitive analyses (snapshots)
#   docs/CONDUCTOR-V0.2-DESIGN.md              — P0.5 design history
#   docs/KPI.md                                — P1.5 baseline measurement
#   CURRENT_WORK.md / SESSION_HANDOFF.md       — session continuity
#   LICENSE / NOTICE                           — legal attribution
#   adapters/*/transform.sh                    — adapter logic (functional defaults, with adopter-customization comments)
#   archive/                                   — frozen v0.1
#
# See docs/DESIGN-DECISIONS.md ADR-026 for the policy rationale.

set -u

# Banned tokens — reference-adopter-specific names that must not appear in framework body.
# Vendor names in legitimate framework context (e.g., "Anthropic" in PROMPT-CACHING-GUIDE)
# are kept by excluding the prompt-caching guide from the scan paths above.
BANNED=(
  "Mile Mind"
  "milemind"
  "getmilemind"
  "apps/web"
  "apps/mobile"
  "Stripe"
  "Plaid"
  "Resend"
  "Supabase"
  "Vercel"
  "Sentry"
  "Postmark"
  "sodam"
  "sangyoublee"
  "milemind.lfamily"
)

# Scan paths — framework body only.
SCAN_PATHS=(
  "core"
  "adapters/claude/hookify-templates"
  "adapters/copilot/hookify-templates"
  "adapters/cursor/hookify-templates"
  "docs/MANUAL-INSTALL.md"
  "README.md"
  "phase-2"
)

cd "$(dirname "$0")/.." || exit 2

LEAK_FOUND=0
TOTAL_LEAKS=0

for term in "${BANNED[@]}"; do
  for path in "${SCAN_PATHS[@]}"; do
    [ -e "$path" ] || continue
    # -F = fixed string, -n = line numbers, -R = recursive, -I = skip binary
    matches=$(grep -FRIn -- "$term" "$path" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
      echo "LEAK: '$term' in $path ($count line(s))"
      printf '%s\n' "$matches" | head -5
      echo
      LEAK_FOUND=1
      TOTAL_LEAKS=$((TOTAL_LEAKS + count))
    fi
  done
done

if [ "$LEAK_FOUND" -eq 0 ]; then
  echo "OK — framework body is consumer-agnostic. No reference-adopter specifics detected."
  exit 0
fi

echo "FAIL — $TOTAL_LEAKS total leak line(s) found."
echo "Policy: docs/DESIGN-DECISIONS.md ADR-026."
exit 1
