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
#   core/runtime-kernel.md         →  <target>/GEMINI.md          (bounded always-loaded kernel)
#   core/universal-rules/*.md      →  <target>/.gemini/conductor/rules/*.md
#   core/recipes/*.md (selected)   →  <target>/.gemini/conductor/recipes/*.md
#   core/recipes/coding-conventions →  <target>/.gemini/styleguide.md  (Gemini style-guide convention; opt-in)
#   core/docs-templates/*.md       →  <target>/docs/*.md          (CURRENT_WORK, REMAINING_TASKS, etc.)
#   core/hooks/*.sh.template       →  Gemini-verified lifecycle/recipe subset only; Claude/Codex have additional verified guards
#   core/roles/*.md                →  <target>/.gemini/agents/*.md (native roles; saved Tier model — ADR-049)
#
# Gemini reality (per adapters/gemini/SUPPORTED-FEATURES.md):
#   - Single bounded always-loaded kernel (GEMINI.md). Complete references use explicit Read routing.
#   - Gemini CLI supports sub-agents / hooks / per-call model routing natively
#     (ADR-031); this adapter emits native role profiles in full/strict mode. CONDUCTOR
#     emits the Reflector hook when --recipes=self-improvement (ADR-032); other
#     additional workflow guards are not emitted by this adapter.
#   The bundle carries universal rule text and states per-tool enforcement truthfully.

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
CONDUCTOR_PREFLIGHT="false"
if [ "${CONDUCTOR_CLI_DISPATCH:-0}" = "2" ]; then
  command -v node >/dev/null 2>&1 || {
    echo "Error: node is required to verify CONDUCTOR adapter dispatch." >&2
    exit 127
  }
  if node "$CONDUCTOR_ROOT/bin/adapter-dispatch.js" verify gemini; then
    CONDUCTOR_CLI_CHILD="true"
  else
    echo "Error: invalid or expired CONDUCTOR CLI adapter-dispatch proof." >&2
    exit 2
  fi
fi
if [ "$CONDUCTOR_CLI_CHILD" = "true" ]; then
  _conductor_forwarded_args=()
  for _conductor_arg in "${ORIGINAL_ARGS[@]}"; do
    if [ "$_conductor_arg" = "--conductor-preflight" ]; then
      CONDUCTOR_PREFLIGHT="true"
    else
      _conductor_forwarded_args+=("$_conductor_arg")
    fi
  done
  ORIGINAL_ARGS=("${_conductor_forwarded_args[@]}")
  set -- "${ORIGINAL_ARGS[@]}"
  [ "$CONDUCTOR_PREFLIGHT" != "true" ] || exit 0
fi
if [ "$CONDUCTOR_CLI_CHILD" != "true" ] && [ "$CONDUCTOR_DELEGATE_TO_CLI" = "true" ]; then
  command -v node >/dev/null 2>&1 || {
    echo "Error: node is required for one-time CONDUCTOR model setup." >&2
    exit 127
  }
  exec node "$CONDUCTOR_ROOT/bin/omniconductor.js" init --target=gemini "${ORIGINAL_ARGS[@]}"
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
Usage: bash adapters/gemini/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Exact recipe list (compact routing in GEMINI.md; complete references separate)
  --mode=<m>            Install preset (ADR-044). One of:
                          full           (default) everything this adapter emits today
                          minimal        discipline text + session continuity only
                                         (GEMINI.md + docs/; no styleguide, no Reflector runtime)
                          strict         full, but ABORT (exit 3) if GEMINI.md already exists
                                         (never overwrites a baseline, even with backup)
                          recipes-only   compact selected-recipe routing appended to GEMINI.md;
                                         complete references stay outside eager context
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

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, non-vacuous-testing, debugging, database-discipline, database-change-assurance, design-system, visual-baseline-integrity, release-provenance, self-improvement, git-hygiene, loop-engineering

