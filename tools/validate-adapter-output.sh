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
# Adapters: cursor | copilot | claude | gemini | codex | windsurf | opencode
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
#     - manifest-owned .cursor/rules/*.mdc exist
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
#     - bounded kernel plus all 5 byte-identical complete references
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
  echo "Usage: $0 <target-dir> <adapter:cursor|copilot|claude|gemini|codex|windsurf|opencode>" >&2
  exit 2
fi

if [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir does not exist: $TARGET" >&2
  exit 2
fi

case "$ADAPTER" in
  cursor|copilot|claude|gemini|codex|windsurf|opencode) ;;
  *) echo "ERROR: unknown adapter '$ADAPTER'. Use cursor|copilot|claude|gemini|codex|windsurf|opencode." >&2; exit 2 ;;
esac

PASS=0
WARN=0
FAIL=0
FAILED_FILES=""
INSTALL_MODE="full"
MANIFEST_PATH="$TARGET/.conductor/manifests/$ADAPTER.json"

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

load_install_mode() {
  [ -e "$MANIFEST_PATH" ] || return 0
  local mode
  if ! mode="$(node -e '
    const fs=require("fs");
    const file=process.argv[1], adapter=process.argv[2];
    const st=fs.lstatSync(file);
    if(!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) process.exit(2);
    const m=JSON.parse(fs.readFileSync(file,"utf8"));
    if(m.schema_version!==2 || m.manifest_scope!=="adapter" || m.adapter!==adapter) process.exit(3);
    if(!["full","minimal","strict","recipes-only","reflector-only"].includes(m.mode)) process.exit(4);
    process.stdout.write(m.mode);
  ' "$MANIFEST_PATH" "$ADAPTER" 2>/dev/null)"; then
    INSTALL_MODE="invalid"
    emit_fail ".conductor/manifests/$ADAPTER.json" "unsafe, malformed, or unsupported install-mode manifest"
    return
  fi
  INSTALL_MODE="$mode"
}

manifest_recipe_enabled() {
  local recipe="$1"
  [ -f "$MANIFEST_PATH" ] || return 1
  node -e '
    const fs=require("fs");
    const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    process.exit(Array.isArray(manifest.recipes_enabled) && manifest.recipes_enabled.includes(process.argv[2]) ? 0 : 1);
  ' "$MANIFEST_PATH" "$recipe" 2>/dev/null
}

manifest_owns_path() {
  local rel="$1"
  [ -s "$MANIFEST_PATH" ] || return 1
  node -e '
    const fs=require("fs");
    const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    process.exit(Array.isArray(manifest.emitted_files)
      && manifest.emitted_files.some((entry)=>entry && entry.path===process.argv[2]) ? 0 : 1);
  ' "$MANIFEST_PATH" "$rel" 2>/dev/null
}

