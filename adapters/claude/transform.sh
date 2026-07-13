#!/usr/bin/env bash
#
# CONDUCTOR — Claude Code adapter transform.sh
#
# Reads core/ assets and writes them into a target project as native Claude Code
# files: .claude/agents/, .claude/rules/, .claude/hooks/, CLAUDE.md, docs/*.
#
# Usage:
#   bash adapters/claude/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--measure-baseline] [--no-prompt] [--check-anti-patterns]
#   bash adapters/claude/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/claude/transform.sh ~/Projects/my-app
#   bash adapters/claude/transform.sh ~/Projects/my-app --recipes=i18n,monorepo,coding-conventions
#   bash adapters/claude/transform.sh /tmp/test-project --dry-run
#   bash adapters/claude/transform.sh . --measure-baseline
#   bash adapters/claude/transform.sh . --no-prompt --recipes=coding-conventions
#   bash adapters/claude/transform.sh . --uninstall              # revert install
#   bash adapters/claude/transform.sh . --uninstall --dry-run    # preview revert
#   bash adapters/claude/transform.sh . --uninstall --force      # bypass safety checks
#
# Layer 2 transformation:
#   core/universal-rules/*.md     →  <target>/.claude/rules/*.md   (paths frontmatter injected)
#   core/roles/{6 files}.md       →  <target>/.claude/agents/*.md  (Claude name/description/model frontmatter)
#   core/recipes/*.md (selected)  →  <target>/.claude/rules/*.md
#   core/hooks/*.sh.template      →  <target>/.claude/hooks/*.sh   (placeholder substitution + chmod +x)
#   core/docs-templates/*.md      →  <target>/docs/*.md            (CURRENT_WORK, REMAINING_TASKS, etc.)
#   <synthesized>                 →  <target>/CLAUDE.md            (orchestrator manual + role table)

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
  exec node "$CONDUCTOR_ROOT/bin/omniconductor.js" init --target=claude "${ORIGINAL_ARGS[@]}"
fi

# ----- arg parsing --------------------------------------------------------

TARGET=""
RECIPES=""
MODE="full"
DRY_RUN="false"
MEASURE_BASELINE="false"
NO_PROMPT="false"
CHECK_ANTI_PATTERNS="false"
UNINSTALL="false"
FORCE="false"

# Onboarding wizard state (set during interactive flow or --no-prompt defaults)
WIZARD_APPLY_RULES="true"
WIZARD_SHOW_ANTI_PATTERNS="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --recipes=*) RECIPES="${1#--recipes=}" ;;
    --mode=*)    MODE="${1#--mode=}" ;;
    --dry-run)   DRY_RUN="true" ;;
    --measure-baseline) MEASURE_BASELINE="true" ;;
    --no-prompt) NO_PROMPT="true" ;;
    --check-anti-patterns) CHECK_ANTI_PATTERNS="true"; WIZARD_SHOW_ANTI_PATTERNS="true" ;;
    --uninstall|--rollback) UNINSTALL="true" ;;
    --force) FORCE="true" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: bash adapters/claude/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated list of recipes to install
  --mode=<m>            Install preset (ADR-044): full (default) | minimal (rules + recipes
                        text + docs + CLAUDE.md; no agents/hooks/hookify) | strict (abort if
                        CLAUDE.md exists) | recipes-only (ONLY the selected recipe rule files;
                        requires --recipes=) | reflector-only (self-improvement loop standalone:
                        recipe + reflector agent + trajectory hook + /reflect)
  --dry-run             Preview only — no files written
  --measure-baseline    After install, measure cache token baseline (opt-in)
  --no-prompt           Skip all interactive prompts; apply sensible defaults (CI-safe)
  --check-anti-patterns Print anti-pattern catalog and pause 5 seconds
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none. Customizations not in the
                        manifest are preserved.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering
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
  echo "Usage: bash adapters/claude/transform.sh <target-project> [--recipes=...]" >&2
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
TOOLS_ROOT="$CONDUCTOR_ROOT/tools"
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
    < <(node "$CONDUCTOR_ROOT/bin/model-routing.js" resolve "$TARGET_ABS" claude)
  [ "${#_conductor_models[@]}" -eq 3 ] || { echo "Error: valid Claude Tier routing is required before installation." >&2; exit 2; }
  export CONDUCTOR_CLAUDE_MODEL_TIER_1="${_conductor_models[0]}"
  export CONDUCTOR_CLAUDE_MODEL_TIER_2="${_conductor_models[1]}"
  export CONDUCTOR_CLAUDE_MODEL_TIER_3="${_conductor_models[2]}"
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

write_file() {
  # write_file <dest> <content>
  local dest="$1"
  shift
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest ($(echo "$*" | /usr/bin/wc -c | /usr/bin/tr -d ' ') bytes)"
  else
    /bin/cat > "$dest" <<EOF
$*
EOF
  fi
}

copy_with_paths_frontmatter() {
  # copy_with_paths_frontmatter <src> <dest> <paths-glob>
  local src="$1" dest="$2" paths="$3"
  if [ "$DRY_RUN" = "true" ]; then
    log "would copy $src -> $dest with paths: $paths"
    return
  fi
  # Inject paths frontmatter at top of file.
  /bin/cat > "$dest" <<EOF
---
paths:
  - "$paths"
---

EOF
  /bin/cat "$src" >> "$dest"
}

substitute_template() {
  # substitute_template <src> <dest>
  # Replaces ${PLACEHOLDER} with environment values; falls back to defaults documented in template.
  local src="$1" dest="$2"
  if [ "$DRY_RUN" = "true" ]; then
    log "would compile template $src -> $dest"
    return
  fi
  /usr/bin/sed \
    -e "s|\${CONDUCTOR_PROJECT_DIR}|${TARGET_ABS}|g" \
    -e "s|\${CONDUCTOR_PROTECTED_BRANCHES}|develop\|main\|release|g" \
    -e "s|\${CONDUCTOR_DIRECT_PUSH_BRANCHES}|develop\|main\|release\|HEAD|g" \
    -e "s|\${CONDUCTOR_FORBIDDEN_SUBAGENT_TYPES}|general-purpose|g" \
    -e "s|\${CONDUCTOR_COOLDOWN_SECONDS}|1800|g" \
    -e "s|\${CONDUCTOR_STALE_MINUTES}|30|g" \
    -e "s|\${CONDUCTOR_SOURCE_GLOB}|ts\|tsx|g" \
    -e "s|\${CONDUCTOR_CURRENT_WORK_PATH}|${CONDUCTOR_CURRENT_WORK_PATH:-docs/CURRENT_WORK.md}|g" \
    -e "s|\${CONDUCTOR_SPEC_PATH}|docs/specs/|g" \
    -e "s|\${CONDUCTOR_REVIEW_COMMAND}|/code-review|g" \
    "$src" > "$dest"
  chmod +x "$dest"
}

