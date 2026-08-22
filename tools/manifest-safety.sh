#!/usr/bin/env bash
# Shared manifest-safety helpers for all adapters.
#
# This file is sourced after an adapter defines TARGET_ABS, MANIFEST_PATH,
# DRY_RUN, and log().  It deliberately uses only bash + shasum/sha256sum so
# installers remain dependency-free.

# Manifest schema v2 keeps one authoritative manifest per adapter so a project
# can install several tool surfaces without the next install destroying the
# previous adapter's ownership record.  The historical root manifest remains a
# compatibility projection for pre-v2 consumers.

# Read the portable difficulty contract from a role source. Keeping this parser
# shared prevents adapters from silently assigning different capability to
# the same role. Only the three tiers defined by meta-discipline.md are valid.
conductor_role_difficulty_tier() {
  local src="$1" tier
  tier="$(/usr/bin/awk '
    BEGIN { in_fm=0 }
    /^---$/ { if (!in_fm) { in_fm=1; next } else { exit } }
    in_fm && /^difficulty_tier:[[:space:]]*[123][[:space:]]*$/ {
      sub(/^difficulty_tier:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit
    }
  ' "$src")"
  case "$tier" in
    1|2|3) printf '%s' "$tier" ;;
    *) echo "Error: role source '$src' has no valid difficulty_tier (expected 1, 2, or 3)" >&2; return 1 ;;
  esac
}

conductor_difficulty_label() {
  case "$1" in
    1) printf '%s' 'Tier 1 — conceptual / complex' ;;
    2) printf '%s' 'Tier 2 — routine' ;;
    3) printf '%s' 'Tier 3 — trivial' ;;
    *) echo "Error: invalid CONDUCTOR difficulty tier '$1'" >&2; return 1 ;;
  esac
}

conductor_codex_effort_for_tier() {
  case "$1" in
    1) printf '%s' high ;;
    2) printf '%s' medium ;;
    3) printf '%s' low ;;
    *) echo "Error: invalid CONDUCTOR difficulty tier '$1'" >&2; return 1 ;;
  esac
}

conductor_validate_model_slug() {
  local slug="$1" context="${2:-model}"
  if [ -z "$slug" ] || ! printf '%s' "$slug" | /usr/bin/grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "Error: invalid $context slug '$slug'" >&2
    return 1
  fi
}

# Cursor additionally documents an optional parameter block such as
# model[effort=high]. Keep this adapter-specific grammar out of the stricter
# provider slug validator used by the other five adapters.
conductor_validate_cursor_model() {
  local model="$1" context="${2:-Cursor model}"
  if [ -z "$model" ] || [ "${#model}" -gt 160 ] \
    || ! printf '%s' "$model" | /usr/bin/grep -qE '^[A-Za-z0-9][A-Za-z0-9._:/-]*(\[[A-Za-z0-9._:=,-]+\])?$'; then
    echo "Error: invalid $context '$model'" >&2
    return 1
  fi
}

# OpenCode model identifiers use the provider/model form. Keep this grammar
# explicit so saved routing cannot inject YAML, whitespace, or extra segments
# into `.opencode/agents/*.md` frontmatter.
conductor_validate_opencode_model() {
  local model="$1" context="${2:-OpenCode model}"
  if [ "$model" = "inherit" ]; then return 0; fi
  if [ -z "$model" ] || [ "${#model}" -gt 160 ] \
    || ! printf '%s' "$model" | /usr/bin/grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*$'; then
    echo "Error: invalid $context '$model' (expected provider/model)" >&2
    return 1
  fi
}

