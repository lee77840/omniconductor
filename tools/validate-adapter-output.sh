#!/usr/bin/env bash
#
# CONDUCTOR — Adapter output format validator
#
# Validates that adapter-produced files conform to per-IDE expected formats.
# Used as a pre-flight check after running an adapter, or in CI/smoke tests.
#
# Usage:
#   bash tools/validate-adapter-output.sh <target-dir> <adapter>
#
# Adapters: cursor | copilot | claude | gemini | codex | windsurf
#
# Exit codes:
#   0  no structural failures (adopter-disabled optional rules may WARN)
#   1  one or more files FAIL
#   2  invocation error (bad args / missing dir)
#
# Implementation: pure bash + grep/sed/awk. No jq / yq.
#
# What gets checked (per adapter):
#   cursor:
#     - .cursor/rules/*.mdc exist
#     - frontmatter delimited by ^---$ (open + close)
#     - description: <string> field present
#     - globs: array OR string present
#     - alwaysApply: true|false (optional but if present must be bool)
#     - body has at least one markdown heading (^#)
#     - code fences ``` balanced (even count)
#
#   copilot:
#     - .github/copilot-instructions.md exists (top-level bundle); markdown body sane
#     - if .github/instructions/*.instructions.md exist:
#         - frontmatter present
#         - applyTo: <CSV string in quotes> (NOT a YAML array)
#         - body sane
#
#   claude:
#     - .claude/rules/*.md exist
#     - frontmatter has paths: array
#     - body sane
#
#   gemini:
#     - GEMINI.md exists, non-empty
#     - all 5 universal-rule sections present (distinctive markers)
#     - no unsubstituted ${...} template placeholders (outside code fences)
#     - no reference-product leakage (tokens from .purity-banned-private; private repo only)
#     - if .gemini/styleguide.md exists, it must be non-empty
#
#   codex:
#     - AGENTS.md exists, non-empty
#     - compact kernel stays within the project-instruction byte budget
#     - all 5 complete universal-rule references are present
#     - no unsubstituted ${...} placeholders (outside code fences)
#     - no reference-product leakage
#
#   windsurf:
#     - .windsurfrules exists, non-empty
#     - .devin/rules/ (or legacy .windsurf/rules/) contains the 5 universal rule files
#       (meta-discipline/operations/quality-gates/spec-as-you-go/workflow)
#     - no unsubstituted ${...} placeholders (outside code fences)
#     - no reference-product leakage
#
# ---------------------------------------------------------------------------

set -eu

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="${1:-}"
ADAPTER="${2:-}"

if [ -z "$TARGET" ] || [ -z "$ADAPTER" ]; then
  echo "Usage: $0 <target-dir> <adapter:cursor|copilot|claude|gemini|codex|windsurf>" >&2
  exit 2
fi

if [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir does not exist: $TARGET" >&2
  exit 2
fi

case "$ADAPTER" in
  cursor|copilot|claude|gemini|codex|windsurf) ;;
  *) echo "ERROR: unknown adapter '$ADAPTER'. Use cursor|copilot|claude|gemini|codex|windsurf." >&2; exit 2 ;;
esac

PASS=0
WARN=0
FAIL=0
FAILED_FILES=""

emit_pass() {
  printf "  PASS  %s\n" "$1"
  PASS=$((PASS + 1))
}

emit_fail() {
  printf "  FAIL  %s :: %s\n" "$1" "$2"
  FAIL=$((FAIL + 1))
  FAILED_FILES="$FAILED_FILES\n  $1 — $2"
}

emit_warn() {
  printf "  WARN  %s :: %s\n" "$1" "$2"
  WARN=$((WARN + 1))
}

# ---- shared helpers ------------------------------------------------------

# Returns line number of opening "---" frontmatter delimiter (1 if present at line 1, 0 if absent).
fm_open_line() {
  awk 'NR==1 && /^---$/ { print 1; exit } NR>=2 { print 0; exit }' "$1"
}

# Returns line number of closing "---" delimiter (must be > 1).
fm_close_line() {
  awk 'NR>1 && /^---$/ { print NR; exit }' "$1"
}

