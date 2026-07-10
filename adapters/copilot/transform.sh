#!/usr/bin/env bash
#
# CONDUCTOR — GitHub Copilot adapter transform.sh
#
# Reads core/ assets and writes them into a target project as native GitHub Copilot
# custom instructions files: .github/copilot-instructions.md (repo-wide) and
# .github/instructions/*.instructions.md (per-file with applyTo: globs).
#
# Strategic value: Copilot custom instructions are IDE-agnostic — a single file format
# is consumed by VS Code, Cursor (Copilot extension), Windsurf (Copilot adapter),
# JetBrains (Copilot plugin), and Neovim (copilot.vim). One adapter covers 5 IDEs.
#
# Usage:
#   bash adapters/copilot/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--no-prompt] [--per-rule] [--force]
#   bash adapters/copilot/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/copilot/transform.sh ~/Projects/my-app
#   bash adapters/copilot/transform.sh ~/Projects/my-app --recipes=monorepo,i18n
#   bash adapters/copilot/transform.sh /tmp/test --dry-run
#   bash adapters/copilot/transform.sh . --no-prompt --recipes=coding-conventions
#   bash adapters/copilot/transform.sh . --per-rule        # split universal rules into 5 per-file files
#   bash adapters/copilot/transform.sh . --uninstall       # revert install
#   bash adapters/copilot/transform.sh . --uninstall --dry-run
#
# Layer 2 transformation (default — single-file universal):
#   core/universal-rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.md
#                                 →  <target>/.github/copilot-instructions.md  (concatenated, body only)
#   core/recipes/<r>.md (selected) →  <target>/.github/instructions/<r>.instructions.md (applyTo: from paths)
#   core/docs-templates/*.md       →  <target>/docs/*.md
#   core/hooks/*                   →  SKIP (Reflector hook emitted via --recipes=self-improvement, ADR-032; other guards Claude-only, ADR-034)
#   core/roles/*                   →  SKIP (role emission is Claude-only today; Copilot supports sub-agents natively — ADR-031)
#
# Layer 2 transformation (--per-rule alternative):
#   core/universal-rules/<r>.md   →  <target>/.github/instructions/<r>.instructions.md (applyTo: '**')
#   (everything else identical to default)
#
# Frontmatter translation:
#   Conductor source frontmatter:
#     ---
#     paths:
#       - "apps/**/*.ts"
#       - "apps/**/*.tsx"
#     ---
#   Copilot output frontmatter:
#     ---
#     applyTo: 'apps/**/*.ts,apps/**/*.tsx'
#     ---
#   Copilot uses a single CSV glob string. Multi-line YAML lists are flattened to
#   comma-separated. If always_loaded:true (or no paths), output applyTo: '**'.

set -eu

# ----- arg parsing --------------------------------------------------------

TARGET=""
RECIPES=""
MODE="full"
DRY_RUN="false"
NO_PROMPT="false"
PER_RULE="false"
UNINSTALL="false"
FORCE="false"

WIZARD_APPLY_RULES="true"

while [ $# -gt 0 ]; do
  case "$1" in
    --recipes=*) RECIPES="${1#--recipes=}" ;;
    --mode=*)    MODE="${1#--mode=}" ;;
    --dry-run)   DRY_RUN="true" ;;
    --no-prompt) NO_PROMPT="true" ;;
    --per-rule)  PER_RULE="true" ;;
    --uninstall|--rollback) UNINSTALL="true" ;;
    --force) FORCE="true" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: bash adapters/copilot/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated list of recipes to install
  --mode=<m>            Install preset (ADR-044): full (default) | minimal (rules text +
                        docs only; no Reflector runtime) | strict (abort if
                        .github/copilot-instructions.md exists) | recipes-only (ONLY the
                        selected recipe .instructions.md files; requires --recipes=) |
                        reflector-only (self-improvement loop standalone)
  --dry-run             Preview only — no files written
  --no-prompt           Skip interactive prompts; apply defaults (CI-safe)
  --per-rule            Split 5 universal rules into per-file .instructions.md
                        (default: concatenate into single .github/copilot-instructions.md)
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering

