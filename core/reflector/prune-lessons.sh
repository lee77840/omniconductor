#!/usr/bin/env bash
#
# CONDUCTOR — deterministic lesson prune (non-LLM). Anti-collapse guarantee.
# Usage: prune-lessons.sh [MEMORY_DIR]   (default: current dir)
#
# Operations (idempotent; NON-destructive except exact-duplicate removal):
#   - decay:     lessons with last_used older than DECAY_WEEKS  -> status: stale
#   - dead-path: lessons whose `source:` is a path that no longer exists
#                -> status: stale  (never deletes a lesson — only marks it)
#   - dedup:     byte-identical lesson files -> keep one, remove the exact copies
#
# Only exact byte-duplicates are ever removed (no information is lost). Decay and
# dead-path never delete — they mark `status: stale`, which a human can review or
# reverse. This matches the propose-only philosophy: an unattended script must not
# destroy user memory.
#
# Env:
#   CONDUCTOR_NOW=YYYY-MM-DD        (default: today, UTC)
#   CONDUCTOR_DECAY_WEEKS=N         (default: 8)
#   CONDUCTOR_PROJECT_ROOT=/path    (root to resolve `source:` paths against;
#                                    default: git toplevel of MEMORY_DIR, else PWD)
set -u

MEM_DIR="${1:-.}"
[ -d "$MEM_DIR" ] || { echo "prune: no memory dir: $MEM_DIR" >&2; exit 0; }

NOW="${CONDUCTOR_NOW:-$(/bin/date -u +%Y-%m-%d)}"
DECAY_WEEKS="${CONDUCTOR_DECAY_WEEKS:-8}"
ROOT="${CONDUCTOR_PROJECT_ROOT:-$(git -C "$MEM_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"

now_epoch=$(/bin/date -j -f '%Y-%m-%d' "$NOW" +%s 2>/dev/null || /bin/date -d "$NOW" +%s 2>/dev/null || echo 0)
cutoff=$(( DECAY_WEEKS * 7 * 86400 ))

# Set the frontmatter `status:` to stale (only within the leading --- block). Idempotent.
mark_stale() {
  /usr/bin/awk '
    /^---[[:space:]]*$/ { d++; print; next }
    d==1 && /^status:/  { print "status: stale"; next }
    { print }
  ' "$1" > "$1.prune.tmp" && /bin/mv "$1.prune.tmp" "$1"
}

# Read a frontmatter field value (first line `key: ...`, whole value incl. spaces).
fm_value() {  # $1=file  $2=key
  /usr/bin/awk -v k="^$2:" '
    $0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
  ' "$1"
}

shopt -s nullglob
for f in "$MEM_DIR"/feedback_lesson-*.md; do
  [ -f "$f" ] || continue
  already_stale=0
  [ "$(fm_value "$f" status)" = "stale" ] && already_stale=1   # frontmatter status (first match)

  # dead-path (NON-destructive): only when source: is a path — contains '/', with
  # no internal whitespace (a retro-line is prose, not a path) — that does not
  # exist under ROOT or as given. Marks stale + logs; never deletes.
  if [ "$already_stale" -eq 0 ]; then
    src="$(fm_value "$f" source)"
    case "$src" in
      *[[:space:]]*) : ;;                 # internal whitespace -> not a path, skip
      */*)
        if [ ! -e "$ROOT/$src" ] && [ ! -e "$src" ]; then
          mark_stale "$f"
          echo "prune: dead-path -> stale: $f (source: $src)" >&2
          already_stale=1
        fi
        ;;
    esac
  fi

  # decay: last_used older than cutoff -> stale
  if [ "$already_stale" -eq 0 ] && [ "$now_epoch" -gt 0 ]; then
    lu="$(fm_value "$f" last_used)"
    if [ -n "$lu" ]; then
      lu_epoch=$(/bin/date -j -f '%Y-%m-%d' "$lu" +%s 2>/dev/null || /bin/date -d "$lu" +%s 2>/dev/null || echo "$now_epoch")
      if [ $(( now_epoch - lu_epoch )) -gt "$cutoff" ]; then
        mark_stale "$f"
      fi
    fi
  fi
done

# dedup: byte-identical lesson files -> keep first, remove exact copies.
# Whitespace-safe: emit hash<TAB>path (a hash never contains a tab or space), so a
# MEMORY_DIR or filename with spaces is handled correctly.
prev=""
while IFS= read -r line; do
  h=${line%%$'\t'*}
  p=${line#*$'\t'}
  if [ "$h" = "$prev" ]; then
    /bin/rm -f "$p" && echo "prune: dedup removed exact copy: $p" >&2
  else
    prev="$h"
  fi
done < <(
  for f in "$MEM_DIR"/feedback_lesson-*.md; do
    [ -f "$f" ] || continue
    hh=$(/sbin/md5 -q "$f" 2>/dev/null || /usr/bin/md5sum "$f" 2>/dev/null | /usr/bin/cut -d' ' -f1)
    [ -n "$hh" ] && printf '%s\t%s\n' "$hh" "$f"   # skip if no hash tool (never treat "" as a dup)
  done | /usr/bin/sort
)

exit 0
