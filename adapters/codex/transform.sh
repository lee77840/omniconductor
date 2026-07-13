#!/usr/bin/env bash
#
# CONDUCTOR — Codex adapter transform.sh
#
# Reads core/ assets and writes a compact always-loaded Codex kernel at the
# project root plus complete on-demand rule references and universal docs.
#
# AGENTS.md is the established cross-agent project-rules convention adopted by
# OpenAI Codex / Codex CLI (supersedes the early-design .codex/codex.md guess —
# see adapters/codex/transform-spec.md Outputs note). Codex auto-loads AGENTS.md
# from the project root at session start.
#
# Usage:
#   bash adapters/codex/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--no-prompt]
#   bash adapters/codex/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/codex/transform.sh ~/Projects/my-app
#   bash adapters/codex/transform.sh ~/Projects/my-app --recipes=tdd,debugging
#   bash adapters/codex/transform.sh /tmp/test-project --dry-run
#   bash adapters/codex/transform.sh . --no-prompt
#   bash adapters/codex/transform.sh . --uninstall              # revert install
#   bash adapters/codex/transform.sh . --uninstall --force      # bypass safety checks
#
# Layer 2 transformation (per ADR-004 honesty + ADR-021):
#   adapters/codex/AGENTS-kernel.md → <target>/AGENTS.md (compact always-loaded contract)
#   core/universal-rules/*.md      →  <target>/.codex/conductor/rules/*.md (complete references)
#   core/recipes/*.md (selected)   →  <target>/.codex/conductor/recipes/*.md (complete references)
#   core/docs-templates/*.md       →  <target>/docs/*.md  (CURRENT_WORK, REMAINING_TASKS, etc.)
#   supported core/hooks/*.sh.template → <target>/.codex/hooks/*.sh + hooks.json
#   core/roles/*.md                →  <target>/.codex/agents/*.toml (native Codex subagents)
#   adapters/claude/hookify-...    →  SKIPPED (Claude-only plugin)
#
# Codex reads one bounded always-loaded project file. Complete source text is
# intentionally kept out of AGENTS.md so Codex's default project-doc byte limit
# cannot silently truncate the execution contract or selected recipe pointers.

set -eu

# Direct adapter calls enter through the CLI so one-time Tier-model setup runs
# before role emission. Array forwarding preserves exact shell argument
# boundaries; the CLI marks its adapter child to prevent wrapper recursion.
ORIGINAL_ARGS=("$@")
CONDUCTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONDUCTOR_DELEGATE_TO_CLI="true"
[ "${#ORIGINAL_ARGS[@]}" -gt 0 ] || CONDUCTOR_DELEGATE_TO_CLI="false"
if [ "${#ORIGINAL_ARGS[@]}" -gt 0 ]; then
  for _conductor_arg in "${ORIGINAL_ARGS[@]}"; do
    case "$_conductor_arg" in --help|-h) CONDUCTOR_DELEGATE_TO_CLI="false" ;; esac
  done
fi
CONDUCTOR_CLI_CHILD="false"
conductor_file_identity() {
  if stat -f '%i:%z' "$1" >/dev/null 2>&1; then
    stat -f '%i:%z' "$1"
  elif stat -c '%i:%s' "$1" >/dev/null 2>&1; then
    stat -c '%i:%s' "$1"
  else
    return 1
  fi
}
if [ "${CONDUCTOR_CLI_DISPATCH:-0}" = "1" ] && [ -r /dev/fd/3 ]; then
  if _conductor_dispatch_identity="$(conductor_file_identity /dev/fd/3)" \
    && _conductor_cli_identity="$(conductor_file_identity "$CONDUCTOR_ROOT/bin/omniconductor.js")" \
    && [ -n "$_conductor_dispatch_identity" ] \
    && [ "$_conductor_dispatch_identity" = "$_conductor_cli_identity" ]; then
    CONDUCTOR_CLI_CHILD="true"
  fi
fi
if [ "$CONDUCTOR_CLI_CHILD" != "true" ] && [ "$CONDUCTOR_DELEGATE_TO_CLI" = "true" ]; then
  command -v node >/dev/null 2>&1 || {
    echo "Error: node is required for one-time CONDUCTOR model setup." >&2
    exit 127
  }
  exec node "$CONDUCTOR_ROOT/bin/omniconductor.js" init --target=codex "${ORIGINAL_ARGS[@]}"
fi

# ----- arg parsing --------------------------------------------------------

TARGET=""
RECIPES=""
MODE="full"
DRY_RUN="false"
NO_PROMPT="false"
UNINSTALL="false"
FORCE="false"

# Onboarding wizard state
WIZARD_APPLY_RULES="true"

