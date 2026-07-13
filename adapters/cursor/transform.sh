#!/usr/bin/env bash
#
# CONDUCTOR — Cursor adapter transform.sh
#
# Reads core/ assets and writes them into a target project as native Cursor
# files: .cursor/rules/*.mdc, optional .cursorrules (legacy bundle), docs/*.
#
# Usage:
#   bash adapters/cursor/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--no-prompt] [--legacy-cursorrules]
#   bash adapters/cursor/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/cursor/transform.sh ~/Projects/my-app
#   bash adapters/cursor/transform.sh ~/Projects/my-app --recipes=i18n,monorepo
#   bash adapters/cursor/transform.sh /tmp/test-project --dry-run
#   bash adapters/cursor/transform.sh . --no-prompt --legacy-cursorrules
#   bash adapters/cursor/transform.sh . --uninstall              # revert install
#   bash adapters/cursor/transform.sh . --uninstall --force      # bypass safety checks
#
# Layer 2 transformation (per ADR-004 honesty + ADR-021):
#   core/universal-rules/*.md      →  <target>/.cursor/rules/*.mdc   (alwaysApply:true, modern Cursor format)
#   core/recipes/*.md (selected)   →  <target>/.cursor/rules/*.mdc   (path-scoped via globs:)
#   core/docs-templates/*.md       →  <target>/docs/*.md             (CURRENT_WORK, REMAINING_TASKS, etc.)
#   <synthesized>                  →  <target>/.cursorrules          (only if --legacy-cursorrules)
#   core/hooks/*.sh.template       →  Cursor-verified lifecycle/recipe subset only; Claude/Codex have additional verified guards
#   core/roles/*.md                →  <target>/.cursor/agents/*.md (native roles; saved Tier model — ADR-049)
#   adapters/claude/hookify-...    →  SKIPPED (Claude-only plugin)

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
  exec node "$CONDUCTOR_ROOT/bin/omniconductor.js" init --target=cursor "${ORIGINAL_ARGS[@]}"
fi

# ----- arg parsing --------------------------------------------------------

TARGET=""
RECIPES=""
MODE="full"
DRY_RUN="false"
NO_PROMPT="false"
UNINSTALL="false"
FORCE="false"
LEGACY_CURSORRULES="false"

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
    --legacy-cursorrules) LEGACY_CURSORRULES="true" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: bash adapters/cursor/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated list of recipes to install
  --mode=<m>            Install preset (ADR-044): full (default) | minimal (rules text +
                        docs only; no Reflector runtime) | strict (abort if .cursor/rules/
                        already has files) | recipes-only (ONLY the selected recipe .mdc
                        files; requires --recipes=) | reflector-only (self-improvement
                        loop standalone)
  --dry-run             Preview only — no files written
  --no-prompt           Skip all interactive prompts; apply sensible defaults (CI-safe)
  --legacy-cursorrules  ALSO emit a flat .cursorrules bundle alongside .cursor/rules/*.mdc
                        (for Cursor versions < 0.45 that only read .cursorrules).
                        Default off — modern .mdc format is the canonical surface.
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none. Customizations not in the
                        manifest are preserved.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering

What this adapter does NOT install (per ADR-004 honesty + ADR-021):
  - Unverified guard ports (CONDUCTOR emits only Cursor contracts verified by this adapter; Reflector is opt-in)
  - Claude-only hook contracts (Agent/Read tool names and Hookify rules)
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
  echo "Usage: bash adapters/cursor/transform.sh <target-project> [--recipes=...]" >&2
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
    < <(node "$CONDUCTOR_ROOT/bin/model-routing.js" resolve "$TARGET_ABS" cursor)
  [ "${#_conductor_models[@]}" -eq 3 ] || { echo "Error: valid Cursor Tier routing is required before installation." >&2; exit 2; }
  export CONDUCTOR_CURSOR_MODEL_TIER_1="${_conductor_models[0]}"
  export CONDUCTOR_CURSOR_MODEL_TIER_2="${_conductor_models[1]}"
  export CONDUCTOR_CURSOR_MODEL_TIER_3="${_conductor_models[2]}"
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
# Print body to stdout. Used by .mdc emit + legacy .cursorrules bundling.
strip_frontmatter() {
  local src="$1"
  /usr/bin/awk 'BEGIN{f=0} /^---$/{c++; if(c==2){f=1; next}} f==1' "$src"
}

# Derive a `description:` value from a markdown file. First H1 line, or filename.
derive_description() {
  local src="$1"
  local desc
  desc="$(strip_frontmatter "$src" | /usr/bin/grep -m1 '^# ' | /usr/bin/sed -e 's/^# *//' -e 's/"/\\"/g' | /usr/bin/head -c 120)"
  if [ -z "$desc" ]; then
    desc="$(basename "$src" .md)"
  fi
  printf '%s' "$desc"
}