Gemini single-file model:
  - GEMINI.md stays bounded; all 5 universal rules and selected recipes are complete on-demand references.
  - There is NO per-pattern rule scoping (Gemini loads the whole file every session).
  - The 'coding-conventions' recipe ALSO produces .gemini/styleguide.md (Gemini's
    native style-guide convention).

What this adapter does NOT install (per ADR-004 honesty + ADR-021):
  - Unverified guard ports (CONDUCTOR emits only Gemini contracts verified by this adapter; Reflector is opt-in)
  - Claude-only Agent/Read hook contracts and Hookify rules
  - Unvalidated model values (the CLI supplies the saved Tier mapping)
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
    < <(node "$CONDUCTOR_ROOT/bin/model-routing.js" resolve "$TARGET_ABS" gemini)
  [ "${#_conductor_models[@]}" -eq 3 ] || { echo "Error: valid Gemini Tier routing is required before installation." >&2; exit 2; }
  export CONDUCTOR_GEMINI_MODEL_TIER_1="${_conductor_models[0]}"
  export CONDUCTOR_GEMINI_MODEL_TIER_2="${_conductor_models[1]}"
  export CONDUCTOR_GEMINI_MODEL_TIER_3="${_conductor_models[2]}"
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
# caller supplies the "## " heading). Tool-specific capability tables in the
# source are preserved verbatim; the adapter must not rewrite them into stale
# provider-only claims.
# Honors DRY_RUN at the caller level (caller guards writes); this fn only prints.
emit_rule_body() {
  local src="$1"
  strip_frontmatter "$src" \
    | /usr/bin/awk '
        BEGIN{dropped=0}
        # Drop the first H1 (the section title is provided by the caller as "## ").
        dropped==0 && /^# /{dropped=1; next}
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

LEGACY_MANIFEST_PATH="$TARGET_ABS/.conductor-manifest.json"
MANIFEST_PATH="$TARGET_ABS/.conductor/manifests/gemini.json"
MANIFEST_STAGE_PATH=""
MANIFEST_TS=""
MANIFEST_LAST_BACKUP=""

# shellcheck source=../../tools/manifest-safety.sh
. "$CONDUCTOR_ROOT/tools/manifest-safety.sh"
conductor_manifest_prepare "gemini"

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
  conductor_manifest_publish_projection
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

  # Try to clean up empty dirs left behind (children before parents).
  for d in .agents/skills/coordinate-work .agents/skills/propose-skill .agents/skills/plan-change .agents/skills/verify-change .agents/skills/review-change .agents/skills .agents .gemini/commands .gemini/agents .gemini/hooks .gemini/conductor/rules .gemini/conductor/recipes .gemini/conductor .conductor/reflect .conductor/manifests .conductor .gemini docs/plans docs/architecture docs/research docs/specs docs; do
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

  if [ "${CONDUCTOR_RECIPE_ONBOARDING_RESOLVED:-0}" = "1" ]; then
    echo "  Recipes resolved once by the central installer: ${RECIPES:-(none)}"
  else
    echo ""
    echo "Available recipes:"
    echo "  web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, non-vacuous-testing, debugging, database-discipline, database-change-assurance, design-system, visual-baseline-integrity, release-provenance, self-improvement, git-hygiene, loop-engineering"
    printf "Select recipes (comma-separated, or leave blank for none): "
    read -r _recipe_answer
    if [ -n "$_recipe_answer" ]; then RECIPES="$_recipe_answer"; echo "  Recipes selected: $RECIPES"; else echo "  No recipes selected."; fi
  fi

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}"
fi

# ----- step 1: GEMINI.md bundle (header + rules + workflow + pointers) ----