while [ $# -gt 0 ]; do
  case "$1" in
    --recipes=*) RECIPES="${1#--recipes=}" ;;
    --mode=*)    MODE="${1#--mode=}" ;;
    --dry-run)   DRY_RUN="true" ;;
    --no-prompt) NO_PROMPT="true" ;;
    --uninstall|--rollback) UNINSTALL="true" ;;
    --force) FORCE="true" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: bash adapters/codex/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated recipes to reference from AGENTS.md and
                        install under .codex/conductor/recipes/
  --mode=<m>            Install preset (ADR-044): full (default) | minimal (rules text +
                        docs only) | strict (abort if AGENTS.md exists) | recipes-only
                        (marked block appended to AGENTS.md; requires --recipes=) |
                        reflector-only (self-improvement loop standalone as a marked block)
  --dry-run             Preview only — no files written
  --no-prompt           Skip all interactive prompts; apply sensible defaults (CI-safe)
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none. Customizations not in the
                        manifest are preserved.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Output (bounded Codex project-instruction model):
  <target>/AGENTS.md    Compact always-loaded execution kernel and reference routing
  <target>/.codex/conductor/rules/*.md    Complete universal-rule references
  <target>/.codex/conductor/recipes/*.md  Complete selected-recipe references
  <target>/.codex/agents/*.toml  Eight native role profiles (full/strict)
  <target>/.codex/hooks.json     Supported native lifecycle guards (full/strict)
  <target>/docs/*.md    Universal doc templates (CURRENT_WORK, REMAINING_TASKS, ...)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering

What this adapter does NOT install (per ADR-004 honesty):
  - Claude-only hook contracts (Agent/Read routing, large-file Read interception, Hookify)
  - Unsupported Codex permissionDecision:ask gates; soft warnings use additionalContext
  - Automatic loading of detailed references (AGENTS.md tells Codex when to open them)
  - Hookify rule templates (Claude-only plugin)
EOF
      exit 0
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [ -z "$TARGET" ]; then
  echo "Error: target-project path is required." >&2
  echo "Usage: bash adapters/codex/transform.sh <target-project> [--recipes=...]" >&2
  exit 1
fi

case "$MODE" in
  full|minimal|strict|recipes-only|reflector-only) : ;;
  *) echo "Error: unknown --mode '$MODE' (one of: full, minimal, strict, recipes-only, reflector-only)" >&2; exit 1 ;;
esac
if [ "$MODE" = "reflector-only" ]; then
  if [ -n "$RECIPES" ] && [ "$RECIPES" != "self-improvement" ]; then
    echo "NOTE: --mode=reflector-only ignores --recipes (installs self-improvement only)" >&2
  fi
  RECIPES="self-improvement"
fi
if [ "$MODE" = "recipes-only" ] && [ -z "$RECIPES" ] && [ "$UNINSTALL" != "true" ]; then
  echo "Error: --mode=recipes-only requires --recipes=A,B,..." >&2
  exit 1
fi

# Resolve CONDUCTOR assets (root was resolved by the invocation wrapper).
CORE_ROOT="$CONDUCTOR_ROOT/core"
[ -d "$CORE_ROOT" ] || { echo "Error: core/ not found at $CORE_ROOT" >&2; exit 1; }

# CONDUCTOR package version for the manifest — parsed at runtime from package.json
# so releases never drift the manifest (falls back to "unknown" on any error).
CONDUCTOR_VERSION="$(/usr/bin/sed -n -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$CONDUCTOR_ROOT/package.json" 2>/dev/null | /usr/bin/head -n 1)"
[ -n "$CONDUCTOR_VERSION" ] || CONDUCTOR_VERSION="unknown"

if [ "$DRY_RUN" = "true" ]; then
  mkdir -p "$TARGET"
fi
TARGET_ABS="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "Error: target directory does not exist or is not a directory: $TARGET" >&2; exit 1; }

if [ "$UNINSTALL" != "true" ] && [ "$DRY_RUN" != "true" ] && [ "$MODE" != "recipes-only" ]; then
  _conductor_models=()
  while IFS= read -r _conductor_model; do _conductor_models+=("$_conductor_model"); done \
    < <(node "$CONDUCTOR_ROOT/bin/model-routing.js" resolve "$TARGET_ABS" codex)
  [ "${#_conductor_models[@]}" -eq 3 ] || { echo "Error: valid Codex Tier routing is required before installation." >&2; exit 2; }
  export CONDUCTOR_CODEX_MODEL_TIER_1="${_conductor_models[0]}"
  export CONDUCTOR_CODEX_MODEL_TIER_2="${_conductor_models[1]}"
  export CONDUCTOR_CODEX_MODEL_TIER_3="${_conductor_models[2]}"
fi

# ----- helpers ------------------------------------------------------------

log() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] $*"
  else
    echo "[conductor] $*"
  fi
}

mkdir_if_real() {
  if [ "$DRY_RUN" = "true" ]; then
    log "would mkdir -p $1"
  else
    mkdir -p "$1"
  fi
}

# Strip the CONDUCTOR universal frontmatter (first --- ... --- block) from src body.
# Print body to stdout. Codex does not consume YAML frontmatter.
strip_frontmatter() {
  local src="$1"
  /usr/bin/awk 'BEGIN{f=0} /^---$/{c++; if(c==2){f=1; next}} f==1' "$src"
}

# Derive a section title for a rule/recipe. First H1 line (sans frontmatter), or filename.
derive_title() {
  local src="$1"
  local title
  title="$(strip_frontmatter "$src" | /usr/bin/grep -m1 '^# ' | /usr/bin/sed -e 's/^# *//' | /usr/bin/head -c 160)"
  if [ -z "$title" ]; then
    title="$(basename "$src" .md)"
  fi
  printf '%s' "$title"
}

has_recipe() {
  case ",$RECIPES," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# Emit one native Codex subagent. Real installs reload the project-saved model
# slugs before this point; inherited environment values are internal transport
# only and cannot override the saved mapping.
emit_codex_agent() {
  local role="$1" description="$2" sandbox="$3" tier effort tier_label
  local src="$CORE_ROOT/roles/$role.md" dest="$TARGET_ABS/.codex/agents/$role.toml"
  local model=""
  tier="$(conductor_role_difficulty_tier "$src")" || exit 1
  effort="$(conductor_codex_effort_for_tier "$tier")" || exit 1
  tier_label="$(conductor_difficulty_label "$tier")" || exit 1
  case "$tier" in
    1) model="$CODEX_TIER_1_MODEL" ;;
    2) model="$CODEX_TIER_2_MODEL" ;;
    3) model="$CODEX_TIER_3_MODEL" ;;
  esac
  if [ -n "$model" ] && ! conductor_validate_model_slug "$model" "Codex model for $role"; then
    /bin/rm -f "${MANIFEST_STAGE_PATH:-}"
    exit 1
  fi
  backup_and_remember "$dest"
  {
    printf 'name = "%s"\n' "$role"
    printf 'description = "%s"\n' "$description"
    [ -z "$model" ] || printf 'model = "%s"\n' "$model"
    printf 'model_reasoning_effort = "%s"\n' "$effort"
    printf 'sandbox_mode = "%s"\n' "$sandbox"
    printf 'developer_instructions = """\n'
    printf 'CONDUCTOR difficulty contract: %s. The triggers in meta-discipline.md section 6 are authoritative; reasoning effort is only this adapter\x27s translation.\n\n' "$tier_label"
    strip_frontmatter "$src"
    printf '\n"""\n'
  } > "$dest"
  record_emit ".codex/agents/$role.toml" "core/roles/$role.md" "$MANIFEST_LAST_BACKUP"
}

pin_codex_hook_dialect() {
  local file="$1" tmp="$1.conductor-tmp"
  /usr/bin/awk '{ print; if ($0 == "set -u") print "export CONDUCTOR_HOOK_DIALECT=codex" }' "$file" > "$tmp"
  /bin/mv "$tmp" "$file"
}

# backup_and_remember <dest>
# If <dest> exists, copy it to <dest>.conductor-backup-<ts> and remember the relative
# backup path in MANIFEST_LAST_BACKUP for the next record_emit. Honors DRY_RUN.
# Origin: ADR-019 (Claude adapter pattern), mirrored per ADR-021.
backup_and_remember() {
  conductor_manifest_backup_and_remember "$1"
}

# ----- manifest tracking (ADR-020, mirrored per ADR-021) ------------------
#
# Format identical to Claude/Cursor adapters' manifest. POSIX shell + sed only — no jq.