# Derive `globs:` from a recipe's filename. Universal rules use ["**"].
# This is best-effort — the spec keeps it simple: each recipe maps to a sensible glob default.
# Adopter is expected to tighten globs after install if they want stricter scoping.
derive_globs_for_recipe() {
  local recipe_id="$1"
  case "$recipe_id" in
    monorepo)            echo '"apps/**", "packages/**"' ;;
    web-mobile-parity)   echo '"apps/web/**", "apps/mobile/**", "packages/shared/**"' ;;
    i18n)                echo '"**/i18n/**", "**/translations.ts", "**/locales/**"' ;;
    branch-strategy)     echo '"**"' ;;
    auto-mock-data)      echo '"**/*.sql", "**/migrations/**", "**/seeds/**"' ;;
    coding-conventions)  echo '"**/*.ts", "**/*.tsx"' ;;
    database-discipline) echo '"**/*.sql", "**/migrations/**"' ;;
    design-system)       echo '"**/*.tsx", "**/*.css", "**/*.scss"' ;;
    tdd)                 echo '"**/*.test.*", "**/*.spec.*", "**/__tests__/**", "**/e2e/**"' ;;
    *)                   echo '"**"' ;;
  esac
}

# Emit a `.mdc` file from a `core/*.md` source.
# emit_mdc <src> <dest> <description> <globs-yaml-array> <alwaysApply-bool>
emit_mdc() {
  local src="$1" dest="$2" desc="$3" globs="$4" always="$5"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest (alwaysApply=$always, globs=$globs)"
    return
  fi
  /bin/cat > "$dest" <<EOF
---
description: "$desc"
globs: [$globs]
alwaysApply: $always
---

EOF
  strip_frontmatter "$src" >> "$dest"
}

# backup_if_exists <dest>
# If <dest> is a regular file, copy it to <dest>.conductor-backup-<timestamp> before any
# downstream step overwrites it. Honors DRY_RUN. Idempotent across re-installs.
# Origin: ADR-019 (Claude adapter pattern, mirrored here per ADR-021).
backup_if_exists() {
  local dest="$1"
  if [ -f "$dest" ]; then
    local ts
    ts="$(/bin/date +%Y%m%d-%H%M%S)"
    local backup="${dest}.conductor-backup-${ts}"
    if [ "$DRY_RUN" = "true" ]; then
      log "would back up existing $dest -> $backup"
    else
      /bin/cp "$dest" "$backup"
      log "  backed up existing $dest -> $backup"
    fi
  fi
}

# ----- manifest tracking (ADR-020, mirrored per ADR-021) ------------------
#
# Format identical to Claude adapter's manifest. POSIX shell + sed only — no jq.

LEGACY_MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_PATH="$TARGET_ABS/.conductor/manifests/cursor.json"
MANIFEST_STAGE_PATH=""
MANIFEST_TS=""
MANIFEST_LAST_BACKUP=""

# shellcheck source=../../tools/manifest-safety.sh
. "$CONDUCTOR_ROOT/tools/manifest-safety.sh"