# Validate all Tier pins before any managed file is emitted. Tier 3 is normally
# handled directly by the orchestrator and has no dedicated role profile.
# Uninstall returned above and remains available even with a stale override.
GEMINI_TIER_1_MODEL="${CONDUCTOR_GEMINI_MODEL_TIER_1:-inherit}"
GEMINI_TIER_2_MODEL="${CONDUCTOR_GEMINI_MODEL_TIER_2:-inherit}"
GEMINI_TIER_3_MODEL="${CONDUCTOR_GEMINI_MODEL_TIER_3:-inherit}"
conductor_validate_model_slug "$GEMINI_TIER_1_MODEL" "Gemini Tier 1 model" || exit 1
conductor_validate_model_slug "$GEMINI_TIER_2_MODEL" "Gemini Tier 2 model" || exit 1
conductor_validate_model_slug "$GEMINI_TIER_3_MODEL" "Gemini Tier 3 model" || exit 1

conductor_assert_portable_skill_collisions "gemini" ".agents/skills" || exit $?
case "$MODE,$RECIPES," in
  full,*|strict,*|*,self-improvement,*) conductor_validate_hook_config "gemini" ".gemini/settings.json" || exit 1 ;;
esac
init_manifest
conductor_install_project_profile
conductor_install_portable_skills "gemini" ".agents/skills"

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
GEMINI_BASELINE_BACKUP="$MANIFEST_LAST_BACKUP"

if [ "$DRY_RUN" = "true" ]; then
  log "would synthesize $GEMINI_DEST (bilingual header + ABSOLUTE rules summary + 5 universal rules + workflow + memory note)"
  if [ "$WIZARD_APPLY_RULES" != "true" ]; then
    log "  (universal-rules opted out — header + workflow + docs pointer only)"
  fi
  if [ -n "$RECIPES" ]; then
    log "  would append recipe sections for: $RECIPES"
  fi
else
  mkdir_if_real "$TARGET_ABS/.gemini/conductor/rules"
  if [ "$WIZARD_APPLY_RULES" = "true" ]; then
    for rule in $UNIVERSAL_RULES; do
      src="$CORE_ROOT/universal-rules/$rule.md"
      [ -f "$src" ] || { echo "Warning: $src not found; skipping" >&2; continue; }
      dest="$TARGET_ABS/.gemini/conductor/rules/$rule.md"
      backup_and_remember "$dest"
      /bin/cp "$src" "$dest"
      record_emit ".gemini/conductor/rules/$rule.md" "core/universal-rules/$rule.md" "$MANIFEST_LAST_BACKUP"
    done
  else
    log "  universal-rules — skipped (user opted out)"
  fi
  mkdir_if_real "$TARGET_ABS/.gemini/conductor/recipes"
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
      dest="$TARGET_ABS/.gemini/conductor/recipes/$r.md"
      backup_and_remember "$dest"
      /bin/cp "$src" "$dest"
      record_emit ".gemini/conductor/recipes/$r.md" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
      INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
    done
  fi
  {
    conductor_render_runtime_kernel "Gemini CLI" ".gemini/conductor/rules" ".gemini/conductor/recipes" "$WIZARD_APPLY_RULES" "$RECIPES"
    /bin/cat <<'GEMINI_APPENDIX'

## Gemini CLI native appendix

Gemini has no verified per-pattern rule loader in this adapter contract. Do not
eagerly import every reference into `GEMINI.md`; use the Read tool for the exact
rule or selected recipe named above. Full/strict installs expose eight native
roles under `.gemini/agents/`. Hook configuration uses only verified Gemini event
and decision schemas; unsupported Claude-only behavior remains an explicit rule.
GEMINI_APPENDIX
  } > "$GEMINI_DEST"

  log "  wrote $GEMINI_DEST ($(/usr/bin/wc -l < "$GEMINI_DEST" | /usr/bin/tr -d ' ') lines)"
