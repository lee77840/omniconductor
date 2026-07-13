#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
let failures = 0;

function temp(name) { return fs.mkdtempSync(path.join(os.tmpdir(), `conductor-path-${name}-`)); }
function run(args) { return spawnSync(process.execPath, [CLI, ...args], { cwd: ROOT, encoding: 'utf8' }); }
function sha(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function check(name, fn) {
  try { fn(); process.stdout.write(`OK   [path-safety] ${name}\n`); }
  catch (error) { failures++; process.stderr.write(`FAIL [path-safety] ${name}: ${error.message}\n`); }
}
function assertRefused(result) {
  assert.notStrictEqual(result.status, 0, `unexpected success:\n${result.stdout}\n${result.stderr}`);
  assert.match(result.stderr, /unsafe|path safety|symbolic link|hard-linked|manifest/i);
}

check('.conductor parent symlink is refused before model config or adapter writes', () => {
  const parent = temp('config-symlink');
  const target = path.join(parent, 'project');
  const outside = path.join(parent, 'outside');
  fs.mkdirSync(target); fs.mkdirSync(outside);
  const sentinel = path.join(outside, 'sentinel');
  fs.writeFileSync(sentinel, 'unchanged');
  fs.symlinkSync(outside, path.join(target, '.conductor'));
  const result = run(['init', '--target=claude', target, '--no-prompt', '--accept-model-defaults']);
  assertRefused(result);
  assert.strictEqual(fs.readFileSync(sentinel, 'utf8'), 'unchanged');
  assert.ok(!fs.existsSync(path.join(target, 'CLAUDE.md')));
  assert.ok(!fs.existsSync(path.join(outside, 'model-routing.json')));
});

check('all six adapter managed-root symlinks are refused', () => {
  const roots = { claude: '.claude', cursor: '.cursor', copilot: '.github', gemini: '.gemini', codex: '.codex', windsurf: '.windsurf' };
  for (const [tool, rel] of Object.entries(roots)) {
    const parent = temp(`${tool}-root`);
    const target = path.join(parent, 'project');
    const outside = path.join(parent, 'outside');
    fs.mkdirSync(target); fs.mkdirSync(outside);
    fs.writeFileSync(path.join(outside, 'sentinel'), tool);
    fs.symlinkSync(outside, path.join(target, rel));
    const result = run(['init', `--target=${tool}`, target, '--no-prompt', '--accept-model-defaults']);
    assertRefused(result);
    assert.deepStrictEqual(fs.readdirSync(outside), ['sentinel']);
    assert.ok(!fs.existsSync(path.join(target, '.conductor/model-routing.json')));
  }
});

check('managed leaf symlink and hardlink are both refused without touching their source', () => {
  for (const kind of ['symlink', 'hardlink']) {
    const parent = temp(`leaf-${kind}`);
    const target = path.join(parent, 'project');
    fs.mkdirSync(target);
    const outside = path.join(parent, 'outside.md');
    fs.writeFileSync(outside, `outside-${kind}`);
    if (kind === 'symlink') fs.symlinkSync(outside, path.join(target, 'CLAUDE.md'));
    else fs.linkSync(outside, path.join(target, 'CLAUDE.md'));
    const result = run(['init', '--target=claude', target, '--no-prompt', '--accept-model-defaults']);
    assertRefused(result);
    assert.strictEqual(fs.readFileSync(outside, 'utf8'), `outside-${kind}`);
    assert.ok(!fs.existsSync(path.join(target, '.conductor/model-routing.json')));
  }
});

check('uninstall refuses traversal, absolute, and foreign backup paths in a crafted manifest', () => {
  const cases = [
    { path: '../outside/victim', backup_path: '' },
    { path: '/tmp/conductor-absolute-victim', backup_path: '' },
    { path: 'user-data.txt', backup_path: '' },
    { path: 'CLAUDE.md', backup_path: '../outside/victim' },
    { path: 'CLAUDE.md', backup_path: 'unrelated.conductor-backup-1' },
  ];
  for (const [index, bad] of cases.entries()) {
    const parent = temp(`manifest-${index}`);
    const target = path.join(parent, 'project');
    const outside = path.join(parent, 'outside');
    fs.mkdirSync(path.join(target, '.conductor/manifests'), { recursive: true });
    fs.mkdirSync(outside);
    const sentinel = path.join(outside, 'victim');
    fs.writeFileSync(sentinel, 'do-not-delete');
    fs.writeFileSync(path.join(target, 'CLAUDE.md'), 'project-file');
    fs.writeFileSync(path.join(target, 'user-data.txt'), 'user-data');
    const manifest = {
      schema_version: 2, manifest_scope: 'adapter', version: 'v1.1.0', adapter: 'claude', mode: 'full',
      emitted_files: [{ path: bad.path, source: '<crafted>', had_backup: Boolean(bad.backup_path), backup_path: bad.backup_path, sha256: sha('project-file') }],
    };
    fs.writeFileSync(path.join(target, '.conductor/manifests/claude.json'), `${JSON.stringify(manifest, null, 2)}\n`);
    const result = run(['init', '--target=claude', target, '--uninstall', '--force', '--no-prompt']);
    assertRefused(result);
    assert.strictEqual(fs.readFileSync(sentinel, 'utf8'), 'do-not-delete');
    assert.strictEqual(fs.readFileSync(path.join(target, 'CLAUDE.md'), 'utf8'), 'project-file');
    assert.strictEqual(fs.readFileSync(path.join(target, 'user-data.txt'), 'utf8'), 'user-data');
    const doctor = run(['doctor', target, '--json']);
    assert.strictEqual(doctor.status, 2, doctor.stdout + doctor.stderr);
    const report = JSON.parse(doctor.stdout);
    assert.ok(report.checks.some((entry) => entry.id === 'D1' && entry.status === 'FAIL'));
  }
});

if (failures) {
  process.stderr.write(`\n${failures} path-safety test(s) failed.\n`);
  process.exit(1);
}
process.stdout.write('\nAll path-safety tests passed.\n');
