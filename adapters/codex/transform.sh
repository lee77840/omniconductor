#!/usr/bin/env bash
#
# CONDUCTOR — Codex adapter transform.sh
#
# Reads core/ assets and writes them into a target project as a single native
# Codex bundle (AGENTS.md at project root) plus universal doc templates.
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
#   <synthesized header>           →  <target>/AGENTS.md  (Codex-flavored bilingual intro)
#   core/universal-rules/*.md      →  <target>/AGENTS.md  (each as "## <title>", body sans frontmatter)
#   core/workflow/PHASES.md        →  <target>/AGENTS.md  (compressed phase table)
#   core/recipes/*.md (selected)   →  <target>/AGENTS.md  (each as "## Recipe — <name>")
#   core/docs-templates/*.md       →  <target>/docs/*.md  (CURRENT_WORK, REMAINING_TASKS, etc.)
#   core/hooks/*.sh.template       →  SKIPPED (Reflector hook emitted via --recipes=self-improvement, ADR-032; other guards Claude-only, ADR-034)
#   core/roles/*.md                →  SKIPPED (role emission is Claude-only today; Codex supports sub-agents natively — ADR-031)
#   adapters/claude/hookify-...    →  SKIPPED (Claude-only plugin)
#
# Single-file model: Codex reads ONE always-loaded rules file. Everything that
# Cursor splits across .cursor/rules/*.mdc is concatenated into AGENTS.md here.

set -eu

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
  --recipes=A,B,C       Comma-separated list of recipes to append into AGENTS.md
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

