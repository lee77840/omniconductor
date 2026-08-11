#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const installerPlatform = require('../bin/installer-platform.js');

if (process.platform !== 'win32') {
  console.log('SKIP: Windows Git Bash installer regression runs on windows-latest');
  process.exit(0);
}

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const bash = installerPlatform.resolveBash();
assert(bash, 'Git Bash is required on the Windows release runner');

function runCli(args, timeout = 120_000) {
  return spawnSync(process.execPath, [CLI, ...args], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout,
    windowsHide: true,
    env: { ...process.env, CONDUCTOR_BASH_PATH: bash.command },
  });
}

function toBashPath(value) { return value.replace(/\\/g, '/'); }

function inventory(root) {
  if (!fs.existsSync(root)) return [];
  const entries = [];
  const walk = (dir) => {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const absolute = path.join(dir, item.name);
      if (item.isDirectory()) walk(absolute);
      else if (item.isFile()) {
        const digest = crypto.createHash('sha256').update(fs.readFileSync(absolute)).digest('hex');
        entries.push(`${path.relative(root, absolute)}:${digest}`);
      } else entries.push(`${path.relative(root, absolute)}:${item.isSymbolicLink() ? 'symlink' : 'other'}`);
    }
  };
  walk(root);
  return entries.sort();
}

const base = fs.mkdtempSync(path.join(os.tmpdir(), 'CONDUCTOR Windows (한글) '));
try {
  for (const tool of TOOLS) {
    const target = path.join(base, `CLI ${tool} project`);
    fs.mkdirSync(target);
    const result = runCli(['init', `--target=${tool}`, target, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, `${tool} CLI install failed or recursed:\n${result.stdout}\n${result.stderr}`);
    assert(fs.existsSync(path.join(target, '.conductor', 'manifests', `${tool}.json`)), `${tool} manifest missing`);
    assert.strictEqual(fs.existsSync(path.join(target, '.conductor', 'model-routing.lock')), false, `${tool} left routing lock`);
    const doctor = runCli(['doctor', target, '--json']);
    assert(doctor.status === 0 || doctor.status === 1, `${tool} doctor failed:\n${doctor.stdout}\n${doctor.stderr}`);
    const report = JSON.parse(doctor.stdout);
    assert.strictEqual(report.summary.FAIL, 0, `${tool} doctor reported failures`);
    assert(report.checks.some((entry) => entry.id === 'D16' && entry.status === 'OK'), `${tool} D16 missing`);
  }

  for (const tool of TOOLS) {
    const target = path.join(base, `Direct ${tool} project`);
    fs.mkdirSync(target);
    const transform = path.join(ROOT, 'adapters', tool, 'transform.sh');
    const result = spawnSync(bash.command, [toBashPath(transform), toBashPath(target), '--no-prompt', '--accept-model-defaults'], {
      cwd: ROOT,
      encoding: 'utf8',
      timeout: 120_000,
      windowsHide: true,
      env: { ...process.env, CONDUCTOR_BASH_PATH: bash.command, CONDUCTOR_CLI_DISPATCH: '' },
    });
    assert.strictEqual(result.status, 0, `${tool} direct install failed or recursed:\n${result.stdout}\n${result.stderr}`);
    assert(fs.existsSync(path.join(target, '.conductor', 'manifests', `${tool}.json`)), `${tool} direct manifest missing`);
  }

  const dryRun = path.join(base, 'Dry Run All');
  fs.mkdirSync(dryRun);
  fs.writeFileSync(path.join(dryRun, 'user.txt'), 'preserve me\n');
  const before = inventory(dryRun);
  let result = runCli(['init', '--target=all', dryRun, '--dry-run', '--no-prompt', '--accept-model-defaults']);
  assert.strictEqual(result.status, 0, `all-target dry-run failed:\n${result.stdout}\n${result.stderr}`);
  assert.deepStrictEqual(inventory(dryRun), before, 'dry-run changed the Windows target');

  const lifecycle = path.join(base, 'All Lifecycle');
  fs.mkdirSync(lifecycle);
  fs.writeFileSync(path.join(lifecycle, 'user.txt'), 'preserve me\n');
  result = runCli(['init', '--target=all', lifecycle, '--no-prompt', '--accept-model-defaults'], 240_000);
  assert.strictEqual(result.status, 0, `all-target install failed:\n${result.stdout}\n${result.stderr}`);
  for (const tool of TOOLS) assert(fs.existsSync(path.join(lifecycle, '.conductor', 'manifests', `${tool}.json`)));
  result = runCli(['init', '--target=all', lifecycle, '--uninstall'], 240_000);
  assert.strictEqual(result.status, 0, `all-target uninstall failed:\n${result.stdout}\n${result.stderr}`);
  assert.strictEqual(fs.readFileSync(path.join(lifecycle, 'user.txt'), 'utf8'), 'preserve me\n');
  const manifests = path.join(lifecycle, '.conductor', 'manifests');
  assert(!fs.existsSync(manifests) || fs.readdirSync(manifests).length === 0);

  console.log('PASS: six CLI and six direct Git Bash adapter installs terminate on Windows');
  console.log('PASS: Windows doctor D16 reports the supported Git Bash execution path');
  console.log('PASS: all-target dry-run is byte-identical and install/uninstall preserves user data');
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}