LEGACY_MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_PATH="$TARGET_ABS/.conductor/manifests/codex.json"
MANIFEST_STAGE_PATH=""
MANIFEST_TS=""
MANIFEST_LAST_BACKUP=""

# shellcheck source=../../tools/manifest-safety.sh
. "$CONDUCTOR_ROOT/tools/manifest-safety.sh"
conductor_manifest_prepare "codex"

init_manifest() {
  if [ "$DRY_RUN" = "true" ]; then
    log "would init manifest staging at $MANIFEST_PATH.staging"
    return
  fi
  MANIFEST_TS="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  MANIFEST_STAGE_PATH="$MANIFEST_PATH.staging"
  conductor_manifest_init_stage
}

record_emit() {
  if [ "$DRY_RUN" = "true" ] || [ "$UNINSTALL" = "true" ]; then
    return
  fi
  local relpath="$1" src="$2" backup="${3:-}"
  local had_backup="false"
  [ -n "$backup" ] && had_backup="true"
  local esc_path esc_src esc_backup emitted_sha
  conductor_manifest_stage_drop_path "$relpath"
  esc_path="$(printf '%s' "$relpath" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_src="$(printf '%s' "$src" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_backup="$(printf '%s' "$backup" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  emitted_sha="$(conductor_sha256_file "$TARGET_ABS/$relpath")"
  printf '    {"path": "%s", "source": "%s", "had_backup": %s, "backup_path": "%s", "sha256": "%s"},\n' \
    "$esc_path" "$esc_src" "$had_backup" "$esc_backup" "$emitted_sha" >> "$MANIFEST_STAGE_PATH"
}

finalize_manifest() {
  if [ "$DRY_RUN" = "true" ]; then
    log "would finalize manifest -> $MANIFEST_PATH"
    return
  fi
  [ -z "$MANIFEST_STAGE_PATH" ] && return
  [ -f "$MANIFEST_STAGE_PATH" ] || return

  if [ -f "$MANIFEST_PATH" ]; then
    local ts
    ts="$(/bin/date +%Y%m%d-%H%M%S)"
    /bin/cp "$MANIFEST_PATH" "$MANIFEST_PATH.conductor-backup-$ts"
    log "  backed up existing $MANIFEST_PATH -> $MANIFEST_PATH.conductor-backup-$ts"
  fi

  local recipes_json="[]"
  if [ -n "$RECIPES" ]; then
    recipes_json="["
    local IFS_BAK=$IFS
    IFS=','
    local first="true"
    for r in $RECIPES; do
      r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
      [ -z "$r" ] && continue
      if [ "$first" = "true" ]; then
        recipes_json="${recipes_json}\"$r\""
        first="false"
      else
        recipes_json="${recipes_json}, \"$r\""
      fi
    done
    IFS=$IFS_BAK
    recipes_json="${recipes_json}]"
  fi

  local entries
  if [ -s "$MANIFEST_STAGE_PATH" ]; then
    entries="$(/usr/bin/sed -e '$ s/,$//' "$MANIFEST_STAGE_PATH")"
  else
    entries=""
  fi

  /bin/cat > "$MANIFEST_PATH" <<EOF
{
  "schema_version": 2,
  "manifest_scope": "adapter",
  "version": "v$CONDUCTOR_VERSION",
  "adapter": "codex",
  "mode": "$MODE",
  "install_timestamp": "$MANIFEST_TS",
  "conductor_root": "$CONDUCTOR_ROOT",
  "recipes_enabled": $recipes_json,
  "emitted_files": [
$entries
  ]
}
EOF
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  log "  wrote manifest $MANIFEST_PATH"
  conductor_manifest_publish_projection
}

# ----- marked append-blocks (ADR-044, --mode=recipes-only / reflector-only) ----
#
# Single-file tools can't take recipes as separate files, so à-la-carte modes
# APPEND a marked block to the existing baseline instead of overwriting it.
# The manifest records {"type": "block", "sha256": <hash of content>, "created_file"}.
# Uninstall strips the block only when its content hash still matches.

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | /usr/bin/awk '{print $1}'
  else /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'; fi
}

# append_block <abs_file> <block_name> <content_file> — sets BLOCK_SHA + BLOCK_CREATED.
append_block() {
  local f="$1" name="$2" content="$3" rel entry expected_sha current_sha open_count close_count
  local open="<!-- conductor:block $name -->" close="<!-- /conductor:block $name -->"
  BLOCK_CREATED="false"; BLOCK_SHA=""
  if [ "$DRY_RUN" = "true" ]; then
    log "would append marked block '$name' to $f"
    return
  fi
  # Content must never contain the marker syntax itself — a colliding line would
  # truncate extraction AND stripping while the hash guard computes the same
  # truncation on both sides (silent data loss). Refuse instead.
  if /usr/bin/grep -qE '<!-- /?conductor:block ' "$content"; then
    echo "Error: block content contains the conductor:block marker syntax — refusing to append." >&2
    /bin/rm -f "${MANIFEST_STAGE_PATH:-}"
    exit 1
  fi
  if [ ! -f "$f" ]; then
    BLOCK_CREATED="true"
    : > "$f"
  else
    rel="${f#$TARGET_ABS/}"
    open_count="$(/usr/bin/grep -cF "$open" "$f" || true)"
    close_count="$(/usr/bin/grep -cF "$close" "$f" || true)"
    if [ "$open_count" -ne 0 ] || [ "$close_count" -ne 0 ]; then
      if [ "$open_count" -ne 1 ] || [ "$close_count" -ne 1 ]; then
        echo "Error: found an unpaired or duplicate '$name' CONDUCTOR marker in $f; refusing to change user content." >&2
        /bin/rm -f "${MANIFEST_STAGE_PATH:-}"
        exit 1
      fi
      entry="$(conductor_manifest_block_entry "$rel" "$name" 2>/dev/null || true)"
      if [ -z "$entry" ]; then
        echo "Error: '$name' marker in $f is not owned by this install manifest; refusing to replace user content." >&2
        /bin/rm -f "${MANIFEST_STAGE_PATH:-}"
        exit 1
      fi
      expected_sha="$(conductor_manifest_field "$entry" sha256 2>/dev/null || true)"
      current_sha="$(/usr/bin/awk -v o="$open" -v c="$close" '$0==o{b=1;next} $0==c{b=0;next} b' "$f" | sha256_of)"
      if [ -z "$expected_sha" ] || [ "$current_sha" != "$expected_sha" ]; then
        echo "Error: managed '$name' block in $f was customized; refusing to overwrite it." >&2
        /bin/rm -f "${MANIFEST_STAGE_PATH:-}"
        exit 1
      fi
      # The manifest owns this one, unmodified block, so replacement is safe.
      /usr/bin/awk -v o="$open" -v c="$close" '$0==o{inb=1; if (heldset && held ~ /^[[:space:]]*$/) heldset=0; next} $0==c{inb=0;next} inb{next} {if (heldset) print held; held=$0; heldset=1} END{if (heldset) print held}' "$f" > "$f.conductor-tmp"
      /bin/mv "$f.conductor-tmp" "$f"
      log "  replaced existing block '$name' in $f"
    fi
  fi
  { echo ""; echo "$open"; /bin/cat "$content"; echo "$close"; } >> "$f"
  BLOCK_SHA="$(/usr/bin/awk -v o="$open" -v c="$close" '$0==o{b=1;next} $0==c{b=0;next} b' "$f" | sha256_of)"
  log "  appended block '$name' to $f (sha256 $(printf '%s' "$BLOCK_SHA" | /usr/bin/cut -c1-12)...)"
}

