#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const SCHEMA_VERSION = 1;
const STATE_DIR_NAME = 'conductor/work-claims-v1';
const RECORD_LIMIT = 128 * 1024;
const DIFF_LIMIT = 16 * 1024 * 1024;
const FILE_HASH_LIMIT = 64 * 1024 * 1024;
const LOCK_STALE_MS = 30_000;
const TOOLS = new Set(['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'human']);
const ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,79}$/;
const SESSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$/;

function git(cwd, args, options = {}) {
  const result = spawnSync('git', args, {
    cwd,
    encoding: options.buffer ? null : 'utf8',
    maxBuffer: options.maxBuffer || DIFF_LIMIT,
    timeout: options.timeout || 15_000,
    env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', LC_ALL: 'C' },
  });
  if (result.error || result.status !== 0) {
    const detail = result.error ? result.error.message : String(result.stderr || '').trim();
    throw new Error(`git ${args.join(' ')} failed${detail ? `: ${detail}` : ''}`);
  }
  return options.buffer ? result.stdout : String(result.stdout).trim();
}

function inspectDirectory(directory, label) {
  const stat = fs.lstatSync(directory);
  if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`${label} must be a real directory: ${directory}`);
  return fs.realpathSync(directory);
}

function resolveRepository(targetDir) {
  const requested = path.resolve(targetDir || '.');
  const cwd = inspectDirectory(requested, 'repository target');
  const top = fs.realpathSync(git(cwd, ['rev-parse', '--show-toplevel']));
  if (top !== cwd && !cwd.startsWith(`${top}${path.sep}`)) throw new Error('target is outside its reported Git top-level');
  let common = git(cwd, ['rev-parse', '--git-common-dir']);
  if (!path.isAbsolute(common)) common = path.resolve(cwd, common);
  common = fs.realpathSync(common);
  inspectDirectory(common, 'Git common directory');
  return { cwd, top, common, stateRoot: path.join(common, STATE_DIR_NAME) };
}

function validateIdentity(tool, session) {
  if (!TOOLS.has(tool)) throw new Error(`tool must be one of: ${[...TOOLS].join(', ')}`);
  if (!SESSION_PATTERN.test(session || '')) throw new Error('session must be 1-128 safe identifier characters');
  return { tool, session };
}

function validateTask(task) {
  if (!ID_PATTERN.test(task || '')) throw new Error('task id must match [a-z0-9][a-z0-9._-]{0,79}');
  return task;
}

function validateNote(note) {
  if (note === undefined || note === null || note === '') return '';
  if (typeof note !== 'string' || note.length > 500 || /[\u0000-\u001f\u007f]/u.test(note)) {
    throw new Error('note must be a single-line string up to 500 characters');
  }
  return note;
}

