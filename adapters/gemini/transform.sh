#!/usr/bin/env bash
#
# CONDUCTOR — Gemini CLI adapter transform.sh
#
# Reads core/ assets and writes them into a target project as native Gemini CLI
# files: a single always-loaded GEMINI.md bundle, an optional .gemini/styleguide.md,
# and docs/* templates.
#
# Usage:
#   bash adapters/gemini/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--no-prompt]
#   bash adapters/gemini/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/gemini/transform.sh ~/Projects/my-app
#   bash adapters/gemini/transform.sh ~/Projects/my-app --recipes=coding-conventions,i18n
#   bash adapters/gemini/transform.sh /tmp/test-project --dry-run
#   bash adapters/gemini/transform.sh . --no-prompt
#   bash adapters/gemini/transform.sh . --uninstall              # revert install
#   bash adapters/gemini/transform.sh . --uninstall --force      # bypass safety checks
#
# Layer 2 transformation (per ADR-004 honesty + ADR-021):
#   core/universal-rules/*.md      →  <target>/GEMINI.md          (all 5 bundled, single always-loaded file)
#   core/workflow/PHASES.md        →  <target>/GEMINI.md          (compressed workflow section)
#   core/recipes/*.md (selected)   →  <target>/GEMINI.md          (## Recipe — <name> sections; Gemini is single-file)
#   core/recipes/coding-conventions →  <target>/.gemini/styleguide.md  (Gemini style-guide convention; opt-in)
#   core/docs-templates/*.md       →  <target>/docs/*.md          (CURRENT_WORK, REMAINING_TASKS, etc.)
#   core/hooks/*.sh.template       →  SKIPPED (Reflector hook emitted via --recipes=self-improvement, ADR-032; other guards Claude-only, ADR-034)
#   core/roles/*.md                →  SKIPPED (role emission is Claude-only today; Gemini supports sub-agents natively — ADR-031)
#
# Gemini reality (per adapters/gemini/SUPPORTED-FEATURES.md):
#   - Single always-loaded rule file (GEMINI.md). No per-pattern rule scoping.
#   - Gemini CLI supports sub-agents / hooks / per-call model routing natively
#     (ADR-031), but this adapter does not emit them yet (Phase 2). CONDUCTOR
#     emits the Reflector hook when --recipes=self-improvement (ADR-032); other
#     guards remain Claude-only emission (ADR-034).
#   The bundle below carries the rule TEXT honestly; Claude-only enforcement mechanisms
#   are noted as self-policed for Gemini, never faked.

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
Usage: bash adapters/gemini/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated list of recipes to install (appended into GEMINI.md)
  --mode=<m>            Install preset (ADR-044). One of:
                          full           (default) everything this adapter emits today
                          minimal        discipline text + session continuity only
                                         (GEMINI.md + docs/; no styleguide, no Reflector runtime)
                          strict         full, but ABORT (exit 3) if GEMINI.md already exists
                                         (never overwrites a baseline, even with backup)
                          recipes-only   ONLY the selected recipes, appended to GEMINI.md as a
                                         marked block (requires --recipes=; block-aware uninstall)
                          reflector-only the self-improvement loop standalone (recipe text as a
                                         marked block + Reflector runtime; least-conflicting with
                                         other frameworks like Spec Kit / BMAD)
  --dry-run             Preview only — no files written
  --no-prompt           Skip all interactive prompts; apply sensible defaults (CI-safe)
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none. Customizations not in the
                        manifest are preserved.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering

Gemini single-file model:
  - All 5 universal rules + selected recipes are bundled into one always-loaded GEMINI.md.
  - There is NO per-pattern rule scoping (Gemini loads the whole file every session).
  - The 'coding-conventions' recipe ALSO produces .gemini/styleguide.md (Gemini's
    native style-guide convention).