# Refuse every managed-path ambiguity before an adapter creates, replaces, or
# removes anything. The Node helper uses lstat (not path-following stat), rejects
# symlink/hardlink/special-file destinations, and validates every authoritative
# adapter manifest before shell code is allowed to consume its paths.
conductor_assert_path_safety() {
  local adapter="$1" manifest expected
  [ -f "$CONDUCTOR_ROOT/bin/path-safety.js" ] || {
    echo "Error: path-safety helper missing from CONDUCTOR package" >&2
    return 1
  }
  /usr/bin/env node "$CONDUCTOR_ROOT/bin/path-safety.js" "$adapter" "$TARGET_ABS"
  for manifest in "$TARGET_ABS"/.conductor/manifests/*.json; do
    [ -f "$manifest" ] || continue
    expected="$(basename "$manifest" .json)"
    /usr/bin/env node "$CONDUCTOR_ROOT/bin/path-safety.js" --manifest "$manifest" "$TARGET_ABS" "$expected"
  done
}

conductor_manifest_prepare() {
  local adapter="$1" legacy adapter_in_legacy scope_in_legacy
  legacy="${LEGACY_MANIFEST_PATH:-$TARGET_ABS/.conductor-manifest.json}"

  conductor_assert_path_safety "$adapter"

  # One-time, lossless migration. Never import another adapter's compatibility
  # projection into this adapter's authoritative manifest.
  if [ ! -f "$MANIFEST_PATH" ] && [ -f "$legacy" ]; then
    adapter_in_legacy="$(/usr/bin/sed -n -E 's/^[[:space:]]*"adapter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$legacy" | /usr/bin/head -n 1)"
    scope_in_legacy="$(/usr/bin/sed -n -E 's/^[[:space:]]*"manifest_scope"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$legacy" | /usr/bin/head -n 1)"
    if [ "$adapter_in_legacy" = "$adapter" ] || { [ "$adapter" = "claude" ] && [ -z "$adapter_in_legacy" ] && [ -z "$scope_in_legacy" ]; }; then
      /usr/bin/env node "$CONDUCTOR_ROOT/bin/path-safety.js" --legacy-manifest "$legacy" "$TARGET_ABS" "$adapter"
      if [ "$DRY_RUN" = "true" ]; then
        log "would migrate legacy manifest $legacy -> $MANIFEST_PATH"
      else
        /bin/mkdir -p "$(dirname "$MANIFEST_PATH")"
        /bin/cp "$legacy" "$MANIFEST_PATH"
        log "  migrated legacy $adapter manifest -> $MANIFEST_PATH"
      fi
    fi
  fi
}

conductor_manifest_init_stage() {
  local line rel block abs
  /bin/mkdir -p "$(dirname "$MANIFEST_STAGE_PATH")"
  /bin/rm -f "$MANIFEST_STAGE_PATH"
  : > "$MANIFEST_STAGE_PATH"

  # A re-install is an ownership refresh, not a new first install. Carry every
  # still-present entry forward before emitters replace the paths they rewrite.
  # Without this, idempotent "already exists — preserve" branches silently
  # dropped ownership and a later uninstall left CONDUCTOR files behind.
  if [ -f "$MANIFEST_PATH" ]; then
    while IFS= read -r line; do
      case "$line" in *'"path":'*) : ;; *) continue ;; esac
      rel="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
      [ -n "$rel" ] || continue
      abs="$TARGET_ABS/$rel"
      case "$line" in
        *'"type": "block"'*)
          block="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
          [ -f "$abs" ] && /usr/bin/grep -qF "<!-- conductor:block $block -->" "$abs" || continue
          ;;
        *) [ -f "$abs" ] || continue ;;
      esac
      printf '%s\n' "$line" | /usr/bin/sed 's/,*$/,/' >> "$MANIFEST_STAGE_PATH"
    done < "$MANIFEST_PATH"
  fi

  # Shared docs/profile are dependencies of every baseline adapter. Import the
  # original ownership entry (including its one-time user backup) so removing
  # adapters in any order leaves the final owner able to restore/delete it.
  case "${MODE:-}" in
    full|minimal|strict)
      local other
      for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
        [ -f "$other" ] || continue
        [ "$other" = "$MANIFEST_PATH" ] && continue
        while IFS= read -r line; do
          case "$line" in *'"type": "block"'*) continue ;; esac
          rel="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
          case "$rel" in .conductor/project.json|docs/*) ;; *) continue ;; esac
          [ -f "$TARGET_ABS/$rel" ] || continue
          conductor_manifest_stage_has_normal_path "$rel" && continue
          printf '%s\n' "$line" | /usr/bin/sed 's/,*$/,/' >> "$MANIFEST_STAGE_PATH"
        done < "$other"
      done
      ;;
  esac
}

# Remove staged ownership for a whole path before an emitter rewrites that
# file. Rewriting replaces both normal-file and marked-block ownership.
conductor_manifest_stage_drop_path() {
  local wanted="$1" tmp
  [ -n "${MANIFEST_STAGE_PATH:-}" ] && [ -f "$MANIFEST_STAGE_PATH" ] || return 0
  tmp="$MANIFEST_STAGE_PATH.$$.tmp"
  /usr/bin/awk -v wanted="$wanted" '
    { p=$0; sub(/^.*"path": *"/, "", p); sub(/".*$/, "", p) }
    p != wanted { print }
  ' "$MANIFEST_STAGE_PATH" > "$tmp"
  /bin/mv -f "$tmp" "$MANIFEST_STAGE_PATH"
}

# Replace one marked block while retaining other blocks on the same host file.
conductor_manifest_stage_drop_block() {
  local wanted_path="$1" wanted_block="$2" tmp
  [ -n "${MANIFEST_STAGE_PATH:-}" ] && [ -f "$MANIFEST_STAGE_PATH" ] || return 0
  tmp="$MANIFEST_STAGE_PATH.$$.tmp"
  /usr/bin/awk -v wanted_path="$wanted_path" -v wanted_block="$wanted_block" '
    {
      p=$0; sub(/^.*"path": *"/, "", p); sub(/".*$/, "", p)
      b=$0
      if (b !~ /"block": *"/) b=""
      else { sub(/^.*"block": *"/, "", b); sub(/".*$/, "", b) }
    }
    p != wanted_path || b != wanted_block { print }
  ' "$MANIFEST_STAGE_PATH" > "$tmp"
  /bin/mv -f "$tmp" "$MANIFEST_STAGE_PATH"
}

conductor_manifest_stage_has_block() {
  local wanted_path="$1" wanted_block="$2"
  [ -n "${MANIFEST_STAGE_PATH:-}" ] && [ -f "$MANIFEST_STAGE_PATH" ] || return 1
  /usr/bin/awk -v wanted_path="$wanted_path" -v wanted_block="$wanted_block" '
    {
      p=$0; sub(/^.*"path": *"/, "", p); sub(/".*$/, "", p)
      b=$0
      if (b !~ /"block": *"/) next
      sub(/^.*"block": *"/, "", b); sub(/".*$/, "", b)
      if (p == wanted_path && b == wanted_block) found=1
    }
    END { exit !found }
  ' "$MANIFEST_STAGE_PATH"
}

conductor_manifest_stage_has_normal_path() {
  local wanted="$1"
  [ -n "${MANIFEST_STAGE_PATH:-}" ] && [ -f "$MANIFEST_STAGE_PATH" ] || return 1
  /usr/bin/awk -v wanted="$wanted" '
    /"type": *"block"/ { next }
    { p=$0; sub(/^.*"path": *"/, "", p); sub(/".*$/, "", p); if (p == wanted) found=1 }
    END { exit !found }
  ' "$MANIFEST_STAGE_PATH"
}

# Keep local trajectory payloads ignored without mutating a user's top-level
# .gitignore. A nested ignore file is naturally scoped and can participate in
# the same checksum/ownership/uninstall lifecycle as every other emitted file.
conductor_install_trajectory_ignore() {
  local src="$CORE_ROOT/reflector/trajectories.gitignore"
  local dest="$TARGET_ABS/.conductor/trajectories/.gitignore"
  local entry=""
  [ -f "$src" ] || { echo "Error: trajectory ignore template missing: $src" >&2; return 1; }

  if [ "$DRY_RUN" = "true" ]; then
    log "  would emit .conductor/trajectories/.gitignore"
    return 0
  fi
  conductor_cleanup_legacy_trajectory_ignore
  /bin/mkdir -p "$TARGET_ABS/.conductor/trajectories"
  entry="$(conductor_manifest_entry_for_path ".conductor/trajectories/.gitignore" 2>/dev/null || true)"
  if [ -f "$dest" ] && [ -z "$entry" ] \
    && ! conductor_manifest_identical_shared_owner ".conductor/trajectories/.gitignore" "$dest"; then
    log "  WARNING: .conductor/trajectories/.gitignore is user-owned; preserved unchanged"
    return 0
  fi
  conductor_manifest_backup_and_remember "$dest"
  /bin/cp "$src" "$dest"
  record_emit ".conductor/trajectories/.gitignore" "core/reflector/trajectories.gitignore" "$MANIFEST_LAST_BACKUP"
}

# Undo the exact unmanifested top-level block emitted by older installers.
# Only the framework-tagged two-line payload is removed; all user lines remain.
conductor_cleanup_legacy_trajectory_ignore() {
  local legacy="$TARGET_ABS/.gitignore" tmp
  [ -f "$legacy" ] || return 0
  /usr/bin/grep -qF '# CONDUCTOR local trajectory data (framework config remains trackable)' "$legacy" || return 0
  tmp="$legacy.$$.conductor-tmp"
  /usr/bin/awk '
    function flush() { if (held) { print prev; held=0 } }
    {
      if ($0 == "# CONDUCTOR local trajectory data (framework config remains trackable)") {
        if ((getline nextline) > 0 && nextline == ".conductor/trajectories/") {
          if (held && prev == "") held=0
          removed=1
          next
        }
        flush(); print $0
        if (nextline != "") { prev=nextline; held=1 }
        next
      }
      flush(); prev=$0; held=1
    }
    END { flush() }
  ' "$legacy" > "$tmp"
  if /usr/bin/cmp -s "$legacy" "$tmp"; then
    /bin/rm -f "$tmp"
    return 0
  fi
  if /usr/bin/grep -q '[^[:space:]]' "$tmp"; then
    /bin/mv -f "$tmp" "$legacy"
  else
    /bin/rm -f "$tmp" "$legacy"
  fi
  log "  removed legacy unmanifested trajectory block from .gitignore"
}

conductor_install_project_profile() {
  local src="$CORE_ROOT/project-profile.json"
  local dest="$TARGET_ABS/.conductor/project.json"
  case "$MODE" in full|minimal|strict) ;; *) return 0 ;; esac
  [ -f "$src" ] || { echo "Error: shared project profile missing: $src" >&2; return 1; }
  if [ -f "$dest" ]; then
    log "  skip .conductor/project.json (existing project profile preserved)"
    return 0
  fi
  if [ "$DRY_RUN" = "true" ]; then
    log "would write $dest"
    return 0
  fi
  /bin/mkdir -p "$(dirname "$dest")"
  /bin/cp "$src" "$dest"
  record_emit ".conductor/project.json" "core/project-profile.json" ""
  log "  wrote $dest"
}

conductor_manifest_write_projection() {
  local legacy tmp other adapter version mode first
  legacy="${LEGACY_MANIFEST_PATH:-$TARGET_ABS/.conductor-manifest.json}"
  tmp="$legacy.$$.tmp"
  first="true"
  {
    printf '{\n  "schema_version": 2,\n  "manifest_scope": "projection",\n  "installed_adapters": ['
    for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
      [ -f "$other" ] || continue
      adapter="$(basename "$other" .json)"
      [ "$first" = "true" ] || printf ', '
      printf '"%s"' "$adapter"
      first="false"
    done
    printf '],\n  "manifests": [\n'
    first="true"
    for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
      [ -f "$other" ] || continue
      adapter="$(basename "$other" .json)"
      version="$(/usr/bin/sed -n -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$other" | /usr/bin/head -n 1)"
      mode="$(/usr/bin/sed -n -E 's/^[[:space:]]*"mode"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$other" | /usr/bin/head -n 1)"
      [ "$first" = "true" ] || printf ',\n'
      printf '    {"adapter": "%s", "path": ".conductor/manifests/%s.json", "version": "%s", "mode": "%s"}' "$adapter" "$adapter" "$version" "$mode"
      first="false"
    done
    printf '\n  ]\n}\n'
  } > "$tmp"
  /bin/mv -f "$tmp" "$legacy"
}

conductor_manifest_publish_projection() {
  local legacy
  legacy="${LEGACY_MANIFEST_PATH:-$TARGET_ABS/.conductor-manifest.json}"
  [ -f "$MANIFEST_PATH" ] || return 0
  if [ "$DRY_RUN" = "true" ]; then
    log "would refresh aggregate compatibility manifest $legacy"
    return 0
  fi
  conductor_manifest_write_projection
}

conductor_manifest_refresh_projection() {
  local legacy any="false" other
  legacy="${LEGACY_MANIFEST_PATH:-$TARGET_ABS/.conductor-manifest.json}"
  for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
    [ -f "$other" ] && { any="true"; break; }
  done
  if [ "$DRY_RUN" = "true" ]; then
    [ "$any" = "true" ] && log "would refresh aggregate compatibility manifest $legacy" || log "would delete compatibility manifest $legacy"
    return 0
  fi
  [ "$any" = "true" ] && conductor_manifest_write_projection || /bin/rm -f "$legacy"
}

# Return success when another active adapter still owns or depends on a path.
# Full/minimal installs all depend on the shared docs/profile even when those
# files predated that adapter and therefore were not recorded as emitted files.
conductor_manifest_path_needed_elsewhere() {
  local rel="$1" other mode
  for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
    [ -f "$other" ] || continue
    [ "$other" = "$MANIFEST_PATH" ] && continue
    if /usr/bin/grep -qF "\"path\": \"$rel\"" "$other"; then
      return 0
    fi
    case "$rel" in
      docs/*|.conductor/project.json)
        mode="$(/usr/bin/sed -n -E 's/^[[:space:]]*"mode"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$other" | /usr/bin/head -n 1)"
        case "$mode" in full|minimal|strict|'') return 0 ;; esac
        ;;
    esac
  done
  return 1
}

conductor_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | /usr/bin/awk '{print $1}'
  else
    /usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}'
  fi
}

# Return the one-line normal-file manifest entry for a relative path.
conductor_manifest_entry_for_path() {
  local wanted="$1" line found
  [ -f "$MANIFEST_PATH" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      *'"path":'*'"source":'*)
        found="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
        [ "$found" = "$wanted" ] && { printf '%s\n' "$line"; return 0; }
        ;;
    esac
  done < "$MANIFEST_PATH"
  return 1
}

# Return success when an identical file is already owned by another adapter.
# This prevents a multi-adapter install from creating backup chains for shared,
# byte-identical runtime assets while each adapter still records the dependency.
conductor_manifest_identical_shared_owner() {
  local rel="$1" dest="$2" other line expected actual
  [ -f "$dest" ] || return 1
  actual="$(conductor_sha256_file "$dest")"
  for other in "$TARGET_ABS"/.conductor/manifests/*.json; do
    [ -f "$other" ] || continue
    [ "$other" = "$MANIFEST_PATH" ] && continue
    line="$(/usr/bin/grep -F "\"path\": \"$rel\"" "$other" | /usr/bin/head -n 1 || true)"
    [ -n "$line" ] || continue
    expected="$(conductor_manifest_field "$line" sha256 2>/dev/null || true)"
    [ -n "$expected" ] && [ "$actual" = "$expected" ] && return 0
  done
  return 1
}

# Portable skills are instruction-only, canonical core assets. Claude uses its
# native project root; the other five adapters intentionally share .agents/skills.
CONDUCTOR_PORTABLE_SKILLS="plan-change verify-change review-change"
CONDUCTOR_SELF_IMPROVEMENT_SKILLS="propose-skill"
CONDUCTOR_GIT_HYGIENE_SKILLS="coordinate-work"

conductor_selected_portable_skills() {
  local selected=""
  case "${MODE:-}" in full|minimal|strict) selected="$CONDUCTOR_PORTABLE_SKILLS" ;; esac
  case ",${RECIPES:-}," in *,self-improvement,*) selected="$selected $CONDUCTOR_SELF_IMPROVEMENT_SKILLS" ;; esac
  case ",${RECIPES:-}," in *,git-hygiene,*) selected="$selected $CONDUCTOR_GIT_HYGIENE_SKILLS" ;; esac
  printf '%s\n' "$selected" | /usr/bin/awk '{$1=$1; print}'
}

# Strict mode may share an identical skill, but must reject every conflicting
# pre-existing entry before manifest staging or adapter output begins.
conductor_assert_portable_skill_collisions() {
  local adapter="$1" skill_root="$2" skill src dest skill_dir extra skills
  skills="$(conductor_selected_portable_skills)"
  [ -n "$skills" ] || return 0

  if [ -e "$TARGET_ABS/$skill_root" ] && [ ! -d "$TARGET_ABS/$skill_root" ]; then
    echo "Error: portable skill root is not a directory: $TARGET_ABS/$skill_root" >&2
    return 1
  fi

  for skill in $skills; do
    src="$CORE_ROOT/skills/$skill/SKILL.md"
    skill_dir="$TARGET_ABS/$skill_root/$skill"
    dest="$skill_dir/SKILL.md"
    [ -f "$src" ] || {
      echo "Error: portable skill source missing: $src" >&2
      return 1
    }
    if [ -e "$skill_dir" ] && [ ! -d "$skill_dir" ]; then
      echo "Error: portable skill directory is not a directory: $skill_dir" >&2
      return 1
    fi
    [ "$MODE" = "strict" ] || continue
    if [ -d "$skill_dir" ]; then
      extra="$(/usr/bin/find "$skill_dir" -mindepth 1 -maxdepth 1 ! -name SKILL.md -print -quit 2>/dev/null)"
      if [ -n "$extra" ]; then
        echo "Error (--mode=strict): $skill_dir contains a non-CONDUCTOR entry; no adapter output was written." >&2
        return 3
      fi
    fi
    [ -e "$dest" ] || continue
    if [ ! -f "$dest" ] || ! /usr/bin/cmp -s "$src" "$dest"; then
      echo "Error (--mode=strict): $dest conflicts with the CONDUCTOR $skill skill; no adapter output was written." >&2
      echo "  Use --mode=full for manifest-backed preservation, or move the conflicting entry first." >&2
      return 3
    fi
  done
  [ "$MODE" != "strict" ] || log "  strict portable-skill preflight passed for $adapter ($skill_root)"
}

conductor_install_portable_skills() {
  local adapter="$1" skill_root="$2" skill src dest rel skills
  skills="$(conductor_selected_portable_skills)"
  [ -n "$skills" ] || return 0

  log "  portable skills → $skill_root/ ($skills)"
  for skill in $skills; do
    src="$CORE_ROOT/skills/$skill/SKILL.md"
    dest="$TARGET_ABS/$skill_root/$skill/SKILL.md"
    rel="$skill_root/$skill/SKILL.md"
    [ -f "$src" ] || {
      echo "Error: portable skill source missing: $src" >&2
      return 1
    }
    if [ "$DRY_RUN" = "true" ]; then
      log "  would emit $rel for $adapter"
      continue
    fi
    /bin/mkdir -p "$(dirname "$dest")"
    conductor_manifest_backup_and_remember "$dest"
    /bin/cp "$src" "$dest"
    record_emit "$rel" "core/skills/$skill/SKILL.md" "$MANIFEST_LAST_BACKUP"
  done
}

# Return a simple string-valued JSON field from a manifest entry.
conductor_manifest_field() {
  local line="$1" key="$2"
  case "$line" in
    *"\"$key\":"*)
      printf '%s' "$line" | /usr/bin/sed -E "s/.*\"$key\": *\"([^\"]*)\".*/\\1/"
      ;;
    *) return 1 ;;
  esac
}