function normalizeScope(value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 300 || value.includes('\0')) {
    throw new Error('scope must be a non-empty repository-relative path up to 300 characters');
  }
  const slash = value.replace(/\\/g, '/').replace(/^\.\//, '').replace(/\/+$/, '') || '.';
  if (slash.startsWith('/') || /^[A-Za-z]:\//.test(slash)) throw new Error(`scope must be relative: ${value}`);
  const normalized = path.posix.normalize(slash);
  if (normalized === '..' || normalized.startsWith('../') || normalized.includes('/../')) {
    throw new Error(`scope escapes the repository: ${value}`);
  }
  return normalized;
}

function normalizeScopes(scopes) {
  const values = (scopes && scopes.length ? scopes : ['.']).map(normalizeScope);
  return [...new Set(values)].sort();
}

function scopesOverlap(left, right) {
  if (left === '.' || right === '.') return true;
  return left === right || left.startsWith(`${right}/`) || right.startsWith(`${left}/`);
}

function safeStateRoot(repo, create) {
  const parent = path.dirname(repo.stateRoot);
  function ensure(directory, label) {
    if (fs.existsSync(directory)) return inspectDirectory(directory, label);
    if (!create) return null;
    try { fs.mkdirSync(directory, { recursive: false, mode: 0o700 }); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    return inspectDirectory(directory, label);
  }
  ensure(parent, 'CONDUCTOR Git state parent');
  ensure(repo.stateRoot, 'work-claim state');
  return repo.stateRoot;
}

function safeRecord(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > RECORD_LIMIT) {
    throw new Error(`unsafe work-claim record: ${file}`);
  }
  return stat;
}

function validateSnapshotShape(snapshotValue, label) {
  if (!snapshotValue || typeof snapshotValue !== 'object'
      || !/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/.test(snapshotValue.head || '')
      || !/^[0-9a-f]{64}$/.test(snapshotValue.digest || '')
      || typeof snapshotValue.branch !== 'string' || !snapshotValue.branch || snapshotValue.branch.length > 300
      || typeof snapshotValue.dirty !== 'boolean'
      || !Number.isInteger(snapshotValue.changed_entries) || snapshotValue.changed_entries < 0
      || !Array.isArray(snapshotValue.untracked)) {
    throw new Error(`invalid ${label}`);
  }
  for (const entry of snapshotValue.untracked) {
    if (!entry || normalizeScope(entry.path) !== entry.path || !/^[0-9a-f]{64}$/.test(entry.sha256 || '')) {
      throw new Error(`invalid ${label} untracked identity`);
    }
  }
  return snapshotValue;
}

function validateStoredIdentity(identity, label) {
  if (!identity || !TOOLS.has(identity.tool) || !SESSION_PATTERN.test(identity.session || '')) {
    throw new Error(`invalid ${label}`);
  }
}

function validateRecord(record, expectedTask) {
  if (!record || record.schema_version !== SCHEMA_VERSION || record.task_id !== expectedTask) {
    throw new Error(`invalid work-claim schema for ${expectedTask}`);
  }
  validateTask(record.task_id);
  if (!['active', 'handed-off', 'released'].includes(record.status)) throw new Error(`invalid claim status for ${expectedTask}`);
  validateStoredIdentity(record.owner, `claim owner for ${expectedTask}`);
  if (!Array.isArray(record.scopes) || !record.scopes.length) throw new Error(`invalid claim scopes for ${expectedTask}`);
  const normalized = normalizeScopes(record.scopes);
  if (JSON.stringify(normalized) !== JSON.stringify(record.scopes)) throw new Error(`claim scopes are not canonical for ${expectedTask}`);
  if (!record.worktree || typeof record.worktree.path !== 'string' || !path.isAbsolute(record.worktree.path)
      || record.worktree.path.includes('\0') || typeof record.worktree.branch !== 'string' || !record.worktree.branch) {
    throw new Error(`invalid worktree identity for ${expectedTask}`);
  }
  validateSnapshotShape(record.claim_snapshot, `claim snapshot for ${expectedTask}`);
  if (!/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/.test(record.base_sha || '')) throw new Error(`invalid base SHA for ${expectedTask}`);
  if (record.status === 'handed-off') {
    if (!record.handoff) throw new Error(`missing handoff state for ${expectedTask}`);
    validateStoredIdentity(record.handoff.from, `handoff source for ${expectedTask}`);
    validateStoredIdentity(record.handoff.to, `handoff recipient for ${expectedTask}`);
    validateSnapshotShape(record.handoff.snapshot, `handoff snapshot for ${expectedTask}`);
    validateNote(record.handoff.note);
  }
  if (record.status === 'released') {
    if (!record.release) throw new Error(`missing release state for ${expectedTask}`);
    validateStoredIdentity(record.release.by, `release owner for ${expectedTask}`);
    validateSnapshotShape(record.release.snapshot, `release snapshot for ${expectedTask}`);
    validateNote(record.release.note);
  }
  if (!Array.isArray(record.history) || record.history.length > 32) throw new Error(`invalid claim history for ${expectedTask}`);
  return record;
}

function recordPath(repo, task) {
  return path.join(repo.stateRoot, `${validateTask(task)}.json`);
}

function readRecord(repo, task) {
  const file = recordPath(repo, task);
  if (!fs.existsSync(file)) return null;
  safeRecord(file);
  let record;
  try { record = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error(`invalid work-claim JSON for ${task}`); }
  return validateRecord(record, task);
}

function readAll(repo) {
  if (!fs.existsSync(repo.stateRoot)) return [];
  safeStateRoot(repo, false);
  const records = [];
  for (const name of fs.readdirSync(repo.stateRoot).sort()) {
    if (name === '.lock' || name.startsWith('.record.')) continue;
    if (!name.endsWith('.json')) throw new Error(`unexpected work-claim state entry: ${name}`);
    const task = name.slice(0, -5);
    records.push(readRecord(repo, task));
  }
  return records;
}

function processAlive(pid) {
  if (!Number.isInteger(pid) || pid < 1) return false;
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code === 'EPERM'; }
}