Output (single-file Codex model):
  <target>/AGENTS.md    Bundled intro + 5 universal rules + compressed workflow + recipes
  <target>/docs/*.md    Universal doc templates (CURRENT_WORK, REMAINING_TASKS, ...)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering

What this adapter does NOT install (per ADR-004 honesty):
  - Hook guards (CONDUCTOR emits the Reflector hook when --recipes=self-improvement, ADR-032; other guards remain Claude-only, ADR-034)
  - Sub-agent personas (not yet emitted for Codex — the tool supports sub-agents natively, ADR-031; agent emission is Phase 2)
  - Per-pattern rule scoping (Codex loads AGENTS.md whole — all rules always-on)
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

# Resolve CONDUCTOR root (where this script lives: adapters/codex/).
CONDUCTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

# backup_and_remember <dest>
# If <dest> exists, copy it to <dest>.conductor-backup-<ts> and remember the relative
# backup path in MANIFEST_LAST_BACKUP for the next record_emit. Honors DRY_RUN.
# Origin: ADR-019 (Claude adapter pattern), mirrored per ADR-021.
backup_and_remember() {
  MANIFEST_LAST_BACKUP=""
  if [ -f "$1" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      log "would back up existing $1 -> $1.conductor-backup-<ts>"
      MANIFEST_LAST_BACKUP=""
    else
      local ts
      ts="$(/bin/date +%Y%m%d-%H%M%S)"
      local backup="$1.conductor-backup-$ts"
      /bin/cp "$1" "$backup"
      log "  backed up existing $1 -> $backup"
      MANIFEST_LAST_BACKUP="${backup#$TARGET_ABS/}"
    fi
  fi
}

# ----- manifest tracking (ADR-020, mirrored per ADR-021) ------------------
#
# Format identical to Claude/Cursor adapters' manifest. POSIX shell + sed only — no jq.

MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_STAGE_PATH=""
MANIFEST_TS=""
MANIFEST_LAST_BACKUP=""

init_manifest() {
  if [ "$DRY_RUN" = "true" ]; then
    log "would init manifest staging at $MANIFEST_PATH.staging"
    return
  fi
  MANIFEST_TS="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  MANIFEST_STAGE_PATH="$TARGET_ABS/.conductor-manifest.json.staging"
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  : > "$MANIFEST_STAGE_PATH"
}

record_emit() {
  if [ "$DRY_RUN" = "true" ] || [ "$UNINSTALL" = "true" ]; then
    return
  fi
  local relpath="$1" src="$2" backup="${3:-}"
  local had_backup="false"
  [ -n "$backup" ] && had_backup="true"
  local esc_path esc_src esc_backup
  esc_path="$(printf '%s' "$relpath" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_src="$(printf '%s' "$src" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_backup="$(printf '%s' "$backup" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '    {"path": "%s", "source": "%s", "had_backup": %s, "backup_path": "%s"},\n' \
    "$esc_path" "$esc_src" "$had_backup" "$esc_backup" >> "$MANIFEST_STAGE_PATH"
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
  local f="$1" name="$2" content="$3"
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
    exit 1
  fi
  if [ ! -f "$f" ]; then
    BLOCK_CREATED="true"
    : > "$f"
  else
    if /usr/bin/grep -qF "$open" "$f"; then
      # Replace our own block in place — no backup (the operation is reversible
      # and per-run backups litter the target).
      /usr/bin/awk -v o="$open" -v c="$close" '$0==o{inb=1; if (heldset && held ~ /^[[:space:]]*$/) heldset=0; next} $0==c{inb=0;next} inb{next} {if (heldset) print held; held=$0; heldset=1} END{if (heldset) print held}' "$f" > "$f.conductor-tmp"
      /bin/mv "$f.conductor-tmp" "$f"
      log "  replaced existing block '$name' in $f"
    else
      # First append into a pre-existing file: one safety backup.
      backup_and_remember "$f"
    fi
  fi
  { echo ""; echo "$open"; /bin/cat "$content"; echo "$close"; } >> "$f"
  BLOCK_SHA="$(/usr/bin/awk -v o="$open" -v c="$close" '$0==o{b=1;next} $0==c{b=0;next} b' "$f" | sha256_of)"
  log "  appended block '$name' to $f (sha256 $(printf '%s' "$BLOCK_SHA" | /usr/bin/cut -c1-12)...)"
}

record_emit_block() {
  if [ "$DRY_RUN" = "true" ] || [ "$UNINSTALL" = "true" ]; then return; fi
  local relpath="$1" name="$2" sha="$3" created="$4"
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
    local rel_path src had_backup backup_path
    rel_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
    src="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"source": *"([^"]*)".*/\1/')"
    had_backup="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"had_backup": *(true|false).*/\1/')"
    backup_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"backup_path": *"([^"]*)".*/\1/')"

    local abs_dest="$TARGET_ABS/$rel_path"
    local abs_backup=""
    [ -n "$backup_path" ] && abs_backup="$TARGET_ABS/$backup_path"

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
    echo "  Skipping universal-rules — AGENTS.md will carry intro + workflow only."
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

# ----- step 1: build AGENTS.md (single-file Codex bundle) -----------------

init_manifest

UNIVERSAL_RULES="workflow spec-as-you-go quality-gates operations meta-discipline"

AGENTS_DEST="$TARGET_ABS/AGENTS.md"

INSTALLED_RECIPES=""