substitute_hookify_template() {
  # substitute_hookify_template <src> <dest>
  # Variant of substitute_template for hookify .local.md files. Same placeholder vocabulary,
  # but the output is a Markdown rule definition (NOT executable), so chmod +x is omitted.
  # Adds hookify-specific placeholders (CURRENT_WORK_PATH, REMAINING_TASKS_PATH, PROJECT_NAME)
  # used only by adapters/claude/hookify-templates/*.local.md.template.
  local src="$1" dest="$2"
  if [ "$DRY_RUN" = "true" ]; then
    log "would compile hookify template $src -> $dest"
    return
  fi
  # SERVER_SECRET_PATTERN default uses generic credential env-var name conventions (overridable), not a vendor reference.
  # It is intentionally narrow (matches *_SECRET_KEY / *_PRIVATE_KEY / SERVICE_ROLE etc., NOT bare SECRET / API_KEY / JWT_SECRET)
  # to avoid false positives on safe client vars; adopters broaden it via the CONDUCTOR_SERVER_SECRET_PATTERN env var.
  /usr/bin/sed \
    -e "s|\${CONDUCTOR_PROJECT_DIR}|${TARGET_ABS}|g" \
    -e "s|\${CONDUCTOR_PROTECTED_BRANCHES}|${CONDUCTOR_PROTECTED_BRANCHES:-main\|release}|g" \
    -e "s|\${CONDUCTOR_CURRENT_WORK_PATH}|${CONDUCTOR_CURRENT_WORK_PATH:-docs/CURRENT_WORK.md}|g" \
    -e "s|\${CONDUCTOR_REMAINING_TASKS_PATH}|${CONDUCTOR_REMAINING_TASKS_PATH:-docs/REMAINING_TASKS.md}|g" \
    -e "s|\${CONDUCTOR_SOURCE_GLOB}|${CONDUCTOR_SOURCE_GLOB:-apps/.*\\\\.(ts\|tsx)\$}|g" \
    -e "s|\${CONDUCTOR_CLIENT_GLOB}|${CONDUCTOR_CLIENT_GLOB:-(src/(components\|hooks\|pages\|ui)\|public)/.*\\\\.(ts\|tsx\|js\|jsx)\$}|g" \
    -e "s|\${CONDUCTOR_SERVER_SECRET_PATTERN}|${CONDUCTOR_SERVER_SECRET_PATTERN:-(SERVICE_ROLE_KEY\|SERVICE_ROLE\|_SECRET_KEY\|_PRIVATE_KEY\|ADMIN_API_KEY\|SECRET_ACCESS_KEY)}|g" \
    -e "s|\${CONDUCTOR_PROJECT_NAME}|${CONDUCTOR_PROJECT_NAME:-your-project}|g" \
    -e "s|\${CONDUCTOR_REVIEW_COMMAND}|/code-review|g" \
    "$src" > "$dest"
}

# Read a single metric line from measure-tokens.sh output.
# Usage: extract_metric <label-substring> <output-text>
extract_metric() {
  local label="$1" text="$2"
  echo "$text" | /usr/bin/grep "$label" | /usr/bin/awk -F': ' '{print $2}' | /usr/bin/tr -d ' '
}

# backup_if_exists <dest>
# If <dest> is a regular file, copy it to <dest>.conductor-backup-<timestamp> before any
# downstream step overwrites it. Honors DRY_RUN (logs only). Idempotent across re-installs:
# every invocation creates a fresh timestamped backup, so two installs in the same second
# still differ by file (the second uses an incremented suffix only if the first second
# happens to collide). The timestamp resolution is 1s; collision in <1s is acceptable since
# transform.sh runs sequentially.
#
# Origin: ADR-019 (audit P0b — silent-overwrite risk on universal-rules / docs-templates /
# hooks). Existing CLAUDE.md backup pattern generalized to every emit target.
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

# ----- manifest tracking (ADR-020, audit P1b) ----------------------------
#
# Each install records every emitted file into <target>/.conductor-manifest.json so a future
# `--uninstall` invocation can revert with surgical precision (restore backups when present,
# delete Conductor-emitted-only files when not, leave adopter customizations untouched).
#
# Manifest is generated using only POSIX shell (no jq dependency). Format:
#
#   {
#     "version": "v<CONDUCTOR package.json version>",
#     "install_timestamp": "2026-05-10T12:00:00Z",
#     "conductor_root": "/abs/path/to/conductor",
#     "recipes_enabled": ["monorepo", "i18n"],
#     "emitted_files": [
#       { "path": ".claude/rules/workflow.md", "source": "core/universal-rules/workflow.md",
#         "had_backup": true,  "backup_path": ".claude/rules/workflow.md.conductor-backup-20260510-120000" },
#       ...
#     ]
#   }
#
# Implementation notes:
#   - During install: helper appends to a temp staging file as each emit succeeds;
#     finalize_manifest() wraps it into well-formed JSON at the end.
#   - During uninstall: load_manifest() parses the JSON line-by-line using grep/sed
#     (no nested objects beyond two levels — flat enough for shell parsing).
#   - Manifest itself is backed up on re-install (the helper calls backup_if_exists
#     on the manifest path before writing fresh).

LEGACY_MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_PATH="$TARGET_ABS/.conductor/manifests/claude.json"
MANIFEST_STAGE_PATH=""   # set by init_manifest()
MANIFEST_TS=""           # ISO-8601 install timestamp (set by init_manifest)
MANIFEST_LAST_BACKUP=""  # backup_if_exists writes the backup path here; emit helpers read it

# shellcheck source=../../tools/manifest-safety.sh
. "$CONDUCTOR_ROOT/tools/manifest-safety.sh"
conductor_manifest_prepare "claude"

init_manifest() {
  # Called once at install start (after wizard, before any emit).
  if [ "$DRY_RUN" = "true" ]; then
    log "would init manifest staging at $MANIFEST_PATH.staging"
    return
  fi
  MANIFEST_TS="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  MANIFEST_STAGE_PATH="$MANIFEST_PATH.staging"
  conductor_manifest_init_stage
}