validate_ala_carte_manifest() {
  local details
  if details="$(node - "$MANIFEST_PATH" "$TARGET" "$ADAPTER" "$INSTALL_MODE" <<'NODE'
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const [manifestFile,target,adapter,mode]=process.argv.slice(2);
const errors=[];
let manifest;
try { manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8')); }
catch (error) { errors.push(`manifest JSON: ${error.message}`); }
if (manifest) {
  if (manifest.adapter!==adapter || manifest.mode!==mode) errors.push('adapter/mode does not match validator invocation');
  const recipes=manifest.recipes_enabled;
  if (!Array.isArray(recipes) || recipes.some((r)=>typeof r!=='string' || !/^[a-z0-9-]+$/.test(r))) {
    errors.push('recipes_enabled must be a safe string array');
  } else if (mode==='reflector-only' && (recipes.length!==1 || recipes[0]!=='self-improvement')) {
    errors.push('reflector-only must enable exactly self-improvement');
  } else if (mode==='recipes-only' && recipes.length===0) {
    errors.push('recipes-only must contain at least one selected recipe');
  }
  const entries=manifest.emitted_files;
  if (!Array.isArray(entries) || entries.length===0) errors.push('emitted_files must be non-empty');
  const sources=[];
  let markedRecipeBlock=false;
  for (const entry of Array.isArray(entries)?entries:[]) {
    const isBlock=entry && entry.type==='block';
    if (!entry || typeof entry.path!=='string' || (!isBlock && typeof entry.source!=='string')) { errors.push('malformed emitted_files entry'); continue; }
    if (!entry.path || path.isAbsolute(entry.path) || entry.path.includes('\\') || entry.path.split('/').includes('..')) {
      errors.push(`unsafe emitted path: ${entry.path}`); continue;
    }
    if (typeof entry.source==='string') sources.push(entry.source);
    if (isBlock && ['recipes','reflector'].includes(entry.block)) markedRecipeBlock=true;
    const absolute=path.resolve(target,entry.path);
    if (absolute!==path.resolve(target) && !absolute.startsWith(path.resolve(target)+path.sep)) { errors.push(`path escape: ${entry.path}`); continue; }
    try {
      const st=fs.lstatSync(absolute);
      if (!st.isFile() || st.isSymbolicLink() || st.nlink!==1) { errors.push(`unsafe emitted file: ${entry.path}`); continue; }
      if (entry.type!=='block' && typeof entry.sha256==='string' && entry.sha256) {
        const actual=crypto.createHash('sha256').update(fs.readFileSync(absolute)).digest('hex');
        if (actual!==entry.sha256) errors.push(`checksum drift: ${entry.path}`);
      }
    } catch { errors.push(`missing emitted file: ${entry.path}`); }
  }
  if (sources.some((s)=>s.startsWith('core/universal-rules/'))) errors.push(`${mode} must not own universal rules`);
  const baselineRoles=new Set(['planner','reviewer','code-reviewer','builder','helper','designer','scribe','utility']);
  if (sources.some((s)=>s.startsWith('core/roles/') && baselineRoles.has(path.basename(s,'.md')))) errors.push(`${mode} must not own baseline roles`);
  if (mode==='reflector-only') {
    for (const required of ['core/recipes/self-improvement.md','core/roles/reflector.md','core/reflector/reflect-brief.md','core/reflector/reflection-proposals.js']) {
      if (!sources.includes(required) && !(required==='core/recipes/self-improvement.md' && markedRecipeBlock)) errors.push(`missing reflector source: ${required}`);
    }
  } else if (Array.isArray(recipes)) {
    for (const recipe of recipes) if (!sources.includes(`core/recipes/${recipe}.md`) && !markedRecipeBlock) errors.push(`missing recipe source: ${recipe}`);
  }
}
if (errors.length) { process.stdout.write(errors.join('\n')); process.exit(1); }
NODE
  )"; then
    emit_pass ".conductor/manifests/$ADAPTER.json ($INSTALL_MODE ownership + checksum contract)"
  else
    while IFS= read -r detail; do
      [ -n "$detail" ] && emit_fail ".conductor/manifests/$ADAPTER.json" "$detail"
    done <<< "$details"
  fi
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
  if [ "$INSTALL_MODE" = "minimal" ]; then
    emit_pass "native role set intentionally omitted (--mode=minimal)"
    return
  fi
  case "$adapter" in
    claude) dir="$TARGET/.claude/agents"; suffix=".md" ;;
    cursor) dir="$TARGET/.cursor/agents"; suffix=".md" ;;
    copilot) dir="$TARGET/.github/agents"; suffix=".agent.md" ;;
    gemini) dir="$TARGET/.gemini/agents"; suffix=".md" ;;
    codex) dir="$TARGET/.codex/agents"; suffix=".toml" ;;
    windsurf) dir="$TARGET/.windsurf/workflows"; suffix=".md" ;;
    opencode) dir="$TARGET/.opencode/agents"; suffix=".md" ;;
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
      case "$role" in planner|reviewer|code-reviewer|reflector) expected_sandbox="read-only" ;; esac
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
      elif [ "$adapter" != "windsurf" ] && [ "$adapter" != "opencode" ] && [ "$name" != "$role" ]; then
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
      elif [ "$adapter" = "opencode" ] && { [ "$(fm_field "$file" "mode")" != "subagent" ] || [ -z "$(fm_field "$file" "model")" ]; }; then
        emit_fail "${file#"$TARGET/"}" "OpenCode role must declare mode: subagent and its saved Tier translation"
        missing=$((missing + 1))
      elif [ "$adapter" = "opencode" ] && printf '%s\n' 'planner reviewer code-reviewer' | /usr/bin/grep -qw "$role" \
        && { ! /usr/bin/grep -qE '^[[:space:]]+edit:[[:space:]]+deny$' "$file" \
          || ! /usr/bin/grep -qE '^[[:space:]]+bash:[[:space:]]+deny$' "$file"; }; then
        emit_fail "${file#"$TARGET/"}" "OpenCode read-only role must deny edit and bash through permission"
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
  shift
  for root in "$@"; do
    [ -e "$root" ] || continue
    if [ -f "$root" ]; then
      hit="$(/usr/bin/awk '
        /^[[:space:]]*model[[:space:]]*[:=]/ { next }
        /saved (Cursor|Copilot) translation/ { next }
        tolower($0) ~ /(^|[^a-z])(opus|sonnet|haiku)([^a-z]|$)/ { print FILENAME ":" FNR ":" $0; exit }
      ' "$root" 2>/dev/null || true)"
    else
      while IFS= read -r file; do
        hit="$(/usr/bin/awk '
          /^[[:space:]]*model[[:space:]]*[:=]/ { next }
          /saved (Cursor|Copilot) translation/ { next }
          tolower($0) ~ /(^|[^a-z])(opus|sonnet|haiku)([^a-z]|$)/ { print FILENAME ":" FNR ":" $0; exit }
        ' "$file" 2>/dev/null || true)"
        [ -z "$hit" ] || break
      done < <(find "$root" -type f ! -name '*.conductor-backup-*' -print 2>/dev/null)
    fi
    [ -z "$hit" ] || break
  done
  if [ -n "$hit" ]; then
    emit_fail "$adapter model isolation" "Claude family alias leaked into non-Claude output: $hit"
  else
    emit_pass "$adapter model isolation (no Claude family aliases)"
  fi
}