if [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then

log "Step 1/2: AGENTS.md → $AGENTS_DEST"
backup_and_remember "$AGENTS_DEST"

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

# build_agents_md — writes the full bundle to stdout. Pure assembly; no side effects.
build_agents_md() {
  # --- header (synthesized inline; no _native/*.tpl exists) ---------------
  /bin/cat <<'HEADER'
# AGENTS.md — CONDUCTOR workflow rules (Codex adapter)

> 이 파일은 CONDUCTOR 프레임워크가 생성한 **프로젝트 규칙 번들**입니다. Codex 는 세션 시작 시
> 프로젝트 루트의 `AGENTS.md` 를 자동 로드합니다. 아래 규칙은 어떤 코드를 생성하든 항상 적용됩니다.
>
> This file is a **project rules bundle** generated by the CONDUCTOR framework. Codex auto-loads
> `AGENTS.md` from the project root at session start. The rules below apply to every change you make.

## How to use this with Codex (한/영)

**한국어** — Codex 는 *한 방(one-shot) 셸 작업* 에 강합니다. 스크립트 작성, 파일 일괄 변환, git 작업,
"이 명령 실행하고 결과 보고" 류 작업이 최적입니다. Codex 는 서브에이전트/훅을 네이티브로 지원하지만
(ADR-031), CONDUCTOR 의 Codex adapter 는 아직 이를 자동 생성하지 않으므로 (Phase 2), 멀티 스텝
오케스트레이션은 순차 프롬프트로 분해하거나 CONDUCTOR 의 full-emission 인 Claude adapter 를 쓰세요.
이 번들은 Codex 가 *인라인으로 생성하는 코드* 가 프로젝트 컨벤션을 따르도록 충분한 맥락을 줍니다.

**English** — Codex shines at *one-shot shell tasks*: writing scripts, batch file transforms, git
operations, and "run this command and report the output" work. Codex supports sub-agents and hooks
natively (ADR-031), but CONDUCTOR's Codex adapter does not emit them yet (Phase 2) — decompose
multi-step orchestration into sequential prompts, or use CONDUCTOR's full-emission Claude adapter.
This bundle gives Codex enough context that the code it generates inline
follows your project conventions.

> **Enforcement note (Codex)**: Codex supports sub-agents, hooks, and per-task model routing
> natively (ADR-031), but CONDUCTOR's Codex adapter currently emits rule text (plus the Reflector
> loop) only — full hook/agent emission is Phase 2. Every rule below is loaded *always* and is
> **self-policed** — CONDUCTOR installs no automated gate here. Enforcement mechanisms cited in
> the rule text (Stop hooks, agent routing) are emitted for Claude only today; treat them as
> reminders. Pair this with a git pre-commit hook if you want a hard gate.

## ABSOLUTE rules (always-on summary)

These five bundles are **ABSOLUTE severity** — they are the universal floor, never skipped regardless
of task size. Full text of each is in its own section below.

| Rule | What it guarantees |
|---|---|
| **Workflow** | Plan-first / docs-first / process-first ordering; never skip phases by scope. |
| **Spec-as-you-go** | Documentation updated in the *same turn* as the code it describes. |
| **Quality Gates** | Two-stage review (pre-commit + pre-merge), test sync, verify-after-change. |
| **Operations** | Session continuity, completed-task hygiene, dev/prod parity. |
| **Meta-Discipline** | Originality, ambiguity policy, token economy, model routing, flat-with-leader. |

> Before any **non-trivial** task: **Read `docs/CURRENT_WORK.md`** for current project state, then act.

HEADER

  # --- universal rules (each as "## <title>", body sans frontmatter) ------
  if [ "$WIZARD_APPLY_RULES" = "true" ]; then
    for rule in $UNIVERSAL_RULES; do
      src="$CORE_ROOT/universal-rules/$rule.md"
      [ -f "$src" ] || { echo "Warning: $src not found; skipping" >&2; continue; }
      title="$(derive_title "$src")"
      echo "---"
      echo ""
      echo "## $title"
      echo ""
      strip_frontmatter "$src"
      echo ""
    done
  fi

  # --- compressed workflow from PHASES.md --------------------------------
  echo "---"
  echo ""
  /bin/cat <<'WORKFLOW'
## Workflow phases (compressed)

The 6-phase model scales with scope. **Codex's typical one-shot use cases skip Plan / Architecture
more often than other tools** — but the gates that remain (Implementation → Review → Spec) still hold.

| Scope | Phases entered | Skip |
|---|---|---|
| Trivial | Implementation → Review → Spec | Plan, Architecture, Tasks |
| Simple  | Tasks → Implementation → Review → Spec | Plan, Architecture |
| Medium  | Plan → Tasks → Implementation → Review → Spec | Architecture |
| Large   | Plan → Architecture → Tasks → Implementation → Review → Spec | — |

- **Plan** — for medium+ scope: write the approach, files affected, risks, stop condition.
- **Architecture** — for large/system-shaping work: record decision(s) under `docs/architecture/`.
- **Tasks** — enumerate work with objective, file paths, constraints, output paths, stop condition.
- **Implementation** — code + test updates per task. Keep changes scoped to the task.
- **Review** — Stage A on the diff (correctness), Stage B before merge (block on HIGH-confidence issues).
- **Spec** — update `docs/specs/<area>.md` to reflect actually-shipped behavior (spec-as-you-go).

> On Codex, phase enforcement is **self-policed** (CONDUCTOR emits no Stop hooks here yet). The rule text above is the reminder.

WORKFLOW

  # --- recipes (opt-in), each as "## Recipe — <name>" --------------------
  if [ -n "$INSTALLED_RECIPES" ]; then
    for r in $INSTALLED_RECIPES; do
      src="$CORE_ROOT/recipes/$r.md"
      [ -f "$src" ] || continue
      echo "---"
      echo ""
      echo "## Recipe — $r"
      echo ""
      strip_frontmatter "$src"
      echo ""
    done
  fi

  # --- memory note (DIY .memory/) ----------------------------------------
  /bin/cat <<'MEMORY'
---

## Memory (DIY `.memory/`)

Codex has **no built-in memory directory**. To persist cross-session context (user role/preferences,
corrections you should not repeat, ongoing project goals, pointers to external systems), create a
`.memory/` directory at the project root and add it to `.gitignore` so personal entries don't leak
into the repo.

Suggested layout (one file per entry + an always-read index):

```
.memory/
├── MEMORY.md         # index, ≤ 200 lines — paste relevant entries into your prompt
├── user_*.md         # role, preferences, knowledge level
├── feedback_*.md     # corrections + validated approaches (lead with the rule, then Why / How)
├── project_*.md      # ongoing work, goals, deadlines (use absolute dates)
└── reference_*.md    # pointers to external systems (issue trackers, dashboards)
```

Do NOT store in memory: code patterns / conventions / file paths (read the code), git history
(use `git log`), debugging fix recipes (the fix is in the commit), or anything already in this
AGENTS.md. Before relying on a memory entry, **verify it's still true** (the path/flag/claim may be stale).
MEMORY
}