Output (default):
  <target>/.github/copilot-instructions.md            (5 universal rules merged)
  <target>/.github/instructions/<recipe>.instructions.md  (per recipe, applyTo: from paths)
  <target>/docs/{CURRENT_WORK,REMAINING_TASKS,PLANS,TASKS,INDEX}.md

Skipped (not yet emitted for Copilot — the tool supports these natively, ADR-031):
  Sub-agent dispatch (roles)  — full agent emission is Phase 2
  PreToolUse / Stop hooks     — full hook emission is Phase 2 (Reflector hook ships via --recipes=self-improvement)

IDE coverage: VS Code, Cursor (Copilot ext), Windsurf (Copilot adapter), JetBrains
              (Copilot plugin), Neovim (copilot.vim) all read .github/instructions/.
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
  echo "Usage: bash adapters/copilot/transform.sh <target-project> [--recipes=...]" >&2
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
TARGET_ABS="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "Error: target directory does not exist: $TARGET" >&2; exit 1; }

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

# strip_frontmatter <src-file>
# Print only the body (everything after the second `---` line). If no frontmatter,
# print the whole file.
strip_frontmatter() {
  /usr/bin/awk 'BEGIN{c=0; f=0} /^---$/{c++; if(c==2){f=1; next} else {next}} f==1 || c==0' "$1"
}