record_emit_block() {
  if [ "$DRY_RUN" = "true" ] || [ "$UNINSTALL" = "true" ]; then return; fi
  local relpath="$1" name="$2" sha="$3" created="$4"
  conductor_manifest_stage_drop_block "$relpath" "$name"
  printf '    {"path": "%s", "type": "block", "block": "%s", "sha256": "%s", "created_file": %s},\n' \
    "$relpath" "$name" "$sha" "$created" >> "$MANIFEST_STAGE_PATH"
}

# ----- framework detection (ADR-044 — suggest, NEVER auto-switch) ----------

detect_coexisting_frameworks() {
  local found=""
  [ -d "$TARGET_ABS/.specify" ] && found="$found Spec-Kit"
  { [ -d "$TARGET_ABS/_bmad" ] || [ -d "$TARGET_ABS/.bmad-core" ]; } && found="$found BMAD"
  if [ -n "$found" ] && [ "$MODE" = "full" ]; then
    log "NOTE: detected coexisting framework(s):$found"
    log "      Consider --mode=recipes-only or --mode=reflector-only to coexist without"
    log "      overlapping workflow rules (suggestion only — nothing was changed)."
  fi
}

# ----- uninstall flow (mirrored from Cursor/Claude adapter) ---------------

do_uninstall() {
  log "uninstall mode (target: $TARGET_ABS)"

  if [ ! -f "$MANIFEST_PATH" ]; then
    if [ "$FORCE" = "true" ]; then
      log "WARNING: no manifest at $MANIFEST_PATH — proceeding under --force (legacy backup scan only)"
      uninstall_legacy_scan
      return 0
    fi
    echo "Error: no manifest at $MANIFEST_PATH." >&2
    echo "  This target was either installed by a pre-manifest version or has already been uninstalled." >&2
    echo "  Re-run with --force to scan for legacy .conductor-backup-* files and delete them anyway:" >&2
    echo "    bash $0 $TARGET_ABS --uninstall --force" >&2
    exit 1
  fi

  if [ -d "$TARGET_ABS/.git" ]; then
    if [ -f "$TARGET_ABS/.git/MERGE_HEAD" ] || [ -f "$TARGET_ABS/.git/REBASE_HEAD" ] || [ -d "$TARGET_ABS/.git/rebase-merge" ]; then
      if [ "$FORCE" != "true" ]; then
        echo "Error: target has an active git operation (merge/rebase in progress)." >&2
        echo "  Resolve the in-flight operation first, or pass --force to override." >&2
        exit 1
      fi
      log "WARNING: active git operation detected — proceeding under --force"
    fi
  fi

  log "loading manifest entries..."
  local entries_count=0
  local restored=0
  local deleted=0
  local missing=0
  local preserved=0
  local blocks_removed=0
  local blocks_kept=0

  while IFS= read -r line; do
    case "$line" in
      *'"type": "block"'*)
        entries_count=$((entries_count + 1))
        local b_rel b_name b_sha b_created b_abs b_open b_close b_cur_sha
        b_rel="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
        b_name="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
        b_sha="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"sha256": *"([^"]*)".*/\1/')"
        b_created="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"created_file": *(true|false).*/\1/')"
        b_abs="$TARGET_ABS/$b_rel"
        b_open="<!-- conductor:block $b_name -->"
        b_close="<!-- /conductor:block $b_name -->"
        if [ ! -f "$b_abs" ] || ! /usr/bin/grep -qF "$b_open" "$b_abs"; then
          log "  skip block '$b_name' ($b_rel absent or markers removed)"
          continue
        fi
        b_cur_sha="$(/usr/bin/awk -v o="$b_open" -v c="$b_close" '$0==o{b=1;next} $0==c{b=0;next} b' "$b_abs" | sha256_of)"
        if [ "$b_cur_sha" = "$b_sha" ]; then
          if [ "$DRY_RUN" = "true" ]; then
            log "  would strip block '$b_name' from $b_rel"
          else
            /usr/bin/awk -v o="$b_open" -v c="$b_close" '$0==o{inb=1; if (heldset && held ~ /^[[:space:]]*$/) heldset=0; next} $0==c{inb=0;next} inb{next} {if (heldset) print held; held=$0; heldset=1} END{if (heldset) print held}' "$b_abs" > "$b_abs.conductor-tmp"
            /bin/mv "$b_abs.conductor-tmp" "$b_abs"
            log "  stripped block '$b_name' from $b_rel"
            if [ "$b_created" = "true" ] && ! /usr/bin/grep -q '[^[:space:]]' "$b_abs"; then
              /bin/rm -f "$b_abs"
              log "  deleted $b_rel (created by CONDUCTOR, now empty)"
            fi
          fi
          blocks_removed=$((blocks_removed + 1))
        else
          log "  WARNING: block '$b_name' in $b_rel was customized (hash mismatch) — left in place"
          blocks_kept=$((blocks_kept + 1))
        fi
        continue
        ;;
      *'"path":'*'"source":'*'"had_backup":'*)
        ;;
      *) continue ;;
    esac
    entries_count=$((entries_count + 1))
    local rel_path src had_backup backup_path expected_sha
    rel_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
    src="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"source": *"([^"]*)".*/\1/')"
    had_backup="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"had_backup": *(true|false).*/\1/')"
    backup_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"backup_path": *"([^"]*)".*/\1/')"
    expected_sha="$(conductor_manifest_field "$line" sha256 2>/dev/null || true)"

    local abs_dest="$TARGET_ABS/$rel_path"
    local abs_backup=""
    [ -n "$backup_path" ] && abs_backup="$TARGET_ABS/$backup_path"

    if conductor_manifest_path_needed_elsewhere "$rel_path"; then
      log "  preserve shared $rel_path (required by another active adapter)"
      preserved=$((preserved + 1))
      continue
    fi

    if [ -f "$abs_dest" ] && ! conductor_manifest_file_matches "$abs_dest" "$expected_sha"; then
      if [ -z "$expected_sha" ]; then
        log "  WARNING: preserving $rel_path (legacy manifest has no checksum)"
      else
        log "  WARNING: preserving user-modified $rel_path"
      fi
      preserved=$((preserved + 1))
      continue
    fi

    if [ "$had_backup" = "true" ] && [ -n "$abs_backup" ]; then
      if [ -f "$abs_backup" ]; then
        if [ "$DRY_RUN" = "true" ]; then
          log "  would restore $abs_backup -> $abs_dest"
        else
          /bin/mv -f "$abs_backup" "$abs_dest"
          log "  restored $abs_backup -> $abs_dest"
        fi
        restored=$((restored + 1))
      else
        if [ "$DRY_RUN" = "true" ]; then
          log "  would delete $abs_dest (backup $abs_backup missing)"
        else
          /bin/rm -f "$abs_dest"
          log "  deleted $abs_dest (backup $abs_backup missing)"
        fi
        missing=$((missing + 1))
      fi
    else
      if [ -f "$abs_dest" ]; then
        if [ "$DRY_RUN" = "true" ]; then
          log "  would delete $abs_dest"
        else
          /bin/rm -f "$abs_dest"
          log "  deleted $abs_dest"
        fi
        deleted=$((deleted + 1))
      else
        log "  skip $abs_dest (already absent)"
      fi
    fi
  done < "$MANIFEST_PATH"

  if [ "$DRY_RUN" = "true" ]; then
    log "  would delete $MANIFEST_PATH"
    for mb in "$MANIFEST_PATH".conductor-backup-*; do
      [ -e "$mb" ] && log "  would delete $mb"
    done
  else
    /bin/rm -f "$MANIFEST_PATH"
    for mb in "$MANIFEST_PATH".conductor-backup-*; do
      [ -e "$mb" ] && /bin/rm -f "$mb"
    done
    log "  deleted $MANIFEST_PATH"
  fi
  conductor_manifest_refresh_projection

  # Try to clean up empty dirs left behind (deepest first).
  for d in .agents/skills/reflect .agents/skills .agents .codex/agents .codex .conductor/reflect .conductor docs/specs docs; do
    local abs_d="$TARGET_ABS/$d"
    if [ -d "$abs_d" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        if [ -z "$(/bin/ls -A "$abs_d" 2>/dev/null)" ]; then
          log "  would rmdir empty $abs_d"
        fi
      else
        /bin/rmdir "$abs_d" 2>/dev/null && log "  rmdir empty $abs_d" || true
      fi
    fi
  done

  echo ""
  echo "========================================================"
  if [ "$DRY_RUN" = "true" ]; then
    echo " Uninstall preview (dry-run)"
  else
    echo " Uninstall complete"
  fi
  echo "  Target: $TARGET_ABS"
  echo "  Entries processed: $entries_count"
  echo "  Backups restored: $restored"
  echo "  Files deleted: $deleted"
  echo "  Backup-missing deletes: $missing"
  [ "$preserved" -gt 0 ] && echo "  User-modified files preserved: $preserved"
  if [ "$blocks_removed" -gt 0 ] || [ "$blocks_kept" -gt 0 ]; then
    echo "  Blocks stripped: $blocks_removed (customized blocks left: $blocks_kept)"
  fi
  echo "========================================================"
}

