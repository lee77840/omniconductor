#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const runtime = require(path.join(ROOT, 'bin', 'runtime-contract.js'));
const base = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-runtime-contract-'));
let passed = 0;

function check(name, fn) {
  try {
    fn();
    passed++;
    process.stdout.write(`ok ${passed} - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n${error.stack}\n`);
    process.exitCode = 1;
  }
}

function runNode(args, options = {}) {
  return spawnSync(process.execPath, args, {
    cwd: ROOT,
    encoding: 'utf8',
    ...options,
  });
}

function install(tool, target) {
  fs.mkdirSync(target, { recursive: true });
  const result = runNode([
    'bin/omniconductor.js', 'init', `--target=${tool}`, target,
    '--no-prompt', '--accept-model-defaults',
  ]);
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
}

function fakeCli(name, version) {
  const dir = fs.mkdtempSync(path.join(base, `${name}-bin-`));
  const file = path.join(dir, name);
  fs.writeFileSync(file, `#!/bin/sh\nif [ "\${1:-}" = "--version" ]; then echo "${version}"; exit 0; fi\nexit 1\n`);
  fs.chmodSync(file, 0o755);
  return dir;
}

function doctor(target, binDir) {
  const result = runNode(['bin/omniconductor.js', 'doctor', target, '--json'], {
    env: { ...process.env, PATH: `${binDir}:${process.env.PATH}` },
  });
  assert.ok(result.status === 0 || result.status === 1, result.stdout + result.stderr);
  return JSON.parse(result.stdout);
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function treeDigest(root) {
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(abs);
      else if (entry.isFile()) files.push(path.relative(root, abs));
      else if (entry.isSymbolicLink()) files.push(`${path.relative(root, abs)}->${fs.readlinkSync(abs)}`);
    }
  };
  walk(root);
  const hash = crypto.createHash('sha256');
  for (const rel of files.sort()) {
    hash.update(rel);
    const abs = path.join(root, rel.split('->')[0]);
    if (fs.existsSync(abs) && fs.lstatSync(abs).isFile()) hash.update(fs.readFileSync(abs));
  }
  return hash.digest('hex');
}

check('all six metadata runtime contracts validate', () => {
  for (const tool of runtime.TOOLS) {
    assert.deepStrictEqual(runtime.validateRuntimeContract(runtime.loadMetadata(tool)), [], tool);
  }
  const result = runNode(['bin/runtime-contract.js', 'validate']);
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
});

check('schema validation rejects an incomplete contract', () => {
  const bad = {
    ...runtime.loadMetadata('claude'),
    headless_cli: null,
    runtime_contract: { schema_version: 1 },
  };
  const problems = runtime.validateRuntimeContract(bad);
  assert.ok(problems.some((problem) => problem.includes('headless_cli')));
  assert.ok(problems.some((problem) => problem.includes('product')));
  assert.ok(problems.some((problem) => problem.includes('probe')));
});

check('CLI rejects an unknown adapter without a stack trace', () => {
  const result = runNode(['bin/runtime-contract.js', 'inspect', '--tool=unknown']);
  assert.strictEqual(result.status, 2);
  assert.ok(result.stderr.includes("unknown adapter 'unknown'"), result.stderr);
  assert.ok(!result.stderr.includes('at '), result.stderr);
});

check('version parsing and comparison are numeric', () => {
  assert.strictEqual(runtime.parseVersion('claude 2.1.121').label, '2.1.121');
  assert.strictEqual(runtime.versionAtLeast('2.10.0', '2.9.9'), true);
  assert.strictEqual(runtime.versionAtLeast('2.1.120', '2.1.121'), false);
});

check('missing CLI is informational and never authenticates', () => {
  const report = runtime.inspectRuntime('copilot', {
    spawnSync: () => ({ error: Object.assign(new Error('missing'), { code: 'ENOENT' }) }),
  });
  assert.strictEqual(report.status, 'not-installed');
  assert.strictEqual(report.severity, 'OK');
});

