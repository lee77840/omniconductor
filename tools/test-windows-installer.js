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
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
const bash = installerPlatform.resolveBash();
assert(bash, 'Git Bash is required on the Windows release runner');
const SINGLE_TIMEOUT_MS = 180_000;
const ALL_TARGET_TIMEOUT_MS = 600_000;

function runCli(args, timeout = SINGLE_TIMEOUT_MS) {
  const started = Date.now();
  const result = spawnSync(process.execPath, [CLI, ...args], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout,
    windowsHide: true,
    env: { ...process.env, CONDUCTOR_BASH_PATH: bash.command },
  });
  result.elapsedMs = Date.now() - started;
  result.timeoutMs = timeout;
  return result;
}

function assertSpawnSuccess(result, label) {
  if (result.status === 0) return;
  const error = result.error
    ? `${result.error.code || result.error.name || 'spawn-error'}: ${result.error.message}`
    : 'none';
  assert.fail(
    `${label}\nstatus=${result.status} signal=${result.signal || 'none'} ` +
    `elapsedMs=${result.elapsedMs} timeoutMs=${result.timeoutMs} error=${error}\n` +
    `stdout:\n${result.stdout || ''}\nstderr:\n${result.stderr || ''}`,
  );
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
        entries.push(`${path.relative(root, absolute).replace(/\\/g, '/')}:${digest}`);
      } else entries.push(`${path.relative(root, absolute).replace(/\\/g, '/')}:${item.isSymbolicLink() ? 'symlink' : 'other'}`);
    }
  };
  walk(root);
  return entries.sort();
}

const base = fs.mkdtempSync(path.join(os.tmpdir(), 'CONDUCTOR Windows (한글) '));
try {
  let copilotTarget = null;
  for (const tool of TOOLS) {
    const target = path.join(base, `CLI ${tool} project`);
    fs.mkdirSync(target);
    const result = runCli(['init', `--target=${tool}`, target, '--no-prompt', '--accept-model-defaults']);
    assertSpawnSuccess(result, `${tool} CLI install failed or recursed`);
    assert(fs.existsSync(path.join(target, '.conductor', 'manifests', `${tool}.json`)), `${tool} manifest missing`);
    assert.strictEqual(fs.existsSync(path.join(target, '.conductor', 'model-routing.lock')), false, `${tool} left routing lock`);
    const doctor = runCli(['doctor', target, '--json']);
    assert(doctor.status === 0 || doctor.status === 1, `${tool} doctor failed:\n${doctor.stdout}\n${doctor.stderr}`);
    const report = JSON.parse(doctor.stdout);
    assert.strictEqual(report.summary.FAIL, 0, `${tool} doctor reported failures`);
    assert(report.checks.some((entry) => entry.id === 'D16' && entry.status === 'OK'), `${tool} D16 missing`);
    if (tool === 'copilot') copilotTarget = target;
    if (tool === 'opencode') {
      const plugin = path.join(target, '.opencode', 'plugins', 'conductor-guards.js');
      assert(fs.existsSync(plugin), 'OpenCode native guard plugin missing');
      const syntax = spawnSync(process.execPath, ['--check', plugin], { encoding: 'utf8', windowsHide: true });
      assert.strictEqual(syntax.status, 0, syntax.stderr || syntax.stdout);
    }
  }

  // A zero exit is vacuous for fail-open hooks. Force the positive branch:
  // three staged source files without CURRENT_WORK must emit a parseable ask
  // decision under native Windows Git Bash, including CRLF on stdin.
  assert(copilotTarget);
  assert.strictEqual(spawnSync('git', ['init', '-q'], { cwd: copilotTarget, windowsHide: true }).status, 0);
  for (const name of ['one.ts', 'two.ts', 'three.ts']) fs.writeFileSync(path.join(copilotTarget, name), 'export {};\n');
  assert.strictEqual(spawnSync('git', ['add', 'one.ts', 'two.ts', 'three.ts'], { cwd: copilotTarget, windowsHide: true }).status, 0);
  const guard = path.join(copilotTarget, '.github', 'hooks', 'conductor', 'pretool-commit-current-work-check.sh');
  const hook = spawnSync(bash.command, [toBashPath(guard)], {
    cwd: copilotTarget,
    input: '{"toolName":"bash","toolArgs":{"command":"git commit -m fixture"}}\r\n',
    encoding: 'utf8',
    windowsHide: true,
    env: { ...process.env, CONDUCTOR_BASH_PATH: bash.command, CONDUCTOR_HOOK_DIALECT: 'copilot' },
  });
  assert.strictEqual(hook.status, 0, hook.stderr || hook.stdout);
  assert(hook.stdout.trim(), `current-work hook silently allowed the positive fixture: ${hook.stderr}`);
  const decision = JSON.parse(hook.stdout);
  assert.strictEqual(decision.permissionDecision, 'ask');
  assert.match(decision.permissionDecisionReason, /CURRENT_WORK/);

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
    assertSpawnSuccess(result, `${tool} direct install failed or recursed`);
    assert(fs.existsSync(path.join(target, '.conductor', 'manifests', `${tool}.json`)), `${tool} direct manifest missing`);
  }

  const dryRun = path.join(base, 'Dry Run All');
  fs.mkdirSync(dryRun);
  fs.writeFileSync(path.join(dryRun, 'user.txt'), 'preserve me\n');
  const before = inventory(dryRun);
  let result = runCli(['init', '--target=all', dryRun, '--dry-run', '--no-prompt', '--accept-model-defaults']);
  assertSpawnSuccess(result, 'all-target dry-run failed');
  assert.deepStrictEqual(inventory(dryRun), before, 'dry-run changed the Windows target');

  const lifecycle = path.join(base, 'All Lifecycle');
  fs.mkdirSync(lifecycle);
  fs.writeFileSync(path.join(lifecycle, 'user.txt'), 'preserve me\n');
  result = runCli(['init', '--target=all', lifecycle, '--no-prompt', '--accept-model-defaults'], ALL_TARGET_TIMEOUT_MS);
  assertSpawnSuccess(result, 'all-target install failed');
  for (const tool of TOOLS) assert(fs.existsSync(path.join(lifecycle, '.conductor', 'manifests', `${tool}.json`)));
  result = runCli(['init', '--target=all', lifecycle, '--uninstall'], ALL_TARGET_TIMEOUT_MS);
  assertSpawnSuccess(result, 'all-target uninstall failed');
  assert.strictEqual(fs.readFileSync(path.join(lifecycle, 'user.txt'), 'utf8'), 'preserve me\n');
  const manifests = path.join(lifecycle, '.conductor', 'manifests');
  assert(!fs.existsSync(manifests) || fs.readdirSync(manifests).length === 0);

  console.log('PASS: seven CLI and seven direct Git Bash adapter installs terminate on Windows');
  console.log('PASS: Windows doctor D16 reports the supported Git Bash execution path');
  console.log('PASS: Windows CRLF hook payload reaches a non-vacuous current-work ask decision');
  console.log('PASS: all-target dry-run is byte-identical and install/uninstall preserves user data');
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}