uninstall_legacy_scan() {
  log "legacy scan mode — searching for .conductor-backup-* files under $TARGET_ABS"
  local found=0
  while IFS= read -r f; do
    found=$((found + 1))
    if [ "$DRY_RUN" = "true" ]; then
      log "  would delete legacy backup $f"
    else
      /bin/rm -f "$f"
      log "  deleted legacy backup $f"
    fi
  done < <(/usr/bin/find "$TARGET_ABS" -type f -name '*.conductor-backup-*' 2>/dev/null)
  log "legacy scan: $found backup file(s)"
  log "WARNING: legacy mode does not delete Conductor-emitted source files (no manifest)."
  log "         Delete AGENTS.md manually if desired."
}

if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Wizard fires when adopter signal is detected: existing AGENTS.md OR existing .codex/.
# Otherwise (truly fresh target) wizard is skipped.

IS_ADOPTER_CASE="false"
if [ -f "$TARGET_ABS/AGENTS.md" ] || [ -d "$TARGET_ABS/.codex" ]; then
  IS_ADOPTER_CASE="true"
fi

detect_coexisting_frameworks

# --mode=strict: never overwrite an existing baseline, even with a backup (ADR-044).
if [ "$MODE" = "strict" ] && [ -f "$TARGET_ABS/AGENTS.md" ]; then
  echo "Error (--mode=strict): $TARGET_ABS/AGENTS.md already exists — strict mode aborts instead of overwriting a baseline." >&2
  echo "  Use --mode=full (timestamped backup + manifest-based restore), or move the file first." >&2
  exit 3
fi

# À-la-carte modes are non-interactive by design.
if [ "$MODE" != "full" ] && [ "$MODE" != "strict" ]; then
  NO_PROMPT="true"
fi

if [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
  echo ""
  echo "========================================================"
  echo " Welcome to CONDUCTOR setup (Codex adapter)"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""

  printf "Detect existing config? (y/N): "
  read -r _detect_answer
  if [ "$_detect_answer" = "y" ] || [ "$_detect_answer" = "Y" ]; then
    _has_agents="no"
    [ -f "$TARGET_ABS/AGENTS.md" ] && _has_agents="yes"
    _has_codex="no"
    [ -d "$TARGET_ABS/.codex" ] && _has_codex="yes"
    echo "  AGENTS.md present: $_has_agents, legacy .codex/ present: $_has_codex"
  fi

  printf "Apply universal-rules? (Y/n): "
  read -r _apply_answer
  if [ "$_apply_answer" = "n" ] || [ "$_apply_answer" = "N" ]; then
    WIZARD_APPLY_RULES="false"
    echo "  Skipping complete universal-rule references — AGENTS.md keeps the compact kernel only."
  fi

  echo ""
  echo "Available recipes:"
  echo "  web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering"
  printf "Select recipes (comma-separated, or leave blank for none): "
  read -r _recipe_answer
  if [ -n "$_recipe_answer" ]; then
    RECIPES="$_recipe_answer"
    echo "  Recipes selected: $RECIPES"
  else
    echo "  No recipes selected."
  fi

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}"
fi

# ----- step 1: build bounded AGENTS.md kernel + complete references --------