# Sanity check on the markdown body (after frontmatter close).
# Returns "OK" or a reason string.
body_sanity() {
  local file="$1"
  local body_start="$2"

  # Must have at least one heading (# or ##) somewhere in body.
  local heading_count
  heading_count=$(awk -v s="$body_start" 'NR>s && /^#/ { c++ } END { print c+0 }' "$file")
  if [ "$heading_count" -lt 1 ]; then
    echo "no_markdown_heading"
    return
  fi

  # Code fence balance: count occurrences of ^``` (start of line).
  local fence_count
  fence_count=$(awk -v s="$body_start" 'NR>s && /^```/ { c++ } END { print c+0 }' "$file")
  if [ $((fence_count % 2)) -ne 0 ]; then
    echo "unbalanced_code_fences (count=$fence_count)"
    return
  fi

  echo "OK"
}

# Extract a single-line frontmatter field value (between ":" and EOL).
# Usage: fm_field <file> <field-name>  → value or empty
fm_field() {
  awk -v key="$2" '
    BEGIN { in_fm=0 }
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm {
      idx = index($0, ":")
      if (idx > 0) {
        k = substr($0, 1, idx-1)
        v = substr($0, idx+1)
        sub(/^[ \t]+/, "", k)
        sub(/[ \t]+$/, "", k)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        if (k == key) { print v; exit }
      }
    }
  ' "$1"
}

# Detect if a frontmatter field value indicates a YAML array literal: starts with "[".
# Or block array (multiline) — caller decides.
is_inline_array() {
  case "$1" in
    \[*\]) return 0 ;;
    *) return 1 ;;
  esac
}

# Check whether a frontmatter has `paths:` followed by indented `- ` lines (block array).
fm_block_array_present() {
  awk -v key="$2" '
    BEGIN { in_fm=0; in_key=0 }
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm && $0 ~ "^"key":" { in_key=1; next }
    in_fm && in_key && /^[ \t]+-[ \t]/ { print "yes"; exit }
    in_fm && in_key && /^[^ \t]/ { in_key=0 }
  ' "$1"
}

# Returns non-empty if file is missing OR empty (zero / whitespace-only bytes).
file_empty() {
  [ ! -s "$1" ] && { echo "empty"; return; }
  # -s catches zero-byte. Also treat whitespace-only as empty.
  if ! grep -q '[^[:space:]]' "$1"; then echo "empty"; fi
}