# The CLI supplies project-saved Tier choices. Direct transform.sh use keeps
# Cursor's native inheritance for backward compatibility.
CURSOR_TIER_1_MODEL="${CONDUCTOR_CURSOR_MODEL_TIER_1:-inherit}"
CURSOR_TIER_2_MODEL="${CONDUCTOR_CURSOR_MODEL_TIER_2:-inherit}"
CURSOR_TIER_3_MODEL="${CONDUCTOR_CURSOR_MODEL_TIER_3:-inherit}"
conductor_validate_cursor_model "$CURSOR_TIER_1_MODEL" "Cursor Tier 1 model" || exit 1
conductor_validate_cursor_model "$CURSOR_TIER_2_MODEL" "Cursor Tier 2 model" || exit 1
conductor_validate_cursor_model "$CURSOR_TIER_3_MODEL" "Cursor Tier 3 model" || exit 1
conductor_manifest_prepare "cursor"

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
    backup_if_exists "$MANIFEST_PATH"
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
  "adapter": "cursor",
  "mode": "$MODE",
  "install_timestamp": "$MANIFEST_TS",
  "conductor_root": "$CONDUCTOR_ROOT",
  "recipes_enabled": $recipes_json,
  "legacy_cursorrules": $LEGACY_CURSORRULES,
  "emitted_files": [
$entries
  ]
}
EOF
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  log "  wrote manifest $MANIFEST_PATH"
  conductor_manifest_publish_projection
}

backup_and_remember() {
  conductor_manifest_backup_and_remember "$1"
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

# ----- uninstall flow (mirrored from Claude adapter) ----------------------

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

  while IFS= read -r line; do
    case "$line" in
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

  # Try to clean up empty .cursor/rules and .cursor dirs left behind.
  # (children before parents so nested empties collapse in one pass)
  for d in .cursor/rules .cursor/skills/reflect .cursor/skills .cursor/agents .cursor .conductor/reflect .conductor; do
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
  log "         Delete .cursor/rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.mdc manually if desired."
}

if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Wizard fires when adopter signal is detected: existing .cursor/ OR existing .cursorrules.
# Otherwise (truly fresh target) wizard is skipped.

IS_ADOPTER_CASE="false"
if [ -d "$TARGET_ABS/.cursor" ] || [ -f "$TARGET_ABS/.cursorrules" ]; then
  IS_ADOPTER_CASE="true"
fi

detect_coexisting_frameworks

