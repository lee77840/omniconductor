#!/usr/bin/env bash
# CONDUCTOR adapter-metadata consistency check (ADR-040).
# Exit 0 = consistent, 1 = drift/inconsistency found, 2 = checker error.
#
# adapters/<tool>/metadata.json is the SINGLE SOURCE for enumerable adapter facts
# (output paths, legacy paths, tier, capabilities, live-verification, headless CLI).
# This checker asserts the places that state those facts agree with it:
#
#   M1: metadata.json exists for all 6 adapters, is valid JSON, has required keys —
#       including NON-EMPTY nested fields (tier, live_verification.status,
#       headless_cli.command, at least one output with a path)
#   M2: every outputs[].path literal appears in adapters/<tool>/transform.sh
#   M3: every outputs[].path with "validated": true appears in tools/validate-adapter-output.sh
#   M4: every reflector_outputs[].path literal appears in adapters/<tool>/transform.sh
#   M5: every legacy_paths[] literal is at least MENTIONED in transform.sh or the
#       validator (legacy awareness in code/comments — a substring check, not proof of
#       functional migration handling)
#   M6: live_verification.status == "verified" requires a date, and that date must
#       appear on a line of docs/ADAPTER-LIVE-VERIFICATION.md that names the tool
#       (fixed-string matching; single-sourced verification claims)
#   M7: headless_cli.command is in the `for c in ...` auto-detect list of
#       core/reflector/run-weekly.sh (word match on that line — comments don't count)
#   M8: tier — the COMPATIBILITY-MATRIX tier-assignment TABLE ROW (a line starting
#       with '| **<tier> — ') must name the adapter's display_name
#   M9: install.ala_carte strategy matches the code — "block" iff transform.sh
#       contains the conductor:block marker machinery (ADR-044)
#
# Dependency: node (already required by the CLI + CI). No jq.

set -u

cd "$(dirname "$0")/.." || exit 2

command -v node >/dev/null 2>&1 || { echo "ERROR: node is required" >&2; exit 2; }

TOOLS="claude cursor copilot gemini codex windsurf"
VALIDATOR="tools/validate-adapter-output.sh"
LIVE_DOC="docs/ADAPTER-LIVE-VERIFICATION.md"
MATRIX_DOC="docs/COMPATIBILITY-MATRIX.md"
RUNNER="core/reflector/run-weekly.sh"

FAIL=0
fail() { echo "FAIL[$1] $2"; FAIL=1; }
ok()   { echo "OK  [$1] $2"; }

# Flatten metadata.json to TSV lines via node (validates nested completeness):
#   OUTPUT<TAB>path<TAB>validated
#   REFLECTOR<TAB>path
#   LEGACY<TAB>path
#   FIELD<TAB>key<TAB>value
flatten_metadata() {
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const die = (msg) => { console.error("INCOMPLETE: " + msg); process.exit(3); };
    const req = ["tool","display_name","tier","outputs","reflector_outputs","legacy_paths","capabilities","live_verification","headless_cli"];
    for (const k of req) if (!(k in m)) die("missing key " + k);
    const nonEmpty = (v, name) => { if (typeof v !== "string" || !v.trim()) die(name + " must be a non-empty string"); };
    nonEmpty(m.tool, "tool"); nonEmpty(m.display_name, "display_name"); nonEmpty(m.tier, "tier");
    if (!Array.isArray(m.outputs) || m.outputs.length === 0) die("outputs must be a non-empty array");
    for (const o of m.outputs) nonEmpty(o.path, "outputs[].path");
    if (!Array.isArray(m.reflector_outputs)) die("reflector_outputs must be an array");
    for (const r of m.reflector_outputs) nonEmpty(r.path, "reflector_outputs[].path");
    if (!Array.isArray(m.legacy_paths)) die("legacy_paths must be an array");
    for (const l of m.legacy_paths) nonEmpty(l, "legacy_paths[]");
    if (!m.capabilities || !m.capabilities.tool_native || !m.capabilities.conductor_emitted) die("capabilities needs tool_native + conductor_emitted");
    if (!m.live_verification) die("live_verification missing");
    nonEmpty(m.live_verification.status, "live_verification.status");
    if (m.live_verification.status === "verified") nonEmpty(m.live_verification.date, "live_verification.date (required when verified)");
    if (!m.headless_cli) die("headless_cli missing");
    nonEmpty(m.headless_cli.command, "headless_cli.command");
    if (!m.install || (m.install.ala_carte !== "block" && m.install.ala_carte !== "per-file")) die("install.ala_carte must be block|per-file");
    for (const o of m.outputs) console.log(["OUTPUT", o.path, o.validated ? "true" : "false"].join("\t"));
    for (const r of m.reflector_outputs) console.log(["REFLECTOR", r.path].join("\t"));
    for (const l of m.legacy_paths) console.log(["LEGACY", l].join("\t"));
    console.log(["FIELD","tool",m.tool].join("\t"));
    console.log(["FIELD","display_name",m.display_name].join("\t"));
    console.log(["FIELD","tier",m.tier].join("\t"));
    console.log(["FIELD","live_status",m.live_verification.status].join("\t"));
    console.log(["FIELD","live_date",m.live_verification.date || ""].join("\t"));
    console.log(["FIELD","headless_command",m.headless_cli.command].join("\t"));
    console.log(["FIELD","ala_carte",m.install.ala_carte].join("\t"));
  ' "$1"
}