validate_portable_skill_set() {
  local root
  case "$ADAPTER" in
    claude) root=".claude/skills" ;;
    cursor|copilot|gemini|codex|windsurf) root=".agents/skills" ;;
    opencode) root=".opencode/skills" ;;
  esac
  if node "$SCRIPT_ROOT/bin/portable-skills.js" \
    --installed "$TARGET" "$ADAPTER" "$SCRIPT_ROOT/core/skills" >/dev/null 2>&1; then
    emit_pass "$root (3 byte-identical portable skills)"
  else
    local details
    details="$(node "$SCRIPT_ROOT/bin/portable-skills.js" \
      --installed "$TARGET" "$ADAPTER" "$SCRIPT_ROOT/core/skills" 2>&1 || true)"
    emit_fail "$root" "$details"
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

# Legacy helper for validating pre-bounded single-file surfaces during migration.
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

# Validate the bounded always-loaded kernel and the byte-complete universal
# references installed outside that eager surface. This proves optimization did
# not silently abbreviate the authoritative rules.
validate_bounded_kernel_and_refs() {
  local kernel="$1" label="$2" refs="$3" bytes rule missing=0
  if [ ! -s "$kernel" ]; then
    emit_fail "$label" "bounded runtime kernel missing or empty"
    return
  fi
  bytes="$(wc -c < "$kernel" | tr -d ' ')"
  if [ "$bytes" -gt 12288 ]; then
    emit_fail "$label" "always-loaded kernel is ${bytes} bytes; exceeds 12288-byte budget"
    missing=$((missing + 1))
  fi
  for marker in '## Non-negotiable execution contract' '## Universal-rule loading table' '## Token and context discipline' '## Selected recipe routing'; do
    if ! grep -qF "$marker" "$kernel"; then
      emit_fail "$label" "bounded runtime kernel missing marker: $marker"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -ne 0 ] || emit_pass "$label (${bytes} bytes; bounded kernel)"

  missing=0
  for rule in workflow spec-as-you-go quality-gates operations meta-discipline; do
    if [ ! -s "$refs/$rule.md" ]; then
      emit_fail "${refs#"$TARGET/"}/$rule.md" "complete universal-rule reference missing"
      missing=$((missing + 1))
    elif ! cmp -s "$SCRIPT_ROOT/core/universal-rules/$rule.md" "$refs/$rule.md"; then
      emit_fail "${refs#"$TARGET/"}/$rule.md" "reference is not byte-identical to authoritative core rule"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -ne 0 ] || emit_pass "${refs#"$TARGET/"}/ (5 byte-identical complete references)"
}

