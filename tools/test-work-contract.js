#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const work = require('../bin/work-contract.js');

const ROOT = path.resolve(__dirname, '..');
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-work-contract-'));
let passed = 0;

function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [work-contract] ${name}\n`);
}

function git(repo, args) {
  const result = spawnSync('git', args, { cwd: repo, encoding: 'utf8' });
  assert.strictEqual(result.status, 0, `${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}

function createRepo(name) {
  const repo = path.join(sandbox, name);
  fs.mkdirSync(repo, { recursive: true });
  git(repo, ['init', '-q']);
  fs.writeFileSync(path.join(repo, 'tracked.txt'), 'base\n');
  fs.mkdirSync(path.join(repo, 'src'));
  fs.writeFileSync(path.join(repo, 'src', 'app.js'), 'module.exports = 1;\n');
  git(repo, ['add', '.']);
  git(repo, ['-c', 'user.name=CONDUCTOR Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'base']);
  return repo;
}

function owner(tool, session) { return { tool, session }; }

try {
  test('a repository without commits fails cleanly and explains the required recovery', () => {
    const repo = path.join(sandbox, 'no-commits');
    fs.mkdirSync(repo, { recursive: true });
    git(repo, ['init', '-q']);
    let result = spawnSync(process.execPath, [
      'bin/omniconductor.js', 'work', 'claim', 'first-task', repo,
      '--tool=codex', '--session=empty-repo', '--scope=.', '--json',
    ], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 2, result.stdout);
    assert.match(result.stderr, /repository has no commits yet; make an initial commit before claiming work/);
    assert.strictEqual(fs.existsSync(path.join(repo, '.git', 'conductor')), false, 'failed claim left work-contract state');

    fs.writeFileSync(path.join(repo, 'README.md'), 'initial\n');
    git(repo, ['add', 'README.md']);
    git(repo, ['-c', 'user.name=CONDUCTOR Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'initial']);
    result = spawnSync(process.execPath, [
      'bin/omniconductor.js', 'work', 'claim', 'first-task', repo,
      '--tool=codex', '--session=empty-repo', '--scope=.', '--json',
    ], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(JSON.parse(result.stdout).record.task_id, 'first-task');
  });

  test('invalid claim input fails before creating work-contract state', () => {
    const repo = createRepo('invalid-claim-input');
    const result = spawnSync(process.execPath, [
      'bin/omniconductor.js', 'work', 'claim', 'INVALID!', repo,
      '--tool=codex', '--session=invalid-input', '--scope=.', '--json',
    ], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 2, result.stdout);
    assert.match(result.stderr, /task id must match/);
    assert.strictEqual(fs.existsSync(path.join(repo, '.git', 'conductor')), false, 'invalid claim left work-contract state');
  });

  test('claim is Git-common-dir local, idempotent, bounded, and does not dirty the worktree', () => {
    const repo = createRepo('claim');
    const first = work.claim(repo, 'task-a', { ...owner('codex', 'session-1'), scopes: ['src'] });
    assert.strictEqual(first.created, true);
    assert(first.state_root.includes(path.join('.git', 'conductor', 'work-claims-v1')));
    const second = work.claim(repo, 'task-a', { ...owner('codex', 'session-1'), scopes: ['src'] });
    assert.strictEqual(second.created, false);
    assert.strictEqual(second.resumed, false);
    assert.strictEqual(git(repo, ['status', '--short']), '');
    assert.throws(() => work.claim(repo, 'task-a', { ...owner('claude', 'session-2'), scopes: ['src'] }), /owned by/);
    assert.throws(() => work.claim(repo, 'TASK!', { ...owner('codex', 'session-1'), scopes: ['src'] }), /task id/);
    assert.throws(() => work.claim(repo, 'task-c', { ...owner('codex', 'session-1'), scopes: ['..'] }), /escapes/);
  });

  test('overlapping active and handed-off scopes fail closed while siblings coexist', () => {
    const repo = createRepo('overlap');
    work.claim(repo, 'frontend', { ...owner('cursor', 'one'), scopes: ['src/ui'] });
    assert.throws(() => work.claim(repo, 'all-src', { ...owner('claude', 'two'), scopes: ['src'] }), /overlaps/);
    const sibling = work.claim(repo, 'backend', { ...owner('claude', 'two'), scopes: ['server'] });
    assert.strictEqual(sibling.created, true);
    work.handoff(repo, 'frontend', { ...owner('cursor', 'one'), toTool: 'codex', toSession: 'three' });
    assert.throws(() => work.claim(repo, 'ui-child', { ...owner('gemini', 'four'), scopes: ['src/ui/button'] }), /overlaps/);
  });

  test('handoff resumes only for the named recipient on the exact snapshot', () => {
    const repo = createRepo('handoff');
    work.claim(repo, 'transfer', { ...owner('claude', 'source'), scopes: ['tracked.txt'] });
    fs.writeFileSync(path.join(repo, 'tracked.txt'), 'handoff-state\n');
    const handed = work.handoff(repo, 'transfer', {
      ...owner('claude', 'source'), toTool: 'codex', toSession: 'recipient', note: 'continue review',
    });
    assert.strictEqual(handed.record.status, 'handed-off');
    assert.throws(() => work.claim(repo, 'transfer', { ...owner('cursor', 'intruder'), scopes: ['tracked.txt'] }), /handed off to/);
    fs.appendFileSync(path.join(repo, 'tracked.txt'), 'drift\n');
    assert.throws(() => work.claim(repo, 'transfer', { ...owner('codex', 'recipient'), scopes: ['tracked.txt'] }), /snapshot changed/);
    fs.writeFileSync(path.join(repo, 'tracked.txt'), 'handoff-state\n');
    const resumed = work.claim(repo, 'transfer', { ...owner('codex', 'recipient'), scopes: ['tracked.txt'] });
    assert.strictEqual(resumed.resumed, true);
    assert.strictEqual(resumed.record.owner.session, 'recipient');
    assert.strictEqual(resumed.record.previous_owner.session, 'source');
  });

  test('release requires the exact owner and retains an immutable task-id tombstone', () => {
    const repo = createRepo('release');
    work.claim(repo, 'done-task', { ...owner('gemini', 'owner'), scopes: ['src'] });
    assert.throws(() => work.releaseClaim(repo, 'done-task', { ...owner('gemini', 'other') }), /owned by/);
    const result = work.releaseClaim(repo, 'done-task', { ...owner('gemini', 'owner'), note: 'complete' });
    assert.strictEqual(result.record.status, 'released');
    assert(result.record.release.snapshot.digest);
    assert.throws(() => work.claim(repo, 'done-task', { ...owner('gemini', 'owner'), scopes: ['src'] }), /cannot be reused/);
    const report = work.inspect(repo);
    assert.strictEqual(report.summary.released, 1);
  });

  test('all worktrees in one clone observe the same claim ledger', () => {
    const repo = createRepo('worktrees');
    const sibling = path.join(sandbox, 'worktrees-sibling');
    git(repo, ['worktree', 'add', '-q', '-b', 'parallel-test', sibling]);
    try {
      work.claim(repo, 'shared', { ...owner('copilot', 'main-session'), scopes: ['src'] });
      const report = work.inspect(sibling);
      assert(report.records.some((record) => record.task_id === 'shared'));
      assert.throws(() => work.claim(sibling, 'collision', { ...owner('codex', 'sibling-session'), scopes: ['src/app.js'] }), /overlaps/);
    } finally {
      git(repo, ['worktree', 'remove', '--force', sibling]);
    }
  });

  test('snapshot digest covers tracked and untracked content without storing tracked diff content', () => {
    const repo = createRepo('snapshot');
    const clean = work.snapshot(repo);
    fs.writeFileSync(path.join(repo, 'untracked.txt'), 'secret-like-value\n');
    const untracked = work.snapshot(repo);
    assert.notStrictEqual(clean.digest, untracked.digest);
    assert.strictEqual(untracked.untracked[0].path, 'untracked.txt');
    assert(!JSON.stringify(untracked).includes('secret-like-value'));
    fs.writeFileSync(path.join(repo, 'tracked.txt'), 'changed\n');
    assert.notStrictEqual(untracked.digest, work.snapshot(repo).digest);
  });

  test('stale lock is reclaimed and symlinked state is refused', () => {
    const repo = createRepo('stale-lock');
    const resolved = work.resolveRepository(repo);
    fs.mkdirSync(resolved.stateRoot, { recursive: true });
    const lock = path.join(resolved.stateRoot, '.lock');
    fs.mkdirSync(lock);
    fs.writeFileSync(path.join(lock, 'owner.json'), `${JSON.stringify({ pid: 99999999, created_at: '2000-01-01T00:00:00.000Z' })}\n`);
    assert.strictEqual(work.claim(repo, 'recovered', { ...owner('human', 'maintainer'), scopes: ['src'] }).created, true);

    const unsafe = createRepo('unsafe-state');
    const unsafeResolved = work.resolveRepository(unsafe);
    const outside = path.join(sandbox, 'outside-state');
    fs.mkdirSync(outside);
    fs.symlinkSync(outside, path.join(unsafeResolved.common, 'conductor'));
    assert.throws(() => work.claim(unsafe, 'blocked', { ...owner('human', 'maintainer'), scopes: ['src'] }), /real directory/);
  });

  test('a newly created ownerless lock is not reclaimed as stale', () => {
    const repo = createRepo('fresh-lock');
    const resolved = work.resolveRepository(repo);
    fs.mkdirSync(resolved.stateRoot, { recursive: true });
    fs.mkdirSync(path.join(resolved.stateRoot, '.lock'));
    assert.throws(
      () => work.claim(repo, 'must-wait', { ...owner('codex', 'fresh-lock'), scopes: ['src'] }),
      /another work-contract mutation is active/,
    );
  });

  test('notes are bounded and untracked hardlinks are rejected', () => {
    const repo = createRepo('bounded-inputs');
    work.claim(repo, 'bounded', { ...owner('codex', 'bounded'), scopes: ['src'] });
    assert.throws(() => work.handoff(repo, 'bounded', {
      ...owner('codex', 'bounded'), toTool: 'claude', toSession: 'next', note: 'x'.repeat(501),
    }), /note must be/);
    const outside = path.join(sandbox, 'hardlink-source');
    fs.writeFileSync(outside, 'content\n');
    fs.linkSync(outside, path.join(repo, 'hardlink-untracked'));
    assert.throws(() => work.snapshot(repo), /single-link regular file/);
  });

  test('tampered record snapshots and cross-clone worktree paths fail closed', () => {
    const repo = createRepo('tampered-record');
    const other = createRepo('other-clone');
    const claimed = work.claim(repo, 'tampered', { ...owner('codex', 'owner'), scopes: ['src'] });
    const file = path.join(claimed.state_root, 'tampered.json');
    let record = JSON.parse(fs.readFileSync(file, 'utf8'));
    record.claim_snapshot.digest = 'bad';
    fs.writeFileSync(file, JSON.stringify(record));
    assert.throws(() => work.inspect(repo), /invalid claim snapshot/);

    fs.unlinkSync(file);
    work.claim(repo, 'cross-clone', { ...owner('codex', 'owner'), scopes: ['src'] });
    const crossFile = path.join(claimed.state_root, 'cross-clone.json');
    record = JSON.parse(fs.readFileSync(crossFile, 'utf8'));
    record.worktree.path = other;
    fs.writeFileSync(crossFile, JSON.stringify(record));
    const report = work.inspect(repo);
    assert(report.problems.some((problem) => /outside this clone/.test(problem.message)));
  });

  test('first-claim state creation tolerates a concurrent directory winner', () => {
    const repo = createRepo('first-claim-race');
    const resolved = work.resolveRepository(repo);
    fs.mkdirSync(path.dirname(resolved.stateRoot), { recursive: true });
    const originalMkdir = fs.mkdirSync;
    let injected = false;
    fs.mkdirSync = function mkdirWithWinner(directory, options) {
      if (!injected && directory === resolved.stateRoot) {
        injected = true;
        originalMkdir.call(fs, directory, options);
        const error = new Error('simulated concurrent creator');
        error.code = 'EEXIST';
        throw error;
      }
      return originalMkdir.call(fs, directory, options);
    };
    try {
      const result = work.claim(repo, 'race-safe', { ...owner('codex', 'race'), scopes: ['src'] });
      assert.strictEqual(result.created, true);
      assert.strictEqual(injected, true);
    } finally { fs.mkdirSync = originalMkdir; }
  });

  test('CLI status is machine-readable and a drifted handoff exits nonzero', () => {
    const repo = createRepo('cli');
    let result = spawnSync(process.execPath, ['bin/omniconductor.js', 'work', 'claim', 'cli-task', repo, '--tool=codex', '--session=cli', '--scope=src', '--json'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(JSON.parse(result.stdout).record.task_id, 'cli-task');
    result = spawnSync(process.execPath, ['bin/omniconductor.js', 'work', 'handoff', 'cli-task', repo, '--tool=codex', '--session=cli', '--to-tool=claude', '--to-session=next'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stderr);
    fs.writeFileSync(path.join(repo, 'tracked.txt'), 'drifted\n');
    result = spawnSync(process.execPath, ['bin/omniconductor.js', 'work', 'status', repo, '--json'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 1);
    assert.strictEqual(JSON.parse(result.stdout).summary.failures, 1);
  });

  process.stdout.write(`OK — work-contract tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