# extract_paths_csv <src-file>
# Read frontmatter `paths:` YAML list, return CSV glob string.
# Falls back to `applies_to:` (used by universal-rules). Returns empty if absent
# or if always_loaded:true is set.
extract_paths_csv() {
  local src="$1"
  # Always-loaded check first.
  local always
  always=$(/usr/bin/awk '
    BEGIN{c=0; in_fm=0}
    /^---$/{c++; if(c==1){in_fm=1; next} else {exit}}
    in_fm && /^always_loaded:[[:space:]]*true/{print "true"; exit}
  ' "$src")
  if [ "$always" = "true" ]; then
    echo "**"
    return
  fi
  # Try paths: list (recipe style).
  local paths_csv
  paths_csv=$(/usr/bin/awk '
    BEGIN{c=0; in_fm=0; in_paths=0; out=""}
    /^---$/{c++; if(c==1){in_fm=1; next} else {exit}}
    in_fm && /^paths:/{in_paths=1; next}
    in_fm && in_paths && /^[[:space:]]*-[[:space:]]*"/{
      gsub(/^[[:space:]]*-[[:space:]]*"/, "")
      gsub(/"[[:space:]]*$/, "")
      if(out=="") out=$0; else out=out "," $0
      next
    }
    in_fm && in_paths && /^[^[:space:]-]/{in_paths=0}
    END{print out}
  ' "$src")
  if [ -n "$paths_csv" ]; then
    echo "$paths_csv"
    return
  fi
  # Try applies_to: list (universal-rule style).
  local applies_csv
  applies_csv=$(/usr/bin/awk '
    BEGIN{c=0; in_fm=0; in_a=0; out=""}
    /^---$/{c++; if(c==1){in_fm=1; next} else {exit}}
    in_fm && /^applies_to:/{
      # Inline form: applies_to: ["a","b"]
      if(match($0, /\[.*\]/)){
        s=substr($0, RSTART+1, RLENGTH-2)
        gsub(/"/, "", s); gsub(/[[:space:]]/, "", s)
        print s; exit
      }
      in_a=1; next
    }
    in_fm && in_a && /^[[:space:]]*-[[:space:]]*"/{
      gsub(/^[[:space:]]*-[[:space:]]*"/, "")
      gsub(/"[[:space:]]*$/, "")
      if(out=="") out=$0; else out=out "," $0
      next
    }
    in_fm && in_a && /^[^[:space:]-]/{in_a=0}
    END{if(out!="") print out}
  ' "$src")
  if [ -n "$applies_csv" ]; then
    # all-tools sentinel maps to ** (matches everything).
    case "$applies_csv" in
      *all-tools*) echo "**" ;;
      *) echo "$applies_csv" ;;
    esac
    return
  fi
  # Default fallback.
  echo "**"
}

# write_copilot_per_file <src> <dest> <apply-to-csv>
# Emit a Copilot per-file instructions.md with applyTo: <csv> frontmatter,
# then strip the source's Conductor frontmatter and append the body.
write_copilot_per_file() {
  local src="$1" dest="$2" applyto="$3"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest with applyTo: '$applyto'"
    return
  fi
  /bin/cat > "$dest" <<EOF
---
applyTo: '$applyto'
---

EOF
  strip_frontmatter "$src" >> "$dest"
}

# backup_if_exists <dest>
backup_if_exists() {
  conductor_manifest_backup_and_remember "$1"
}

# ----- manifest tracking (mirrors claude adapter ADR-020) ----------------

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
  "adapter": "copilot",
  "mode": "$MODE",
  "install_timestamp": "$MANIFEST_TS",
  "conductor_root": "$CONDUCTOR_ROOT",
  "per_rule_mode": $PER_RULE,
  "recipes_enabled": $recipes_json,
  "emitted_files": [
$entries
  ]
}
EOF
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  log "  wrote manifest $MANIFEST_PATH"
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

# ----- uninstall flow ----------------------------------------------------

do_uninstall() {
  log "uninstall mode (target: $TARGET_ABS)"

  if [ ! -f "$MANIFEST_PATH" ]; then
    if [ "$FORCE" = "true" ]; then
      log "WARNING: no manifest at $MANIFEST_PATH — proceeding under --force (legacy scan)"
      uninstall_legacy_scan
      return 0
    fi
    echo "Error: no manifest at $MANIFEST_PATH." >&2
    echo "  Re-run with --force to scan for legacy .conductor-backup-* files anyway." >&2
    exit 1
  fi

  if [ -d "$TARGET_ABS/.git" ]; then
    if [ -f "$TARGET_ABS/.git/MERGE_HEAD" ] || [ -f "$TARGET_ABS/.git/REBASE_HEAD" ] || [ -d "$TARGET_ABS/.git/rebase-merge" ]; then
      if [ "$FORCE" != "true" ]; then
        echo "Error: target has an active git operation (merge/rebase in progress)." >&2
        echo "  Resolve or pass --force to override." >&2
        exit 1
      fi
      log "WARNING: active git operation — proceeding under --force"
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
      *'"path":'*'"source":'*'"had_backup":'*) ;;
      *) continue ;;
    esac
    entries_count=$((entries_count + 1))
    local rel_path had_backup backup_path expected_sha
    rel_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
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

  for d in .github/instructions .github/hooks .github/prompts .github/agents .github .conductor/reflect .conductor; do
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
  log "WARNING: legacy mode does not delete Conductor-emitted source files."
  log "         Manually remove .github/copilot-instructions.md and .github/instructions/*.instructions.md if desired."
}

if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Adopter case = .github/copilot-instructions.md OR .github/instructions/ already exists.

IS_ADOPTER_CASE="false"
if [ -f "$TARGET_ABS/.github/copilot-instructions.md" ] || [ -d "$TARGET_ABS/.github/instructions" ]; then
  IS_ADOPTER_CASE="true"
fi

detect_coexisting_frameworks

# --mode=strict: never overwrite an existing baseline, even with a backup (ADR-044).
if [ "$MODE" = "strict" ]; then
  if [ -f "$TARGET_ABS/.github/copilot-instructions.md" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/.github/copilot-instructions.md already exists — strict mode aborts instead of overwriting a baseline." >&2
    echo "  Use --mode=full (timestamped backup + manifest-based restore), or move the file first." >&2
    exit 3
  fi
  if [ -d "$TARGET_ABS/.github/instructions" ] && [ -n "$(/bin/ls -A "$TARGET_ABS/.github/instructions" 2>/dev/null)" ]; then
    echo "Error (--mode=strict): $TARGET_ABS/.github/instructions/ already has files — strict mode never writes next to an existing rules surface." >&2
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
  echo " Welcome to CONDUCTOR (Copilot adapter) setup"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""
  echo " Detected existing Copilot custom instructions."
  echo " Existing files will be backed up to .conductor-backup-<timestamp> before overwrite."
  echo ""

  printf "Apply universal-rules? (Y/n): "
  read -r _apply_answer
  if [ "$_apply_answer" = "n" ] || [ "$_apply_answer" = "N" ]; then
    WIZARD_APPLY_RULES="false"
    echo "  Skipping universal-rules installation."
  fi

  echo ""
  echo "Available recipes:"
  echo "  web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene, loop-engineering"
  printf "Select recipes (comma-separated, blank for none): "
  read -r _recipe_answer
  if [ -n "$_recipe_answer" ]; then
    RECIPES="$_recipe_answer"
    echo "  Recipes selected: $RECIPES"
  fi

  printf "Use --per-rule mode (split universal-rules into 5 separate per-file files)? (y/N): "
  read -r _per_rule_answer
  if [ "$_per_rule_answer" = "y" ] || [ "$_per_rule_answer" = "Y" ]; then
    PER_RULE="true"
    echo "  Per-rule mode enabled (output: .github/instructions/{workflow,...}.instructions.md)."
  fi

  echo ""
elif [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "true" ]; then
  log "Adopter case detected — applying defaults (--no-prompt): rules=yes, recipes=${RECIPES:-(none)}, per_rule=$PER_RULE"
fi

# ----- step 1: universal rules → .github/copilot-instructions.md ---------

init_manifest

if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  log "Step 1/4: universal-rules — skipped (--mode=$MODE is à la carte)"
elif [ "$WIZARD_APPLY_RULES" = "true" ]; then
  if [ "$PER_RULE" = "true" ]; then
    log "Step 1/4: universal-rules → .github/instructions/*.instructions.md (per-rule mode)"
    mkdir_if_real "$TARGET_ABS/.github/instructions"
    for rule in workflow spec-as-you-go quality-gates operations meta-discipline; do
      src="$CORE_ROOT/universal-rules/$rule.md"
      dest="$TARGET_ABS/.github/instructions/$rule.instructions.md"
      if [ ! -f "$src" ]; then
        echo "Warning: $src not found; skipping" >&2
        continue
      fi
      backup_if_exists "$dest"
      # Universal rules are always-loaded → applyTo: '**'
      write_copilot_per_file "$src" "$dest" "**"
      record_emit ".github/instructions/$rule.instructions.md" "core/universal-rules/$rule.md" "$MANIFEST_LAST_BACKUP"
    done
  else
    log "Step 1/4: universal-rules → .github/copilot-instructions.md (single-file mode)"
    mkdir_if_real "$TARGET_ABS/.github"
    dest="$TARGET_ABS/.github/copilot-instructions.md"
    backup_if_exists "$dest"
    if [ "$DRY_RUN" = "true" ]; then
      log "would synthesize $dest from 5 universal-rule bodies"
    else
      /bin/cat > "$dest" <<'HEADER_EOF'
# Project Custom Instructions (installed by CONDUCTOR — Copilot adapter)

> Loaded automatically by GitHub Copilot for every chat in this repository.
> Read the 5 universal rules below before any tool call.
> Source: https://github.com/<your-org>/conductor (universal-rules/*.md)

## Topology note (Copilot)

GitHub Copilot supports sub-agent dispatch and hooks natively (ADR-031), but
CONDUCTOR's Copilot adapter currently emits rule text (plus the Reflector loop)
only — full hook/agent emission is Phase 2. The 5
universal rules below are therefore self-policed: the human (and Copilot Chat) must follow
the same Plan → Architecture → Tasks → Implementation → Review → Spec workflow
that Claude Code enforces with CONDUCTOR-emitted hooks. Two-stage code review degrades to the
Copilot PR review feature for Stage B (configure separately at the repo level).

---

HEADER_EOF
      for rule in workflow spec-as-you-go quality-gates operations meta-discipline; do
        src="$CORE_ROOT/universal-rules/$rule.md"
        if [ ! -f "$src" ]; then
          echo "Warning: $src not found; skipping" >&2
          continue
        fi
        echo "" >> "$dest"
        echo "<!-- ===== universal-rule: $rule ===== -->" >> "$dest"
        echo "" >> "$dest"
        strip_frontmatter "$src" >> "$dest"
        echo "" >> "$dest"
        echo "---" >> "$dest"
      done
      log "  wrote $dest ($(/usr/bin/wc -l < "$dest" | /usr/bin/tr -d ' ') lines)"
    fi
    record_emit ".github/copilot-instructions.md" "<synthesized:5-universal-rules>" "$MANIFEST_LAST_BACKUP"
  fi
else
  log "Step 1/4: universal-rules — skipped (user opted out)"
fi

# ----- step 2: recipes → .github/instructions/<r>.instructions.md --------

log "Step 2/4: recipes (opt-in) → .github/instructions/"
INSTALLED_RECIPES=""
if [ -n "$RECIPES" ]; then
  mkdir_if_real "$TARGET_ABS/.github/instructions"
  IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
  for r in "${RECIPE_LIST[@]}"; do
    r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ -z "$r" ] && continue
    src="$CORE_ROOT/recipes/$r.md"
    dest="$TARGET_ABS/.github/instructions/$r.instructions.md"
    if [ ! -f "$src" ]; then
      echo "Warning: recipe '$r' not found at $src; skipping" >&2
      continue
    fi
    backup_if_exists "$dest"
    applyto="$(extract_paths_csv "$src")"
    [ -z "$applyto" ] && applyto="**"
    write_copilot_per_file "$src" "$dest" "$applyto"
    log "  recipe $r → applyTo: '$applyto'"
    record_emit ".github/instructions/$r.instructions.md" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
    INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
  done
else
  log "  (no recipes selected — pass --recipes=name1,name2 to install)"
fi

# ---- Step 2.6: self-improvement runtime (only with --recipes=self-improvement) ----
if [ "$MODE" = "recipes-only" ] && [ -z "${INSTALLED_RECIPES// /}" ] && [ "$DRY_RUN" != "true" ]; then
  echo "Error: --mode=recipes-only resolved ZERO valid recipes from '--recipes=$RECIPES' — nothing to install (check the names)." >&2
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  exit 1
fi

if [ "$MODE" = "minimal" ]; then
  RECIPES_FOR_RUNTIME=""
  log "Step 2.6/4: self-improvement runtime — skipped (--mode=minimal ships text only)"
else
  RECIPES_FOR_RUNTIME="$RECIPES"
fi
case ",$RECIPES_FOR_RUNTIME," in
  *",self-improvement,"*)
    log "Step 2.6/4: self-improvement (Reflector) → hooks/prompt/agent"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.github/hooks" "$TARGET_ABS/.github/prompts" "$TARGET_ABS/.github/agents"
      gi="$TARGET_ABS/.gitignore"
      grep -qxF '.conductor/' "$gi" 2>/dev/null || printf '\n# CONDUCTOR runtime (local trajectories/lessons)\n.conductor/\n' >> "$gi"
      for s in trajectory-log prune-lessons run-weekly; do
        d="$TARGET_ABS/.conductor/reflect/$s.sh"
        backup_if_exists "$d"; /bin/cp "$CORE_ROOT/reflector/$s.sh" "$d"; /bin/chmod +x "$d"
        record_emit ".conductor/reflect/$s.sh" "core/reflector/$s.sh" "$MANIFEST_LAST_BACKUP"
      done
      # scheduling assets: run-weekly.sh needs the brief; SCHEDULING.md documents registration
      for m in reflect-brief SCHEDULING; do
        d="$TARGET_ABS/.conductor/reflect/$m.md"
        backup_if_exists "$d"; /bin/cp "$CORE_ROOT/reflector/$m.md" "$d"
        record_emit ".conductor/reflect/$m.md" "core/reflector/$m.md" "$MANIFEST_LAST_BACKUP"
      done
      hc="$TARGET_ABS/.github/hooks/conductor-reflect.json"
      if [ ! -f "$hc" ]; then
        backup_if_exists "$hc"
        /bin/cat > "$hc" <<'HOOK'
{
  "version": 1,
  "hooks": {
    "agentStop": [ { "type": "command", "bash": "./.conductor/reflect/trajectory-log.sh", "timeoutSec": 10 } ]
  }
}
HOOK
        record_emit ".github/hooks/conductor-reflect.json" "<synthesized>" "$MANIFEST_LAST_BACKUP"
      else
        log "  .github/hooks/conductor-reflect.json exists — add an agentStop hook calling ./.conductor/reflect/trajectory-log.sh manually"
      fi
      pr="$TARGET_ABS/.github/prompts/reflect.prompt.md"
      backup_if_exists "$pr"
      { printf -- "---\ndescription: 'Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only)'\nagent: 'agent'\n---\n\n"; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; } > "$pr"
      record_emit ".github/prompts/reflect.prompt.md" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      ag="$TARGET_ABS/.github/agents/reflector.agent.md"
      backup_if_exists "$ag"
      { printf -- '---\nname: reflector\ndescription: "Reads session trajectories and proposes atomic lesson deltas. Propose-only; never applies."\n---\n\n'; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; } > "$ag"
      record_emit ".github/agents/reflector.agent.md" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
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