# Every selected recipe must remain available as a byte-complete, non-eager
# reference. The manifest is authoritative for the selected set.
validate_selected_recipe_references() {
  [ -s "$MANIFEST_PATH" ] || return 0
  local details root
  case "$ADAPTER" in
    claude) root=".claude/conductor/recipes" ;;
    cursor) root=".cursor/conductor/recipes" ;;
    copilot) root=".github/conductor/recipes" ;;
    gemini) root=".gemini/conductor/recipes" ;;
    codex) root=".codex/conductor/recipes" ;;
    windsurf) root=".devin/conductor/recipes" ;;
    opencode) root=".opencode/conductor/recipes" ;;
  esac
  if details="$(node - "$MANIFEST_PATH" "$TARGET" "$SCRIPT_ROOT/core/recipes" "$root" <<'NODE'
const fs=require('fs'), path=require('path');
const [manifestFile,target,sourceRoot,relativeRoot]=process.argv.slice(2);
const manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
const errors=[];
for (const recipe of manifest.recipes_enabled || []) {
  const source=path.join(sourceRoot,`${recipe}.md`);
  const installed=path.join(target,relativeRoot,`${recipe}.md`);
  if (!fs.existsSync(source) || !fs.existsSync(installed)) errors.push(`${recipe}: complete recipe reference missing`);
  else if (!fs.readFileSync(source).equals(fs.readFileSync(installed))) errors.push(`${recipe}: reference differs from authoritative core recipe`);
}
if (errors.length) { process.stdout.write(errors.join('\n')); process.exit(1); }
NODE
  )"; then
    emit_pass "$root (selected recipes are byte-identical complete references)"
  else
    while IFS= read -r detail; do [ -n "$detail" ] && emit_fail "$root" "$detail"; done <<< "$details"
  fi
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

  validate_bounded_kernel_and_refs "$main" "GEMINI.md" "$TARGET/.gemini/conductor/rules"

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
  # Full/strict mode emits both the output cap and native review-stop guard.
  # Their BeforeTool / AfterAgent registrations share one schema-aware merge.
  local gcap="$TARGET/.gemini/hooks/output-cap.sh"
  if [ -e "$gcap" ]; then
    local greview="$TARGET/.gemini/hooks/stop-r6-review-check.sh"
    if [ ! -x "$gcap" ] || [ ! -x "$greview" ]; then
      emit_fail ".gemini/hooks" "output-cap or review-stop hook is missing/not executable"
    else
      local gsettings="$TARGET/.gemini/settings.json"
      if [ ! -s "$gsettings" ]; then
        emit_fail ".gemini/settings.json" "native hooks exist but settings.json is missing"
      elif node -e '
        const fs = require("fs");
        try {
          const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          const before = (s.hooks && s.hooks.BeforeTool) || [];
          const after = (s.hooks && s.hooks.AfterAgent) || [];
          const ok = before.some((g) => (g.hooks || []).some((h) => /output-cap\.sh/.test(h.command || "")))
            && after.some((g) => (g.hooks || []).some((h) => /stop-r6-review-check\.sh/.test(h.command || "")));
          process.exit(ok ? 0 : 1);
        } catch { process.exit(1); }
      ' "$gsettings" 2>/dev/null; then
        emit_pass ".gemini/hooks (executable output-cap + review-stop guards)"
        emit_pass ".gemini/settings.json (valid JSON; BeforeTool + AfterAgent registered)"
      else
        emit_fail ".gemini/settings.json" "invalid JSON, or missing BeforeTool/AfterAgent registration"
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

  validate_bounded_kernel_and_refs "$main" "AGENTS.md" "$TARGET/.codex/conductor/rules"

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

  validate_role_set codex
  validate_no_claude_model_aliases codex "$TARGET/AGENTS.md" "$TARGET/.codex/conductor" "$TARGET/.codex/agents"
  local hooks="$TARGET/.codex/hooks.json"
  local manifest="$TARGET/.conductor/manifests/codex.json"
  # The installer intentionally preserves a pre-existing user-owned registry.
  # In that case it is absent from the Codex ownership manifest and must not be
  # judged as if CONDUCTOR emitted it. The warning printed during installation
  # remains the activation signal; this validator only certifies owned output.
  if [ "$INSTALL_MODE" = "minimal" ]; then
    emit_pass ".codex/hooks.json intentionally omitted (--mode=minimal)"
  elif [ -s "$hooks" ] && [ -s "$manifest" ] \
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

  # native config: tool_output_token_limit (Spec E, token-economy). Only
  # emitted in full/strict mode (config-only, no hook); accept a user-owned
  # pre-existing config.toml the same way .codex/hooks.json is preserved.
  local cfg="$TARGET/.codex/config.toml"
  local cfg_manifest="$TARGET/.conductor/manifests/codex.json"
  if [ -s "$cfg" ]; then
    # Official key takes a positive integer token budget. Accept TOML digit
    # separators and an inline comment, but reject strings/zero/unknown shapes.
    if grep -qE '^tool_output_token_limit[[:space:]]*=[[:space:]]*[1-9][0-9_]*([[:space:]]*(#.*)?)?$' "$cfg"; then
      emit_pass ".codex/config.toml (documented tool_output_token_limit has a positive numeric budget)"
    elif [ -s "$cfg_manifest" ] && ! grep -q '"path"[[:space:]]*:[[:space:]]*"\.codex/config\.toml"' "$cfg_manifest"; then
      emit_pass ".codex/config.toml (user-owned; preserved and excluded from CONDUCTOR output validation)"
    else
      emit_fail ".codex/config.toml" "missing a 'tool_output_token_limit = <value>' line"
    fi
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
    validate_bounded_kernel_and_refs "$top" ".windsurfrules" "$TARGET/.devin/conductor/rules"
  fi

  # Optional selected-recipe pointers use the verified native .devin/rules
  # surface. The five complete universal references deliberately do not: the
  # bounded kernel routes to them on demand.
  local rules_dir="" rules_label=""
  if [ -d "$TARGET/.devin/rules" ]; then
    rules_dir="$TARGET/.devin/rules"; rules_label=".devin/rules"
  elif [ -d "$TARGET/.windsurf/rules" ]; then
    rules_dir="$TARGET/.windsurf/rules"; rules_label=".windsurf/rules"
  else
    emit_pass ".devin/rules/ recipe pointers intentionally absent (no selected recipes)"
  fi

  validate_role_set windsurf
  validate_no_claude_model_aliases windsurf "$TARGET/.windsurfrules" "$TARGET/.devin/conductor" "$TARGET/.devin/rules" "$TARGET/.windsurf/workflows"
}

