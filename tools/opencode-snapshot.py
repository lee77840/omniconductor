"""Read a bounded, stable copy of an explicitly selected OpenCode SQLite DB.

No source SQLite connection is opened (even mode=ro can create WAL sidecars).
Only metadata/counters leave this process; message bodies are never returned.
"""
import hashlib
import json
import math
import os
import pathlib
import shutil
import sqlite3
import stat
import sys
import tempfile
import time

MAX_BYTES = 256 * 1024 * 1024
MAX_ROWS = 50000


def signature(file):
    s = os.lstat(file)
    if not stat.S_ISREG(s.st_mode) or s.st_nlink != 1:
        raise ValueError("database and WAL must be regular single-link files")
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def digest(file):
    h = hashlib.sha256()
    with open(file, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def number(value):
    return value if type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 9007199254740991 else None


def counter(value):
    return value if type(value) is int and 0 <= value <= 9007199254740991 else None


def label(value):
    # Never emit arbitrary message text in a metadata slot.
    import re
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:/-]{1,180}", value) else None


def main():
    source = pathlib.Path(sys.argv[1]).absolute()
    for ancestor in (source, *source.parents):
        if ancestor.is_symlink():
            raise ValueError("database path must not traverse symbolic links")
    if os.path.exists(str(source) + "-journal"):
        raise ValueError("rollback journal present; close OpenCode cleanly before taking a snapshot")
    originals = [source]
    wal = pathlib.Path(str(source) + "-wal")
    if wal.exists():
        originals.append(wal)
    before = {str(f): signature(f) for f in originals}
    if sum(s[2] for s in before.values()) > MAX_BYTES:
        raise ValueError("database plus WAL exceeds 256 MiB snapshot budget")
    with tempfile.TemporaryDirectory(prefix="conductor-opencode-read-") as temporary:
        db = pathlib.Path(temporary) / "snapshot.db"
        for original in originals:
            copied = pathlib.Path(str(db) + ("-wal" if original == wal else ""))
            shutil.copyfile(original, copied)
            if signature(original) != before[str(original)] or digest(original) != digest(copied):
                raise ValueError("database changed during snapshot; retry after OpenCode becomes idle")
        if os.path.exists(str(source) + '-journal') or wal.exists() != (wal in originals) or any(signature(f) != before[str(f)] for f in originals):
            raise ValueError("database/WAL changed during snapshot")
        # Any recovery/shm writes are confined to the private disposable copy.
        from contextlib import closing
        with closing(sqlite3.connect(db.as_uri() + "?mode=ro", uri=True, timeout=2)) as connection:
            connection.execute("PRAGMA query_only=ON")
            deadline = time.monotonic() + 20
            connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
            schema = {table: [(r[1], r[2]) for r in connection.execute("PRAGMA table_info(" + table + ")")]
                      for table in ("session", "message")}
            columns = {table: {r[0] for r in rows} for table, rows in schema.items()}
            required = {"session": {"id", "directory"}, "message": {"id", "session_id", "time_created", "data"}}
            if any(not required[t].issubset(columns[t]) for t in required):
                raise ValueError("unsupported OpenCode schema; expected session(id,directory), message(id,session_id,time_created,data)")
            fingerprint = hashlib.sha256(json.dumps(schema, sort_keys=True).encode()).hexdigest()
            parent = 's.parent_id' if 'parent_id' in columns['session'] else 'NULL'
            sessions = []
            for sid, directory, parent_id in connection.execute('SELECT s.id,s.directory,' + parent + ' FROM session s LIMIT ?', (MAX_ROWS + 1,)):
                if len(sessions) == MAX_ROWS:
                    raise ValueError('session metadata exceeds inspection budget')
                if not label(sid) or (parent_id is not None and not label(parent_id)):
                    raise ValueError('unsupported session identity')
                sessions.append(dict(session=sid, directory=directory, parent=parent_id))
            sql = "SELECT m.id,m.session_id,m.time_created,m.data,s.directory," + parent + " FROM message m JOIN session s ON s.id=m.session_id ORDER BY m.time_created,m.id LIMIT ?"
            rows = []
            total_json = 0
            for index, (mid, sid, created, data, directory, parent_id) in enumerate(connection.execute(sql, (MAX_ROWS + 1,))):
                if index == MAX_ROWS:
                    raise ValueError("database exceeds 50000-message inspection budget; use a smaller exported database")
                if not isinstance(data, str) or len(data.encode()) > 1024 * 1024:
                    raise ValueError("invalid or oversized message JSON")
                total_json += len(data.encode())
                if total_json > 64 * 1024 * 1024:
                    raise ValueError("message JSON exceeds 64 MiB inspection budget")
                try:
                    message = json.loads(data)
                except Exception:
                    raise ValueError("invalid message JSON; usage not inferred")
                if not isinstance(message, dict):
                    raise ValueError("message JSON must be an object")
                if message.get('role') != 'assistant':
                    continue
                tokens = message.get('tokens') if isinstance(message.get('tokens'), dict) else {}
                cache = tokens.get('cache') if isinstance(tokens.get('cache'), dict) else {}
                rows.append(dict(id=label(mid), session=label(sid), parent=label(parent_id),
                                 directory=directory, time_created=number(created),
                                 provider=label(message.get('providerID')), model=label(message.get('modelID')),
                                 role=label(message.get('agent') or message.get('mode')),
                                 cost=number(message.get('cost')), input=counter(tokens.get('input')),
                                 output=counter(tokens.get('output')), reasoning=counter(tokens.get('reasoning')),
                                 cache_read=counter(cache.get('read')), cache_write=counter(cache.get('write'))))
        print(json.dumps(dict(schema_fingerprint=fingerprint, schema=schema,
                              parent_attribution_available='parent_id' in columns['session'], sessions=sessions, rows=rows)))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Errors intentionally omit raw SQL data, paths, and message contents.
        print('OpenCode snapshot: ' + (str(error) if isinstance(error, ValueError) else type(error).__name__), file=sys.stderr)
        sys.exit(2)