What this adapter does NOT install (per ADR-004 honesty + ADR-021):
  - Hook guards (CONDUCTOR emits the Reflector hook when --recipes=self-improvement, ADR-032; other guards remain Claude-only, ADR-034)
  - Sub-agent personas (not yet emitted for Gemini — the tool supports sub-agents natively, ADR-031; agent emission is Phase 2)
  - Per-call model routing (supported natively by Gemini CLI, ADR-031; not yet automated by CONDUCTOR)
  - Built-in memory directory (DIY at .memory/ — see the note inside GEMINI.md)
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
  echo "Usage: bash adapters/gemini/transform.sh <target-project> [--recipes=...]" >&2
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

# Resolve CONDUCTOR root (where this script lives: adapters/gemini/).
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
# Print body to stdout.
strip_frontmatter() {
  local src="$1"
  /usr/bin/awk 'BEGIN{f=0} /^---$/{c++; if(c==2){f=1; next}} f==1' "$src"
}

# Derive a section title from a rule/recipe markdown file: the first H1 after the
# frontmatter, with the leading "# " stripped. Falls back to the basename.
derive_title() {
  local src="$1"
  local title
  title="$(strip_frontmatter "$src" | /usr/bin/grep -m1 '^# ' | /usr/bin/sed -e 's/^# *//')"
  if [ -z "$title" ]; then
    title="$(basename "$src" .md)"
  fi
  printf '%s' "$title"
}

# Emit a rule/recipe body into GEMINI.md as a section.
# The body (sans frontmatter) is demoted: its H1 "# Title" line is dropped (the
# caller supplies the "## " heading) and the Claude-only callout is rewritten for
# Gemini reality per transform-spec.md:
#   "> **Claude-only mechanism**: ..."  ->  "> **Note (Gemini)**: enforced by hook
#   on Claude Code; on Gemini CLI, follow self-policed."
# Honors DRY_RUN at the caller level (caller guards writes); this fn only prints.
emit_rule_body() {
  local src="$1"
  strip_frontmatter "$src" \
    | /usr/bin/awk '
        BEGIN{dropped=0}
        # Drop the first H1 (the section title is provided by the caller as "## ").
        dropped==0 && /^# /{dropped=1; next}
        # Rewrite Claude-only mechanism callouts for Gemini self-policing.
        /^> \*\*Claude-only mechanism\*\*/{
          print "> **Note (Gemini)**: enforced by hook on Claude Code; on Gemini CLI, follow self-policed."
          next
        }
        {print}
      '
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
# Format identical to Claude/Cursor adapter manifests. POSIX shell + sed only — no jq.

MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_STAGE_PATH=""
MANIFEST_TS=""
MANIFEST_LAST_BACKUP=""

# shellcheck source=../../tools/manifest-safety.sh
. "$CONDUCTOR_ROOT/tools/manifest-safety.sh"

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
  local esc_path esc_src esc_backup emitted_sha
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
  "version": "v$CONDUCTOR_VERSION",
  "adapter": "gemini",
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

backup_and_remember() {
  conductor_manifest_backup_and_remember "$1"
}

# ----- marked append-blocks (ADR-044, --mode=recipes-only / reflector-only) ----
#
# Single-file tools can't take recipes as separate files, so à-la-carte modes
# APPEND a marked block to the existing baseline instead of overwriting it:
#   <!-- conductor:block <name> -->
#   ...content...
#   <!-- /conductor:block <name> -->
# The manifest records {"type": "block", "sha256": <hash of content>, "created_file"}.
# Uninstall strips the block only when its content hash still matches (a customized
# block is left in place with a warning — backup ≠ silently destroying user edits).

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | /usr/bin/awk '{print $1}'
  else /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'; fi
}