validate_role_set() {
  local adapter="$1" dir suffix="" role file missing=0
  case "$adapter" in
    claude) dir="$TARGET/.claude/agents"; suffix=".md" ;;
    cursor) dir="$TARGET/.cursor/agents"; suffix=".md" ;;
    copilot) dir="$TARGET/.github/agents"; suffix=".agent.md" ;;
    gemini) dir="$TARGET/.gemini/agents"; suffix=".md" ;;
    codex) dir="$TARGET/.codex/agents"; suffix=".toml" ;;
    windsurf) dir="$TARGET/.windsurf/workflows"; suffix=".md" ;;
  esac
  for role in planner reviewer code-reviewer builder helper designer scribe utility; do
    local expected_tier expected_effort expected_model actual_model
    case "$role" in
      planner|reviewer|code-reviewer|builder) expected_tier=1; expected_effort=high ;;
      helper|designer|scribe) expected_tier=2; expected_effort=medium ;;
      utility) expected_tier=3; expected_effort=low ;;
    esac
    file="$dir/$role$suffix"
    if [ ! -s "$file" ]; then
      emit_fail "${file#"$TARGET/"}" "required native role entry missing or empty"
      missing=$((missing + 1))
      continue
    fi
    expected_model=""
    if [ -f "$TARGET/.conductor/model-routing.json" ]; then
      expected_model="$(node -e '
        try {
          const c=require(process.argv[1]), a=c.adapters[process.argv[2]], t=process.argv[3];
          if(a&&a.tiers&&a.tiers[t]) process.stdout.write(a.tiers[t].resolved||"");
        } catch { process.exit(1) }
      ' "$TARGET/.conductor/model-routing.json" "$adapter" "$expected_tier" 2>/dev/null || true)"
    fi
    if [ "$adapter" = "codex" ]; then
      local expected_sandbox="workspace-write"
      case "$role" in planner|reviewer|code-reviewer) expected_sandbox="read-only" ;; esac
      if ! /usr/bin/awk -v role="$role" -v sandbox="$expected_sandbox" -v expected_effort="$expected_effort" '
        BEGIN { state="header"; name=0; desc=0; effort=0; box=0; opened=0; closed=0; bad=0 }
        state=="header" && $0 == "developer_instructions = \"\"\"" { opened++; state="body"; next }
        state=="header" && $0 ~ /^name = "[A-Za-z0-9_-]+"$/ {
          if ($0 == "name = \"" role "\"") name=1; else bad=1; next
        }
        state=="header" && $0 ~ /^description = ".+"$/ { desc=1; next }
        state=="header" && $0 ~ /^model = "[A-Za-z0-9._-]+"$/ { next }
        state=="header" && $0 == "model_reasoning_effort = \"" expected_effort "\"" { effort=1; next }
        state=="header" && $0 ~ /^sandbox_mode = "(read-only|workspace-write)"$/ {
          if ($0 == "sandbox_mode = \"" sandbox "\"") box=1; else bad=1; next
        }
        state=="header" && $0 !~ /^[[:space:]]*$/ { bad=1; next }
        state=="body" && $0 == "\"\"\"" { closed++; state="tail"; next }
        state=="tail" && $0 !~ /^[[:space:]]*$/ { bad=1 }
        END { exit !(name && desc && effort && box && opened==1 && closed==1 && !bad) }
      ' "$file"; then
        emit_fail "${file#"$TARGET/"}" "invalid Codex agent TOML contract or role sandbox"
        missing=$((missing + 1))
      fi
      if [ -n "$expected_model" ] && ! /usr/bin/grep -qF "model = \"$expected_model\"" "$file"; then
        emit_fail "${file#"$TARGET/"}" "model does not match saved Tier $expected_tier translation '$expected_model'"
        missing=$((missing + 1))
      fi
    else
      local fm_open fm_close desc name body_check
      fm_open=$(fm_open_line "$file")
      fm_close=$(fm_close_line "$file")
      desc=$(fm_field "$file" "description")
      name=$(fm_field "$file" "name")
      body_check=""; [ -n "$fm_close" ] && body_check=$(body_sanity "$file" "$fm_close")
      if [ "$fm_open" != "1" ] || [ -z "$fm_close" ] || [ -z "$desc" ] || [ "$body_check" != "OK" ]; then
        emit_fail "${file#"$TARGET/"}" "invalid native role frontmatter or markdown body"
        missing=$((missing + 1))
      elif [ "$adapter" != "windsurf" ] && [ "$name" != "$role" ]; then
        emit_fail "${file#"$TARGET/"}" "frontmatter name '$name' does not match role '$role'"
        missing=$((missing + 1))
      elif [ "$adapter" = "claude" ] && [ -z "$(fm_field "$file" "model")" ]; then
        emit_fail "${file#"$TARGET/"}" "Claude role must declare its Tier-translated model"
        missing=$((missing + 1))
      elif [ "$adapter" = "cursor" ] && [ -z "$(fm_field "$file" "model")" ]; then
        emit_fail "${file#"$TARGET/"}" "Cursor role must declare its saved Tier translation or inherit"
        missing=$((missing + 1))
      elif [ "$adapter" = "gemini" ] && [ -z "$(fm_field "$file" "model")" ]; then
        emit_fail "${file#"$TARGET/"}" "Gemini role must declare inherit or an explicit Tier override"
        missing=$((missing + 1))
      fi
      actual_model="$(fm_field "$file" "model")"
      if [ -n "$expected_model" ] && [ "$adapter" != "windsurf" ] && [ "$actual_model" != "$expected_model" ]; then
        emit_fail "${file#"$TARGET/"}" "model '$actual_model' does not match saved Tier $expected_tier translation '$expected_model'"
        missing=$((missing + 1))
      fi
      if [ "$adapter" = "windsurf" ] && [ -n "$expected_model" ] \
        && ! /usr/bin/grep -qF 'select **Adaptive**' "$file"; then
        emit_fail "${file#"$TARGET/"}" "Windsurf workflow must disclose the saved Adaptive advisory requirement"
        missing=$((missing + 1))
      fi
    fi
    if [ -s "$file" ] && ! /usr/bin/grep -qE "CONDUCTOR difficulty contract:.*Tier ${expected_tier}([^0-9]|$)" "$file"; then
      emit_fail "${file#"$TARGET/"}" "missing or drifted Tier $expected_tier difficulty contract"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ] && emit_pass "native role set ($adapter: 8 roles including Tier 3 utility)"
}