# Validate every advertised override before any managed file is emitted. Tier 3
# has no dedicated default role, so lazy per-role validation is insufficient.
# Uninstall returned above and remains available even with a stale override.
CODEX_TIER_1_MODEL="${CONDUCTOR_CODEX_MODEL_TIER_1:-${CONDUCTOR_CODEX_MODEL_HIGH:-}}"
CODEX_TIER_2_MODEL="${CONDUCTOR_CODEX_MODEL_TIER_2:-${CONDUCTOR_CODEX_MODEL_STANDARD:-}}"
CODEX_TIER_3_MODEL="${CONDUCTOR_CODEX_MODEL_TIER_3:-${CONDUCTOR_CODEX_MODEL_FAST:-}}"
[ -z "$CODEX_TIER_1_MODEL" ] || conductor_validate_model_slug "$CODEX_TIER_1_MODEL" "Codex Tier 1 model" || exit 1
[ -z "$CODEX_TIER_2_MODEL" ] || conductor_validate_model_slug "$CODEX_TIER_2_MODEL" "Codex Tier 2 model" || exit 1
[ -z "$CODEX_TIER_3_MODEL" ] || conductor_validate_model_slug "$CODEX_TIER_3_MODEL" "Codex Tier 3 model" || exit 1

init_manifest
conductor_install_project_profile

UNIVERSAL_RULES="workflow spec-as-you-go quality-gates operations meta-discipline"

AGENTS_DEST="$TARGET_ABS/AGENTS.md"

INSTALLED_RECIPES=""

# Emit a complete rule/recipe as an on-demand Codex reference.
emit_codex_reference() {
  local src="$1" rel="$2" dest="$TARGET_ABS/$2"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest"
    return
  fi
  /bin/mkdir -p "$(dirname "$dest")"
  backup_and_remember "$dest"
  strip_frontmatter "$src" > "$dest"
  record_emit "$rel" "${src#"$CONDUCTOR_ROOT/"}" "$MANIFEST_LAST_BACKUP"
}

if [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then

log "Step 1/2: AGENTS.md → $AGENTS_DEST"
backup_and_remember "$AGENTS_DEST"
AGENTS_BASELINE_BACKUP="$MANIFEST_LAST_BACKUP"

# Collect installed recipe ids (for the summary + manifest), validating each exists.
INSTALLED_RECIPES=""
if [ -n "$RECIPES" ]; then
  IFS=',' read -ra _RECIPE_LIST <<< "$RECIPES"
  for r in "${_RECIPE_LIST[@]}"; do
    r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ -z "$r" ] && continue
    if [ ! -f "$CORE_ROOT/recipes/$r.md" ]; then
      echo "Warning: recipe '$r' not found at $CORE_ROOT/recipes/$r.md; skipping" >&2
      continue
    fi
    INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
  done
fi

if [ "$WIZARD_APPLY_RULES" = "true" ]; then
  for rule in $UNIVERSAL_RULES; do
    src="$CORE_ROOT/universal-rules/$rule.md"
    [ -f "$src" ] || { echo "Warning: $src not found; skipping" >&2; continue; }
    emit_codex_reference "$src" ".codex/conductor/rules/$rule.md"
  done
fi
if [ -n "$INSTALLED_RECIPES" ]; then
  for r in $INSTALLED_RECIPES; do
    src="$CORE_ROOT/recipes/$r.md"
    [ -f "$src" ] || continue
    emit_codex_reference "$src" ".codex/conductor/recipes/$r.md"
  done
fi

# build_agents_md — writes the bounded always-loaded kernel to stdout.
build_agents_md() {
  /bin/cat "$CONDUCTOR_ROOT/adapters/codex/AGENTS-kernel.md"

  if [ "$WIZARD_APPLY_RULES" != "true" ]; then
    /bin/cat <<'NORULES'

## Detailed universal rules

The installer was told not to emit the complete universal-rule references. The
non-negotiable kernel above still applies, but `.codex/conductor/rules/*.md` is
intentionally absent.
NORULES
  fi

  if [ -n "$INSTALLED_RECIPES" ]; then
    echo ""
    echo "## Selected recipe routing"
    echo ""
    echo "Selected recipes are not automatically loaded. Read the matching complete"
    echo "reference before work in that domain:"
    echo ""
    for r in $INSTALLED_RECIPES; do
      echo "- \`$r\` → \`.codex/conductor/recipes/$r.md\`"
    done
  else
    /bin/cat <<'NORECIPES'

## Selected recipe routing

No optional CONDUCTOR recipes were selected for this installation.
NORECIPES
  fi

  /bin/cat <<'TAIL'

<!-- CONDUCTOR_KERNEL_END: validator and doctor use this marker to detect truncation risk. -->
TAIL
}

if [ "$DRY_RUN" = "true" ]; then
  log "would write bounded $AGENTS_DEST kernel + $( [ "$WIZARD_APPLY_RULES" = "true" ] && echo 5 || echo 0 ) detailed rule references + recipes:${INSTALLED_RECIPES:- none}"
else
  build_agents_md > "$AGENTS_DEST"
  record_emit "AGENTS.md" "<synthesized>" "$AGENTS_BASELINE_BACKUP"
  log "  wrote $AGENTS_DEST"
fi