# append_block <abs_file> <block_name> <content_file>
# Sets BLOCK_SHA + BLOCK_CREATED. Replaces the block if markers already exist.
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
        # Marked append-block entry (ADR-044) — strip the block, hash-guarded.
        entries_count=$((entries_count + 1))
        local b_rel b_name b_sha b_created b_abs b_open b_close b_cur b_cur_sha
        b_rel="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
        b_name="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
        b_sha="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"sha256": *"([^"]*)".*/\1/')"
        b_created="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"created_file": *(true|false).*/\1/')"
        b_abs="$TARGET_ABS/$b_rel"
        b_open="<!-- conductor:block $b_name -->"
        b_close="<!-- /conductor:block $b_name -->"
        if [ ! -f "$b_abs" ]; then
          log "  skip block '$b_name' ($b_rel already absent)"
          continue
        fi
        if ! /usr/bin/grep -qF "$b_open" "$b_abs"; then
          log "  skip block '$b_name' (markers already removed from $b_rel)"
          continue
        fi
        # Hash via the same direct pipe as emit-time (a shell-variable roundtrip
        # strips trailing newlines and breaks the comparison).
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
              log "  deleted $b_rel (file was created by CONDUCTOR and is now empty)"
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

  # Try to clean up empty dirs left behind (children before parents).
  for d in .gemini/commands .gemini/agents .conductor/reflect .conductor .gemini; do
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
  log "         Delete GEMINI.md and .gemini/styleguide.md manually if desired."
}

if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Wizard fires when adopter signal is detected: existing GEMINI.md OR existing .gemini/.
# Otherwise (truly fresh target) wizard is skipped.

IS_ADOPTER_CASE="false"
if [ -f "$TARGET_ABS/GEMINI.md" ] || [ -d "$TARGET_ABS/.gemini" ]; then
  IS_ADOPTER_CASE="true"
fi

detect_coexisting_frameworks

# --mode=strict: never overwrite an existing baseline, even with a backup (ADR-044).
if [ "$MODE" = "strict" ]; then
  for _sf in "GEMINI.md" ".gemini/styleguide.md"; do
    if [ -f "$TARGET_ABS/$_sf" ]; then
      echo "Error (--mode=strict): $TARGET_ABS/$_sf already exists — strict mode aborts instead of overwriting a baseline." >&2
      echo "  Use --mode=full (timestamped backup + manifest-based restore), or move the file first." >&2
      exit 3
    fi
  done
fi

# À-la-carte modes are non-interactive by design (they never touch the universal-rule choice).
if [ "$MODE" != "full" ] && [ "$MODE" != "strict" ]; then
  NO_PROMPT="true"
fi

if [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
  echo ""
  echo "========================================================"
  echo " Welcome to CONDUCTOR setup (Gemini CLI adapter)"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""

  printf "Detect existing config? (y/N): "
  read -r _detect_answer
  if [ "$_detect_answer" = "y" ] || [ "$_detect_answer" = "Y" ]; then
    _has_gemini="no"
    [ -f "$TARGET_ABS/GEMINI.md" ] && _has_gemini="yes"
    _has_styleguide="no"
    [ -f "$TARGET_ABS/.gemini/styleguide.md" ] && _has_styleguide="yes"
    echo "  GEMINI.md present: $_has_gemini, .gemini/styleguide.md present: $_has_styleguide"
  fi

  printf "Apply universal-rules bundle? (Y/n): "
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

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}"
fi

# ----- step 1: GEMINI.md bundle (header + rules + workflow + pointers) ----

init_manifest

UNIVERSAL_RULES="workflow spec-as-you-go quality-gates operations meta-discipline"
GEMINI_DEST="$TARGET_ABS/GEMINI.md"
INSTALLED_RECIPES=""

# Detect whether the coding-conventions recipe is in the selection (drives styleguide emit).
WANT_STYLEGUIDE="false"
if [ -n "$RECIPES" ]; then
  _old_ifs="$IFS"; IFS=','
  for _r in $RECIPES; do
    _r="$(printf '%s' "$_r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ "$_r" = "coding-conventions" ] && WANT_STYLEGUIDE="true"
  done
  IFS="$_old_ifs"
fi

if [ "$MODE" != "recipes-only" ] && [ "$MODE" != "reflector-only" ]; then

log "Step 1/3: GEMINI.md bundle → $GEMINI_DEST"

if [ -f "$GEMINI_DEST" ] && [ "$DRY_RUN" = "false" ]; then
  backup_and_remember "$GEMINI_DEST"
fi