fi
record_emit "GEMINI.md" "core/runtime-kernel.md" "$GEMINI_BASELINE_BACKUP"

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
      echo "> block: --uninstall strips it when unmodified. Complete recipe text is"
      echo "> stored outside the eager GEMINI.md surface and read only when applicable."
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
        /bin/mkdir -p "$TARGET_ABS/.gemini/conductor/recipes"
        ref="$TARGET_ABS/.gemini/conductor/recipes/$r.md"
        backup_and_remember "$ref"
        /bin/cp "$src" "$ref"
        record_emit ".gemini/conductor/recipes/$r.md" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
        conductor_render_recipe_pointer_body "$src" ".gemini/conductor/recipes/$r.md"
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
        conductor_manifest_stage_has_block "GEMINI.md" "$_pname" && continue
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

gemini_role_tools() {
  local src="$1" items="" tool
  if conductor_role_has_capability "$src" read; then
    for tool in read_file read_many_files list_directory; do items="${items}${items:+, }\"$tool\""; done
  fi
  if conductor_role_has_capability "$src" search; then
    for tool in glob grep_search; do items="${items}${items:+, }\"$tool\""; done
  fi
  if conductor_role_has_capability "$src" edit-code || conductor_role_has_capability "$src" edit-docs; then
    for tool in replace write_file; do items="${items}${items:+, }\"$tool\""; done
  fi
  if conductor_role_has_capability "$src" shell; then items="${items}${items:+, }\"run_shell_command\""; fi
  if conductor_role_has_capability "$src" delegate; then
    echo "Error: Gemini role '$src' grants delegate, but Gemini subagents cannot call other subagents" >&2
    return 1
  fi
  if conductor_role_has_capability "$src" mcp; then
    echo "Error: Gemini role '$src' grants abstract mcp without a named server/tool allowlist" >&2
    return 1
  fi
  [ -n "$items" ] || { echo "Error: Gemini role '$src' compiles to an empty native tool allowlist" >&2; return 1; }
  printf '[%s]' "$items"
}

if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  log "Step: native roles → .gemini/agents/"
  if [ "$DRY_RUN" != "true" ]; then
    /bin/mkdir -p "$TARGET_ABS/.gemini/agents"
    for role in planner reviewer code-reviewer builder helper designer scribe utility; do
      role_src="$CORE_ROOT/roles/$role.md"
      tier="$(conductor_role_difficulty_tier "$role_src")" || exit 1
      tier_label="$(conductor_difficulty_label "$tier")" || exit 1
      role_tools="$(gemini_role_tools "$role_src")" || exit 1
      capability_contract="$(conductor_role_capability_contract "$role_src")" || exit 1
      max_turns="$(conductor_role_max_turns "$role_src" 2>/dev/null || true)"
      case "$tier" in
        1) model="$GEMINI_TIER_1_MODEL" ;;
        2) model="$GEMINI_TIER_2_MODEL" ;;
        3) model="$GEMINI_TIER_3_MODEL" ;;
      esac
      conductor_validate_model_slug "$model" "Gemini model for $role" || exit 1
      case "$role" in
        planner) desc="Architecture, gap analysis, and trade-off planning without implementation." ;;
        reviewer) desc="Read-only pre-implementation review of plans, architecture, and tasks." ;;
        code-reviewer) desc="Read-only post-implementation review for correctness, security, regressions, and tests." ;;
        builder) desc="Primary implementation owner for cross-cutting or high-risk changes." ;;
        helper) desc="Focused implementation owner for bounded, independent changes." ;;
        designer) desc="UI and interaction implementation owner with design-system discipline." ;;
        scribe) desc="Documentation, changelog, index, and session-state maintenance." ;;
        utility) desc="Bounded Tier 3 lookup or trivial one-file edit; escalate immediately if scope grows." ;;
      esac
      ag="$TARGET_ABS/.gemini/agents/$role.md"
      backup_and_remember "$ag"
      {
        printf -- '---\nname: %s\ndescription: %s\nmodel: %s\ntools: %s\n' "$role" "$desc" "$model" "$role_tools"
        [ -z "$max_turns" ] || printf 'max_turns: %s\n' "$max_turns"
        printf -- '---\n\n> CONDUCTOR difficulty contract: **%s**. The Tier is invariant; `model: %s` is the Gemini adapter translation.\n\n> CONDUCTOR capability contract: **%s**. Native enforcement: Gemini `tools` is an isolated allowlist; test never widens to `run_shell_command`, edit-code / edit-docs share replace/write_file, and MCP requires a separately named grant.\n\n' "$tier_label" "$model" "$capability_contract"
        strip_frontmatter "$role_src"
      } > "$ag"
      record_emit ".gemini/agents/$role.md" "core/roles/$role.md" "$MANIFEST_LAST_BACKUP"
    done
  fi