# record_emit <relative-path> <source-relative-to-conductor-root> [<backup-path-or-empty>]
# Append one emitted-file entry to the staging file. Skipped under DRY_RUN.
record_emit() {
  if [ "$DRY_RUN" = "true" ] || [ "$UNINSTALL" = "true" ]; then
    return
  fi
  local relpath="$1" src="$2" backup="${3:-}"
  local had_backup="false"
  [ -n "$backup" ] && had_backup="true"
  # Escape backslashes and double quotes for JSON.
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
  # Called at the end of install. Wraps staged entries into JSON, backs up old manifest,
  # writes the new one.
  if [ "$DRY_RUN" = "true" ]; then
    log "would finalize manifest -> $MANIFEST_PATH"
    return
  fi
  [ -z "$MANIFEST_STAGE_PATH" ] && return
  [ -f "$MANIFEST_STAGE_PATH" ] || return

  # Back up existing manifest before overwrite (idempotent re-install).
  if [ -f "$MANIFEST_PATH" ]; then
    backup_if_exists "$MANIFEST_PATH"
  fi

  # Build recipes_enabled JSON array.
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

  # Strip trailing comma from last staged line for valid JSON.
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
  "adapter": "claude",
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

# Wrappers around backup_if_exists / cp / write that also remember the backup path so the
# next record_emit() call can reference it. Keeps emit-step changes minimal.
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

# ----- uninstall flow (ADR-020, audit P1b) --------------------------------
#
# Logic:
#   1. Load manifest (require it unless --force).
#   2. Safety checks: warn on active worktrees, missing .git, etc. Unless --force, abort.
#   3. For each emitted file:
#       had_backup=true  → restore backup, delete backup file
#       had_backup=false → delete file (truly fresh install path)
#   4. Delete manifest itself (always last).
#   5. DRY_RUN logs each action without performing it.

do_uninstall() {
  log "uninstall mode (target: $TARGET_ABS)"

  # Safety: missing manifest.
  if [ ! -f "$MANIFEST_PATH" ]; then
    if [ "$FORCE" = "true" ]; then
      log "WARNING: no manifest at $MANIFEST_PATH — proceeding under --force (will only delete legacy backups it can find)"
      uninstall_legacy_scan
      return 0
    fi
    echo "Error: no manifest at $MANIFEST_PATH." >&2
    echo "  This target was either installed by a pre-manifest version or has already been uninstalled." >&2
    echo "  Re-run with --force to scan for legacy .conductor-backup-* files and delete them anyway:" >&2
    echo "    bash $0 $TARGET_ABS --uninstall --force" >&2
    exit 1
  fi

  # Safety: active git worktree mid-rebase / merge.
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

  # Parse manifest. Each emitted_files entry is one line with:
  #   {"path": "...", "source": "...", "had_backup": true|false, "backup_path": "..."},
  log "loading manifest entries..."
  local entries_count=0
  local restored=0
  local deleted=0
  local missing=0
  local preserved=0

  # Iterate manifest entries by line. Tolerate trailing comma absence on last entry.
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

  # Remove the manifest itself + its own backups (.conductor-manifest.json.conductor-backup-*).
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

  # Try to clean up empty dirs left behind (children before parents). Includes the
  # self-improvement gate dir .conductor/reflect/ — leaving it would keep the
  # always-on trajectory hook active after uninstall.
  for d in .claude/rules .claude/agents .claude/hooks .claude/commands .conductor/reflect .conductor .claude; do
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

# Fallback when --force --uninstall is invoked with no manifest.
# Conservatively scans for *.conductor-backup-* files and offers to delete them.
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
  log "WARNING: legacy mode does not delete Conductor-emitted source files (no manifest to identify them)."
  log "         Delete .claude/rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.md"
  log "         and .claude/agents/{planner,builder,reviewer,code-reviewer,helper,designer,scribe,utility}.md manually if desired."
}

# Dispatch uninstall path before the install steps.
if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Wizard semantic (ADR-019, audit P1a):
#   - Truly fresh target (no `.claude/` AND no `CLAUDE.md`)  → wizard SKIP, autopilot install.
#   - Adopter case (`.claude/` OR `CLAUDE.md` already present) → wizard FIRE, walk the user
#     through detect/apply/recipes/baseline/anti-pattern decisions before any emit.
#   - --no-prompt always skips wizard regardless of state (CI / scripted installs).
#   - --dry-run always skips wizard (no interactive prompts in preview mode).
#
# Rationale: the most common adopter (existing Claude Code project with `.claude/agents/` or
# a hand-written `CLAUDE.md`) was previously bypassing wizard entirely and getting default
# behavior. Inverting the trigger surfaces the choice points where overwrite/backup matters
# most.

IS_ADOPTER_CASE="false"
if [ -d "$TARGET_ABS/.claude" ] || [ -f "$TARGET_ABS/CLAUDE.md" ]; then
  IS_ADOPTER_CASE="true"
fi

detect_coexisting_frameworks

# --mode=strict: never overwrite an existing baseline, even with a backup (ADR-044).
if [ "$MODE" = "strict" ]; then
  if [ -f "$TARGET_ABS/CLAUDE.md" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/CLAUDE.md already exists — strict mode aborts instead of overwriting a baseline." >&2
    echo "  Use --mode=full (timestamped backup + manifest-based restore), or move the file first." >&2
    exit 3
  fi
  if [ -d "$TARGET_ABS/.claude/rules" ] && [ -n "$(/bin/ls -A "$TARGET_ABS/.claude/rules" 2>/dev/null)" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/.claude/rules/ already has files — strict mode never writes next to an existing rules surface." >&2
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
  echo " Welcome to CONDUCTOR setup"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""

  # 1. Detect existing rules?
  printf "Detect existing rules? (y/N): "
  read -r _detect_answer
  if [ "$_detect_answer" = "y" ] || [ "$_detect_answer" = "Y" ]; then
    _existing_rules=$(ls "$TARGET_ABS/.claude/rules/" 2>/dev/null | wc -l | /usr/bin/tr -d ' ')
    _existing_agents=$(ls "$TARGET_ABS/.claude/agents/" 2>/dev/null | wc -l | /usr/bin/tr -d ' ')
    echo "  Found $_existing_rules rule files, $_existing_agents agent files in .claude/"
  fi

  # 2. Apply universal-rules + roles?
  printf "Apply universal-rules + roles? (Y/n): "
  read -r _apply_answer
  if [ "$_apply_answer" = "n" ] || [ "$_apply_answer" = "N" ]; then
    WIZARD_APPLY_RULES="false"
    echo "  Skipping universal-rules + roles installation."
  fi

  # 3. Select recipes
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

  # 4. Measure cache baseline?
  printf "Measure cache baseline? (recommended) (Y/n): "
  read -r _baseline_answer
  if [ "$_baseline_answer" = "n" ] || [ "$_baseline_answer" = "N" ]; then
    MEASURE_BASELINE="false"
  else
    MEASURE_BASELINE="true"
    echo "  Baseline measurement enabled."
  fi

  # 5. Show anti-pattern catalog?
  printf "Show anti-pattern catalog? (recommended) (Y/n): "
  read -r _antipattern_answer
  if [ "$_antipattern_answer" = "n" ] || [ "$_antipattern_answer" = "N" ]; then
    WIZARD_SHOW_ANTI_PATTERNS="false"
  else
    WIZARD_SHOW_ANTI_PATTERNS="true"
    CHECK_ANTI_PATTERNS="true"
  fi

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}, baseline=$MEASURE_BASELINE, anti-patterns=$CHECK_ANTI_PATTERNS"
fi

# ----- step 1: universal rules -------------------------------------------

# Validate all advertised model translations before any managed file is emitted.
# Uninstall returned above, so a stale/invalid install override cannot block cleanup.
CLAUDE_TIER_1_MODEL="${CONDUCTOR_CLAUDE_MODEL_TIER_1:-opus}"
CLAUDE_TIER_2_MODEL="${CONDUCTOR_CLAUDE_MODEL_TIER_2:-sonnet}"
CLAUDE_TIER_3_MODEL="${CONDUCTOR_CLAUDE_MODEL_TIER_3:-haiku}"
conductor_validate_model_slug "$CLAUDE_TIER_1_MODEL" "Claude Tier 1 model" || exit 1
conductor_validate_model_slug "$CLAUDE_TIER_2_MODEL" "Claude Tier 2 model" || exit 1
conductor_validate_model_slug "$CLAUDE_TIER_3_MODEL" "Claude Tier 3 model" || exit 1

# Initialize manifest before any emit happens.
init_manifest
conductor_install_project_profile

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 1/6: universal-rules — skipped (--mode=$MODE is à la carte)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  log "Step 1/6: universal-rules → .claude/rules/"
  mkdir_if_real "$TARGET_ABS/.claude/rules"

  for rule in workflow spec-as-you-go quality-gates operations meta-discipline; do
    src="$CORE_ROOT/universal-rules/$rule.md"
    dest="$TARGET_ABS/.claude/rules/$rule.md"
    if [ ! -f "$src" ]; then
      echo "Warning: $src not found; skipping" >&2
      continue
    fi
    backup_and_remember "$dest"
    copy_with_paths_frontmatter "$src" "$dest" "**"
    record_emit ".claude/rules/$rule.md" "core/universal-rules/$rule.md" "$MANIFEST_LAST_BACKUP"
  done
else
  log "Step 1/6: universal-rules — skipped (user opted out)"
fi

# ----- step 2: roles -----------------------------------------------------

if [ "$MODE" = "minimal" ]; then
  log "Step 2/6: roles — skipped (--mode=minimal ships text only)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  log "Step 2/6: roles → .claude/agents/"
  # À la carte without self-improvement must not leave an empty .claude/agents/.
  if [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then
    mkdir_if_real "$TARGET_ABS/.claude/agents"
  else
    case ",$RECIPES," in *",self-improvement,"*) mkdir_if_real "$TARGET_ABS/.claude/agents" ;; esac
  fi

  # Claude family aliases intentionally track the provider's current model in
  # each family. Exact version pins remain opt-in and never alter difficulty.
  # Map each universal role's portable difficulty to Claude-native frontmatter.
  declare_agent() {
    # declare_agent <role> <description>
    local role="$1" desc="$2" tier model tier_label
    local src="$CORE_ROOT/roles/$role.md"
    local dest="$TARGET_ABS/.claude/agents/$role.md"
    [ -f "$src" ] || { echo "Warning: $src not found; skipping" >&2; return; }
    tier="$(conductor_role_difficulty_tier "$src")" || exit 1
    tier_label="$(conductor_difficulty_label "$tier")" || exit 1
    case "$tier" in
      1) model="$CLAUDE_TIER_1_MODEL" ;;
      2) model="$CLAUDE_TIER_2_MODEL" ;;
      3) model="$CLAUDE_TIER_3_MODEL" ;;
    esac
    backup_and_remember "$dest"
    if [ "$DRY_RUN" = "true" ]; then
      log "would write Claude agent $dest (model=$model)"
      return
    fi
    /bin/cat > "$dest" <<EOF