if [ "$DRY_RUN" = "true" ]; then
  log "would synthesize $GEMINI_DEST (bilingual header + ABSOLUTE rules summary + 5 universal rules + workflow + memory note)"
  if [ "$WIZARD_APPLY_RULES" != "true" ]; then
    log "  (universal-rules opted out — header + workflow + docs pointer only)"
  fi
  if [ -n "$RECIPES" ]; then
    log "  would append recipe sections for: $RECIPES"
  fi
else
  # --- Header (synthesized inline; bilingual 한/영) ---
  /bin/cat > "$GEMINI_DEST" <<'HEADER_EOF'
# CONDUCTOR — Orchestrator Manual (Gemini CLI)

> Installed by CONDUCTOR (Gemini adapter). Gemini CLI auto-loads this file every session.
> Replace `{{PROJECT_NAME}}` below with your project name.

## You are the orchestrator / 당신은 오케스트레이터입니다

**EN** — You are the lead orchestrator for **{{PROJECT_NAME}}**. You translate the
user's intent into a disciplined Plan → Architecture → Tasks → Implementation →
Review → Spec workflow. The universal rules below are your operating floor; every
turn inherits them. Gemini CLI supports sub-agents and hooks natively (ADR-031),
but CONDUCTOR's Gemini adapter currently emits rule text (plus the Reflector loop)
only — full hook/agent emission is Phase 2 — so these rules are **self-policed**:
you follow them by reading them, not because an emitted hook blocks you.

**KO** — 당신은 **{{PROJECT_NAME}}** 의 리드 오케스트레이터입니다. 사용자의 의도를
Plan → Architecture → Tasks → Implementation → Review → Spec 워크플로로 옮깁니다.
아래 universal rule 은 모든 턴이 상속하는 기본 규칙입니다. Gemini CLI 는 sub-agent 와
hook 을 네이티브로 지원하지만 (ADR-031), CONDUCTOR 의 Gemini adapter 는 현재 rule 텍스트
(+ Reflector loop) 만 생성합니다 (hook/agent 자동 생성은 Phase 2) — 따라서 이 규칙들은
**자기 규율(self-policed)** 로 지켜야 합니다.

> **Note (Gemini)**: Claude Code enforces parts of these rules with PreToolUse / Stop
> hooks and sub-agent dispatch. Gemini CLI has those surfaces natively too (ADR-031),
> but CONDUCTOR does not emit hooks/agents here yet (Phase 2). Where a rule mentions a
> Claude-only mechanism, treat it as self-policed: read the rule, follow it.

## ABSOLUTE rules (summary) / 절대 규칙 요약

These are ABSOLUTE — no user shortcut ("just do it", "skip", "fast") waives them.
The full text is in the universal-rule sections that follow.

1. **Plan-first / docs-first** — Plan → Architecture → Tasks → Implementation, in order.
   Ad-hoc work is logged in `docs/CURRENT_WORK.md` BEFORE implementation. (Workflow)
2. **Spec-as-you-go** — a source edit and its spec/doc update happen in the SAME turn,
   never batched for later. (Spec-as-you-go)
3. **Quality gates** — pre-commit + pre-merge review, test-coverage sync, and
   verify-after-changes (evidence before any "done" claim). (Quality Gates)
4. **Operations hygiene** — read `docs/CURRENT_WORK.md` first every session; delete
   completed tasks from active lists; keep dev/prod in parity. (Operations)
5. **Meta-discipline** — framework originality, ambiguity handling (ASK on the AMB
   triggers), token economy, model-tier classification, flat-with-leader topology.
   (Meta-Discipline)

> **Process over speed**: if a rule marked ABSOLUTE was skipped mid-turn, STOP, surface
> the violation in your next message, repair it, then continue. Silent recovery is worse
> than the original skip.

---