fi

# ----- native config: output-cap (Spec E, token-economy) -------------------
# Always-on BeforeTool guard for full/strict — independent of recipes, same
# gating as the native roles step above and as Claude's PostToolUse output-cap
# hook. Gemini has no post-hoc tool-output edit surface, so the cap rewrites
# run_shell_command to merge stdout+stderr and pipe the combined stream through
# a byte-capping awk truncator before the
# command runs (see core/hooks/output-cap.sh.template, gemini dialect).
GEMINI_CAP_APPLIES="false"
GEMINI_HOOK_FEATURES=""
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  GEMINI_CAP_APPLIES="true"
  GEMINI_HOOK_FEATURES="baseline,output-cap"
  log "Step: output-cap (BeforeTool shell-arg rewrite) → .gemini/hooks/output-cap.sh"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $TARGET_ABS/.gemini/hooks/output-cap.sh"
  else
    /bin/mkdir -p "$TARGET_ABS/.gemini/hooks"
    cap_dest="$TARGET_ABS/.gemini/hooks/output-cap.sh"
    backup_and_remember "$cap_dest"
    /bin/cp "$CORE_ROOT/hooks/output-cap.sh.template" "$cap_dest"
    /bin/chmod +x "$cap_dest"
    record_emit ".gemini/hooks/output-cap.sh" "core/hooks/output-cap.sh.template" "$MANIFEST_LAST_BACKUP"
    review_dest="$TARGET_ABS/.gemini/hooks/stop-r6-review-check.sh"
    backup_and_remember "$review_dest"
    /bin/cp "$CORE_ROOT/hooks/stop-r6-review-check.sh.template" "$review_dest"
    /bin/chmod +x "$review_dest"
    record_emit ".gemini/hooks/stop-r6-review-check.sh" "core/hooks/stop-r6-review-check.sh.template" "$MANIFEST_LAST_BACKUP"
  fi
fi