---
name: $role
description: $desc
model: $model
---

> CONDUCTOR difficulty contract: **$tier_label**. The task triggers in
> meta-discipline.md section 6 are authoritative; the model alias is only this
> adapter's current translation.

EOF
    # Strip the universal CONDUCTOR frontmatter from src body, append the rest.
    /usr/bin/awk 'BEGIN{f=0} /^---$/{c++; if(c==2){f=1; next}} f==1' "$src" >> "$dest"
    record_emit ".claude/agents/$role.md" "core/roles/$role.md" "$MANIFEST_LAST_BACKUP"
  }

  if [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then
  declare_agent planner  "Architecture, gap analysis, ADRs, trade-off decisions. No implementation code."
  declare_agent builder  "Multi-file or cross-cutting code implementation (3+ files)."
  declare_agent reviewer "Plan validation before implementation. Read-only gatekeeper."
  declare_agent code-reviewer "Post-implementation correctness, security, regression, and test review. Read-only."
  declare_agent helper   "Single-file or 1-2-file work where the pattern is established."
  declare_agent designer "UI / UX implementation. Visual components, design tokens, accessibility."
  declare_agent scribe   "Documentation sync after implementation. No code edits."
  declare_agent utility  "Bounded Tier 3 lookups, one-file renames, and trivial text edits."
  else
    log "  (à la carte — the 8 universal role agents skipped)"
  fi
  case ",$RECIPES," in *",self-improvement,"*)
    declare_agent reflector "Reads session trajectories; proposes atomic lesson deltas for human approval. No code, no auto-apply." ;;
  esac
else
  log "Step 2/6: roles — skipped (user opted out)"
fi

# ----- step 3: recipes (opt-in) ------------------------------------------

log "Step 3/6: recipes (opt-in) → .claude/rules/"
RECIPES_EMITTED=0
if [ -n "$RECIPES" ]; then
  mkdir_if_real "$TARGET_ABS/.claude/rules"
  IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
  for r in "${RECIPE_LIST[@]}"; do
    src="$CORE_ROOT/recipes/$r.md"
    dest="$TARGET_ABS/.claude/rules/$r.md"
    if [ ! -f "$src" ]; then
      echo "Warning: recipe '$r' not found at $src; skipping" >&2
      continue
    fi
    backup_and_remember "$dest"
    copy_with_paths_frontmatter "$src" "$dest" "**"
    record_emit ".claude/rules/$r.md" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
    RECIPES_EMITTED=$((RECIPES_EMITTED + 1))
  done