# ---- OpenCode mode -------------------------------------------------------

run_opencode() {
  local config="$TARGET/opencode.json" plugin="$TARGET/.opencode/plugins/conductor-guards.js"
  # Optional recipe command surface: .opencode/commands/*.md
  if [ ! -s "$config" ]; then
    emit_fail "opencode.json" "project config missing or empty"
  elif node -e '
    const fs=require("fs"); const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    if(!Array.isArray(c.instructions)) process.exit(1);
    for(const p of [".opencode/rules/conductor-kernel.md"]) if(!c.instructions.includes(p)) process.exit(1);
  ' "$config" 2>/dev/null; then
    emit_pass "opencode.json (valid instructions registry)"
  else
    emit_fail "opencode.json" "invalid JSON or missing baseline instruction glob"
  fi

  validate_bounded_kernel_and_refs "$TARGET/.opencode/rules/conductor-kernel.md" ".opencode/rules/conductor-kernel.md" "$TARGET/.opencode/conductor/rules"

  if [ "$INSTALL_MODE" = "minimal" ]; then
    emit_pass ".opencode/plugins intentionally omitted (--mode=minimal)"
  elif [ ! -s "$plugin" ]; then
    emit_fail ".opencode/plugins" "native guard plugin missing"
  elif node --check "$plugin" >/dev/null 2>&1 \
    && /usr/bin/grep -qF "'tool.execute.before'" "$plugin" \
    && /usr/bin/grep -qF 'execFileSync' "$plugin"; then
    emit_pass ".opencode/plugins/conductor-guards.js (native pre-tool guard contract)"
  else
    emit_fail ".opencode/plugins/conductor-guards.js" "syntax or native hook contract invalid"
  fi

  validate_role_set opencode
  validate_no_claude_model_aliases opencode "$TARGET/.opencode/rules" "$TARGET/.opencode/agents" "$TARGET/.opencode/skills"
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
  local rules_dir="$TARGET/.cursor/rules" rel
  if [ ! -d "$rules_dir" ]; then
    emit_fail ".cursor/rules/" "directory missing"
    return
  fi
  local found=0
  for f in "$rules_dir"/*.mdc; do
    [ -e "$f" ] || continue
    rel="${f#"$TARGET/"}"
    # Upgrades deliberately preserve adopter-modified legacy rules while
    # releasing them from manifest ownership. The adapter-output validator
    # certifies CONDUCTOR output; it must not reinterpret retained adopter
    # content as a malformed current Cursor rule.
    if [ -s "$MANIFEST_PATH" ] && ! manifest_owns_path "$rel"; then
      emit_pass "$rel (user-owned; preserved and excluded from CONDUCTOR output validation)"
      continue
    fi
    found=$((found + 1))
    validate_cursor_mdc "$f"
  done
  if [ "$found" -eq 0 ]; then
    emit_fail ".cursor/rules/" "no .mdc files found"
  fi
  validate_bounded_kernel_and_refs "$TARGET/.cursor/rules/conductor-kernel.mdc" ".cursor/rules/conductor-kernel.mdc" "$TARGET/.cursor/conductor/rules"
  validate_role_set cursor
  validate_no_claude_model_aliases cursor "$TARGET/.cursorrules" "$TARGET/.cursor/rules" "$TARGET/.cursor/agents"

  local hook="$TARGET/.cursor/hooks/stop-r6-review-check.sh"
  local config="$TARGET/.cursor/hooks.json"
  if [ -e "$hook" ] || [ -e "$config" ]; then
    if [ ! -x "$hook" ]; then
      emit_fail ".cursor/hooks/stop-r6-review-check.sh" "native stop hook missing or not executable"
    elif node -e '
      const fs=require("fs");
      try {
        const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        const stop=c.hooks?.stop;
        process.exit(c.version===1 && Array.isArray(stop)
          && stop.some((h)=>/stop-r6-review-check\.sh/.test(h.command||"")) ? 0 : 1);
      } catch { process.exit(1) }
    ' "$config" 2>/dev/null; then
      emit_pass ".cursor/hooks (executable review-stop guard)"
      emit_pass ".cursor/hooks.json (valid v1 stop-hook registry)"
    else
      emit_fail ".cursor/hooks.json" "invalid JSON/version or missing review-stop registration"
    fi
  fi
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

  local copilot_kernel="$TARGET/.github/copilot-instructions.md"
  [ -s "$copilot_kernel" ] || copilot_kernel="$TARGET/.github/instructions/conductor-kernel.instructions.md"
  validate_bounded_kernel_and_refs "$copilot_kernel" "${copilot_kernel#"$TARGET/"}" "$TARGET/.github/conductor/rules"

  local instr_dir="$TARGET/.github/instructions"
  if [ -d "$instr_dir" ]; then
    for f in "$instr_dir"/*.instructions.md; do
      [ -e "$f" ] || continue
      validate_copilot_instruction "$f"
    done
  fi
  validate_role_set copilot
  validate_no_claude_model_aliases copilot "$TARGET/.github/copilot-instructions.md" "$TARGET/.github/instructions" "$TARGET/.github/agents"

  local hooks_dir="$TARGET/.github/hooks/conductor"
  local config="$TARGET/.github/hooks/conductor-reflect.json"
  if [ -e "$hooks_dir" ] || [ -e "$config" ]; then
    local script missing=0
    for script in pretool-commit-current-work-check pretool-commit-test-coverage-check stop-r6-review-check; do
      if [ ! -x "$hooks_dir/$script.sh" ]; then
        emit_fail ".github/hooks/conductor/$script.sh" "native hook missing or not executable"
        missing=$((missing + 1))
      fi
    done
    if [ "$missing" -eq 0 ] && node -e '
      const fs=require("fs");
      try {
        const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        const strings=JSON.stringify(c);
        const pre=c.hooks?.preToolUse, stop=c.hooks?.agentStop;
        const ok=c.version===1 && Array.isArray(pre) && Array.isArray(stop)
          && /pretool-commit-current-work-check\.sh/.test(strings)
          && /pretool-commit-test-coverage-check\.sh/.test(strings)
          && /stop-r6-review-check\.sh/.test(strings);
        process.exit(ok ? 0 : 1);
      } catch { process.exit(1) }
    ' "$config" 2>/dev/null; then
      emit_pass ".github/hooks (3 executable native guards)"
      emit_pass ".github/hooks/conductor-reflect.json (valid v1 preToolUse/agentStop registry)"
    elif [ "$missing" -eq 0 ]; then
      emit_fail ".github/hooks/conductor-reflect.json" "invalid JSON/version or incomplete native guard registry"
    fi
  fi
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
  validate_bounded_kernel_and_refs "$TARGET/CLAUDE.md" "CLAUDE.md" "$TARGET/.claude/conductor/rules"
  local rules_dir="$TARGET/.claude/rules"
  if [ ! -d "$rules_dir" ]; then
    emit_pass ".claude/rules/ recipe pointers intentionally absent (no selected recipes)"
  else
    local found=0
    for f in "$rules_dir"/*.md; do
      [ -e "$f" ] || continue
      found=$((found + 1))
      validate_claude_rule "$f"
    done
    if [ "$found" -eq 0 ]; then
      emit_pass ".claude/rules/ recipe pointers intentionally absent (no selected recipes)"
    fi
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
    local claude_self_improvement="false"
    manifest_recipe_enabled self-improvement && claude_self_improvement="true"
    if node -e '
      const helper=require(process.argv[1]);
      const settings=process.argv[2];
      const options={selfImprovement: process.argv[3]==="true"};
      process.exit(helper.configuredState(settings)==="enabled" && helper.missingCoreHooks(settings,options).length===0 ? 0 : 1)
    ' "$SCRIPT_ROOT/bin/claude-hookify.js" "$TARGET/.claude/settings.json" "$claude_self_improvement" 2>/dev/null; then
      [ "$hookify_bad" -ne 0 ] || emit_pass "Hookify dependency + $hookify_count valid rule definition(s) ($hookify_disabled disabled)"
    else
      emit_fail ".claude/settings.json" "$hookify_count Hookify rules exist but the plugin/core-hook runtime registry is incomplete"
    fi
  fi
  # output-cap.sh (Spec E, token-economy): only emitted in full/strict mode.
  # When present it must be executable AND registered under a PostToolUse
  # bucket in .claude/settings.json (mirrors the hookify core-hook check above,
  # narrowed to this one hook so it also fires when no Hookify rules exist).
  local cap="$TARGET/.claude/hooks/output-cap.sh"
  if [ -e "$cap" ]; then
    if [ ! -x "$cap" ]; then
      emit_fail ".claude/hooks/output-cap.sh" "hook exists but is not executable (chmod +x)"
    elif node -e '
      const h=require(process.argv[1]);
      try {
        const missing=h.missingCoreHooks(process.argv[2]);
        process.exit(missing.includes(".claude/hooks/output-cap.sh") ? 1 : 0);
      } catch { process.exit(1); }
    ' "$SCRIPT_ROOT/bin/claude-hookify.js" "$TARGET/.claude/settings.json" 2>/dev/null; then
      emit_pass ".claude/hooks/output-cap.sh (executable; registered under PostToolUse)"
    else
      emit_fail ".claude/hooks/output-cap.sh" "hook exists but is not registered under PostToolUse in .claude/settings.json"
    fi
  fi

  validate_role_set claude
}

# ---- shared documentation contract --------------------------------------

validate_canonical_docs() {
  # À-la-carte modes intentionally omit docs. When the document bundle is
  # present, however, all seven adapters must emit the same visible precedent.
  [ -e "$TARGET/docs/INDEX.md" ] || return

  local rel
  for rel in docs/plans/README.md docs/architecture/README.md docs/research/README.md; do
    if [ -s "$TARGET/$rel" ]; then
      emit_pass "$rel"
    else
      emit_fail "$rel" "canonical document-location seed is missing or empty"
    fi
  done

  if /usr/bin/grep -qF 'Existing files or plugin-created' "$TARGET/docs/INDEX.md" \
    && /usr/bin/grep -qF 'docs/plans/YYYY-MM-DD-<topic>.md' "$TARGET/docs/INDEX.md" \
    && /usr/bin/grep -qF 'docs/specs/<area>.md' "$TARGET/docs/INDEX.md"; then
    emit_pass "docs/INDEX.md canonical-path precedence"
  else
    # Existing documentation templates are adopter-owned and intentionally
    # skip-if-existing. A pre-ADR-052 INDEX therefore survives a safe upgrade
    # even though the always-loaded workflow rule and visible directory seeds
    # are current. Report that drift without making a lossless upgrade fail.
    # Fresh-output regressions remain fail-closed in test-doc-path-policy.sh.
    emit_warn "docs/INDEX.md" "canonical path map or legacy-precedent rule is missing; preserve adopter content and merge the current template manually"
  fi
}

# ---- main ---------------------------------------------------------------

echo "=========================================="
echo " CONDUCTOR adapter-output validator"
echo "  target  = $TARGET"
echo "  adapter = $ADAPTER"
echo "=========================================="

load_install_mode
echo "  mode    = $INSTALL_MODE"

case "$INSTALL_MODE" in
  recipes-only|reflector-only)
    validate_ala_carte_manifest
    ;;
  full|minimal|strict)
    case "$ADAPTER" in
      cursor)   run_cursor   ;;
      copilot)  run_copilot  ;;
      claude)   run_claude   ;;
      gemini)   run_gemini   ;;
      codex)    run_codex    ;;
      windsurf) run_windsurf ;;
      opencode) run_opencode ;;
    esac
    validate_portable_skill_set
    validate_canonical_docs
    ;;
  *) : ;;
esac

case "$INSTALL_MODE" in
  full|minimal|strict|recipes-only|reflector-only) validate_selected_recipe_references ;;
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