if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
GEMINI_REFLECTOR_APPLIES="false"
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    GEMINI_REFLECTOR_APPLIES="true"
    GEMINI_HOOK_FEATURES="${GEMINI_HOOK_FEATURES:+$GEMINI_HOOK_FEATURES,}self-improvement"
    log "Step: self-improvement (Reflector) → .gemini hooks/command/agent"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.gemini/commands" "$TARGET_ABS/.gemini/agents"
      conductor_install_trajectory_ignore
      for s in trajectory-log prune-lessons run-weekly; do
        d="$TARGET_ABS/.conductor/reflect/$s.sh"
        backup_and_remember "$d"; /bin/cp "$CORE_ROOT/reflector/$s.sh" "$d"; /bin/chmod +x "$d"
        record_emit ".conductor/reflect/$s.sh" "core/reflector/$s.sh" "$MANIFEST_LAST_BACKUP"
      done
      d="$TARGET_ABS/.conductor/reflect/reflection-proposals.js"
      backup_and_remember "$d"; /bin/cp "$CORE_ROOT/reflector/reflection-proposals.js" "$d"
      record_emit ".conductor/reflect/reflection-proposals.js" "core/reflector/reflection-proposals.js" "$MANIFEST_LAST_BACKUP"
      # scheduling assets: run-weekly.sh needs the brief; SCHEDULING.md documents registration
      for m in reflect-brief SCHEDULING; do
        d="$TARGET_ABS/.conductor/reflect/$m.md"
        backup_and_remember "$d"; /bin/cp "$CORE_ROOT/reflector/$m.md" "$d"
        record_emit ".conductor/reflect/$m.md" "core/reflector/$m.md" "$MANIFEST_LAST_BACKUP"
      done
      cmd="$TARGET_ABS/.gemini/commands/reflect.toml"
      backup_and_remember "$cmd"
      { printf 'description = "Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only)."\nprompt = """\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; printf '\n"""\n'; } > "$cmd"
      record_emit ".gemini/commands/reflect.toml" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      ag="$TARGET_ABS/.gemini/agents/reflector.md"
      backup_and_remember "$ag"
      tier="$(conductor_role_difficulty_tier "$CORE_ROOT/roles/reflector.md")" || exit 1
      tier_label="$(conductor_difficulty_label "$tier")" || exit 1
      model="$GEMINI_TIER_1_MODEL"
      conductor_validate_model_slug "$model" "Gemini model for reflector" || exit 1
      role_tools="$(gemini_role_tools "$CORE_ROOT/roles/reflector.md")" || exit 1
      capability_contract="$(conductor_role_capability_contract "$CORE_ROOT/roles/reflector.md")" || exit 1
      { printf -- '---\nname: reflector\ndescription: Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies.\nmodel: %s\ntools: %s\n---\n\n> CONDUCTOR difficulty contract: **%s**. The Tier is invariant; `model: %s` is the Gemini adapter translation.\n\n> CONDUCTOR capability contract: **%s**. Native enforcement: Gemini `tools` is an isolated allowlist; test never widens to `run_shell_command`, edit-code / edit-docs share replace/write_file, and MCP requires a separately named grant.\n\n' "$model" "$role_tools" "$tier_label" "$model" "$capability_contract"; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; } > "$ag"
      record_emit ".gemini/agents/reflector.md" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
    fi
    ;;
esac

# ----- unified .gemini/settings.json -------------------------------------
if [ -n "$GEMINI_HOOK_FEATURES" ]; then
  log "Step: .gemini/settings.json → schema-aware native hook composition"
  conductor_install_hook_config "gemini" ".gemini/settings.json" "$GEMINI_HOOK_FEATURES" || exit 1
fi

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

for doc_rel in plans/README.md architecture/README.md research/README.md; do
  src="$CORE_ROOT/docs-templates/$doc_rel"
  dest="$TARGET_ABS/docs/$doc_rel"
  [ -f "$src" ] || continue
  mkdir_if_real "$TARGET_ABS/docs/${doc_rel%/*}"
  if [ -f "$dest" ]; then
    log "  $dest exists — leaving in place"
  elif [ "$DRY_RUN" = "true" ]; then
    log "would copy $src -> $dest"
  else
    /bin/cp "$src" "$dest"
    record_emit "docs/$doc_rel" "core/docs-templates/$doc_rel" ""
  fi
done

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
  echo "  GEMINI.md: bounded kernel + complete on-demand rule/recipe references"
fi
echo "  Style guide: $([ "$WANT_STYLEGUIDE" = "true" ] && echo ".gemini/styleguide.md emitted" || echo "(not emitted — select coding-conventions)")"
echo "  Recipes installed:${INSTALLED_RECIPES:- (none)}"
echo ""
echo " Runtime / capability boundary:"
echo "  - Hooks: only verified Gemini contracts are emitted; the Reflector hook is opt-in (ADR-032/045)."
if [ "$MODE" = "full" ] || [ "$MODE" = "strict" ]; then
  echo "  - Native roles: 8 profiles in .gemini/agents/."
else
  echo "  - Native roles: omitted by --mode=$MODE."
fi
echo "  - Model routing: profiles use the project-saved Tier mapping; recommended aliases are pro/flash/flash-lite."
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
