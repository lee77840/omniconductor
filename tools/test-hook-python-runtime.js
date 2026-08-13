#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

if (process.platform === 'win32') {
  console.log('SKIP: Windows positive Python hook branch is covered by test:windows-installer');
  process.exit(0);
}

const ROOT = path.resolve(__dirname, '..');
const base = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-hook-python-'));
const bash = require('../bin/installer-platform.js').resolveBash();
const pythonHooks = [
  'output-cap.sh.template',
  'pretool-agent-routing.sh.template',
  'pretool-commit-current-work-check.sh.template',
  'pretool-commit-test-coverage-check.sh.template',
  'pretool-large-file-read-guard.sh.template',
  'pretool-loop-guard.sh.template',
  'stop-cache-hit-baseline-check.sh.template',
  'stop-r6-review-check.sh.template',
  'stop-session-log-check.sh.template',
];

function executable(file, source) {
  fs.writeFileSync(file, source, { mode: 0o755 });
  fs.chmodSync(file, 0o755);
}

function fixtureRepo(name) {
  const repo = path.join(base, name);
  fs.mkdirSync(repo);
  assert.strictEqual(spawnSync('git', ['init', '-q'], { cwd: repo }).status, 0);
  for (const file of ['one.ts', 'two.ts', 'three.ts']) fs.writeFileSync(path.join(repo, file), 'export {};\n');
  assert.strictEqual(spawnSync('git', ['add', '.'], { cwd: repo }).status, 0);
  return repo;
}

try {
  for (const name of pythonHooks) {
    const source = fs.readFileSync(path.join(ROOT, 'core', 'hooks', name), 'utf8');
    assert(source.includes('CONDUCTOR_PYTHON_BIN'), `${name} lacks the portable Python resolver`);
    assert(source.includes('Python 3 is unavailable'), `${name} lacks an explicit degraded-enforcement diagnostic`);
    assert(!source.includes('/usr/bin/python3'), `${name} retains a Unix-only Python path`);
  }

  const actualPython = spawnSync(bash.command, ['-lc', 'for p in python3 python; do command -v "$p" >/dev/null 2>&1 && "$p" -c "import json,sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)" >/dev/null 2>&1 && { command -v "$p"; exit 0; }; done; exit 1'], { encoding: 'utf8' }).stdout.trim();
  assert(actualPython, 'test host needs one working Python 3 runtime');

  const fallbackBin = path.join(base, 'fallback-bin');
  fs.mkdirSync(fallbackBin);
  executable(path.join(fallbackBin, 'python3'), '#!/bin/sh\nexit 91\n');
  executable(path.join(fallbackBin, 'python'), `#!/bin/sh\nexec "${actualPython}" "$@"\n`);
  const positiveRepo = fixtureRepo('positive');
  // Invoke the resolved Bash directly for the payload-bearing assertion.
  const payloadResult = spawnSync(bash.command, [path.join(ROOT, 'core/hooks/pretool-commit-current-work-check.sh.template')], {
    cwd: positiveRepo,
    input: '{"toolName":"bash","toolArgs":{"command":"git commit -m fixture"}}\r\n',
    encoding: 'utf8',
    env: { ...process.env, PATH: `${fallbackBin}:/usr/bin:/bin`, CONDUCTOR_HOOK_DIALECT: 'copilot' },
  });
  assert.strictEqual(payloadResult.status, 0, payloadResult.stderr);
  const parsed = JSON.parse(payloadResult.stdout);
  assert.strictEqual(parsed.permissionDecision, 'ask');

  const session = path.join(base, 'session.jsonl');
  fs.writeFileSync(session, `${JSON.stringify({ message: { usage: { input_tokens: 3, output_tokens: 5 } } })}\n`);
  const measurement = spawnSync(bash.command, [path.join(ROOT, 'tools', 'measure-tokens.sh'), `--session=${session}`], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${fallbackBin}:/usr/bin:/bin` },
  });
  assert.strictEqual(measurement.status, 0, measurement.stderr);
  assert.match(measurement.stdout, /Output tokens\s*:\s*5/);

  const missingBin = path.join(base, 'missing-bin');
  fs.mkdirSync(missingBin);
  executable(path.join(missingBin, 'python3'), '#!/bin/sh\nexit 91\n');
  executable(path.join(missingBin, 'python'), '#!/bin/sh\nexit 92\n');
  const missing = spawnSync(bash.command, [path.join(ROOT, 'core/hooks/pretool-commit-current-work-check.sh.template')], {
    input: '{}\n',
    encoding: 'utf8',
    env: { ...process.env, PATH: `${missingBin}:/usr/bin:/bin` },
  });
  assert.strictEqual(missing.status, 0);
  assert.strictEqual(missing.stdout, '');
  assert.match(missing.stderr, /Python 3 is unavailable/);

  console.log('PASS: hook falls back from broken python3 to working python');
  console.log('PASS: missing Python is explicit rather than a silent successful no-op');
  console.log('PASS: every Python-backed hook uses the portable resolver and diagnostic');
  console.log('PASS: token measurement uses the same Python fallback contract');
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}
