#!/usr/bin/env bash
# Shared manifest-safety helpers for the six adapters.
#
# This file is sourced after an adapter defines TARGET_ABS, MANIFEST_PATH,
# DRY_RUN, and log().  It deliberately uses only bash + shasum/sha256sum so
# installers remain dependency-free.

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
