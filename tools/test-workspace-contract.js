#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const workspaceContract = require('../bin/workspace-contract.js');

const ROOT = path.resolve(__dirname, '..');
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-workspace-'));
let passed = 0;

function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [workspace-contract] ${name}\n`);
}

function git(repo, args) {
  const result = spawnSync('git', args, { cwd: repo, encoding: 'utf8' });
  assert.strictEqual(result.status, 0, `${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}

function repo(root, name) {
  const target = path.join(root, name);
  fs.mkdirSync(target, { recursive: true });
  git(target, ['init', '-q']);
  fs.writeFileSync(path.join(target, 'README.md'), `${name}\n`);
  git(target, ['add', '.']);
  git(target, ['-c', 'user.name=CONDUCTOR Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'base']);
  return target;
}

function makeWorkspace(name, mutate) {
  const root = path.join(sandbox, name);
  fs.mkdirSync(root, { recursive: true });
  const shared = repo(root, 'shared');
  const app = repo(root, 'app');
  const manifest = {
    schema_version: 1,
    workspace_id: name,
    repositories: [
      { id: 'shared', path: 'shared', depends_on: [], write_scopes: ['src'], target_branch: git(shared, ['branch', '--show-current']), required_adapters: [] },
      { id: 'app', path: 'app', depends_on: ['shared'], write_scopes: ['.'], target_branch: git(app, ['branch', '--show-current']), required_adapters: [] },
    ],
  };
  if (mutate) mutate(manifest, { root, shared, app });
  fs.mkdirSync(path.join(root, '.conductor'));
  fs.writeFileSync(path.join(root, '.conductor', 'workspace.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return { root, shared, app, manifest };
}

function policyManifest(repoRoot, tool, version) {
  const dir = path.join(repoRoot, '.conductor', 'manifests');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${tool}.json`), `${JSON.stringify({
    schema_version: 2,
    manifest_scope: 'adapter',
    adapter: tool,
    version,
    emitted_files: [],
  }, null, 2)}\n`);
}

try {
  test('doctor is deterministic, dependency ordered, snapshot exact, and read-only', () => {
    const item = makeWorkspace('valid');
    const manifestStat = fs.statSync(path.join(item.root, '.conductor', 'workspace.json'));
    const before = [git(item.shared, ['status', '--porcelain']), git(item.app, ['status', '--porcelain'])];
    const first = workspaceContract.inspect(item.root);
    const second = workspaceContract.inspect(item.root);
    assert.strictEqual(first.change_set_digest, second.change_set_digest);
    assert.deepStrictEqual(first.dependency_order, ['shared', 'app']);
    assert.strictEqual(first.summary.FAIL, 0);
    assert.deepStrictEqual(before, [git(item.shared, ['status', '--porcelain']), git(item.app, ['status', '--porcelain'])]);
    assert.strictEqual(fs.statSync(path.join(item.root, '.conductor', 'workspace.json')).mtimeMs, manifestStat.mtimeMs);
    fs.writeFileSync(path.join(item.app, 'untracked.txt'), 'delta\n');
    const changed = workspaceContract.inspect(item.root);
    assert.notStrictEqual(first.change_set_digest, changed.change_set_digest);
    assert(changed.repositories.find((entry) => entry.id === 'app').snapshot.dirty);
  });

  test('change-set digest binds dependency, scope, branch, and required-adapter policy', () => {
    const item = makeWorkspace('manifest-bound-digest');
    const file = path.join(item.root, '.conductor', 'workspace.json');
    const baseline = workspaceContract.inspect(item.root).change_set_digest;
    const variants = [
      (manifest) => { manifest.repositories[1].write_scopes = ['src']; },
      (manifest) => { manifest.repositories[1].target_branch = 'review-target'; },
      (manifest) => { manifest.repositories[1].required_adapters = ['codex']; },
      (manifest) => { manifest.repositories[1].depends_on = []; },
    ];
    for (const mutate of variants) {
      const manifest = JSON.parse(JSON.stringify(item.manifest));
      mutate(manifest);
      fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
      assert.notStrictEqual(workspaceContract.inspect(item.root).change_set_digest, baseline);
    }
  });

  test('unknown fields, path escape, duplicate roots, and dependency cycles fail closed', () => {
    const unknown = makeWorkspace('unknown-field', (manifest) => { manifest.repositories[0].authority = 'invented'; });
    assert.throws(() => workspaceContract.inspect(unknown.root), /unknown field/);
    const escape = makeWorkspace('escape', (manifest) => { manifest.repositories[0].path = '../outside'; });
    assert.throws(() => workspaceContract.inspect(escape.root), /escapes/);
    const duplicate = makeWorkspace('duplicate', (manifest) => { manifest.repositories[1].path = 'shared'; });
    assert.throws(() => workspaceContract.inspect(duplicate.root), /duplicate canonical/);
    const cycle = makeWorkspace('cycle', (manifest) => { manifest.repositories[0].depends_on = ['app']; });
    assert.throws(() => workspaceContract.inspect(cycle.root), /dependency cycle/);
  });

  test('symlinked repositories and hard-linked manifests are rejected before traversal', () => {
    const linkedRoot = path.join(sandbox, 'linked-repo');
    fs.mkdirSync(linkedRoot);
    const real = repo(linkedRoot, 'real');
    fs.symlinkSync(real, path.join(linkedRoot, 'alias'));
    fs.mkdirSync(path.join(linkedRoot, '.conductor'));
    fs.writeFileSync(path.join(linkedRoot, '.conductor', 'workspace.json'), JSON.stringify({
      schema_version: 1, workspace_id: 'linked-repo', repositories: [{ id: 'alias', path: 'alias' }],
    }));
    assert.throws(() => workspaceContract.inspect(linkedRoot), /symbolic-link component|real directory/);

    const hardRoot = path.join(sandbox, 'hard-manifest');
    fs.mkdirSync(path.join(hardRoot, '.conductor'), { recursive: true });
    const original = path.join(hardRoot, 'manifest-source.json');
    fs.writeFileSync(original, JSON.stringify({ schema_version: 1, workspace_id: 'hard-manifest', repositories: [] }));
    fs.linkSync(original, path.join(hardRoot, '.conductor', 'workspace.json'));
    assert.throws(() => workspaceContract.inspect(hardRoot), /single-link regular file/);

    const parentLinkRoot = path.join(sandbox, 'linked-manifest-parent');
    const externalState = path.join(sandbox, 'external-workspace-state');
    fs.mkdirSync(parentLinkRoot);
    fs.mkdirSync(externalState);
    fs.writeFileSync(path.join(externalState, 'workspace.json'), JSON.stringify({
      schema_version: 1, workspace_id: 'linked-manifest-parent', repositories: [],
    }));
    fs.symlinkSync(externalState, path.join(parentLinkRoot, '.conductor'));
    assert.throws(() => workspaceContract.inspect(parentLinkRoot), /symbolic-link component/);
  });

  test('required adapters fail when absent and exact adapter manifests satisfy policy', () => {
    const item = makeWorkspace('required', (manifest) => { manifest.repositories[1].required_adapters = ['codex']; });
    let report = workspaceContract.inspect(item.root);
    assert(report.checks.some((check) => check.id === 'policy:app' && check.status === 'FAIL'));
    policyManifest(item.app, 'codex', '1.3.3');
    report = workspaceContract.inspect(item.root);
    assert(!report.checks.some((check) => check.id === 'policy:app' && check.status === 'FAIL'));
    assert.deepStrictEqual(report.repositories.find((entry) => entry.id === 'app').policy.adapters, ['codex']);
  });

  test('policy-version drift and target-branch drift are visible warnings, not invented enforcement', () => {
    const item = makeWorkspace('drift');
    policyManifest(item.shared, 'claude', '1.3.2');
    policyManifest(item.app, 'codex', '1.3.3');
    const file = path.join(item.root, '.conductor', 'workspace.json');
    const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
    manifest.repositories[1].target_branch = 'main-that-is-not-current';
    fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
    const report = workspaceContract.inspect(item.root);
    assert(report.checks.some((check) => check.id === 'workspace:policy-drift' && check.status === 'WARN'));
    assert(report.checks.some((check) => check.id === 'branch:app' && check.status === 'WARN'));
    assert.strictEqual(report.summary.FAIL, 0);
  });

  test('declared paths must be exact Git roots, not subdirectories of a repository', () => {
    const root = path.join(sandbox, 'nested');
    const parent = repo(root, 'parent');
    fs.mkdirSync(path.join(parent, 'packages', 'app'), { recursive: true });
    fs.mkdirSync(path.join(root, '.conductor'));
    fs.writeFileSync(path.join(root, '.conductor', 'workspace.json'), JSON.stringify({
      schema_version: 1,
      workspace_id: 'nested',
      repositories: [{ id: 'app', path: 'parent/packages/app' }],
    }));
    const report = workspaceContract.inspect(root);
    assert.strictEqual(report.summary.FAIL, 1);
    assert.match(report.repositories[0].error, /not an exact repository root/);
  });

  test('CLI returns 0 for clean state, 1 for warnings, and 2 for failures', () => {
    const clean = makeWorkspace('cli-clean');
    let result = spawnSync(process.execPath, ['bin/omniconductor.js', 'workspace', 'doctor', clean.root, '--json'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(JSON.parse(result.stdout).workspace_id, 'cli-clean');
    const warnFile = path.join(clean.root, '.conductor', 'workspace.json');
    const warnManifest = JSON.parse(fs.readFileSync(warnFile, 'utf8'));
    warnManifest.repositories[0].target_branch = 'different';
    fs.writeFileSync(warnFile, JSON.stringify(warnManifest));
    result = spawnSync(process.execPath, ['bin/omniconductor.js', 'workspace', 'doctor', clean.root, '--json'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 1);

    const fail = makeWorkspace('cli-fail', (manifest) => { manifest.repositories[0].required_adapters = ['claude']; });
    result = spawnSync(process.execPath, ['bin/omniconductor.js', 'workspace', 'doctor', fail.root, '--json'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 2);
    assert.strictEqual(JSON.parse(result.stdout).summary.FAIL, 1);
  });

  process.stdout.write(`OK — workspace-contract tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