function reclaimStaleLock(lock) {
  let stat;
  try { stat = fs.lstatSync(lock); } catch { return false; }
  if (!stat.isDirectory() || stat.isSymbolicLink()) return false;
  const names = fs.readdirSync(lock);
  if (names.some((name) => name !== 'owner.json')) return false;
  let owner;
  const ownerFile = path.join(lock, 'owner.json');
  try {
    const ownerStat = fs.lstatSync(ownerFile);
    if (!ownerStat.isFile() || ownerStat.isSymbolicLink() || ownerStat.nlink !== 1 || ownerStat.size > 4096) return false;
    owner = JSON.parse(fs.readFileSync(ownerFile, 'utf8'));
  } catch { owner = null; }
  const created = owner && Date.parse(owner.created_at);
  const age = Number.isFinite(created) ? Date.now() - created : Date.now() - stat.mtimeMs;
  if (age < LOCK_STALE_MS) return false;
  if (owner && processAlive(owner.pid)) return false;
  const tombstone = `${lock}.stale.${process.pid}.${Date.now()}`;
  try { fs.renameSync(lock, tombstone); } catch { return false; }
  try { fs.unlinkSync(path.join(tombstone, 'owner.json')); } catch { /* absent */ }
  try { fs.rmdirSync(tombstone); } catch { /* visible but no longer blocking */ }
  return true;
}

function acquireLock(repo) {
  safeStateRoot(repo, true);
  const lock = path.join(repo.stateRoot, '.lock');
  const deadline = Date.now() + 5000;
  while (true) {
    try {
      fs.mkdirSync(lock, { mode: 0o700 });
      const nonce = crypto.randomBytes(16).toString('hex');
      fs.writeFileSync(path.join(lock, 'owner.json'), `${JSON.stringify({ pid: process.pid, nonce, created_at: new Date().toISOString() })}\n`, { flag: 'wx', mode: 0o600 });
      return () => {
        try {
          const ownerFile = path.join(lock, 'owner.json');
          const ownerStat = fs.lstatSync(ownerFile);
          if (!ownerStat.isFile() || ownerStat.isSymbolicLink() || ownerStat.nlink !== 1 || ownerStat.size > 4096) return;
          const owner = JSON.parse(fs.readFileSync(ownerFile, 'utf8'));
          if (owner.pid !== process.pid || owner.nonce !== nonce) return;
        } catch { return; }
        try { fs.unlinkSync(path.join(lock, 'owner.json')); } catch { /* ignore */ }
        try { fs.rmdirSync(lock); } catch { /* ignore */ }
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (reclaimStaleLock(lock)) continue;
      if (Date.now() >= deadline) throw new Error('another work-contract mutation is active; retry later');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    }
  }
}

function atomicWrite(repo, task, record) {
  const payload = `${JSON.stringify(record, null, 2)}\n`;
  if (Buffer.byteLength(payload) > RECORD_LIMIT) throw new Error('work-claim record exceeds 128 KiB');
  const file = recordPath(repo, task);
  if (fs.existsSync(file)) safeRecord(file);
  const temp = path.join(repo.stateRoot, `.record.${process.pid}.${Date.now()}.${crypto.randomBytes(6).toString('hex')}`);
  let fd;
  try {
    fd = fs.openSync(temp, 'wx', 0o600);
    fs.writeFileSync(fd, payload, 'utf8');
    fs.fsyncSync(fd);
    fs.closeSync(fd); fd = null;
    fs.renameSync(temp, file);
    try {
      const dirFd = fs.openSync(repo.stateRoot, 'r');
      fs.fsyncSync(dirFd); fs.closeSync(dirFd);
    } catch { /* directory fsync is platform-dependent */ }
  } finally {
    if (fd !== undefined && fd !== null) try { fs.closeSync(fd); } catch { /* ignore */ }
    try { fs.unlinkSync(temp); } catch { /* ignore */ }
  }
}

function hashRegularFile(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > FILE_HASH_LIMIT) {
    throw new Error(`untracked snapshot input must be a single-link regular file no larger than 64 MiB: ${file}`);
  }
  const hash = crypto.createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.allocUnsafe(64 * 1024);
  try {
    let offset = 0;
    while (offset < stat.size) {
      const length = fs.readSync(fd, buffer, 0, Math.min(buffer.length, stat.size - offset), offset);
      if (!length) break;
      hash.update(buffer.subarray(0, length));
      offset += length;
    }
  } finally { fs.closeSync(fd); }
  return hash.digest('hex');
}