conductor_unique_backup_path() {
  local dest="$1" ts candidate n=0
  ts="$(/bin/date +%Y%m%d-%H%M%S)"
  candidate="${dest}.conductor-backup-${ts}"
  while [ -e "$candidate" ]; do
    n=$((n + 1))
    candidate="${dest}.conductor-backup-${ts}-${n}"
  done
  printf '%s' "$candidate"
}

# Preserve the initial pre-CONDUCTOR backup across an unmodified re-install.
# If the prior emitted file was edited, back up that edit before replacing it.
conductor_manifest_backup_and_remember() {
  local dest="$1" rel entry prior_sha prior_backup current_sha backup
  MANIFEST_LAST_BACKUP=""
  [ -f "$dest" ] || return 0

  if [ "$DRY_RUN" = "true" ]; then
    log "would safely back up existing $dest"
    return 0
  fi

  rel="${dest#$TARGET_ABS/}"
  entry="$(conductor_manifest_entry_for_path "$rel" 2>/dev/null || true)"
  if [ -z "$entry" ] && conductor_manifest_identical_shared_owner "$rel" "$dest"; then
    log "  reusing identical shared file $dest"
    return 0
  fi
  if [ -n "$entry" ]; then
    prior_sha="$(conductor_manifest_field "$entry" sha256 2>/dev/null || true)"
    prior_backup="$(conductor_manifest_field "$entry" backup_path 2>/dev/null || true)"
    current_sha="$(conductor_sha256_file "$dest")"

    if [ -n "$prior_sha" ] && [ "$current_sha" = "$prior_sha" ]; then
      if [ -n "$prior_backup" ] && [ -f "$TARGET_ABS/$prior_backup" ]; then
        MANIFEST_LAST_BACKUP="$prior_backup"
        log "  retained original backup for $dest across re-install"
      else
        log "  re-installing unchanged CONDUCTOR file $dest"
      fi
      return 0
    fi

    # A different adapter may already have refreshed a shared, byte-identical
    # asset from the same core source. Treat that as an owned update, not as a
    # user edit, and retain this adapter's original pre-CONDUCTOR backup.
    if conductor_manifest_identical_shared_owner "$rel" "$dest"; then
      if [ -n "$prior_backup" ] && [ -f "$TARGET_ABS/$prior_backup" ]; then
        MANIFEST_LAST_BACKUP="$prior_backup"
      fi
      log "  reusing shared owner update for $dest"
      return 0
    fi

    if [ -n "$prior_sha" ]; then
      log "  preserved user-modified file before re-install: $dest"
    else
      log "  preserved legacy manifest file before re-install: $dest"
    fi
  fi

  backup="$(conductor_unique_backup_path "$dest")"
  /bin/cp "$dest" "$backup"
  MANIFEST_LAST_BACKUP="${backup#$TARGET_ABS/}"
  log "  backed up existing $dest -> $backup"
}