HEADER_EOF

  # --- Universal rules (each as "## <title>" + body sans frontmatter) ---
  if [ "$WIZARD_APPLY_RULES" = "true" ]; then
    for rule in $UNIVERSAL_RULES; do
      src="$CORE_ROOT/universal-rules/$rule.md"
      if [ ! -f "$src" ]; then
        echo "Warning: $src not found; skipping" >&2
        continue
      fi
      title="$(derive_title "$src")"
      {
        echo "## $title"
        echo ""
        emit_rule_body "$src"
        echo ""
        echo "---"
        echo ""
      } >> "$GEMINI_DEST"
    done
  else
    log "  universal-rules — skipped (user opted out)"
  fi

  # --- Compressed workflow section from core/workflow/PHASES.md ---
  PHASES_SRC="$CORE_ROOT/workflow/PHASES.md"
  if [ -f "$PHASES_SRC" ]; then
    {
      echo "## Workflow phases (compressed)"
      echo ""
      echo "> Full reference: CONDUCTOR's core/workflow/PHASES.md. Compressed here for the"
      echo "> single-file Gemini bundle. Phases scale with scope (see the table at the end)."
      echo ""
      # Compress: keep numbered phase headers + their Trigger/Owner/Inputs/Outputs
      # lines and the scaling table; drop the "How to read this file" template
      # preamble and the per-phase "P1 fill" scaffolding.
      /usr/bin/awk '
        /^## [0-9]+\. /{inphase=1; print "### " substr($0,4); next}
        inphase==1 && /^\*\*Trigger\*\*/{print; next}
        inphase==1 && /^\*\*Owner\*\*/{print; next}
        inphase==1 && /^\*\*Inputs\*\*/{print; next}
        inphase==1 && /^\*\*Outputs\*\*/{print; next}
        /^## Phase scaling reminder/{inphase=0; intable=1; print "### Phase scaling"; next}
        /^## Tool-agnostic enforcement reminder/{intable=0; next}
        intable==1{print; next}
      ' "$PHASES_SRC"
      echo ""
      echo "---"
      echo ""
    } >> "$GEMINI_DEST"
  fi

  # --- Recipe sections (Gemini is single-file: append into GEMINI.md) ---
  if [ -n "$RECIPES" ]; then
    IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
    for r in "${RECIPE_LIST[@]}"; do
      r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
      [ -z "$r" ] && continue
      src="$CORE_ROOT/recipes/$r.md"
      if [ ! -f "$src" ]; then
        echo "Warning: recipe '$r' not found at $src; skipping" >&2
        continue
      fi
      {
        echo "## Recipe — $r"
        echo ""
        echo "> Opt-in recipe (installed via --recipes=$r). Gemini has no per-file rule"
        echo "> scoping, so this is always-loaded alongside the universal rules."
        echo ""
        emit_rule_body "$src"
        echo ""
        echo "---"
        echo ""
      } >> "$GEMINI_DEST"
      INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
    done
  fi

  # --- Docs pointer + memory note (footer) ---
  /bin/cat >> "$GEMINI_DEST" <<'FOOTER_EOF'
## First read every session / 매 세션 첫 작업

**Read `docs/CURRENT_WORK.md` first every session.** It is the single source of
"what is happening right now" — current state, immediate next action, in-progress
items, blockers. Without it you risk duplicating finished work or pushing
conflicting changes. (See the Operations rule above.)

## Memory (.memory/) — DIY on Gemini / 메모리 설정

Gemini CLI has no built-in memory directory. CONDUCTOR's 4-type memory pattern
(user / feedback / project / reference) still applies — just host it yourself:

1. Create a `.memory/` directory at the project root.
2. Add `.memory/` to `.gitignore` so personal entries don't leak into the repo.
3. Keep a `.memory/MEMORY.md` index (≤ 200 lines) and `*.md` entries per type.
4. Gemini won't auto-load it — paste the relevant `.memory/*.md` entry into your
   prompt (or @-mention the file) when it's relevant to the task.

Save: a user's role/preferences, corrections + validated approaches, ongoing
project goals/deadlines (use absolute dates), and pointers to external systems.
Do NOT save code patterns, file paths, git history, or anything already in the
rules above — verify before recommending from memory ("memory says X" ≠ "X is true now").
FOOTER_EOF

  log "  wrote $GEMINI_DEST ($(/usr/bin/wc -l < "$GEMINI_DEST" | /usr/bin/tr -d ' ') lines)"

  # Gemini context-limit advisory (per transform-spec.md edge case).
  _gemini_lines="$(/usr/bin/wc -l < "$GEMINI_DEST" | /usr/bin/tr -d ' ')"
  if [ "$_gemini_lines" -gt 2000 ]; then
    log "  NOTE: GEMINI.md is large ($_gemini_lines lines). Most Gemini Pro models have a"
    log "        large context window, but if you hit a limit, trim recipes or move detail to docs/."
  fi