function snapshot(targetDir) {
  const repo = resolveRepository(targetDir);
  const head = git(repo.cwd, ['rev-parse', '--verify', 'HEAD']);
  let branch = '(detached)';
  const branchResult = spawnSync('git', ['symbolic-ref', '--quiet', '--short', 'HEAD'], {
    cwd: repo.cwd, encoding: 'utf8', timeout: 5000,
    env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', LC_ALL: 'C' },
  });
  if (branchResult.status === 0) branch = String(branchResult.stdout).trim();
  const diff = git(repo.cwd, ['diff', '--binary', '--no-ext-diff', 'HEAD', '--'], { buffer: true, maxBuffer: DIFF_LIMIT });
  const status = git(repo.cwd, ['status', '--porcelain=v1', '-z', '--untracked-files=all'], { buffer: true, maxBuffer: DIFF_LIMIT });
  const others = git(repo.cwd, ['ls-files', '--others', '--exclude-standard', '-z'], { buffer: true, maxBuffer: DIFF_LIMIT });
  const untracked = others.toString('utf8').split('\0').filter(Boolean).sort();
  const hash = crypto.createHash('sha256');
  hash.update(`head\0${head}\0`);
  hash.update(diff);
  hash.update(status);
  const identities = [];
  for (const relative of untracked) {
    const normalized = normalizeScope(relative);
    const absolute = path.resolve(repo.top, normalized);
    if (absolute !== repo.top && !absolute.startsWith(`${repo.top}${path.sep}`)) throw new Error(`untracked path escapes repository: ${relative}`);
    const stat = fs.lstatSync(absolute);
    let digest;
    if (stat.isSymbolicLink()) digest = crypto.createHash('sha256').update(`symlink:${fs.readlinkSync(absolute)}`).digest('hex');
    else digest = hashRegularFile(absolute);
    identities.push({ path: normalized, sha256: digest });
    hash.update(`untracked\0${normalized}\0${digest}\0`);
  }
  return {
    head,
    branch,
    digest: hash.digest('hex'),
    dirty: status.length > 0,
    changed_entries: status.toString('utf8').split('\0').filter(Boolean).length,
    untracked: identities,
  };
}

function sameOwner(record, identity) {
  return record.owner.tool === identity.tool && record.owner.session === identity.session;
}

function appendHistory(record, event) {
  const history = [...record.history, event];
  return history.slice(-32);
}

function assertNoOverlap(records, task, scopes) {
  for (const record of records) {
    if (record.task_id === task || !['active', 'handed-off'].includes(record.status)) continue;
    for (const mine of scopes) {
      for (const theirs of record.scopes) {
        if (scopesOverlap(mine, theirs)) {
          throw new Error(`scope '${mine}' overlaps ${record.status} task '${record.task_id}' scope '${theirs}'`);
        }
      }
    }
  }
}