check('version probes receive only execution-safe environment values and never echo raw output', () => {
  const secret = 'must-not-reach-the-version-command';
  const report = runtime.inspectRuntime('copilot', {
    env: {
      PATH: process.env.PATH,
      OPENAI_API_KEY: secret,
      GITHUB_TOKEN: secret,
      SERVICE_PASSWORD: secret,
      INTERNAL_SECRET_VALUE: secret,
      SAFE_RUNTIME_LABEL: 'kept',
    },
    spawnSync: (_command, _args, options) => {
      assert.strictEqual(options.env.PATH, process.env.PATH);
      assert.strictEqual(options.env.SAFE_RUNTIME_LABEL, undefined);
      assert.ok(!Object.values(options.env).includes(secret), JSON.stringify(options.env));
      return { status: 0, stdout: `unparseable ${secret}`, stderr: '' };
    },
  });
  assert.strictEqual(report.status, 'installed-unverified');
  assert.ok(!report.detail.includes(secret));
  assert.ok(report.detail.includes('(detected)'));
});

check('a capability floor is ignored when its artifact was not emitted', () => {
  const report = runtime.inspectRuntime('claude', {
    emittedPaths: [],
    spawnSync: () => ({ status: 0, stdout: '2.1.120 (Claude Code)', stderr: '' }),
  });
  assert.strictEqual(report.status, 'active');
  assert.strictEqual(report.severity, 'OK');
});

check('new hook floors are artifact-scoped for Cursor and Copilot', () => {
  const cursorWithoutReview = runtime.inspectRuntime('cursor', {
    emittedPaths: ['.cursor/hooks.json'],
    spawnSync: () => ({ status: 0, stdout: 'cursor-agent 2.3.9', stderr: '' }),
  });
  assert.strictEqual(cursorWithoutReview.status, 'installed-unverified');

  const cursorWithReview = runtime.inspectRuntime('cursor', {
    emittedPaths: ['.cursor/hooks.json', '.cursor/hooks/stop-r6-review-check.sh'],
    spawnSync: () => ({ status: 0, stdout: 'cursor-agent 2.3.9', stderr: '' }),
  });
  assert.strictEqual(cursorWithReview.status, 'unsupported-version');
  assert.ok(cursorWithReview.detail.includes('stop-followup-message>=2.4.0'));

  const copilotWithAsk = runtime.inspectRuntime('copilot', {
    emittedPaths: ['.github/hooks/conductor/pretool-commit-current-work-check.sh'],
    spawnSync: () => ({ status: 0, stdout: 'copilot 1.0.3', stderr: '' }),
  });
  assert.strictEqual(copilotWithAsk.status, 'unsupported-version');
  assert.ok(copilotWithAsk.detail.includes('pretool-ask-decision>=1.0.4'));
});

check('full Claude settings bind Agent routing and retain the complete-hook-set runtime floor', () => {
  const target = path.join(base, 'claude-old');
  install('claude', target);
  const settings = JSON.parse(fs.readFileSync(path.join(target, '.claude', 'settings.json'), 'utf8'));
  const routingGroups = settings.hooks.PreToolUse.filter((group) =>
    group.hooks?.some((hook) => String(hook.command).includes('pretool-agent-routing.sh')));
  assert.strictEqual(routingGroups.length, 1);
  assert.strictEqual(routingGroups[0].matcher, 'Agent');
  const manifest = JSON.parse(fs.readFileSync(path.join(target, '.conductor', 'manifests', 'claude.json'), 'utf8'));
  const emitted = new Set(manifest.emitted_files.map((entry) => entry.path));
  assert.ok(emitted.has('.claude/hooks/pretool-agent-routing.sh'));
  assert.ok(emitted.has('.claude/hooks/output-cap.sh'));
  const report = doctor(target, fakeCli('claude', '2.1.120 (Claude Code)'));
  const d13 = report.checks.find((entry) => entry.id === 'D13' && entry.detail.includes('claude'));
  assert.ok(d13, JSON.stringify(report.checks, null, 2));
  assert.strictEqual(d13.status, 'WARN');
  assert.ok(d13.detail.includes('[unsupported-version]'), d13.detail);
  assert.ok(d13.detail.includes('posttool-output-rewrite>=2.1.121'), d13.detail);
  assert.ok(!report.checks.some((entry) => entry.id === 'D5' && entry.detail.includes('2.1.121')),
    'the version floor must have one owner: D13/runtime_contract');
});