else
  log "  (no recipes selected — pass --recipes=name1,name2 to install)"
fi
if [ "$MODE" = "recipes-only" ] && [ "${RECIPES_EMITTED:-0}" -eq 0 ] && [ "$DRY_RUN" != "true" ]; then
  echo "Error: --mode=recipes-only resolved ZERO valid recipes from '--recipes=$RECIPES' — nothing to install (check the names)." >&2
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  exit 1
fi

# ----- step 4: hooks + settings.json -------------------------------------

INSTALLED_HOOKS=()

if [ "$MODE" = "minimal" ]; then
  log "Step 4/6: hooks + settings.json — skipped (--mode=minimal ships text only)"
elif [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  # À la carte: only the Reflector's trajectory hook (when self-improvement is selected).
  case ",$RECIPES," in
    *",self-improvement,"*)
      log "Step 4/6: hooks — à la carte: stop-trajectory-log only (--mode=$MODE)"
      mkdir_if_real "$TARGET_ABS/.claude/hooks"
      src="$CORE_ROOT/hooks/stop-trajectory-log.sh.template"
      dest="$TARGET_ABS/.claude/hooks/stop-trajectory-log.sh"
      if [ -f "$src" ]; then
        backup_and_remember "$dest"
        substitute_template "$src" "$dest"
        record_emit ".claude/hooks/stop-trajectory-log.sh" "core/hooks/stop-trajectory-log.sh.template" "$MANIFEST_LAST_BACKUP"
      fi
      SETTINGS_PATH="$TARGET_ABS/.claude/settings.json"
      if [ -f "$SETTINGS_PATH" ]; then
        log "  $SETTINGS_PATH exists — add the Stop hook manually: \"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-trajectory-log.sh"
      elif [ "$DRY_RUN" = "true" ]; then
        log "would write minimal $SETTINGS_PATH (trajectory Stop hook only)"
      else
        /bin/cat > "$SETTINGS_PATH" <<'MINSETTINGS_EOF'
{
  "$comment": "Minimal project settings generated by CONDUCTOR (à-la-carte mode): registers only the Reflector trajectory Stop hook.",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-trajectory-log.sh" }
        ]
      }
    ]
  }
}
MINSETTINGS_EOF
        log "  wrote minimal $SETTINGS_PATH (trajectory Stop hook only)"
        record_emit ".claude/settings.json" "<synthesized:minimal>" ""
      fi
      ;;
    *)
      log "Step 4/6: hooks — skipped (--mode=$MODE without self-improvement)"
      ;;
  esac
else
log "Step 4/6: hooks → .claude/hooks/"
mkdir_if_real "$TARGET_ABS/.claude/hooks"

# Core hooks (always emitted when template exists). Optional hooks (cache-hit baseline, large-file
# read guard) emit only if their templates are present in the CONDUCTOR core/ tree, allowing the
# adapter to remain forward-compatible with P1.7 work in progress.
for hook in pretool-agent-routing stop-session-log-check stop-r6-review-check stop-cache-hit-baseline-check pretool-large-file-read-guard pretool-commit-current-work-check pretool-commit-test-coverage-check stop-trajectory-log stop-git-hygiene-guard pretool-loop-guard; do
  src="$CORE_ROOT/hooks/$hook.sh.template"
  dest="$TARGET_ABS/.claude/hooks/$hook.sh"
  if [ ! -f "$src" ]; then
    log "  hook template $hook not found in core/hooks — skipping"
    continue
  fi
  backup_and_remember "$dest"
  substitute_template "$src" "$dest"
  record_emit ".claude/hooks/$hook.sh" "core/hooks/$hook.sh.template" "$MANIFEST_LAST_BACKUP"
  INSTALLED_HOOKS+=("$hook")
done

# Emit .claude/settings.json with permissions allowlist + hook registry. Pre-approves
# read-only / safe Bash commands to reduce permission-prompt friction.
# Mutating commands are intentionally excluded.
SETTINGS_PATH="$TARGET_ABS/.claude/settings.json"
if [ -f "$SETTINGS_PATH" ]; then
  log "  $SETTINGS_PATH exists — leaving in place (project may have local customizations)"
elif [ "$DRY_RUN" = "true" ]; then
  log "would write $SETTINGS_PATH with permissions.allow + hooks registry"
else
  /bin/cat > "$SETTINGS_PATH" <<'SETTINGS_EOF'
{
  "$comment": "Project-level Claude Code settings, generated by CONDUCTOR Claude adapter. Personal settings go in settings.local.json. Permissions allowlist pre-approves read-only/safe Bash commands; mutating commands deliberately omitted.",
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git show:*)",
      "Bash(git branch:*)",
      "Bash(grep:*)",
      "Bash(rg:*)",
      "Bash(find:*)",
      "Bash(ls:*)",
      "Bash(wc:*)",
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(pwd)",
      "Bash(which:*)",
      "Bash(gh pr view:*)",
      "Bash(gh pr list:*)",
      "Bash(gh pr diff:*)",
      "Bash(gh repo view:*)",
      "Bash(npm ls:*)",
      "Bash(npx tsc --noEmit:*)",
      "Bash(bash -n:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool-agent-routing.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool-commit-current-work-check.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool-commit-test-coverage-check.sh" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool-large-file-read-guard.sh" }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool-loop-guard.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-session-log-check.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-r6-review-check.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-cache-hit-baseline-check.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-trajectory-log.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-git-hygiene-guard.sh" }
        ]
      }
    ]
  }
}
SETTINGS_EOF
  log "  wrote $SETTINGS_PATH ($(printf '%s' "${INSTALLED_HOOKS[*]}" | /usr/bin/wc -w | /usr/bin/tr -d ' ') hook(s) installed in .claude/hooks; settings.json registers 10 core hooks: 5 PreToolUse + 5 Stop)"
  record_emit ".claude/settings.json" "<synthesized>" ""
fi
fi

# ----- step 4.5: hookify rule templates ----------------------------------
#
# Hookify (a Claude Code plugin) reads .claude/hookify.<name>.local.md files at runtime and
# injects warning/blocker messages on Bash, file-edit, prompt, and stop events. This step copies
# the framework-curated universal hookify templates into the consumer project. Existing files are
# never overwritten — adopter customizations always win.
#
# Origin: 2026-05-09 reference-adopter sync (hookify rule port). See docs/DESIGN-DECISIONS.md ADR-018.
# Forward-compat: silent skip if the hookify-templates directory is empty or missing.