function claim(targetDir, task, options) {
  const repo = resolveRepository(targetDir);
  const identity = validateIdentity(options.tool, options.session);
  const scopes = normalizeScopes(options.scopes);
  const release = acquireLock(repo);
  try {
    const records = readAll(repo);
    const existing = records.find((record) => record.task_id === validateTask(task));
    const now = new Date().toISOString();
    if (existing) {
      if (existing.status === 'active') {
        if (!sameOwner(existing, identity)) throw new Error(`task '${task}' is owned by ${existing.owner.tool}/${existing.owner.session}`);
        if (existing.worktree.path !== repo.top) throw new Error(`task '${task}' belongs to another worktree`);
        if (JSON.stringify(existing.scopes) !== JSON.stringify(scopes)) throw new Error('idempotent claim must preserve exact scopes');
        assertNoOverlap(records, task, existing.scopes);
        return { created: false, resumed: false, record: existing, state_root: repo.stateRoot };
      }
      if (existing.status === 'released') throw new Error(`task '${task}' is released and its audit id cannot be reused`);
      const target = existing.handoff && existing.handoff.to;
      if (!target || target.tool !== identity.tool || target.session !== identity.session) {
        throw new Error(`task '${task}' is handed off to ${target ? `${target.tool}/${target.session}` : 'an invalid recipient'}`);
      }
      if (repo.top !== existing.worktree.path) throw new Error('handoff must resume in the exact source worktree');
      const current = snapshot(repo.cwd);
      if (current.head !== existing.handoff.snapshot.head || current.digest !== existing.handoff.snapshot.digest) {
        throw new Error('handoff snapshot changed; previous handoff is invalid and must be recreated by its owner');
      }
      if (options.scopes && options.scopes.length && JSON.stringify(existing.scopes) !== JSON.stringify(scopes)) {
        throw new Error('handoff resume cannot change claimed scopes');
      }
      assertNoOverlap(records, task, existing.scopes);
      existing.status = 'active';
      existing.previous_owner = existing.owner;
      existing.owner = identity;
      existing.updated_at = now;
      existing.claim_snapshot = current;
      existing.history = appendHistory(existing, { event: 'resumed', at: now, owner: identity, snapshot: { head: current.head, digest: current.digest } });
      atomicWrite(repo, task, existing);
      return { created: false, resumed: true, record: existing, state_root: repo.stateRoot };
    }
    assertNoOverlap(records, task, scopes);
    const current = snapshot(repo.cwd);
    const record = {
      schema_version: SCHEMA_VERSION,
      task_id: task,
      status: 'active',
      owner: identity,
      scopes,
      base_sha: current.head,
      claim_snapshot: current,
      worktree: { path: repo.top, branch: current.branch },
      created_at: now,
      updated_at: now,
      history: [{ event: 'claimed', at: now, owner: identity, snapshot: { head: current.head, digest: current.digest } }],
    };
    atomicWrite(repo, task, record);
    return { created: true, resumed: false, record, state_root: repo.stateRoot };
  } finally { release(); }
}

function requireActiveOwner(repo, task, options) {
  const identity = validateIdentity(options.tool, options.session);
  const record = readRecord(repo, task);
  if (!record) throw new Error(`task '${task}' is not claimed`);
  if (record.status !== 'active') throw new Error(`task '${task}' is ${record.status}, not active`);
  if (!sameOwner(record, identity)) throw new Error(`task '${task}' is owned by ${record.owner.tool}/${record.owner.session}`);
  if (record.worktree.path !== repo.top) throw new Error(`task '${task}' belongs to another worktree`);
  return { record, identity };
}

function handoff(targetDir, task, options) {
  const repo = resolveRepository(targetDir);
  const recipient = validateIdentity(options.toTool, options.toSession);
  const release = acquireLock(repo);
  try {
    const { record, identity } = requireActiveOwner(repo, validateTask(task), options);
    if (sameOwner(record, recipient)) throw new Error('handoff recipient must differ from the current owner');
    const current = snapshot(repo.cwd);
    const now = new Date().toISOString();
    record.status = 'handed-off';
    record.updated_at = now;
    record.handoff = {
      from: identity,
      to: recipient,
      created_at: now,
      snapshot: current,
      note: validateNote(options.note),
    };
    record.history = appendHistory(record, { event: 'handed-off', at: now, from: identity, to: recipient, snapshot: { head: current.head, digest: current.digest } });
    atomicWrite(repo, task, record);
    return { record, state_root: repo.stateRoot };
  } finally { release(); }
}