else
  # ----- à-la-carte modes: marked block appended to AGENTS.md (ADR-044) ------
  BLOCK_NAME="recipes"; [ "$MODE" = "reflector-only" ] && BLOCK_NAME="reflector"
  log "Step 1/2: --mode=$MODE — compact '$BLOCK_NAME' block → $AGENTS_DEST (no full kernel)"
  if [ "$DRY_RUN" = "true" ]; then
    log "would append marked block '$BLOCK_NAME' (selected recipes: $RECIPES) to $AGENTS_DEST"
  else
    IFS=',' read -ra _RECIPE_LIST <<< "$RECIPES"
    for r in "${_RECIPE_LIST[@]}"; do
      r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
      [ -z "$r" ] && continue
      src="$CORE_ROOT/recipes/$r.md"
      if [ ! -f "$src" ]; then
        echo "Warning: recipe '$r' not found at $src; skipping" >&2
        continue
      fi
      INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
    done
    if [ -z "${INSTALLED_RECIPES// /}" ]; then
      echo "Error: --mode=$MODE resolved ZERO valid recipes from '--recipes=$RECIPES' — nothing to install (check the names)." >&2
      /bin/rm -f "$MANIFEST_STAGE_PATH"
      exit 1
    fi
    for r in $INSTALLED_RECIPES; do
      emit_codex_reference "$CORE_ROOT/recipes/$r.md" ".codex/conductor/recipes/$r.md"
    done
    _blk="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/conductor-block.XXXXXX")"
    {
      echo "# CONDUCTOR — à la carte (--mode=$MODE)"
      echo ""
      echo "> Installed WITHOUT the universal-rule kernel. This managed block stays compact"
      echo "> so an existing AGENTS.md is not pushed across Codex's instruction budget."
      echo ""
      echo "Read each complete recipe before work in its domain:"
      echo ""
      for r in $INSTALLED_RECIPES; do
        echo "- \`$r\` → \`.codex/conductor/recipes/$r.md\`"
      done
    } > "$_blk"
    append_block "$AGENTS_DEST" "$BLOCK_NAME" "$_blk"
    /bin/rm -f "$_blk"
    record_emit_block "AGENTS.md" "$BLOCK_NAME" "$BLOCK_SHA" "$BLOCK_CREATED"
    # Preserve OTHER à-la-carte blocks from a previous install (e.g. recipes-only
    # then reflector-only): carry their manifest entries forward so uninstall can
    # still strip them (ADR-044 review fix — cross-mode orphaned block).
    if [ -f "$MANIFEST_PATH" ]; then
      while IFS= read -r _prev; do
        case "$_prev" in *'"type": "block"'*) : ;; *) continue ;; esac
        _pname="$(printf '%s' "$_prev" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
        [ "$_pname" = "$BLOCK_NAME" ] && continue
        conductor_manifest_stage_has_block "AGENTS.md" "$_pname" && continue
        if /usr/bin/grep -qF "<!-- conductor:block $_pname -->" "$AGENTS_DEST" 2>/dev/null; then
          printf '%s\n' "$_prev" | /usr/bin/sed 's/,*$/,/' >> "$MANIFEST_STAGE_PATH"
          log "  preserved previous block '$_pname' in manifest"
        fi
      done < "$MANIFEST_PATH"
    fi
  fi
fi

# ----- Codex-native roles and supported hook contracts --------------------

if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  log "Step: native Codex roles → .codex/agents/"
  if [ "$DRY_RUN" != "true" ]; then
    /bin/mkdir -p "$TARGET_ABS/.codex/agents"
    emit_codex_agent planner "Architecture, gap analysis, and trade-off planning without implementation." read-only
    emit_codex_agent reviewer "Read-only pre-implementation review of plans, architecture, and task decomposition." read-only
    emit_codex_agent code-reviewer "Read-only post-implementation review for correctness, security, regressions, and tests." read-only
    emit_codex_agent builder "Primary implementation owner for cross-cutting or high-risk changes." workspace-write
    emit_codex_agent helper "Focused implementation owner for bounded, independent changes." workspace-write
    emit_codex_agent designer "UI and interaction implementation owner with design-system discipline." workspace-write
    emit_codex_agent scribe "Documentation, changelog, index, and session-state maintenance." workspace-write
    emit_codex_agent utility "Bounded Tier 3 lookup or trivial one-file edit; escalate immediately if scope grows." workspace-write
  fi
fi

# Codex hook coverage is intentionally narrower than Claude's. Only hooks with
# a verified Codex event/input/output contract are compiled. Agent/Read routing,
# large-file Read interception, and Hookify remain explicit fallbacks.
INSTALL_CODEX_HOOKS="false"
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ] || { [ "$MODE" = "reflector-only" ] && has_recipe self-improvement; }; then
  INSTALL_CODEX_HOOKS="true"
fi
if [ "$INSTALL_CODEX_HOOKS" = "true" ]; then
  log "Step: Codex-native hooks → .codex/hooks.json + .codex/hooks/"
  if [ "$DRY_RUN" != "true" ]; then
    /bin/mkdir -p "$TARGET_ABS/.codex/hooks"
    if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
      for h in pretool-commit-current-work-check pretool-commit-test-coverage-check stop-session-log-check stop-r6-review-check; do
        src="$CORE_ROOT/hooks/$h.sh.template"
        dest="$TARGET_ABS/.codex/hooks/$h.sh"
        backup_and_remember "$dest"
        /bin/cp "$src" "$dest"
        pin_codex_hook_dialect "$dest"
        /bin/chmod +x "$dest"
        record_emit ".codex/hooks/$h.sh" "core/hooks/$h.sh.template" "$MANIFEST_LAST_BACKUP"
      done
      if has_recipe loop-engineering; then
        h="pretool-loop-guard"; src="$CORE_ROOT/hooks/$h.sh.template"; dest="$TARGET_ABS/.codex/hooks/$h.sh"
        backup_and_remember "$dest"; /bin/cp "$src" "$dest"; pin_codex_hook_dialect "$dest"; /bin/chmod +x "$dest"
        record_emit ".codex/hooks/$h.sh" "core/hooks/$h.sh.template" "$MANIFEST_LAST_BACKUP"
      fi
      if has_recipe git-hygiene; then
        h="stop-git-hygiene-guard"; src="$CORE_ROOT/hooks/$h.sh.template"; dest="$TARGET_ABS/.codex/hooks/$h.sh"
        backup_and_remember "$dest"; /bin/cp "$src" "$dest"; pin_codex_hook_dialect "$dest"; /bin/chmod +x "$dest"
        record_emit ".codex/hooks/$h.sh" "core/hooks/$h.sh.template" "$MANIFEST_LAST_BACKUP"
      fi
    fi

    hc="$TARGET_ABS/.codex/hooks.json"
    hc_entry="$(conductor_manifest_entry_for_path ".codex/hooks.json" 2>/dev/null || true)"
    if [ ! -f "$hc" ] || [ -n "$hc_entry" ]; then
      backup_and_remember "$hc"
      if [ "$MODE" = "reflector-only" ]; then
        /bin/cat > "$hc" <<'HOOKJSON'
{
  "hooks": {
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "bash \"$(git rev-parse --show-toplevel)/.conductor/reflect/trajectory-log.sh\"", "timeout": 30, "statusMessage": "Recording CONDUCTOR trajectory" }
      ] }
    ]
  }
}
HOOKJSON
      else
        {
          /bin/cat <<'HOOKJSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "^Bash$", "hooks": [
        { "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex bash \"$(git rev-parse --show-toplevel)/.codex/hooks/pretool-commit-current-work-check.sh\"", "timeout": 30, "statusMessage": "Checking CURRENT_WORK synchronization" },
        { "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex bash \"$(git rev-parse --show-toplevel)/.codex/hooks/pretool-commit-test-coverage-check.sh\"", "timeout": 30, "statusMessage": "Checking staged test coverage" }
HOOKJSON
          if has_recipe loop-engineering; then
            /bin/cat <<'HOOKJSON'
        ,{ "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex CONDUCTOR_LOOP_RECIPE_PATH=.codex/conductor/recipes/loop-engineering.md bash \"$(git rev-parse --show-toplevel)/.codex/hooks/pretool-loop-guard.sh\"", "timeout": 30, "statusMessage": "Checking loop budget" }
HOOKJSON
          fi
          /bin/cat <<'HOOKJSON'
      ] }
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex bash \"$(git rev-parse --show-toplevel)/.codex/hooks/stop-session-log-check.sh\"", "timeout": 30, "statusMessage": "Checking session and spec state" },
        { "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex bash \"$(git rev-parse --show-toplevel)/.codex/hooks/stop-r6-review-check.sh\"", "timeout": 30, "statusMessage": "Checking pre-merge review state" }