if [ "$DRY_RUN" = "true" ]; then
  log "would write $AGENTS_DEST (intro + $( [ "$WIZARD_APPLY_RULES" = "true" ] && echo 5 || echo 0 ) universal rules + compressed workflow + recipes:${INSTALLED_RECIPES:- none})"
else
  build_agents_md > "$AGENTS_DEST"
  record_emit "AGENTS.md" "<synthesized>" "$MANIFEST_LAST_BACKUP"
  log "  wrote $AGENTS_DEST"
fi

else
  # ----- à-la-carte modes: marked block appended to AGENTS.md (ADR-044) ------
  BLOCK_NAME="recipes"; [ "$MODE" = "reflector-only" ] && BLOCK_NAME="reflector"
  log "Step 1/2: --mode=$MODE — '$BLOCK_NAME' marked block → $AGENTS_DEST (no full bundle)"
  if [ "$DRY_RUN" = "true" ]; then
    log "would append marked block '$BLOCK_NAME' (selected recipes: $RECIPES) to $AGENTS_DEST"
  else
    _blk="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/conductor-block.XXXXXX")"
    {
      echo "# CONDUCTOR — à la carte (--mode=$MODE)"
      echo ""
      echo "> Installed by CONDUCTOR WITHOUT the universal-rule bundle. This is a managed"
      echo "> block: --uninstall strips it when unmodified. Full workflow: --mode=full."
      echo ""
      IFS=',' read -ra _RECIPE_LIST <<< "$RECIPES"
      for r in "${_RECIPE_LIST[@]}"; do
        r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
        [ -z "$r" ] && continue
        src="$CORE_ROOT/recipes/$r.md"
        if [ ! -f "$src" ]; then
          echo "Warning: recipe '$r' not found at $src; skipping" >&2
          continue
        fi
        echo "## Recipe — $r"
        echo ""
        strip_frontmatter "$src"
        echo ""
        INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
      done
    } > "$_blk"
    if [ -z "${INSTALLED_RECIPES// /}" ]; then
      /bin/rm -f "$_blk"
      echo "Error: --mode=$MODE resolved ZERO valid recipes from '--recipes=$RECIPES' — nothing to install (check the names)." >&2
      /bin/rm -f "$MANIFEST_STAGE_PATH"
      exit 1
    fi
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
        if /usr/bin/grep -qF "<!-- conductor:block $_pname -->" "$AGENTS_DEST" 2>/dev/null; then
          printf '%s\n' "$_prev" | /usr/bin/sed 's/,*$/,/' >> "$MANIFEST_STAGE_PATH"
          log "  preserved previous block '$_pname' in manifest"
        fi
      done < "$MANIFEST_PATH"
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
      gi="$TARGET_ABS/.gitignore"
      grep -qxF '.conductor/' "$gi" 2>/dev/null || printf '\n# CONDUCTOR runtime (local trajectories/lessons)\n.conductor/\n' >> "$gi"
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
      hc="$TARGET_ABS/.codex/hooks.json"
      if [ ! -f "$hc" ]; then
        backup_and_remember "$hc"
        /bin/cat > "$hc" <<'HOOK'
{
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash ./.conductor/reflect/trajectory-log.sh", "timeout": 30 } ] }
    ]
  }
}
HOOK
        record_emit ".codex/hooks.json" "<synthesized>" "$MANIFEST_LAST_BACKUP"
      else
        log "  .codex/hooks.json exists — add a Stop hook calling ./.conductor/reflect/trajectory-log.sh manually"
      fi
      sk="$TARGET_ABS/.agents/skills/reflect/SKILL.md"
      backup_and_remember "$sk"
      { printf -- '---\nname: reflect\ndescription: Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only). Use when wrapping up work.\n---\n\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; } > "$sk"
      record_emit ".agents/skills/reflect/SKILL.md" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      ag="$TARGET_ABS/.codex/agents/reflector.toml"
      backup_and_remember "$ag"
      { printf 'name = "reflector"\ndescription = "Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies."\ndeveloper_instructions = """\n'; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; printf '\n"""\n'; } > "$ag"
      record_emit ".codex/agents/reflector.toml" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
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
  echo "  AGENTS.md: marked à-la-carte block appended (no universal-rule bundle)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  echo "  AGENTS.md: intro + 5 universal rules + compressed workflow + memory note"
else
  echo "  AGENTS.md: intro + compressed workflow + memory note (universal rules skipped)"
fi
echo "  Recipes appended:${INSTALLED_RECIPES:- (none)}"
echo ""
echo " Skipped (per ADR-004 honesty):"
echo "  - Hooks: CONDUCTOR emits the Reflector hook when --recipes=self-improvement (ADR-032); other guards remain Claude-only (ADR-034)."
echo "  - Sub-agent personas: not yet emitted for Codex (tool supports sub-agents natively — ADR-031; Phase 2)."
echo "  - Per-pattern scoping: Codex loads AGENTS.md whole — all rules are always-on."
echo "  - Hookify rule templates: Claude-only plugin."
echo ""
echo " Activation: AGENTS.md auto-loads on Codex session start (project root)."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open $TARGET_ABS with Codex."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. (optional) Create .memory/ and add it to .gitignore — see the Memory section in AGENTS.md."
echo "  4. Verify Codex cites project conventions when generating code (confirms AGENTS.md loaded)."