# Compose one adapter-native JSON hook registry without replacing user-owned
# keys or hook entries. Rendering happens before backup/mutation, so invalid
# JSON or an unsupported shape leaves both the target and manifest stage
# untouched. The adapter's normal manifest lifecycle provides exact uninstall
# restoration and unchanged-reinstall backup retention.
conductor_validate_hook_config() {
  local adapter="$1" rel="$2"
  local dest="$TARGET_ABS/$rel"
  [ -f "$CONDUCTOR_ROOT/bin/hook-config.js" ] || {
    echo "Error: hook config compiler missing from CONDUCTOR package" >&2
    return 1
  }
  if ! /usr/bin/env node "$CONDUCTOR_ROOT/bin/hook-config.js" render \
    "--adapter=$adapter" "--config=$dest" "--features=" >/dev/null; then
    echo "Error: refusing to modify invalid or unsupported hook config: $dest" >&2
    return 1
  fi
}

conductor_install_hook_config() {
  local adapter="$1" rel="$2" features="$3"
  local dest="$TARGET_ABS/$rel" dir tmp entry mode=""
  if [ "$DRY_RUN" = "true" ]; then
    log "would semantically compose $rel from core/hooks/registry.json (features: ${features:-none})"
    return 0
  fi
  [ -f "$CONDUCTOR_ROOT/bin/hook-config.js" ] || {
    echo "Error: hook config compiler missing from CONDUCTOR package" >&2
    return 1
  }
  dir="$(dirname "$dest")"
  /bin/mkdir -p "$dir"
  tmp="$dir/.${rel##*/}.conductor-render-$$.tmp"
  /bin/rm -f "$tmp"
  if ! /usr/bin/env node "$CONDUCTOR_ROOT/bin/hook-config.js" render \
    "--adapter=$adapter" "--config=$dest" "--features=$features" > "$tmp"; then
    /bin/rm -f "$tmp"
    echo "Error: refusing to modify invalid or unsupported hook config: $dest" >&2
    return 1
  fi

  entry="$(conductor_manifest_entry_for_path "$rel" 2>/dev/null || true)"
  if [ -f "$dest" ] && /usr/bin/cmp -s "$dest" "$tmp" && [ -n "$entry" ]; then
    /bin/rm -f "$tmp"
    log "  $rel already contains the selected CONDUCTOR hook registry; preserved"
    return 0
  fi

  if [ -f "$dest" ]; then
    mode="$(/usr/bin/stat -f '%Lp' "$dest" 2>/dev/null || /usr/bin/stat -c '%a' "$dest" 2>/dev/null || true)"
  fi
  conductor_manifest_backup_and_remember "$dest"
  if [ -n "$mode" ]; then /bin/chmod "$mode" "$tmp"; else /bin/chmod 644 "$tmp"; fi
  /bin/mv -f "$tmp" "$dest"
  record_emit "$rel" "<semantic-merge:core/hooks/registry.json>" "$MANIFEST_LAST_BACKUP"
  log "  composed $rel (existing non-CONDUCTOR settings preserved)"
}

