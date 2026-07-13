#!/usr/bin/env bash
# Shared manifest-safety helpers for the six adapters.
#
# This file is sourced after an adapter defines TARGET_ABS, MANIFEST_PATH,
# DRY_RUN, and log().  It deliberately uses only bash + shasum/sha256sum so
# installers remain dependency-free.

# Manifest schema v2 keeps one authoritative manifest per adapter so a project
# can install several tool surfaces without the next install destroying the
# previous adapter's ownership record.  The historical root manifest remains a
# compatibility projection for pre-v2 consumers.

# Read the portable difficulty contract from a role source. Keeping this parser
# shared prevents six adapters from silently assigning different capability to
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

conductor_manifest_file_matches() {
  local file="$1" expected_sha="$2"
  [ -n "$expected_sha" ] && [ -f "$file" ] \
    && [ "$(conductor_sha256_file "$file")" = "$expected_sha" ]
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