HOOKIFY_TEMPLATE_DIR="$CONDUCTOR_ROOT/adapters/claude/hookify-templates"
if [ "$MODE" != "full" ] && [ "$MODE" != "strict" ]; then
  log "Step 4.5/6: hookify rules — skipped (--mode=$MODE)"
elif [ -d "$HOOKIFY_TEMPLATE_DIR" ]; then
  log "Step 4.5/6: hookify rules → .claude/hookify.*.local.md"
  HOOKIFY_INSTALLED=0
  HOOKIFY_SKIPPED=0
  for tpl in "$HOOKIFY_TEMPLATE_DIR"/*.local.md.template; do
    [ -f "$tpl" ] || continue
    basename_tpl="$(basename "$tpl")"
    # strip ".template" suffix; result e.g. "warn-console-direct.local.md"
    out_name="${basename_tpl%.template}"
    # Recipe-scoping (ADR-028): if this template is listed in .recipe-scoped, emit only when its recipe is selected.
    # awk '$1==k' does a LITERAL field-1 compare (out_name contains regex-special dots) — also excludes
    # '#' comment lines and prevents prefix/substring collisions. '|| true' keeps set -eu safe if the map is absent.
    scoped_recipe="$(/usr/bin/awk -v k="$out_name" '$1==k {print $2}' "$HOOKIFY_TEMPLATE_DIR/.recipe-scoped" 2>/dev/null || true)"
    if [ -n "$scoped_recipe" ]; then
      case ",$RECIPES," in
        *",$scoped_recipe,"*) : ;;  # recipe selected — emit
        *) log "  $out_name — skipped (requires --recipes=$scoped_recipe)"; continue ;;
      esac
    fi
    dest="$TARGET_ABS/.claude/$(echo "hookify.$out_name")"
    if [ -f "$dest" ]; then
      log "  $dest exists — leaving in place (adopter customization wins)"
      HOOKIFY_SKIPPED=$((HOOKIFY_SKIPPED + 1))
      continue
    fi
    substitute_hookify_template "$tpl" "$dest"
    record_emit ".claude/hookify.$out_name" "adapters/claude/hookify-templates/$basename_tpl" ""
    HOOKIFY_INSTALLED=$((HOOKIFY_INSTALLED + 1))
  done
  log "  hookify rules: $HOOKIFY_INSTALLED installed, $HOOKIFY_SKIPPED skipped (pre-existing)"
fi

# ---- Step 4.6: self-improvement runtime artifacts (only when recipe selected) ----
if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step 4.6: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    log "Step 4.6: emitting self-improvement runtime (prune script + /reflect command)"
    # prune script → .conductor/reflect/prune-lessons.sh
    if [ -f "$CORE_ROOT/reflector/prune-lessons.sh" ]; then
      dest="$TARGET_ABS/.conductor/reflect/prune-lessons.sh"
      if [ "$DRY_RUN" = "true" ]; then
        log "  would emit .conductor/reflect/prune-lessons.sh"
      else
        /bin/mkdir -p "$TARGET_ABS/.conductor/reflect"
        backup_and_remember "$dest"
        /bin/cp "$CORE_ROOT/reflector/prune-lessons.sh" "$dest"
        /bin/chmod +x "$dest"
        record_emit ".conductor/reflect/prune-lessons.sh" "core/reflector/prune-lessons.sh" "$MANIFEST_LAST_BACKUP"
      fi
    fi
    # /reflect command → .claude/commands/reflect.md
    if [ -f "$CORE_ROOT/reflector/reflect.command.md" ]; then
      dest="$TARGET_ABS/.claude/commands/reflect.md"
      if [ "$DRY_RUN" = "true" ]; then
        log "  would emit .claude/commands/reflect.md"
      else
        /bin/mkdir -p "$TARGET_ABS/.claude/commands"
        backup_and_remember "$dest"
        /bin/cp "$CORE_ROOT/reflector/reflect.command.md" "$dest"
        record_emit ".claude/commands/reflect.md" "core/reflector/reflect.command.md" "$MANIFEST_LAST_BACKUP"
      fi
    fi
    # scheduling assets → .conductor/reflect/ (weekly runner + brief + registration guide)
    if [ "$DRY_RUN" = "true" ]; then
      log "  would emit .conductor/reflect/{run-weekly.sh,reflect-brief.md,SCHEDULING.md}"
    else
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect"
      conductor_install_trajectory_ignore
      for f in run-weekly.sh reflect-brief.md SCHEDULING.md; do
        [ -f "$CORE_ROOT/reflector/$f" ] || continue
        dest="$TARGET_ABS/.conductor/reflect/$f"
        backup_and_remember "$dest"
        /bin/cp "$CORE_ROOT/reflector/$f" "$dest"
        case "$f" in *.sh) /bin/chmod +x "$dest" ;; esac
        record_emit ".conductor/reflect/$f" "core/reflector/$f" "$MANIFEST_LAST_BACKUP"
      done
    fi
    ;;
  *)
    # Not opted in: clear a stale gate + orphaned opt-in artifacts left by a prior
    # opted-in install, so a recipe-less re-install is fully dormant (the always-on
    # trajectory hook gates on .conductor/reflect/, and /reflect must not dangle).
    if [ "$DRY_RUN" != "true" ] && [ -d "$TARGET_ABS/.conductor/reflect" ]; then
      /bin/rm -f "$TARGET_ABS/.conductor/reflect/prune-lessons.sh" "$TARGET_ABS/.conductor/reflect/run-weekly.sh" "$TARGET_ABS/.conductor/reflect/reflect-brief.md" "$TARGET_ABS/.conductor/reflect/SCHEDULING.md"
      /bin/rm -f "$TARGET_ABS/.claude/commands/reflect.md" "$TARGET_ABS/.claude/agents/reflector.md" 2>/dev/null || true
      if /bin/rmdir "$TARGET_ABS/.conductor/reflect" 2>/dev/null; then
        log "Step 4.6: self-improvement not selected — cleared stale .conductor/reflect gate + /reflect artifacts"
      else
        log "Step 4.6: WARNING — .conductor/reflect not empty; trajectory hook stays ACTIVE (remove that dir manually to disable)"
      fi
    fi
    ;;
esac

# ----- step 5: docs templates --------------------------------------------

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 5/6: docs templates — skipped (--mode=$MODE is à la carte)"
else
log "Step 5/6: docs templates → docs/"
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

fi

# ----- step 6: synthesize CLAUDE.md --------------------------------------

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 6/6: CLAUDE.md — skipped (--mode=$MODE is à la carte)"
else
log "Step 6/6: synthesize CLAUDE.md"
CLAUDE_MD="$TARGET_ABS/CLAUDE.md"

CLAUDE_MD_CONTENT=$(/bin/cat <<'EOF'
# Project Orchestrator Manual (installed by CONDUCTOR)

You are the orchestrator. You coordinate, delegate, and verify. You do not implement code yourself except for the smallest tasks — developer roles handle that.

Sub-agents in Claude Code are isolated and do not inherit this file. Every dispatch brief must be self-contained: objective, file paths, constraints, output path, stop condition.

## ABSOLUTE rules (read before every tool call)

The following universal rules are loaded from `.claude/rules/` and apply to every turn:

| Rule file | Bundles |
|---|---|
| `workflow.md` | Plan-first, docs-first, 7-step, process-over-speed, never-skip |
| `spec-as-you-go.md` | Same-turn spec update, real-time docs sync |
| `quality-gates.md` | Pre-commit + pre-merge review, test sync, verify-after-changes |
| `operations.md` | Session continuity, completed-task delete, dev/prod sync |
| `meta-discipline.md` | Originality, ambiguity AMB-1..7 triggers, token economy, model routing, flat-with-leader |

If you catch yourself about to break one, STOP and fix course. Silent recovery is worse than explicit acknowledgment.

## Roles available for dispatch

| Role | Difficulty | Claude translation | When to use |
|---|---|---|---|
| `@planner` | Tier 1 | `{{CLAUDE_TIER_1_MODEL}}` | Architecture, ADRs, gap analysis (no code) |
| `@builder` | Tier 1 | `{{CLAUDE_TIER_1_MODEL}}` | Multi-file (3+) cross-cutting code |
| `@reviewer` | Tier 1 | `{{CLAUDE_TIER_1_MODEL}}` | Plan validation (read-only) |
| `@code-reviewer` | Tier 1 | `{{CLAUDE_TIER_1_MODEL}}` | Post-implementation code review (read-only) |
| `@helper` | Tier 2 | `{{CLAUDE_TIER_2_MODEL}}` | Single-file work, established patterns |
| `@designer` | Tier 2 | `{{CLAUDE_TIER_2_MODEL}}` | UI / UX, design tokens, accessibility |
| `@scribe` | Tier 2 | `{{CLAUDE_TIER_2_MODEL}}` | Documentation sync (no code) |
| `@utility` | Tier 3 | `{{CLAUDE_TIER_3_MODEL}}` | Direct lookup or trivial one-file edit; escalate if scope grows |

Per `meta-discipline.md` section 6, the orchestrator classifies every task first,
then passes the matching Claude model explicitly. Family aliases follow current
Claude releases; exact model IDs are saved with
`omniconductor models configure --target=claude`. The PreToolUse hook
(`.claude/hooks/pretool-agent-routing.sh`) enforces explicit selection.

## Topology — flat-with-leader

Roles do NOT dispatch each other. Multi-step work returns intermediate results to the orchestrator, which decides the next dispatch. See `meta-discipline.md` section 7.

## Ambiguity policy

Default: ACT-WITH-DECLARATION (proceed with best-guess + surface assumption in response prefix).

Override: ASK (multiple-choice template) when any of AMB-1..7 fires:
- AMB-1 deictic ("this", "like before"), AMB-2 unspecified scope, AMB-3 external system invocation, AMB-4 protected-branch merge, AMB-5 design decisions, AMB-6 dependency add, AMB-7 user manual action required.

Full catalog: `meta-discipline.md` section 3.

## Session startup (lazy-load by default)

Auto-load on every session: `docs/CURRENT_WORK.md` only.

Lazy-load on demand:
- `docs/architecture/README.md` — when designing / changing system structure.
- `docs/specs/<area>.md` — when touching that area's code.
- Recipe files in `.claude/rules/` — auto-loaded by Claude Code when matching files are touched (via `paths:` frontmatter).

## Hooks installed

| Hook | Trigger | Action |
|---|---|---|
| `pretool-agent-routing.sh` | Agent tool dispatch | Block forbidden subagent_type, require explicit model |
| `pretool-commit-current-work-check.sh` | Bash `git commit` | Soft `ask` warn (non-blocking) when 3+ source files are staged but CURRENT_WORK.md is not in the commit (skip: `CONDUCTOR_SKIP_CURRENT_WORK_HOOK=1`) |
| `pretool-commit-test-coverage-check.sh` | Bash `git commit` | Soft `ask` warn (non-blocking, quality-gates Q3) when a new feature-shaped file is added with no new test in the commit (skip: `CONDUCTOR_SKIP_TEST_COVERAGE_HOOK=1`) |
| `pretool-large-file-read-guard.sh` | Read tool | Block Read of files ≥ 500 lines without offset/limit; recommends range-read or Grep (override: `CONDUCTOR_ALLOW_LARGE_READ=1`) |
| `stop-session-log-check.sh` | Session stop | Block stop when CURRENT_WORK.md / specs are stale after recent commits |
| `stop-r6-review-check.sh` | Session stop | Remind to run pre-merge review on open PR |
| `stop-cache-hit-baseline-check.sh` | Session stop | Non-blocking cache-hit-rate diagnostic vs baseline (skip: `CONDUCTOR_SKIP_CACHE_CHECK=1`) |

## Prompt caching (recommended)

When using the Anthropic SDK directly, place this orchestrator manual + the universal-rules + recipes in the cacheable prefix. See the CONDUCTOR repo's `docs/PROMPT-CACHING-GUIDE.md` for the recommended structure.
EOF
)
CLAUDE_MD_CONTENT="$(printf '%s' "$CLAUDE_MD_CONTENT" | /usr/bin/sed \
  -e "s/{{CLAUDE_TIER_1_MODEL}}/$CLAUDE_TIER_1_MODEL/g" \
  -e "s/{{CLAUDE_TIER_2_MODEL}}/$CLAUDE_TIER_2_MODEL/g" \
  -e "s/{{CLAUDE_TIER_3_MODEL}}/$CLAUDE_TIER_3_MODEL/g")"

backup_and_remember "$CLAUDE_MD"
if [ "$DRY_RUN" = "true" ]; then
  log "would write CLAUDE.md ($(echo "$CLAUDE_MD_CONTENT" | /usr/bin/wc -c | /usr/bin/tr -d ' ') bytes)"
else
  printf '%s\n' "$CLAUDE_MD_CONTENT" > "$CLAUDE_MD"
  record_emit "CLAUDE.md" "<synthesized>" "$MANIFEST_LAST_BACKUP"
fi

# Finalize manifest now that all emits are complete (before optional baseline measurement).
fi

finalize_manifest

# ----- step 7 (optional): baseline measurement ---------------------------

BASELINE_HIT_RATE=""

if [ "$MEASURE_BASELINE" = "true" ]; then
  log "Step 7/9: baseline measurement (--measure-baseline)"
  BASELINE_DIR="$TARGET_ABS/.conductor"
  BASELINE_CSV="$BASELINE_DIR/baseline-$(date +%Y%m%d).csv"
  MEASURE_SCRIPT="$TOOLS_ROOT/measure-tokens.sh"

  if [ ! -f "$MEASURE_SCRIPT" ]; then
    echo "Warning: measure-tokens.sh not found at $MEASURE_SCRIPT; skipping baseline" >&2
  else
    if [ "$DRY_RUN" = "true" ]; then
      log "would run: bash $MEASURE_SCRIPT --latest --export-csv=$BASELINE_CSV"
      log "would save baseline to $BASELINE_CSV"
    else
      mkdir -p "$BASELINE_DIR"
      echo ""
      echo "[conductor] Running baseline measurement..."
      MEASURE_OUTPUT=""
      if MEASURE_OUTPUT=$(bash "$MEASURE_SCRIPT" --latest --export-csv="$BASELINE_CSV" 2>&1); then
        echo "$MEASURE_OUTPUT"
        # Extract cache hit rate for step 8 decision.
        BASELINE_HIT_RATE=$(echo "$MEASURE_OUTPUT" | /usr/bin/grep "Cache hit rate" | /usr/bin/awk '{print $NF}' | /usr/bin/tr -d '%')
        echo ""
        echo "[conductor] Baseline saved: $BASELINE_CSV"
      else
        echo "Warning: baseline measurement failed (no Claude Code sessions found?)" >&2
        echo "$MEASURE_OUTPUT" >&2
      fi
    fi
  fi
else
  if [ "$DRY_RUN" = "true" ] && [ "$MEASURE_BASELINE" = "false" ]; then
    log "Step 7/9: baseline measurement — skipped (pass --measure-baseline to enable)"
  fi
fi

# ----- step 8 (conditional): anti-pattern advice -------------------------

# Show anti-patterns if:
#   a) --check-anti-patterns flag is set, OR
#   b) --measure-baseline ran and hit rate < 95%

SHOW_ANTIPATTERNS_NOW="false"

if [ "$CHECK_ANTI_PATTERNS" = "true" ] || [ "$WIZARD_SHOW_ANTI_PATTERNS" = "true" ]; then
  SHOW_ANTIPATTERNS_NOW="true"
fi

# If baseline ran and hit rate is below 95, also show.
if [ -n "$BASELINE_HIT_RATE" ]; then
  # Compare as integer (strip decimal part).
  HIT_RATE_INT="${BASELINE_HIT_RATE%%.*}"
  if [ -n "$HIT_RATE_INT" ] && [ "$HIT_RATE_INT" -lt 95 ] 2>/dev/null; then
    SHOW_ANTIPATTERNS_NOW="true"
    echo ""
    echo "[conductor] Cache hit rate is ${BASELINE_HIT_RATE}% (below 95% threshold) — showing anti-pattern catalog."
  fi
fi

ANTIPATTERN_README="$CORE_ROOT/anti-patterns/README.md"

if [ "$SHOW_ANTIPATTERNS_NOW" = "true" ]; then
  log "Step 8/9: anti-pattern catalog"
  if [ "$DRY_RUN" = "true" ]; then
    log "would print $ANTIPATTERN_README (5 second pause)"
  else
    echo ""
    echo "========================================================"
    echo " CONDUCTOR Anti-Pattern Catalog"
    echo "========================================================"
    if [ -f "$ANTIPATTERN_README" ]; then
      /bin/cat "$ANTIPATTERN_README"
    else
      echo "(catalog not found at $ANTIPATTERN_README)"
    fi
    echo ""
    echo "========================================================"
    echo " Next steps:"
    echo "   1. Review $CORE_ROOT/anti-patterns/ for detailed fixes."
    echo "   2. Apply fixes (move volatile content below cache boundary,"
    echo "      add Grep-before-Read discipline)."
    echo "   3. Re-measure in 1 week:"
    echo "      bash $CONDUCTOR_ROOT/tools/measure-tokens.sh --latest"
    echo "      --export-csv=<project>/.conductor/followup-$(date +%Y%m%d).csv"
    echo "========================================================"
    echo ""
    echo "(pausing 5 seconds — press Enter to continue sooner)"
    read -r -t 5 || true
  fi
else
  if [ "$DRY_RUN" = "true" ]; then
    log "Step 8/9: anti-pattern catalog — skipped (pass --check-anti-patterns or hit rate < 95% to enable)"
  fi
fi

# ----- step 9 (always): restart reminder ---------------------------------

log "Step 9/9: activation reminder"
echo ""
echo "========================================================"
echo " Done."
echo "  Target: $TARGET_ABS"
echo "  Mode: $MODE"
if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  echo "  Universal rules: 0 (à la carte)"
  case ",$RECIPES," in
    *",self-improvement,"*) echo "  Roles: 1 (reflector only)" ;;
    *)                      echo "  Roles: 0" ;;
  esac
else
  echo "  Universal rules: 5"
  if [ "$MODE" = "minimal" ]; then
    echo "  Roles: 0 (--mode=minimal)"
  else
    case ",$RECIPES," in
      *",self-improvement,"*) echo "  Roles: 8 (incl. reflector)" ;;
      *)                      echo "  Roles: 7" ;;
    esac
  fi
fi
echo "  Recipes installed: ${RECIPES:-(none)}"
echo "  Hooks: ${#INSTALLED_HOOKS[@]} (${INSTALLED_HOOKS[*]:-none})"
if [ -f "$TARGET_ABS/.claude/settings.json" ]; then
  echo "  Settings: .claude/settings.json (permissions allowlist + hooks registry)"
fi
echo ""
echo " Run \`claude\` (Claude Code restart) to activate new rules."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open $TARGET_ABS in Claude Code."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. Edit CLAUDE.md if you have project-specific orchestrator rules to add."
echo "  4. Verify hook installation: ls -la $TARGET_ABS/.claude/hooks/"