# ----- step 4: skip notice -----------------------------------------------

log "Step 4/4: skipped layers (not yet emitted for Copilot — tool supports them natively, ADR-031)"
log "  - core/roles/         → SKIP (agent emission is Phase 2; Copilot supports sub-agents natively — ADR-031)"
log "  - core/hooks/         → SKIP except Reflector hook (--recipes=self-improvement, ADR-032; other guards Claude-only, ADR-034)"
log "  - hookify-templates/  → SKIP (Claude Code plugin only)"

fi

finalize_manifest

# ----- summary -----------------------------------------------------------

echo ""
echo "========================================================"
echo " Done."
echo "  Target: $TARGET_ABS"
if [ "$MODE" = "recipes-only" ] || [ "$MODE" = "reflector-only" ]; then
  echo "  Universal rules: 0 (à la carte)"
elif [ "$PER_RULE" = "true" ]; then
  echo "  Universal rules: 5 → .github/instructions/*.instructions.md (per-rule mode)"
else
  echo "  Universal rules: 5 → .github/copilot-instructions.md (single-file mode)"
fi
echo "  Recipes installed: ${RECIPES:-(none)}"
echo "  Mode: $MODE"
echo "  Not emitted (Phase 2 — Copilot supports these natively, ADR-031/034): roles, guard hooks, hookify"
echo ""
echo " Activation:"
echo "   GitHub Copilot reads .github/copilot-instructions.md and .github/instructions/"
echo "   automatically — no restart required. The same files work in:"
echo "     - VS Code (Copilot extension)"
echo "     - Cursor (Copilot extension)"
echo "     - Windsurf (Copilot adapter)"
echo "     - JetBrains IDEs (Copilot plugin)"
echo "     - Neovim (copilot.vim)"
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open the project in any IDE with Copilot enabled."
[ -d "$TARGET_ABS/docs" ] && echo "  2. Edit docs/CURRENT_WORK.md with the project's current state."
echo "  3. Configure Copilot PR review at the repo level (Stage B analog)."
echo "  4. Verify: cat $TARGET_ABS/.github/copilot-instructions.md | head -30"