# --mode=strict: never write next to an existing rules surface (ADR-044).
if [ "$MODE" = "strict" ]; then
  if [ -d "$TARGET_ABS/.cursor/rules" ] && [ -n "$(/bin/ls -A "$TARGET_ABS/.cursor/rules" 2>/dev/null)" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/.cursor/rules/ already has files — strict mode aborts instead of writing next to an existing baseline." >&2
    echo "  Use --mode=full (timestamped backups + manifest-based restore), or move them first." >&2
    exit 3
  fi
  if [ -f "$TARGET_ABS/.cursorrules" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/.cursorrules already exists — strict mode never overwrites a rules surface (the legacy bundle step would touch it)." >&2
    exit 3
  fi
fi

# À-la-carte modes are non-interactive by design.
if [ "$MODE" != "full" ] && [ "$MODE" != "strict" ]; then
  NO_PROMPT="true"
fi

if [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
  echo ""
  echo "========================================================"
  echo " Welcome to CONDUCTOR setup (Cursor adapter)"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""

  printf "Detect existing rules? (y/N): "
  read -r _detect_answer
  if [ "$_detect_answer" = "y" ] || [ "$_detect_answer" = "Y" ]; then
    _existing_rules=$(ls "$TARGET_ABS/.cursor/rules/" 2>/dev/null | wc -l | /usr/bin/tr -d ' ')
    _has_legacy="no"
    [ -f "$TARGET_ABS/.cursorrules" ] && _has_legacy="yes"
    echo "  Found $_existing_rules .mdc rule files in .cursor/rules/, .cursorrules present: $_has_legacy"
  fi

  printf "Apply universal-rules? (Y/n): "
  read -r _apply_answer
  if [ "$_apply_answer" = "n" ] || [ "$_apply_answer" = "N" ]; then
    WIZARD_APPLY_RULES="false"
    echo "  Skipping universal-rules installation."
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

  printf "Also emit legacy .cursorrules bundle? (for Cursor < 0.45) (y/N): "
  read -r _legacy_answer
  if [ "$_legacy_answer" = "y" ] || [ "$_legacy_answer" = "Y" ]; then
    LEGACY_CURSORRULES="true"
    echo "  Will emit .cursorrules bundle."
  fi

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}, legacy_cursorrules=$LEGACY_CURSORRULES"
fi

# ----- step 1: universal rules -> .cursor/rules/*.mdc --------------------

init_manifest
conductor_install_project_profile

UNIVERSAL_RULES="workflow spec-as-you-go quality-gates operations meta-discipline"

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 1/4: universal-rules — skipped (--mode=$MODE is à la carte)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  log "Step 1/4: universal-rules → .cursor/rules/"
  mkdir_if_real "$TARGET_ABS/.cursor/rules"

  for rule in $UNIVERSAL_RULES; do
    src="$CORE_ROOT/universal-rules/$rule.md"
    dest="$TARGET_ABS/.cursor/rules/$rule.mdc"
    if [ ! -f "$src" ]; then
      echo "Warning: $src not found; skipping" >&2
      continue
    fi
    backup_and_remember "$dest"
    desc="$(derive_description "$src")"
    # All universal rules are always-loaded per core/universal-rules/README.md → alwaysApply: true
    emit_mdc "$src" "$dest" "$desc" '"**"' "true"
    record_emit ".cursor/rules/$rule.mdc" "core/universal-rules/$rule.md" "$MANIFEST_LAST_BACKUP"
  done
else
  log "Step 1/4: universal-rules — skipped (user opted out)"
fi

# ----- step 2: recipes (opt-in) -> .cursor/rules/*.mdc -------------------

log "Step 2/4: recipes (opt-in) → .cursor/rules/"
INSTALLED_RECIPES=""
if [ -n "$RECIPES" ]; then
  mkdir_if_real "$TARGET_ABS/.cursor/rules"
  IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
  for r in "${RECIPE_LIST[@]}"; do
    r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ -z "$r" ] && continue
    src="$CORE_ROOT/recipes/$r.md"
    dest="$TARGET_ABS/.cursor/rules/$r.mdc"
    if [ ! -f "$src" ]; then
      echo "Warning: recipe '$r' not found at $src; skipping" >&2
      continue
    fi
    backup_and_remember "$dest"
    desc="$(derive_description "$src")"
    globs="$(derive_globs_for_recipe "$r")"
    # Recipes are path-scoped (alwaysApply: false) — Cursor lazy-loads when a matching path is touched.
    emit_mdc "$src" "$dest" "$desc" "$globs" "false"
    record_emit ".cursor/rules/$r.mdc" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
    INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
  done
else
  log "  (no recipes selected — pass --recipes=name1,name2 to install)"
fi

# ----- step 2.5: optional legacy .cursorrules bundle ---------------------
#
# When --legacy-cursorrules is set, also emit a flat .cursorrules file at the project root that
# concatenates the universal-rules body + selected recipes. This is for Cursor versions < 0.45
# that don't yet read .cursor/rules/*.mdc. Modern Cursor reads BOTH (per ADR-021) — adopters can
# safely keep both surfaces during a transition.

if [ "$LEGACY_CURSORRULES" = "true" ] && [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then
  log "Step 2.5/4: legacy bundle → .cursorrules"
  CURSORRULES_DEST="$TARGET_ABS/.cursorrules"
  backup_and_remember "$CURSORRULES_DEST"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $CURSORRULES_DEST (universal + recipes bundle)"
  else
    {
      echo "# CONDUCTOR — .cursorrules (legacy bundle)"
      echo ""
      echo "> Auto-generated by adapters/cursor/transform.sh with --legacy-cursorrules."
      echo "> Modern Cursor (>= 0.45) reads .cursor/rules/*.mdc. This file is for older versions."
      echo "> Edit .cursor/rules/*.mdc as the source of truth; re-run the adapter to regenerate."
      echo ""
      if [ "$WIZARD_APPLY_RULES" = "true" ]; then
        for rule in $UNIVERSAL_RULES; do
          src="$CORE_ROOT/universal-rules/$rule.md"
          [ -f "$src" ] || continue
          echo "## Universal rule: $rule"
          echo ""
          strip_frontmatter "$src"
          echo ""
        done
      fi
      if [ -n "$INSTALLED_RECIPES" ]; then
        for r in $INSTALLED_RECIPES; do
          src="$CORE_ROOT/recipes/$r.md"
          [ -f "$src" ] || continue
          echo "## Recipe: $r"
          echo ""
          strip_frontmatter "$src"
          echo ""
        done
      fi
    } > "$CURSORRULES_DEST"
    record_emit ".cursorrules" "<synthesized>" "$MANIFEST_LAST_BACKUP"
    log "  wrote $CURSORRULES_DEST"
  fi
fi

# ---- Step 2.6: self-improvement runtime (only with --recipes=self-improvement) ----
if [ "$MODE" = "recipes-only" ] && [ -z "${INSTALLED_RECIPES// /}" ] && [ "$DRY_RUN" != "true" ]; then
  echo "Error: --mode=recipes-only resolved ZERO valid recipes from '--recipes=$RECIPES' — nothing to install (check the names)." >&2
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  exit 1
fi

# Native Cursor role profiles. These are emitted only with the complete runtime;
# minimal and à-la-carte modes remain intentionally text-only.
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  log "Step 2.5/4: native roles → .cursor/agents/"
  if [ "$DRY_RUN" != "true" ]; then
    /bin/mkdir -p "$TARGET_ABS/.cursor/agents"
    for role in planner reviewer code-reviewer builder helper designer scribe utility; do
      tier="$(conductor_role_difficulty_tier "$CORE_ROOT/roles/$role.md")" || exit 1
      tier_label="$(conductor_difficulty_label "$tier")" || exit 1
      case "$tier" in
        1) model="$CURSOR_TIER_1_MODEL" ;;
        2) model="$CURSOR_TIER_2_MODEL" ;;
        3) model="$CURSOR_TIER_3_MODEL" ;;
      esac
      case "$role" in
        planner) desc="Architecture, gap analysis, and trade-off planning without implementation."; readonly=true ;;
        reviewer) desc="Read-only pre-implementation review of plans, architecture, and tasks."; readonly=true ;;
        code-reviewer) desc="Read-only post-implementation review for correctness, security, regressions, and tests."; readonly=true ;;
        builder) desc="Primary implementation owner for cross-cutting or high-risk changes."; readonly=false ;;
        helper) desc="Focused implementation owner for bounded, independent changes."; readonly=false ;;
        designer) desc="UI and interaction implementation owner with design-system discipline."; readonly=false ;;
        scribe) desc="Documentation, changelog, index, and session-state maintenance."; readonly=false ;;
        utility) desc="Bounded Tier 3 lookup or trivial one-file edit; escalate immediately if scope grows."; readonly=false ;;
      esac
      ag="$TARGET_ABS/.cursor/agents/$role.md"
      backup_and_remember "$ag"
      { printf -- '---\nname: %s\ndescription: %s\nmodel: %s\nreadonly: %s\n---\n\n> CONDUCTOR difficulty contract: **%s**. The Tier is invariant; `model: %s` is the saved Cursor translation. Cursor may still apply account, plan, or administrator fallback.\n\n' "$role" "$desc" "$model" "$readonly" "$tier_label" "$model"; strip_frontmatter "$CORE_ROOT/roles/$role.md"; } > "$ag"
      record_emit ".cursor/agents/$role.md" "core/roles/$role.md" "$MANIFEST_LAST_BACKUP"
    done
  fi