conductor_manifest_file_matches() {
  local file="$1" expected_sha="$2"
  [ -n "$expected_sha" ] && [ -f "$file" ] \
    && [ "$(conductor_sha256_file "$file")" = "$expected_sha" ]
}

# Render the portable bounded kernel without importing complete references into
# the always-loaded surface. Complete rule/recipe files are emitted separately by
# each adapter. The selected recipe list contains only trusted core metadata and
# exact reference paths; it is intentionally small enough to remain eager.
conductor_render_runtime_kernel() {
  local tool_name="$1" rule_root="$2" recipe_root="$3" rules_enabled="$4" recipes="$5"
  local kernel="$CORE_ROOT/runtime-kernel.md" r src recipe_name applies_when
  [ -f "$kernel" ] || {
    echo "Error: portable runtime kernel missing: $kernel" >&2
    return 1
  }
  TOOL_NAME="$tool_name" RULE_ROOT="$rule_root" RECIPE_ROOT="$recipe_root" \
    /usr/bin/awk '
      {
        gsub(/\{\{TOOL_NAME\}\}/, ENVIRON["TOOL_NAME"])
        gsub(/\{\{RULE_ROOT\}\}/, ENVIRON["RULE_ROOT"])
        gsub(/\{\{RECIPE_ROOT\}\}/, ENVIRON["RECIPE_ROOT"])
        if ($0 == "{{SELECTED_RECIPES_SECTION}}") next
        print
      }
    ' "$kernel"

  if [ "$rules_enabled" != "true" ]; then
    /bin/cat <<EOF

## Complete universal-rule references

This installation intentionally omitted complete universal-rule references. The
non-negotiable kernel remains active; do not claim that files under
\`$rule_root/\` were loaded.
EOF
  fi

  echo ""
  echo "## Selected recipe routing"
  echo ""
  if [ -z "$recipes" ]; then
    echo "No optional CONDUCTOR recipes were selected for this installation."
    return 0
  fi
  echo "Read a matching complete recipe before acting in its domain:"
  echo ""
  _old_ifs="$IFS"; IFS=','
  for r in $recipes; do
    r="$(printf '%s' "$r" | /usr/bin/sed 's/^ *//; s/ *$//')"
    [ -n "$r" ] || continue
    src="$CORE_ROOT/recipes/$r.md"
    [ -f "$src" ] || continue
    recipe_name="$(/usr/bin/sed -n -E 's/^recipe_name:[[:space:]]*"?([^"].*[^" ]|[^" ])"?[[:space:]]*$/\1/p' "$src" | /usr/bin/head -n 1)"
    applies_when="$(/usr/bin/sed -n -E 's/^applies_when:[[:space:]]*"?([^"].*[^" ]|[^" ])"?[[:space:]]*$/\1/p' "$src" | /usr/bin/head -n 1)"
    [ -n "$recipe_name" ] || recipe_name="$r"
    [ -n "$applies_when" ] || applies_when="when the selected recipe domain applies"
    printf -- '- `%s` (%s): %s. Reference: `%s/%s.md`\n' "$r" "$recipe_name" "$applies_when" "$recipe_root" "$r"
  done
  IFS="$_old_ifs"
}

# Body for a small native path-triggered recipe pointer. The adapter supplies its
# own frontmatter, preserving native path/glob scoping while the complete recipe
# stays outside the eager instruction surface.
conductor_render_recipe_pointer_body() {
  local src="$1" reference="$2" recipe_id recipe_name applies_when
  recipe_id="$(/usr/bin/sed -n -E 's/^recipe_id:[[:space:]]*([^[:space:]]+).*/\1/p' "$src" | /usr/bin/head -n 1)"
  recipe_name="$(/usr/bin/sed -n -E 's/^recipe_name:[[:space:]]*"?([^"].*[^" ]|[^" ])"?[[:space:]]*$/\1/p' "$src" | /usr/bin/head -n 1)"
  applies_when="$(/usr/bin/sed -n -E 's/^applies_when:[[:space:]]*"?([^"].*[^" ]|[^" ])"?[[:space:]]*$/\1/p' "$src" | /usr/bin/head -n 1)"
  [ -n "$recipe_id" ] || recipe_id="$(basename "$src" .md)"
  [ -n "$recipe_name" ] || recipe_name="$recipe_id"
  [ -n "$applies_when" ] || applies_when="when this selected recipe domain applies"
  /bin/cat <<EOF
# CONDUCTOR recipe trigger — $recipe_name

Applies when: $applies_when.

Before acting in this domain, read \`$reference\`. Its complete content is the
mandatory selected recipe. This pointer preserves native scoping without loading
the full recipe into unrelated requests. If the reference is missing, report an
incomplete CONDUCTOR installation instead of inventing the policy.
EOF
}

# Canonical recipe activation globs. Adapters translate this CSV into their
# native frontmatter; keeping the map here prevents Cursor/Claude/Copilot from
# silently assigning different path scope to the same selected recipe.
conductor_recipe_globs_csv() {
  case "$1" in
    monorepo)            printf '%s' 'apps/**,packages/**' ;;
    web-mobile-parity)   printf '%s' 'apps/web/**,apps/mobile/**,packages/shared/**' ;;
    i18n)                printf '%s' '**/i18n/**,**/translations.ts,**/locales/**' ;;
    auto-mock-data)      printf '%s' '**/*.sql,**/migrations/**,**/seeds/**' ;;
    coding-conventions)  printf '%s' '**/*.ts,**/*.tsx' ;;
    database-discipline|database-change-assurance)
                         printf '%s' '**/*.sql,**/migrations/**' ;;
    design-system)       printf '%s' '**/*.tsx,**/*.css,**/*.scss' ;;
    tdd|non-vacuous-testing)
                         printf '%s' '**/*.test.*,**/*.spec.*,**/__tests__/**,**/e2e/**' ;;
    visual-baseline-integrity)
                         printf '%s' '**/screenshots/**,**/visual/**,**/*.spec.*' ;;
    *)                   printf '%s' '**' ;;
  esac
}

# Retire a path from a previous authoritative manifest only when CONDUCTOR still
# owns the exact bytes. User-modified files are preserved and simply lose
# CONDUCTOR ownership. A pre-CONDUCTOR backup is restored when one exists.
conductor_retire_owned_path() {
  local rel="$1" reason="$2" entry expected backup had_backup=false dest
  entry="$(conductor_manifest_entry_for_path "$rel" 2>/dev/null || true)"
  [ -n "$entry" ] || return 0
  expected="$(conductor_manifest_field "$entry" sha256 2>/dev/null || true)"
  backup="$(conductor_manifest_field "$entry" backup_path 2>/dev/null || true)"
  case "$entry" in *'"had_backup": true'*) had_backup=true ;; esac
  dest="$TARGET_ABS/$rel"

  if [ -f "$dest" ] && ! conductor_manifest_file_matches "$dest" "$expected"; then
    log "  preserving user-modified $rel while retiring $reason; ownership released"
  elif [ "$had_backup" = "true" ] && [ -n "$backup" ] && [ -f "$TARGET_ABS/$backup" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      log "would restore $backup -> $rel while retiring $reason"
    else
      /bin/mv -f "$TARGET_ABS/$backup" "$dest"
      log "  restored pre-CONDUCTOR $rel while retiring $reason"
    fi
  else
    if [ "$DRY_RUN" = "true" ]; then
      log "would remove CONDUCTOR-owned $rel while retiring $reason"
    else
      /bin/rm -f "$dest"
      log "  removed CONDUCTOR-owned $rel while retiring $reason"
    fi
  fi
  conductor_manifest_stage_drop_path "$rel"
}

# Return the one-line block manifest entry matching a host relative path/name.
conductor_manifest_block_entry() {
  local wanted_path="$1" wanted_name="$2" line found_path found_name
  [ -f "$MANIFEST_PATH" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      *'"type": "block"'*)
        found_path="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"path": *"([^"]*)".*/\1/')"
        found_name="$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"block": *"([^"]*)".*/\1/')"
        [ "$found_path" = "$wanted_path" ] && [ "$found_name" = "$wanted_name" ] && {
          printf '%s\n' "$line"; return 0;
        }
        ;;
    esac
  done < "$MANIFEST_PATH"
  return 1
}