# Universal outputs for a non-Claude adapter must never teach Claude family
# names as if they were portable difficulty labels.
validate_no_claude_model_aliases() {
  local adapter="$1" root file hit=""
  local -a files=()
  shift
  for root in "$@"; do
    [ -e "$root" ] || continue
    if [ -f "$root" ]; then
      files=("$root")
    else
      files=()
      while IFS= read -r file; do files+=("$file"); done \
        < <(find "$root" -type f ! -name '*.conductor-backup-*' -print 2>/dev/null)
    fi
    for file in "${files[@]}"; do
      hit="$(/usr/bin/awk '
        /^[[:space:]]*model[[:space:]]*[:=]/ { next }
        /saved (Cursor|Copilot) translation/ { next }
        tolower($0) ~ /(^|[^a-z])(opus|sonnet|haiku)([^a-z]|$)/ { print FILENAME ":" FNR ":" $0; exit }
      ' "$file" 2>/dev/null || true)"
      [ -z "$hit" ] || break 2
    done
  done
  if [ -n "$hit" ]; then
    emit_fail "$adapter model isolation" "Claude family alias leaked into non-Claude output: $hit"
  else
    emit_pass "$adapter model isolation (no Claude family aliases)"
  fi
}

# Detect unsubstituted ${...} template placeholders OUTSIDE fenced code blocks.
# Legit bash parameter expansions live inside ```...``` fences and are ignored.
# Prints the first offending "line: text" or empty if clean.
unsubstituted_placeholder() {
  awk '
    BEGIN { infence = 0 }
    /^```/ { infence = !infence; next }
    !infence && /\$\{[A-Za-z_][A-Za-z0-9_]*\}/ { print NR": "$0; exit }
  ' "$1"
}

# Detect reference-product leakage. Tokens come from the PRIVATE-only .purity-banned-private
# (not synced to the public mirror / npm); if absent (public repo), this is a no-op.
# Prints the matching line or empty if clean.
leakage_scan() {
  local priv pat
  priv="$(dirname "$0")/../.purity-banned-private"
  [ -f "$priv" ] || return 0
  pat="$(grep -vE '^#|^[[:space:]]*$' "$priv" | paste -sd'|' -)"
  [ -n "$pat" ] || return 0
  grep -nE "$pat" "$1" 2>/dev/null | head -1 || true
}

# Check that a file contains all 5 universal-rule sections by distinctive markers.
# Markers are derived from the rule titles emitted into the bundled GEMINI.md/AGENTS.md.
# Prints the name of the first MISSING section, or empty if all present.
missing_rule_section() {
  local file="$1"
  grep -qE '^#+ +Workflow — Plan-First Order' "$file"               || { echo "workflow"; return; }
  grep -qE '^#+ +Spec-as-you-go — Same-Turn' "$file"                || { echo "spec-as-you-go"; return; }
  grep -qE '^#+ +Quality Gates — Two-Stage Review' "$file"          || { echo "quality-gates"; return; }
  grep -qE '^#+ +Operations — Session Continuity' "$file"           || { echo "operations"; return; }
  grep -qE '^#+ +Meta-Discipline — How CONDUCTOR Stays' "$file"     || { echo "meta-discipline"; return; }
}

# ---- gemini mode ---------------------------------------------------------

run_gemini() {
  local main="$TARGET/GEMINI.md"
  if [ ! -f "$main" ]; then
    emit_fail "GEMINI.md" "file missing"
    return
  fi
  if [ -n "$(file_empty "$main")" ]; then
    emit_fail "GEMINI.md" "file is empty"
    return
  fi

  local miss
  miss=$(missing_rule_section "$main")
  if [ -n "$miss" ]; then
    emit_fail "GEMINI.md" "missing universal-rule section: $miss"
    return
  fi

  local ph
  ph=$(unsubstituted_placeholder "$main")
  if [ -n "$ph" ]; then
    emit_fail "GEMINI.md" "unsubstituted placeholder at $ph"
    return
  fi

  local leak
  leak=$(leakage_scan "$main")
  if [ -n "$leak" ]; then
    emit_fail "GEMINI.md" "reference-product leakage: $leak"
    return
  fi

  emit_pass "GEMINI.md"

  # Optional styleguide — if present must be non-empty.
  local style="$TARGET/.gemini/styleguide.md"
  if [ -f "$style" ]; then
    if [ -n "$(file_empty "$style")" ]; then
      emit_fail ".gemini/styleguide.md" "file is empty"
    else
      local sleak
      sleak=$(leakage_scan "$style")
      if [ -n "$sleak" ]; then
        emit_fail ".gemini/styleguide.md" "reference-product leakage: $sleak"
      else
        emit_pass ".gemini/styleguide.md"
      fi
    fi
  fi
  validate_role_set gemini
  validate_no_claude_model_aliases gemini "$TARGET/GEMINI.md" "$TARGET/.gemini/agents" "$TARGET/.gemini/styleguide.md"
}

# ---- codex mode ----------------------------------------------------------

run_codex() {
  local main="$TARGET/AGENTS.md"
  if [ ! -f "$main" ]; then
    emit_fail "AGENTS.md" "file missing"
    return
  fi
  if [ -n "$(file_empty "$main")" ]; then
    emit_fail "AGENTS.md" "file is empty"
    return
  fi

  local bytes
  bytes=$(wc -c < "$main" | tr -d ' ')
  if [ "$bytes" -gt 24576 ]; then
    emit_fail "AGENTS.md" "kernel is ${bytes} bytes; exceeds the 24576-byte CONDUCTOR safety budget"
    return
  fi

  if ! grep -qF 'CONDUCTOR_KERNEL_END' "$main" \
    || ! grep -q '^## Non-negotiable execution contract' "$main" \
    || ! grep -q '^## Rule loading table' "$main" \
    || ! grep -q '^## Native role routing' "$main"; then
    emit_fail "AGENTS.md" "bounded runtime kernel is incomplete"
    return
  fi

  local ph
  ph=$(unsubstituted_placeholder "$main")
  if [ -n "$ph" ]; then
    emit_fail "AGENTS.md" "unsubstituted placeholder at $ph"
    return
  fi

  local leak
  leak=$(leakage_scan "$main")
  if [ -n "$leak" ]; then
    emit_fail "AGENTS.md" "reference-product leakage: $leak"
    return
  fi

  emit_pass "AGENTS.md (${bytes} bytes; bounded kernel)"

  local refs_ok=true
  local rule ref
  for rule in workflow spec-as-you-go quality-gates operations meta-discipline; do
    ref="$TARGET/.codex/conductor/rules/$rule.md"
    if [ ! -s "$ref" ]; then
      emit_fail ".codex/conductor/rules/$rule.md" "complete universal-rule reference missing"
      refs_ok=false
    fi
  done
  $refs_ok && emit_pass ".codex/conductor/rules/ (5 complete references)"

  validate_role_set codex
  validate_no_claude_model_aliases codex "$TARGET/AGENTS.md" "$TARGET/.codex/conductor" "$TARGET/.codex/agents"
  local hooks="$TARGET/.codex/hooks.json"
  local manifest="$TARGET/.conductor/manifests/codex.json"
  # The installer intentionally preserves a pre-existing user-owned registry.
  # In that case it is absent from the Codex ownership manifest and must not be
  # judged as if CONDUCTOR emitted it. The warning printed during installation
  # remains the activation signal; this validator only certifies owned output.
  if [ -s "$hooks" ] && [ -s "$manifest" ] \
    && ! grep -q '"path"[[:space:]]*:[[:space:]]*"\.codex/hooks\.json"' "$manifest"; then
    emit_pass ".codex/hooks.json (user-owned; preserved and excluded from CONDUCTOR output validation)"
  elif [ ! -s "$hooks" ]; then
    emit_fail ".codex/hooks.json" "native hook registry missing"
  elif grep -q 'permissionDecision[^\n]*ask' "$hooks" || grep -q '\.Codex/' "$hooks"; then
    emit_fail ".codex/hooks.json" "unsupported ask decision or case-drift path"
  elif ! grep -q 'git rev-parse --show-toplevel' "$hooks"; then
    emit_fail ".codex/hooks.json" "hook commands are not anchored to the Git root"
  else
    emit_pass ".codex/hooks.json"
  fi
}

# ---- windsurf mode -------------------------------------------------------

validate_windsurf_file() {
  local file="$1"
  local rel="${file#"$TARGET/"}"

  if [ -n "$(file_empty "$file")" ]; then
    emit_fail "$rel" "file is empty"
    return
  fi
  local ph
  ph=$(unsubstituted_placeholder "$file")
  if [ -n "$ph" ]; then
    emit_fail "$rel" "unsubstituted placeholder at $ph"
    return
  fi
  local leak
  leak=$(leakage_scan "$file")
  if [ -n "$leak" ]; then
    emit_fail "$rel" "reference-product leakage: $leak"
    return
  fi
  emit_pass "$rel"
}

run_windsurf() {
  local top="$TARGET/.windsurfrules"
  if [ ! -f "$top" ]; then
    emit_fail ".windsurfrules" "file missing"
  else
    validate_windsurf_file "$top"
  fi

  # Rules moved to .devin/rules/ (2026 Devin Desktop rebrand); legacy .windsurf/rules/
  # is still read, so accept either — prefer .devin/rules/.
  local rules_dir rules_label
  if [ -d "$TARGET/.devin/rules" ]; then
    rules_dir="$TARGET/.devin/rules"; rules_label=".devin/rules"
  elif [ -d "$TARGET/.windsurf/rules" ]; then
    rules_dir="$TARGET/.windsurf/rules"; rules_label=".windsurf/rules"
  else
    emit_fail ".devin/rules/ (or legacy .windsurf/rules/)" "directory missing"
    return
  fi

  # The 5 required universal rule files must each be present.
  local required="meta-discipline operations quality-gates spec-as-you-go workflow"
  local r
  for r in $required; do
    local rf="$rules_dir/$r.md"
    if [ ! -f "$rf" ]; then
      emit_fail "$rules_label/$r.md" "required universal rule file missing"
    else
      validate_windsurf_file "$rf"
    fi
  done
  validate_role_set windsurf
  validate_no_claude_model_aliases windsurf "$TARGET/.windsurfrules" "$TARGET/.devin/rules" "$TARGET/.windsurf/workflows"
}

# ---- cursor mode ---------------------------------------------------------

validate_cursor_mdc() {
  local file="$1"
  local rel="${file#"$TARGET/"}"

  local fm_open
  fm_open=$(fm_open_line "$file")
  if [ "$fm_open" != "1" ]; then
    emit_fail "$rel" "missing frontmatter open delimiter (---)"
    return
  fi

  local fm_close
  fm_close=$(fm_close_line "$file")
  if [ -z "$fm_close" ]; then
    emit_fail "$rel" "missing frontmatter close delimiter"
    return
  fi

  # description: must exist
  local desc
  desc=$(fm_field "$file" "description")
  if [ -z "$desc" ]; then
    emit_fail "$rel" "frontmatter missing 'description:' field"
    return
  fi

  # globs: must exist (inline array OR block array OR string)
  local globs
  globs=$(fm_field "$file" "globs")
  local globs_block
  globs_block=$(fm_block_array_present "$file" "globs")
  if [ -z "$globs" ] && [ -z "$globs_block" ]; then
    emit_fail "$rel" "frontmatter missing 'globs:' field"
    return
  fi

  # alwaysApply if present must be true|false
  local always
  always=$(fm_field "$file" "alwaysApply")
  if [ -n "$always" ] && [ "$always" != "true" ] && [ "$always" != "false" ]; then
    emit_fail "$rel" "alwaysApply must be true|false (got '$always')"
    return
  fi

  local body_check
  body_check=$(body_sanity "$file" "$fm_close")
  if [ "$body_check" != "OK" ]; then
    emit_fail "$rel" "body: $body_check"
    return
  fi

  emit_pass "$rel"
}

run_cursor() {
  local rules_dir="$TARGET/.cursor/rules"
  if [ ! -d "$rules_dir" ]; then
    emit_fail ".cursor/rules/" "directory missing"
    return
  fi
  local found=0
  for f in "$rules_dir"/*.mdc; do
    [ -e "$f" ] || continue
    found=$((found + 1))
    validate_cursor_mdc "$f"
  done
  if [ "$found" -eq 0 ]; then
    emit_fail ".cursor/rules/" "no .mdc files found"
  fi
  validate_role_set cursor
  validate_no_claude_model_aliases cursor "$TARGET/.cursorrules" "$TARGET/.cursor/rules" "$TARGET/.cursor/agents"
}

# ---- copilot mode --------------------------------------------------------

validate_copilot_top_level() {
  local file="$TARGET/.github/copilot-instructions.md"
  if [ ! -f "$file" ]; then
    # Top-level bundle is optional when using --per-rule mode; downgrade to warning emit_pass-equivalent only if instructions/ exists.
    if [ -d "$TARGET/.github/instructions" ]; then
      printf "  SKIP  .github/copilot-instructions.md (per-rule mode active)\n"
      return
    fi
    emit_fail ".github/copilot-instructions.md" "file missing"
    return
  fi

  # No frontmatter required at top-level; just body sanity from line 0.
  local body_check
  body_check=$(body_sanity "$file" "0")
  if [ "$body_check" != "OK" ]; then
    emit_fail ".github/copilot-instructions.md" "body: $body_check"
    return
  fi
  emit_pass ".github/copilot-instructions.md"
}

validate_copilot_instruction() {
  local file="$1"
  local rel="${file#"$TARGET/"}"

  local fm_open
  fm_open=$(fm_open_line "$file")
  if [ "$fm_open" != "1" ]; then
    emit_fail "$rel" "missing frontmatter open delimiter (---)"
    return
  fi

  local fm_close
  fm_close=$(fm_close_line "$file")
  if [ -z "$fm_close" ]; then
    emit_fail "$rel" "missing frontmatter close delimiter"
    return
  fi

  # applyTo: must be a CSV string (NOT a YAML array) per Copilot spec.
  local apply
  apply=$(fm_field "$file" "applyTo")
  if [ -z "$apply" ]; then
    emit_fail "$rel" "frontmatter missing 'applyTo:' field"
    return
  fi
  # Reject YAML inline array form (Copilot rejects it).
  if is_inline_array "$apply"; then
    emit_fail "$rel" "applyTo must be a CSV string in quotes, not a YAML array (got '$apply')"
    return
  fi
  # Reject block-array form.
  local apply_block
  apply_block=$(fm_block_array_present "$file" "applyTo")
  if [ -n "$apply_block" ]; then
    emit_fail "$rel" "applyTo must be a CSV string in quotes, not a YAML block array"
    return
  fi

  local body_check
  body_check=$(body_sanity "$file" "$fm_close")
  if [ "$body_check" != "OK" ]; then
    emit_fail "$rel" "body: $body_check"
    return
  fi

  emit_pass "$rel"
}

run_copilot() {
  validate_copilot_top_level

  local instr_dir="$TARGET/.github/instructions"
  if [ -d "$instr_dir" ]; then
    for f in "$instr_dir"/*.instructions.md; do
      [ -e "$f" ] || continue
      validate_copilot_instruction "$f"
    done
  fi
  validate_role_set copilot
  validate_no_claude_model_aliases copilot "$TARGET/.github/copilot-instructions.md" "$TARGET/.github/instructions" "$TARGET/.github/agents"
}

# ---- claude mode ---------------------------------------------------------

validate_claude_rule() {
  local file="$1"
  local rel="${file#"$TARGET/"}"

  local fm_open
  fm_open=$(fm_open_line "$file")
  if [ "$fm_open" != "1" ]; then
    emit_fail "$rel" "missing frontmatter open delimiter (---)"
    return
  fi

  local fm_close
  fm_close=$(fm_close_line "$file")
  if [ -z "$fm_close" ]; then
    emit_fail "$rel" "missing frontmatter close delimiter"
    return
  fi

  # paths: must be a block array (one or more "- " entries).
  local paths_block
  paths_block=$(fm_block_array_present "$file" "paths")
  local paths_inline
  paths_inline=$(fm_field "$file" "paths")
  if [ -z "$paths_block" ] && ! is_inline_array "$paths_inline"; then
    emit_fail "$rel" "frontmatter 'paths:' must be a YAML array (block or inline)"
    return
  fi

  local body_check
  body_check=$(body_sanity "$file" "$fm_close")
  if [ "$body_check" != "OK" ]; then
    emit_fail "$rel" "body: $body_check"
    return
  fi

  emit_pass "$rel"
}

run_claude() {
  local rules_dir="$TARGET/.claude/rules"
  if [ ! -d "$rules_dir" ]; then
    emit_fail ".claude/rules/" "directory missing"
    return
  fi
  local found=0
  for f in "$rules_dir"/*.md; do
    [ -e "$f" ] || continue
    found=$((found + 1))
    validate_claude_rule "$f"
  done
  if [ "$found" -eq 0 ]; then
    emit_fail ".claude/rules/" "no .md files found"
  fi
  local hookify_count=0 hookify_file hookify_bad=0 hookify_disabled=0
  for hookify_file in "$TARGET"/.claude/hookify.*.local.md; do
    [ -e "$hookify_file" ] || continue
    hookify_count=$((hookify_count + 1))
    local hookify_enabled hookify_event
    hookify_enabled="$(fm_field "$hookify_file" "enabled")"
    hookify_event="$(fm_field "$hookify_file" "event")"
    if [ "$(fm_open_line "$hookify_file")" != "1" ] \
      || [ -z "$(fm_close_line "$hookify_file")" ] \
      || [ -z "$(fm_field "$hookify_file" "name")" ] \
      || { [ "$hookify_enabled" != "true" ] && [ "$hookify_enabled" != "false" ]; } \
      || ! printf '%s\n' "$hookify_event" | /usr/bin/grep -Eq '^(bash|file|stop|prompt|all)$'; then
      emit_fail "${hookify_file#"$TARGET/"}" "invalid Hookify rule frontmatter (name, boolean enabled, and supported event required)"
      hookify_bad=$((hookify_bad + 1))
    elif [ "$hookify_enabled" = "false" ]; then
      hookify_disabled=$((hookify_disabled + 1))
      emit_warn "${hookify_file#"$TARGET/"}" "valid Hookify rule intentionally disabled by adopter"
    fi
  done
  if [ "$hookify_count" -gt 0 ]; then
    if node -e '
      const helper=require(process.argv[1]);
      const settings=process.argv[2];
      process.exit(helper.configuredState(settings)==="enabled" && helper.missingCoreHooks(settings).length===0 ? 0 : 1)
    ' "$SCRIPT_ROOT/bin/claude-hookify.js" "$TARGET/.claude/settings.json" 2>/dev/null; then
      [ "$hookify_bad" -ne 0 ] || emit_pass "Hookify dependency + $hookify_count valid rule definition(s) ($hookify_disabled disabled)"
    else
      emit_fail ".claude/settings.json" "$hookify_count Hookify rules exist but the plugin/core-hook runtime registry is incomplete"
    fi
  fi
  validate_role_set claude
}

# ---- main ---------------------------------------------------------------

echo "=========================================="
echo " CONDUCTOR adapter-output validator"
echo "  target  = $TARGET"
echo "  adapter = $ADAPTER"
echo "=========================================="

case "$ADAPTER" in
  cursor)   run_cursor   ;;
  copilot)  run_copilot  ;;
  claude)   run_claude   ;;
  gemini)   run_gemini   ;;
  codex)    run_codex    ;;
  windsurf) run_windsurf ;;
esac

echo ""
echo "------------------------------------------"
echo " Aggregate: PASS=$PASS  WARN=$WARN  FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf " Failures:%b\n" "$FAILED_FILES"
fi
echo "------------------------------------------"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