fi
record_emit "GEMINI.md" "<synthesized:5-universal-rules+workflow>" "$MANIFEST_LAST_BACKUP"

else
  # ----- à-la-carte modes: marked block appended to GEMINI.md (ADR-044) ------
  BLOCK_NAME="recipes"; [ "$MODE" = "reflector-only" ] && BLOCK_NAME="reflector"
  log "Step 1/3: --mode=$MODE — '$BLOCK_NAME' marked block → $GEMINI_DEST (no full bundle)"
  if [ "$DRY_RUN" = "true" ]; then
    log "would append marked block '$BLOCK_NAME' (selected recipes: $RECIPES) to $GEMINI_DEST"
  else
    _blk="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/conductor-block.XXXXXX")"
    {
      echo "# CONDUCTOR — à la carte (--mode=$MODE)"
      echo ""
      echo "> Installed by CONDUCTOR WITHOUT the universal-rule bundle. This is a managed"
      echo "> block: --uninstall strips it when unmodified. Full workflow: --mode=full."
      echo ""
      IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
      for r in "${RECIPE_LIST[@]}"; do
        r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
        [ -z "$r" ] && continue
        src="$CORE_ROOT/recipes/$r.md"
        if [ ! -f "$src" ]; then
          echo "Warning: recipe '$r' not found at $src; skipping" >&2
          continue
        fi
        echo "## Recipe — $r"
        echo ""
        emit_rule_body "$src"
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
    append_block "$GEMINI_DEST" "$BLOCK_NAME" "$_blk"
    /bin/rm -f "$_blk"
    record_emit_block "GEMINI.md" "$BLOCK_NAME" "$BLOCK_SHA" "$BLOCK_CREATED"
    # Preserve OTHER à-la-carte blocks from a previous install (e.g. recipes-only
    # then reflector-only): carry their manifest entries forward so uninstall can
    # still strip them (ADR-044 review fix — cross-mode orphaned block).
    if [ -f "$MANIFEST_PATH" ]; then
      while IFS= read -r _prev; do
        case "$_prev" in *'"type": "block"'*) : ;; *) continue ;; esac
        _pname="$(printf '%s' "$_prev" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
        [ "$_pname" = "$BLOCK_NAME" ] && continue
        if /usr/bin/grep -qF "<!-- conductor:block $_pname -->" "$GEMINI_DEST" 2>/dev/null; then
          printf '%s\n' "$_prev" | /usr/bin/sed 's/,*$/,/' >> "$MANIFEST_STAGE_PATH"
          log "  preserved previous block '$_pname' in manifest"
        fi
      done < "$MANIFEST_PATH"
    fi
  fi
fi

# ----- step 2: .gemini/styleguide.md (opt-in: coding-conventions) ---------

if [ "$MODE" != "full" ] && [ "$MODE" != "strict" ]; then
  # À la carte: the marked block is the sole carrier (no side files); minimal ships text only.
  WANT_STYLEGUIDE="false"
fi
log "Step 2/3: .gemini/styleguide.md (opt-in via --recipes=coding-conventions)"
if [ "$WANT_STYLEGUIDE" = "true" ]; then
  STYLE_SRC="$CORE_ROOT/recipes/coding-conventions.md"
  STYLE_DEST="$TARGET_ABS/.gemini/styleguide.md"
  if [ ! -f "$STYLE_SRC" ]; then
    echo "Warning: $STYLE_SRC not found; skipping styleguide" >&2
  else
    mkdir_if_real "$TARGET_ABS/.gemini"
    if [ "$DRY_RUN" = "true" ]; then
      log "would write $STYLE_DEST (coding-conventions body, header '# Code style guide')"
    else
      backup_and_remember "$STYLE_DEST"
      {
        echo "# Code style guide for {{PROJECT_NAME}}"
        echo ""
        echo "> Installed by CONDUCTOR (Gemini adapter) from the coding-conventions recipe."
        echo "> Gemini CLI treats .gemini/styleguide.md as the canonical code-style reference."
        echo "> Replace {{PROJECT_NAME}} with your project name."
        echo ""
        emit_rule_body "$STYLE_SRC"
      } > "$STYLE_DEST"
      record_emit ".gemini/styleguide.md" "core/recipes/coding-conventions.md" "$MANIFEST_LAST_BACKUP"
      log "  wrote $STYLE_DEST"
    fi
  fi
