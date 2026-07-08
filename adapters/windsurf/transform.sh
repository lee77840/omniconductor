#!/usr/bin/env bash
#
# CONDUCTOR — Windsurf adapter transform.sh
#
# Reads core/ assets and writes them into a target project as native Windsurf
# files: .windsurfrules (always-loaded baseline), .devin/rules/*.md, docs/*.
#
# Usage:
#   bash adapters/windsurf/transform.sh <target-project> [--recipes=<comma-list>] [--dry-run]
#     [--no-prompt]
#   bash adapters/windsurf/transform.sh <target-project> --uninstall [--dry-run] [--force]
#
# Examples:
#   bash adapters/windsurf/transform.sh ~/Projects/my-app
#   bash adapters/windsurf/transform.sh ~/Projects/my-app --recipes=i18n,monorepo
#   bash adapters/windsurf/transform.sh /tmp/test-project --dry-run
#   bash adapters/windsurf/transform.sh . --no-prompt
#   bash adapters/windsurf/transform.sh . --uninstall              # revert install
#   bash adapters/windsurf/transform.sh . --uninstall --force      # bypass safety checks
#
# Layer 2 transformation (per ADR-004 honesty + ADR-021):
#   core/universal-rules/*.md      →  <target>/.devin/rules/*.md     (front-matter stripped; preferred over legacy .windsurf/rules/)
#   <synthesized>                  →  <target>/.windsurfrules        (always-loaded baseline)
#   core/recipes/*.md (selected)   →  <target>/.devin/rules/*.md     (front-matter stripped)
#   core/docs-templates/*.md       →  <target>/docs/*.md             (CURRENT_WORK, REMAINING_TASKS, etc.)
#   core/hooks/*.sh.template       →  SKIPPED (Reflector hook emitted via --recipes=self-improvement, ADR-032; other guards Claude-only, ADR-034)
#   core/roles/*.md                →  SKIPPED (Windsurf has no sub-agent dispatch)
#   adapters/claude/hookify-...    →  SKIPPED (Claude-only plugin)
#
# Windsurf has NO per-pattern glob scoping (all files in .devin/rules/ load
# together) and NO sub-agents. CONDUCTOR emits the Reflector hook when
# --recipes=self-improvement (ADR-032); other guards remain Claude-only (ADR-034)
# and are noted in .windsurfrules.

set -eu

# ----- arg parsing --------------------------------------------------------

TARGET=""
RECIPES=""
DRY_RUN="false"
NO_PROMPT="false"
UNINSTALL="false"
FORCE="false"

# Onboarding wizard state
WIZARD_APPLY_RULES="true"

while [ $# -gt 0 ]; do
  case "$1" in
    --recipes=*) RECIPES="${1#--recipes=}" ;;
    --dry-run)   DRY_RUN="true" ;;
    --no-prompt) NO_PROMPT="true" ;;
    --uninstall|--rollback) UNINSTALL="true" ;;
    --force) FORCE="true" ;;
    --help|-h)
      /bin/cat <<EOF
Usage: bash adapters/windsurf/transform.sh <target-project> [options]

Options:
  --recipes=A,B,C       Comma-separated list of recipes to install
  --dry-run             Preview only — no files written
  --no-prompt           Skip all interactive prompts; apply sensible defaults (CI-safe)
  --uninstall           Revert a previous install using <target>/.conductor-manifest.json
                        (alias: --rollback). Restores backups when present, deletes
                        Conductor-emitted files when none. Customizations not in the
                        manifest are preserved.
  --force               Bypass uninstall safety checks (active worktrees, missing manifest)

Recipes available: web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene

What this adapter does NOT install (per ADR-004 honesty + ADR-021):
  - Hook guards (CONDUCTOR emits the Reflector hook when --recipes=self-improvement, ADR-032; other guards remain Claude-only, ADR-034)
  - Sub-agent personas (Windsurf has no sub-agent dispatch — single chat session per task)
  - Per-pattern glob scoping (all .devin/rules/*.md load together)
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
  echo "Usage: bash adapters/windsurf/transform.sh <target-project> [--recipes=...]" >&2
  exit 1
fi

# Resolve CONDUCTOR root (where this script lives: adapters/windsurf/).
CONDUCTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_ROOT="$CONDUCTOR_ROOT/core"
[ -d "$CORE_ROOT" ] || { echo "Error: core/ not found at $CORE_ROOT" >&2; exit 1; }

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
# Print body to stdout. Used by .devin/rules/*.md emit + .windsurfrules bundling.
strip_frontmatter() {
  local src="$1"
  /usr/bin/awk 'BEGIN{f=0} /^---$/{c++; if(c==2){f=1; next}} f==1' "$src"
}

# Emit a `.devin/rules/<name>.md` file from a `core/*.md` source.
# Windsurf does NOT use front-matter for filtering, so we strip it entirely and
# preserve the body verbatim.
# emit_rule <src> <dest>
emit_rule() {
  local src="$1" dest="$2"
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest (front-matter stripped)"
    return
  fi
  strip_frontmatter "$src" > "$dest"
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
  "version": "v0.2.0",
  "adapter": "windsurf",
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

# ----- uninstall flow (mirrored from Cursor adapter) ----------------------

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

  while IFS= read -r line; do
    case "$line" in
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

  # Try to clean up empty Conductor-emitted dirs left behind.
  for d in .windsurf/rules .windsurf/workflows .windsurf/hooks .windsurf .devin/rules .devin .conductor/reflect .conductor; do
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
  log "         Delete .windsurfrules and .devin/rules/*.md (or legacy .windsurf/rules/*.md) manually if desired."
}

if [ "$UNINSTALL" = "true" ]; then
  do_uninstall
  exit 0
fi

# ----- onboarding wizard --------------------------------------------------
# Wizard fires when adopter signal is detected: existing .windsurf/ OR existing .windsurfrules.
# Otherwise (truly fresh target) wizard is skipped.

IS_ADOPTER_CASE="false"
if [ -d "$TARGET_ABS/.windsurf" ] || [ -f "$TARGET_ABS/.windsurfrules" ]; then
  IS_ADOPTER_CASE="true"
fi

if [ "$IS_ADOPTER_CASE" = "true" ] && [ "$NO_PROMPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
  echo ""
  echo "========================================================"
  echo " Welcome to CONDUCTOR setup (Windsurf adapter)"
  echo " Target: $TARGET_ABS"
  echo "========================================================"
  echo ""

  printf "Detect existing rules? (y/N): "
  read -r _detect_answer
  if [ "$_detect_answer" = "y" ] || [ "$_detect_answer" = "Y" ]; then
    _existing_rules=$(( $(ls "$TARGET_ABS/.devin/rules/" 2>/dev/null | wc -l | /usr/bin/tr -d ' ') + $(ls "$TARGET_ABS/.windsurf/rules/" 2>/dev/null | wc -l | /usr/bin/tr -d ' ') ))
    _has_baseline="no"
    [ -f "$TARGET_ABS/.windsurfrules" ] && _has_baseline="yes"
    echo "  Found $_existing_rules rule files in .devin/rules/ + .windsurf/rules/ (legacy), .windsurfrules present: $_has_baseline"
  fi

  printf "Apply universal-rules? (Y/n): "
  read -r _apply_answer
  if [ "$_apply_answer" = "n" ] || [ "$_apply_answer" = "N" ]; then
    WIZARD_APPLY_RULES="false"
    echo "  Skipping universal-rules installation."
  fi

  echo ""
  echo "Available recipes:"
  echo "  web-mobile-parity, i18n, monorepo, branch-strategy, auto-mock-data, coding-conventions, tdd, debugging, database-discipline, design-system, self-improvement, git-hygiene"
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

# ----- step 1: synthesize .windsurfrules (always-loaded baseline) --------

init_manifest

UNIVERSAL_RULES="workflow spec-as-you-go quality-gates operations meta-discipline"

log "Step 1/4: synthesize .windsurfrules (always-loaded baseline)"
WINDSURFRULES_DEST="$TARGET_ABS/.windsurfrules"

if [ -f "$WINDSURFRULES_DEST" ]; then
  log "  $WINDSURFRULES_DEST exists — SKIP (exists), leaving in place"
elif [ "$DRY_RUN" = "true" ]; then
  log "would write $WINDSURFRULES_DEST (orchestrator intro + ABSOLUTE rules summary + pointers)"
else
  /bin/cat > "$WINDSURFRULES_DEST" <<'EOF'
# Project Orchestrator Manual (installed by CONDUCTOR)
# CONDUCTOR 가 설치한 프로젝트 오케스트레이터 매뉴얼

> This file is the always-loaded baseline for Windsurf. It loads on every session.
> 이 파일은 Windsurf 의 항상-로드 베이스라인입니다. 매 세션마다 자동 로드됩니다.

## Role / 역할

You are the orchestrator: plan first, act deliberately, verify before declaring done.
당신은 오케스트레이터입니다: 먼저 계획하고, 신중하게 실행하고, 완료 선언 전에 검증하세요.

Windsurf runs a single chat session per task (no sub-agent dispatch). You play
both planner and implementer; keep the plan explicit so it survives context resets.
Windsurf 는 작업당 단일 채팅 세션으로 동작합니다 (서브에이전트 디스패치 없음). 계획을
명시적으로 유지해 컨텍스트 리셋에도 살아남게 하세요.

## ABSOLUTE rules / 절대 규칙 (read before every change)

These are the universal floor. The full text loads from `.devin/rules/`.
이것들이 보편 규칙의 최소선입니다. 전체 본문은 `.devin/rules/` 에서 로드됩니다.

| Rule | Summary |
|---|---|
| `workflow.md` | Plan-first, docs-first, 7-step process, process-over-speed, never-skip ABSOLUTE rules |
| `spec-as-you-go.md` | Update the spec in the SAME turn as the code edit; keep docs synced in real time |
| `quality-gates.md` | Pre-commit + pre-merge review, test coverage sync, verify-after-changes |
| `operations.md` | Session continuity, delete completed tasks, keep dev/prod in sync |
| `meta-discipline.md` | Originality, ambiguity AMB-1..7 triggers, token economy, model routing |

If you catch yourself about to break one, STOP and fix course. Silent recovery is
worse than explicit acknowledgment.
하나라도 어기려는 자신을 발견하면 멈추고 바로잡으세요. 조용한 무마는 명시적 인정보다 나쁩니다.

## Ambiguity policy / 모호성 정책

Default: ACT-WITH-DECLARATION — proceed with the best-guess interpretation and
surface the assumption at the top of your response.
기본값: 선언과 함께 실행 — 최선의 해석으로 진행하되 가정을 응답 상단에 명시하세요.

Override to ASK (multiple-choice) when AMB-1..7 fires: deictic reference,
unspecified scope, external-system invocation, protected-branch merge, design
decisions, dependency add, or user-manual-action required. Full catalog:
`.devin/rules/meta-discipline.md`.

## Session startup / 세션 시작

Read `docs/CURRENT_WORK.md` FIRST every session before touching code.
매 세션마다 코드를 건드리기 전에 `docs/CURRENT_WORK.md` 를 먼저 읽으세요.

Lazy-load on demand: `docs/specs/<area>.md` when touching that area's code;
`docs/PLANS.md` / `docs/TASKS.md` for planning context.

## Additional rules / 추가 규칙

Additional rules load from `.devin/rules/` (preferred; legacy `.windsurf/rules/`
is still read) — all files in that directory load together (Windsurf has no
per-pattern glob scoping). Selected recipes are emitted there too.
추가 규칙은 `.devin/rules/` 에서 로드됩니다 (선호 경로; 레거시 `.windsurf/rules/` 도 계속
읽힘) — 해당 디렉터리의 모든 파일이 함께 로드됩니다 (Windsurf 는 패턴별 glob 스코핑이
없음). 선택한 recipe 도 이곳에 생성됩니다.

## Not enforced on Windsurf / Windsurf 에서 미강제

Windsurf has no hooks and no sub-agent dispatch. The following are self-policed
reminders here (on Claude Code they are enforced by hooks):
Windsurf 는 훅과 서브에이전트 디스패치가 없습니다. 다음 항목은 여기서는 자율 준수 사항입니다
(Claude Code 에서는 훅으로 강제됨):

- Spec-as-you-go same-turn update — no Stop hook to block stale docs.
- Two-stage code review (pre-commit / pre-merge) — pair with a git pre-commit hook for mechanical enforcement.
- Model routing — Windsurf uses a single model per session; choose deliberately.
EOF
  record_emit ".windsurfrules" "<synthesized>" ""
  log "  wrote $WINDSURFRULES_DEST"
fi

# ----- step 2: universal rules -> .devin/rules/*.md ----------------------

if [ "$WIZARD_APPLY_RULES" = "true" ]; then
  log "Step 2/4: universal-rules → .devin/rules/ (preferred; legacy .windsurf/rules/ still read)"
  mkdir_if_real "$TARGET_ABS/.devin/rules"

  for rule in $UNIVERSAL_RULES; do
    src="$CORE_ROOT/universal-rules/$rule.md"
    dest="$TARGET_ABS/.devin/rules/$rule.md"
    if [ ! -f "$src" ]; then
      echo "Warning: $src not found; skipping" >&2
      continue
    fi
    if [ -f "$dest" ] && [ "$DRY_RUN" = "false" ]; then
      log "  $dest exists — SKIP (exists)"
      continue
    fi
    backup_and_remember "$dest"
    emit_rule "$src" "$dest"
    record_emit ".devin/rules/$rule.md" "core/universal-rules/$rule.md" "$MANIFEST_LAST_BACKUP"
  done
else
  log "Step 2/4: universal-rules — skipped (user opted out)"
fi

# ----- step 3: recipes (opt-in) -> .devin/rules/*.md ---------------------

log "Step 3/4: recipes (opt-in) → .devin/rules/ (preferred; legacy .windsurf/rules/ still read)"
INSTALLED_RECIPES=""
if [ -n "$RECIPES" ]; then
  mkdir_if_real "$TARGET_ABS/.devin/rules"
  IFS=',' read -ra RECIPE_LIST <<< "$RECIPES"
  for r in "${RECIPE_LIST[@]}"; do
    r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ -z "$r" ] && continue
    src="$CORE_ROOT/recipes/$r.md"
    dest="$TARGET_ABS/.devin/rules/$r.md"
    if [ ! -f "$src" ]; then
      echo "Warning: recipe '$r' not found at $src; skipping" >&2
      continue
    fi
    if [ -f "$dest" ] && [ "$DRY_RUN" = "false" ]; then
      log "  $dest exists — SKIP (exists)"
      INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
      continue
    fi
    backup_and_remember "$dest"
    emit_rule "$src" "$dest"
    record_emit ".devin/rules/$r.md" "core/recipes/$r.md" "$MANIFEST_LAST_BACKUP"
    INSTALLED_RECIPES="$INSTALLED_RECIPES $r"
  done
else
  log "  (no recipes selected — pass --recipes=name1,name2 to install)"
fi

# ----- step 3.5: self-improvement runtime (only with --recipes=self-improvement) ----

case ",$RECIPES," in
  *",self-improvement,"*)
    log "Step: self-improvement (Reflector) → hook/workflow/rule"
    if [ "$DRY_RUN" != "true" ]; then
      /bin/mkdir -p "$TARGET_ABS/.conductor/reflect" "$TARGET_ABS/.windsurf/workflows" "$TARGET_ABS/.devin/rules"
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
      hc="$TARGET_ABS/.windsurf/hooks.json"
      if [ ! -f "$hc" ]; then
        backup_and_remember "$hc"
        /bin/cat > "$hc" <<'HOOK'
{
  "hooks": {
    "post_cascade_response_with_transcript": [
      { "command": "./.conductor/reflect/trajectory-log.sh", "show_output": false }
    ]
  }
}
HOOK
        record_emit ".windsurf/hooks.json" "<synthesized>" "$MANIFEST_LAST_BACKUP"
      else
        log "  .windsurf/hooks.json exists — add a post_cascade_response_with_transcript hook calling ./.conductor/reflect/trajectory-log.sh manually"
      fi
      wf="$TARGET_ABS/.windsurf/workflows/reflect.md"
      backup_and_remember "$wf"
      { printf -- '---\ndescription: Run the CONDUCTOR Reflector — propose lessons from recent sessions (propose-only)\n---\n\n'; /bin/cat "$CORE_ROOT/reflector/reflect-brief.md"; } > "$wf"
      record_emit ".windsurf/workflows/reflect.md" "core/reflector/reflect-brief.md" "$MANIFEST_LAST_BACKUP"
      rl="$TARGET_ABS/.devin/rules/reflector.md"
      backup_and_remember "$rl"
      { printf -- '---\ntrigger: manual\ndescription: Reflector persona — propose lesson deltas, apply nothing.\n---\n\n'; strip_frontmatter "$CORE_ROOT/roles/reflector.md"; } > "$rl"
      record_emit ".devin/rules/reflector.md" "core/roles/reflector.md" "$MANIFEST_LAST_BACKUP"
    fi
    ;;
esac

# ----- step 4: docs templates --------------------------------------------

log "Step 4/4: docs templates → docs/"
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
finalize_manifest

# ----- completion summary -------------------------------------------------

echo ""
echo "========================================================"
echo " Done."
echo "  Target: $TARGET_ABS"
echo "  Adapter: windsurf"
echo "  Always-loaded baseline: .windsurfrules"
echo "  Universal rules: 5 (.devin/rules/*.md, front-matter stripped)"
echo "  Recipes installed:${INSTALLED_RECIPES:- (none)}"
echo ""
echo " Skipped (per ADR-004 honesty):"
echo "  - Hooks: CONDUCTOR emits the Reflector hook when --recipes=self-improvement (ADR-032); other guards remain Claude-only (ADR-034)."
echo "  - Sub-agent personas: Windsurf has no sub-agent dispatch — single chat session per task."
echo "  - Per-pattern glob scoping: all .devin/rules/*.md load together."
echo "  - Hookify rule templates: Claude-only plugin."
echo ""
echo " Activation: reopen the project in Windsurf so .windsurfrules + .devin/rules/ reload."
echo "========================================================"
echo ""
echo "Next steps for the project:"
echo "  1. Open $TARGET_ABS in Windsurf."
echo "  2. Edit docs/CURRENT_WORK.md with your project's current state."
echo "  3. Verify rule loading: confirm .windsurfrules + all .devin/rules/*.md show in the rule indicator."
echo "  4. Add .memory/ to .gitignore if you adopt the DIY memory pattern."