fi

if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step 2.6/4: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    log "Step 2.6/4: self-improvement (Reflector) → hooks/skills/agents"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.cursor/skills/reflect" "$TARGET_ABS/.cursor/agents"
      conductor_install_trajectory_ignore
      # portable scripts
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
      # hook config — write only if absent (never clobber a user's hooks.json)
      hc="$TARGET_ABS/.cursor/hooks.json"
      hc_entry="$(conductor_manifest_entry_for_path ".cursor/hooks.json" 2>/dev/null || true)"
      if [ ! -f "$hc" ] || [ -n "$hc_entry" ]; then
        backup_and_remember "$hc"
        /bin/cat > "$hc" <<'HOOK'
{
  "version": 1,
  "hooks": {
    "stop": [ { "command": "bash \"$(git rev-parse --show-toplevel)/.conductor/reflect/trajectory-log.sh\"" } ]
  }
}
HOOK
        record_emit ".cursor/hooks.json" "<synthesized>" "$MANIFEST_LAST_BACKUP"
      else
        log "  WARNING: .cursor/hooks.json is user-owned — preserved; merge the CONDUCTOR stop hook manually"
      fi
      # /reflect skill (self-contained brief)
      sk="$TARGET_ABS/.cursor/skills/reflect/SKILL.md"
      backup_and_remember "$sk"
      { printf -- '---\nname: reflect\ndescription: Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only).\ndisable-model-invocation: true\n---\n\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; } > "$sk"
      record_emit ".cursor/skills/reflect/SKILL.md" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      # reflector agent (native persona) — strip core frontmatter, add Cursor frontmatter
      ag="$TARGET_ABS/.cursor/agents/reflector.md"
      backup_and_remember "$ag"
      tier="$(conductor_role_difficulty_tier "$CORE_ROOT/roles/reflector.md")" || exit 1
      tier_label="$(conductor_difficulty_label "$tier")" || exit 1
      case "$tier" in 1) model="$CURSOR_TIER_1_MODEL" ;; 2) model="$CURSOR_TIER_2_MODEL" ;; 3) model="$CURSOR_TIER_3_MODEL" ;; esac
      { printf -- '---\nname: reflector\ndescription: Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies.\nmodel: %s\nreadonly: true\n---\n\n> CONDUCTOR difficulty contract: **%s**. The Tier is invariant; `model: %s` is the saved Cursor translation. Cursor may still apply account, plan, or administrator fallback.\n\n' "$model" "$tier_label" "$model"; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; } > "$ag"
      record_emit ".cursor/agents/reflector.md" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
    fi
    ;;