else
  log "  (coding-conventions not selected — pass --recipes=coding-conventions to emit styleguide)"
fi

# ----- self-improvement (opt-in: self-improvement recipe) ------------------

if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    log "Step: self-improvement (Reflector) → .gemini hooks/command/agent"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.gemini/commands" "$TARGET_ABS/.gemini/agents"
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
      # settings.json hooks — only if absent (merging JSON is unsafe in bash)
      hc="$TARGET_ABS/.gemini/settings.json"
      if [ ! -f "$hc" ]; then
        backup_and_remember "$hc"
        /bin/cat > "$hc" <<'HOOK'
{
  "hooks": {
    "SessionEnd": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "\"$GEMINI_PROJECT_DIR\"/.conductor/reflect/trajectory-log.sh", "timeout": 30000 } ] }
    ]
  }
}
HOOK
        record_emit ".gemini/settings.json" "<synthesized>" "$MANIFEST_LAST_BACKUP"
      else
        log "  .gemini/settings.json exists — add a SessionEnd hook calling .conductor/reflect/trajectory-log.sh manually"
      fi
      cmd="$TARGET_ABS/.gemini/commands/reflect.toml"
      backup_and_remember "$cmd"
      { printf 'description = "Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only)."\nprompt = """\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; printf '\n"""\n'; } > "$cmd"
      record_emit ".gemini/commands/reflect.toml" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      ag="$TARGET_ABS/.gemini/agents/reflector.md"
      backup_and_remember "$ag"
      { printf -- '---\nname: reflector\ndescription: Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies.\n---\n\n'; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; } > "$ag"
      record_emit ".gemini/agents/reflector.md" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
    fi
    ;;
esac

# ----- step 3: docs templates --------------------------------------------

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 3/3: docs templates — skipped (--mode=$MODE is à la carte; docs ship with full/minimal)"
else
log "Step 3/3: docs templates → docs/"
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
echo " Done."
echo "  Target: $TARGET_ABS"
echo "  Adapter: gemini"
echo "  Mode: $MODE"
if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  echo "  GEMINI.md: marked à-la-carte block appended (no universal-rule bundle)"
else
  echo "  GEMINI.md: 1 bundled file (5 universal rules + workflow, always-loaded)"
fi
echo "  Style guide: $([ "$WANT_STYLEGUIDE" = "true" ] && echo ".gemini/styleguide.md emitted" || echo "(not emitted — select coding-conventions)")"
echo "  Recipes installed:${INSTALLED_RECIPES:- (none)}"
echo ""
echo " Skipped (per ADR-004 honesty):"
echo "  - Hooks: CONDUCTOR emits the Reflector hook when --recipes=self-improvement (ADR-032); other guards remain Claude-only (ADR-034)."
echo "  - Sub-agent personas: not yet emitted for Gemini (tool supports sub-agents natively — ADR-031; Phase 2)."
echo "  - Per-call model routing: supported natively by Gemini CLI (ADR-031); not yet automated by CONDUCTOR."
echo "  - Built-in memory: DIY at .memory/ (see the note inside GEMINI.md)."
echo ""
echo " Activation: open $TARGET_ABS with Gemini CLI — it loads GEMINI.md automatically."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Replace {{PROJECT_NAME}} in GEMINI.md (and .gemini/styleguide.md if present)."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. Add .memory/ to .gitignore if you adopt the DIY memory pattern."
echo "  4. Rename docs/specs/_example.md → docs/specs/<your-area>.md."