function releaseClaim(targetDir, task, options) {
  const repo = resolveRepository(targetDir);
  const release = acquireLock(repo);
  try {
    const { record, identity } = requireActiveOwner(repo, validateTask(task), options);
    const current = snapshot(repo.cwd);
    const now = new Date().toISOString();
    record.status = 'released';
    record.updated_at = now;
    record.release = { by: identity, at: now, snapshot: current, note: validateNote(options.note) };
    record.history = appendHistory(record, { event: 'released', at: now, owner: identity, snapshot: { head: current.head, digest: current.digest } });
    atomicWrite(repo, task, record);
    return { record, state_root: repo.stateRoot };
  } finally { release(); }
}

function inspect(targetDir) {
  const repo = resolveRepository(targetDir);
  const records = readAll(repo);
  const problems = [];
  for (let index = 0; index < records.length; index += 1) {
    const left = records[index];
    if (!['active', 'handed-off'].includes(left.status)) continue;
    let recordedRepo = null;
    if (!fs.existsSync(left.worktree.path)) {
      problems.push({ severity: 'FAIL', task: left.task_id, message: 'recorded worktree is missing' });
    } else {
      try {
        recordedRepo = resolveRepository(left.worktree.path);
        if (recordedRepo.top !== left.worktree.path || recordedRepo.common !== repo.common) {
          throw new Error('recorded worktree is outside this clone/worktree family');
        }
      } catch (error) {
        problems.push({ severity: 'FAIL', task: left.task_id, message: error.message });
      }
    }
    if (left.status === 'handed-off' && recordedRepo) {
      try {
        const current = snapshot(recordedRepo.top);
        if (current.head !== left.handoff.snapshot.head || current.digest !== left.handoff.snapshot.digest) {
          problems.push({ severity: 'FAIL', task: left.task_id, message: 'handoff snapshot drifted before resume' });
        }
      } catch (error) { problems.push({ severity: 'FAIL', task: left.task_id, message: error.message }); }
    }
    for (let otherIndex = index + 1; otherIndex < records.length; otherIndex += 1) {
      const right = records[otherIndex];
      if (!['active', 'handed-off'].includes(right.status)) continue;
      if (left.scopes.some((a) => right.scopes.some((b) => scopesOverlap(a, b)))) {
        problems.push({ severity: 'FAIL', task: left.task_id, message: `scope overlaps task '${right.task_id}'` });
      }
    }
  }
  return {
    schema_version: SCHEMA_VERSION,
    repository: repo.top,
    state_root: repo.stateRoot,
    records,
    problems,
    summary: {
      total: records.length,
      active: records.filter((record) => record.status === 'active').length,
      handed_off: records.filter((record) => record.status === 'handed-off').length,
      released: records.filter((record) => record.status === 'released').length,
      failures: problems.filter((problem) => problem.severity === 'FAIL').length,
    },
  };
}

function render(report) {
  const lines = [`Work claims for ${report.repository}`];
  if (!report.records.length) lines.push('  (none)');
  for (const record of report.records) {
    lines.push(`  ${record.task_id}: ${record.status} · ${record.owner.tool}/${record.owner.session} · ${record.scopes.join(', ')} · ${record.worktree.branch}@${record.claim_snapshot.head.slice(0, 12)}`);
  }
  for (const problem of report.problems) lines.push(`  ${problem.severity} ${problem.task}: ${problem.message}`);
  lines.push(`Summary: ${report.summary.active} active, ${report.summary.handed_off} handed-off, ${report.summary.released} released, ${report.summary.failures} failure(s)`);
  return lines.join('\n');
}

module.exports = {
  STATE_DIR_NAME,
  claim,
  handoff,
  inspect,
  normalizeScope,
  releaseClaim,
  render,
  resolveRepository,
  scopesOverlap,
  snapshot,
};