for tool in $TOOLS; do
  meta="adapters/$tool/metadata.json"
  transform="adapters/$tool/transform.sh"

  # M1 — exists + valid JSON + required keys + non-empty nested fields
  if [ ! -f "$meta" ]; then
    fail "M1" "$meta missing"
    continue
  fi
  if ! flat="$(flatten_metadata "$meta" 2>&1)"; then
    fail "M1" "$meta invalid or incomplete: $(printf '%s' "$flat" | head -1)"
    continue
  fi
  ok "M1" "$meta valid + complete"

  tier="";     display=""
  live_status=""; live_date=""; headless=""; ala_carte=""
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      OUTPUT)
        # M2 — path literal present in transform.sh
        if grep -qF -- "$a" "$transform"; then
          ok "M2" "$tool: transform.sh mentions '$a'"
        else
          fail "M2" "$tool: outputs path '$a' NOT found in $transform (metadata drift?)"
        fi
        # M3 — validated paths must be known to the validator
        if [ "$b" = "true" ]; then
          if grep -qF -- "$a" "$VALIDATOR"; then
            ok "M3" "$tool: validator covers '$a'"
          else
            fail "M3" "$tool: validated path '$a' NOT found in $VALIDATOR"
          fi
        fi
        ;;
      REFLECTOR)
        # M4 — reflector path literal present in transform.sh
        if grep -qF -- "$a" "$transform"; then
          ok "M4" "$tool: transform.sh mentions reflector path '$a'"
        else
          fail "M4" "$tool: reflector path '$a' NOT found in $transform"
        fi
        ;;
      LEGACY)
        # M5 — legacy path at least mentioned in code (awareness, not proof of handling)
        if grep -qF -- "$a" "$transform" || grep -qF -- "$a" "$VALIDATOR"; then
          ok "M5" "$tool: legacy path '$a' mentioned in code"
        else
          fail "M5" "$tool: legacy path '$a' not mentioned in $transform or $VALIDATOR"
        fi
        ;;
      FIELD)
        case "$a" in
          tier) tier="$b" ;;
          display_name) display="$b" ;;
          live_status) live_status="$b" ;;
          live_date) live_date="$b" ;;
          headless_command) headless="$b" ;;
          ala_carte) ala_carte="$b" ;;
          tool)
            [ "$b" = "$tool" ] || fail "M1" "$meta: tool field '$b' != directory '$tool'"
            ;;
        esac
        ;;
    esac
  done <<< "$flat"

  # M6 — verified => dated + the date co-appears with the tool name in the live doc
  # (fixed-string greps; no user data interpolated into a regex)
  if [ "$live_status" = "verified" ]; then
    if [ -z "$live_date" ]; then
      fail "M6" "$tool: live_verification.status=verified but date is empty"
    elif { grep -iF -- "$display" "$LIVE_DOC"; grep -iF -- "$tool" "$LIVE_DOC"; } | grep -qF -- "$live_date"; then
      ok "M6" "$tool: live verification date $live_date matches $LIVE_DOC"
    else
      fail "M6" "$tool: verified date '$live_date' not found next to '$display' in $LIVE_DOC"
    fi
  else
    ok "M6" "$tool: live status '$live_status' (no date assertion)"
  fi

  # M7 — headless CLI must be a word in the runner's `for c in ...` auto-detect list
  # (strict: comments/usage text do NOT count; strip the trailing `; do`)
  detect_line="$(grep -E 'for c in ' "$RUNNER" | head -1 | sed 's/;.*$//')"
  if [ -z "$detect_line" ]; then
    fail "M7" "no 'for c in' auto-detect line found in $RUNNER"
  elif printf '%s\n' "$detect_line" | grep -qE "(^| )${headless}( |\$)"; then
    ok "M7" "$tool: headless CLI '$headless' in $RUNNER auto-detect list"
  else
    fail "M7" "$tool: headless CLI '$headless' NOT in $RUNNER auto-detect list: $detect_line"
  fi

  # M9 — à-la-carte strategy matches the code (block ⇔ marker machinery present)
  if [ "$ala_carte" = "block" ]; then
    if grep -qF 'conductor:block' "$transform"; then
      ok "M9" "$tool: ala_carte=block matches conductor:block machinery in transform.sh"
    else
      fail "M9" "$tool: metadata says ala_carte=block but $transform has no conductor:block machinery"
    fi
  else
    if grep -qF 'conductor:block' "$transform"; then
      fail "M9" "$tool: metadata says ala_carte=per-file but $transform contains conductor:block machinery"
    else
      ok "M9" "$tool: ala_carte=per-file (no block machinery, as declared)"
    fi
  fi

  # M8 — the tier-assignment TABLE ROW must name this adapter
  tier_row="$(grep -E "^\| \*\*${tier} — " "$MATRIX_DOC" | head -1)"
  if [ -z "$tier_row" ]; then
    fail "M8" "$tool: no tier table row '| **${tier} — ' in $MATRIX_DOC"
  elif printf '%s' "$tier_row" | grep -qF -- "$display"; then
    ok "M8" "$tool: matrix tier row ${tier} names ${display}"
  else
    fail "M8" "$tool: matrix tier row ${tier} does not name '${display}': $tier_row"
  fi
done

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK — adapter metadata is consistent with transform.sh / validator / live-verification doc / matrix."
  exit 0
fi
echo "FAIL — adapter metadata inconsistency. metadata.json is the single source (ADR-040):"
echo "fix the code/doc to match it, or update metadata.json if reality changed."
exit 1