check('doctor D13 accepts a runtime at the applicable floor', () => {
  const target = path.join(base, 'claude-floor');
  install('claude', target);
  const report = doctor(target, fakeCli('claude', '2.1.121 (Claude Code)'));
  const d13 = report.checks.find((entry) => entry.id === 'D13' && entry.detail.includes('claude'));
  assert.ok(d13);
  assert.strictEqual(d13.status, 'OK');
  assert.ok(d13.detail.includes('[active]'), d13.detail);
});

check('Gemini first-party auth conflict stays verification-required', () => {
  const target = path.join(base, 'gemini-conflict');
  install('gemini', target);
  const report = doctor(target, fakeCli('gemini', 'gemini-cli 0.30.0'));
  const d13 = report.checks.find((entry) => entry.id === 'D13' && entry.detail.includes('gemini'));
  assert.ok(d13);
  assert.strictEqual(d13.status, 'WARN');
  assert.ok(d13.detail.includes('[verification-required]'), d13.detail);
  assert.ok(d13.detail.includes('auth=source-conflict'), d13.detail);
});

check('a verified renamed product reports product-migrated without changing the adapter id', () => {
  const meta = JSON.parse(JSON.stringify(runtime.loadMetadata('windsurf')));
  meta.live_verification = {
    status: 'verified',
    date: '2026-07-27',
    cli: 'devin 1.0.0',
    note: 'controlled test fixture',
  };
  const report = runtime.inspectRuntime('windsurf', {
    meta,
    spawnSync: () => ({ status: 0, stdout: 'devin 1.0.0', stderr: '' }),
  });
  assert.strictEqual(report.tool, 'windsurf');
  assert.strictEqual(report.status, 'product-migrated');
  assert.strictEqual(report.severity, 'OK');
  assert.ok(report.detail.includes('Devin Desktop'), report.detail);
});

check('doctor D13 leaves an installed project byte-identical', () => {
  const target = path.join(base, 'doctor-read-only');
  install('codex', target);
  const before = treeDigest(target);
  const report = doctor(target, fakeCli('codex', 'codex-cli 0.144.0'));
  assert.ok(report.checks.some((entry) => entry.id === 'D13' && entry.status === 'OK'));
  assert.strictEqual(treeDigest(target), before);
});

check('runtime-only live verification mode is read-only', () => {
  const meta = path.join(ROOT, 'adapters', 'copilot', 'metadata.json');
  const before = sha256(meta);
  const runtimeBin = fs.mkdtempSync(path.join(base, 'runtime-only-bin-'));
  fs.symlinkSync(process.execPath, path.join(runtimeBin, 'node'));
  const result = spawnSync('bash', ['tools/live-verify.sh', '--runtime-only', '--tool=copilot'], {
    cwd: ROOT,
    encoding: 'utf8',
    env: { ...process.env, PATH: `${runtimeBin}:/usr/bin:/bin` },
  });
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
  assert.ok(result.stdout.includes('[not-installed]'), result.stdout);
  assert.strictEqual(sha256(meta), before);
});

fs.rmSync(base, { recursive: true, force: true });
if (!process.exitCode) process.stdout.write(`runtime-contract tests: ${passed}/${passed} passed\n`);