HOOKJSON
          if has_recipe git-hygiene; then
            /bin/cat <<'HOOKJSON'
        ,{ "type": "command", "command": "CONDUCTOR_HOOK_DIALECT=codex CONDUCTOR_GIT_HYGIENE_RECIPE_PATH=.codex/conductor/recipes/git-hygiene.md bash \"$(git rev-parse --show-toplevel)/.codex/hooks/stop-git-hygiene-guard.sh\"", "timeout": 30, "statusMessage": "Checking git hygiene" }
HOOKJSON
          fi
          if has_recipe self-improvement; then
            /bin/cat <<'HOOKJSON'
        ,{ "type": "command", "command": "bash \"$(git rev-parse --show-toplevel)/.conductor/reflect/trajectory-log.sh\"", "timeout": 30, "statusMessage": "Recording CONDUCTOR trajectory" }
HOOKJSON
          fi
          /bin/cat <<'HOOKJSON'
      ] }
    ]
  }
}
HOOKJSON
        } > "$hc"
      fi
      record_emit ".codex/hooks.json" "<synthesized:codex-native>" "$MANIFEST_LAST_BACKUP"
    else
      log "  WARNING: .codex/hooks.json is user-owned; preserved unchanged. Merge the CONDUCTOR hooks manually or reinstall after moving it."
    fi
  fi
fi

# ----- opt-in: self-improvement (Reflector) --------------------------------

if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    log "Step: self-improvement (Reflector) → .codex hook/skill/agent"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.codex" "$TARGET_ABS/.codex/agents" "$TARGET_ABS/.agents/skills/reflect"
      conductor_install_trajectory_ignore
      for s in trajectory-log prune-lessons run-weekly; do
        d="$TARGET_ABS/.conductor/reflect/$s.sh"
        backup_and_remember "$d"; /bin/cp "$CORE_ROOT/reflector/$s.sh" "$d"; /bin/chmod +x "$d"
        record_emit ".conductor/reflect/$s.sh" "core/reflector/$s.sh" "$MANIFEST_LAST_BACKUP"
      done
      # scheduling assets: run-weekly.sh needs the brief; SCHEDULING.md documents registration
      for m in reflect-brief SCHEDULING; do
        d="$TARGET_ABS/.conductor/reflect/$m.md"
        backup_and_remember "$d"; /bin/cp "$CORE_ROOT/reflector/$m.md" "$d"
        record_emit ".conductor/reflect/$m.md" "core/reflector/$m.md" "$MANIFEST_LAST_BACKUP"
      done
      sk="$TARGET_ABS/.agents/skills/reflect/SKILL.md"
      backup_and_remember "$sk"
      { printf -- '---\nname: reflect\ndescription: Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only). Use when wrapping up work.\n---\n\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; } > "$sk"
      record_emit ".agents/skills/reflect/SKILL.md" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      emit_codex_agent reflector "Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies." workspace-write
    fi
    ;;
esac

# ----- step 2: docs templates --------------------------------------------

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 2/2: docs templates — skipped (--mode=$MODE is à la carte; docs ship with full/minimal)"
else
log "Step 2/2: docs templates → docs/"
mkdir_if_real "$TARGET_ABS/docs"
mkdir_if_real "$TARGET_ABS/docs/specs"

for tpl in CURRENT_WORK REMAINING_TASKS PLANS TASKS INDEX; do
  src="$CORE_ROOT/docs-templates/$tpl.md"
  dest="$TARGET_ABS/docs/$tpl.md"
  [ -f "$src" ] || continue
  if [ -f "$dest" ]; then
    log "  $dest exists — leaving in place"
    continue
  fi
  if [ "$DRY_RUN" = "true" ]; then
    log "would copy $src -> $dest"
  else
    /bin/cp "$src" "$dest"
    record_emit "docs/$tpl.md" "core/docs-templates/$tpl.md" ""
  fi
done

if [ -f "$CORE_ROOT/docs-templates/specs/_example.md" ]; then
  src="$CORE_ROOT/docs-templates/specs/_example.md"
  dest="$TARGET_ABS/docs/specs/_example.md"
  if [ ! -f "$dest" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      log "would copy $src -> $dest"
    else
      /bin/cp "$src" "$dest"
      record_emit "docs/specs/_example.md" "core/docs-templates/specs/_example.md" ""
    fi
  fi
fi

# Finalize manifest after all emits.
fi

finalize_manifest

# ----- completion summary -------------------------------------------------

echo ""
echo "========================================================"
if [ "$DRY_RUN" = "true" ]; then
  echo " Dry-run preview complete (no files written)."
else
  echo " Done."
fi
echo "  Target: $TARGET_ABS"
echo "  Adapter: codex"
if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  echo "  AGENTS.md: compact à-la-carte pointer block appended (no universal-rule kernel)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  echo "  AGENTS.md: bounded always-loaded kernel; complete rules in .codex/conductor/rules/"
else
  echo "  AGENTS.md: bounded always-loaded kernel (detailed universal rules skipped)"
fi
echo "  Recipe references installed:${INSTALLED_RECIPES:- (none)}"
echo ""
echo " Native runtime:"
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  echo "  - Roles: 8 native Codex subagents in .codex/agents/."
  echo "  - Hooks: supported PreToolUse/Stop guards in .codex/hooks.json."
  echo "  - Trust: run /hooks in Codex after install or hook changes."
else
  echo "  - Full roles/guards are omitted by --mode=$MODE."
fi
echo " Skipped (per ADR-004 honesty):"
echo "  - Claude-only Agent/Read routing and large-file interception."
echo "  - Detailed references are on-demand; AGENTS.md states when Codex must open them."
echo "  - Hookify rule templates: Claude-only plugin."
echo ""
echo " Activation: AGENTS.md auto-loads on Codex session start (project root)."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open $TARGET_ABS with Codex."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. (optional) Create .memory/ and add it to .gitignore — see the Memory section in AGENTS.md."
echo "  4. Run /hooks, review and trust project hooks, then verify project conventions are loaded."