esac

# ----- step 3: docs templates --------------------------------------------

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 3/4: docs templates — skipped (--mode=$MODE is à la carte; docs ship with full/minimal)"
else
log "Step 3/4: docs templates → docs/"
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

# ----- step 4: completion summary ----------------------------------------

log "Step 4/4: activation reminder"
echo ""
echo "========================================================"
echo " Done."
echo "  Target: $TARGET_ABS"
echo "  Adapter: cursor"
echo "  Mode: $MODE"
if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  echo "  Universal rules: 0 (à la carte)"
else
  echo "  Universal rules: 5 (.cursor/rules/*.mdc, alwaysApply:true)"
fi
echo "  Recipes installed:${INSTALLED_RECIPES:- (none)}"
if [ "$LEGACY_CURSORRULES" = "true" ]; then
  echo "  Legacy .cursorrules bundle: emitted"
fi
echo ""
echo " Runtime / capability boundary:"
echo "  - Hooks: only verified Cursor contracts are emitted; the Reflector hook is opt-in (ADR-032/045)."
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
echo "  - Native roles: 8 profiles in .cursor/agents/."
else
  echo "  - Native roles: omitted by --mode=$MODE."
fi
echo "  - Hookify rule templates: Claude-only plugin."
echo ""
echo " Activation: reload Cursor window (Cmd/Ctrl+Shift+P → 'Developer: Reload Window')."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open $TARGET_ABS in Cursor."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. Verify rule loading: open the Cursor settings → Rules tab → confirm 5 universal + recipes shown."
echo "  4. Tighten recipe globs if needed (.cursor/rules/<recipe>.mdc has a sensible default)."
