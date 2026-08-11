#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const contract = require('../bin/evidence-contract.js');

const root = path.resolve(__dirname, '..');
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [evidence-contract] ${name}\n`);
}

function validReport(status = 'passed') {
  const unresolved = status !== 'passed' && status !== 'failed';
  return {
    schema_version: 1,
    snapshot: { kind: 'git-commit', value: 'a'.repeat(40), dirty: false },
    claims: [{
      id: 'build.pass',
      claim: 'The final build succeeds on the recorded snapshot.',
      status,
      reason: status === 'passed' ? 'Command exited zero.' : 'Required runtime was unavailable.',
      command: 'npm test',
      evidence: status === 'passed' || status === 'failed'
        ? [{ kind: 'command', ref: status === 'passed' ? 'npm test: exit 0' : 'npm test: exit 1', digest: 'sha256:abc' }]
        : [],
      ...(unresolved ? { missing: ['trusted runtime'] } : {}),
      reproducible: status === 'passed',
    }],
  };
}

test('accepts a snapshot-bound passed claim with concrete evidence', () => {
  assert.deepStrictEqual(contract.validateReport(validReport()), []);
  assert.strictEqual(contract.summarize(validReport()).complete, true);
});

test('accepts explicit unresolved statuses without converting them to pass', () => {
  for (const status of ['blocked', 'not-run', 'environment-limited', 'verification-required']) {
    const report = validReport(status);
    assert.deepStrictEqual(contract.validateReport(report), []);
    assert.strictEqual(contract.summarize(report).complete, false);
  }
});

test('rejects vacuous pass, unknown fields, duplicate ids, and unresolved claims without gaps', () => {
  const report = validReport();
  report.claims[0].evidence = [];
  report.claims[0].invented = true;
  report.claims.push({ ...report.claims[0] });
  report.claims.push({ ...validReport('blocked').claims[0], id: 'blocked.no-gap', missing: [] });
  const problems = contract.validateReport(report).join('\n');
  assert.match(problems, /passed requires at least one evidence/);
  assert.match(problems, /unknown field 'invented'/);
  assert.match(problems, /duplicates 'build.pass'/);
  assert.match(problems, /blocked requires at least one missing requirement/);
});

test('rejects a failed claim with no contradictory evidence', () => {
  const report = validReport('failed');
  report.claims[0].evidence = [];
  assert.match(contract.validateReport(report).join('\n'), /failed requires at least one evidence/);
});

test('rejects dirty commit labels and malformed snapshot identifiers', () => {
  const dirty = validReport();
  dirty.snapshot.dirty = true;
  assert.match(contract.validateReport(dirty).join('\n'), /dirty snapshot must use content-digest/);
  const malformed = validReport();
  malformed.snapshot.value = 'main';
  assert.match(contract.validateReport(malformed).join('\n'), /lowercase hex git-commit id/);
  const exactDirty = validReport();
  exactDirty.snapshot = { kind: 'content-digest', value: `sha256:${'b'.repeat(64)}`, dirty: true };
  assert.deepStrictEqual(contract.validateReport(exactDirty), []);
});

test('CLI validate separates schema validity from gate completion', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-evidence-'));
  try {
    const passedFile = path.join(temp, 'passed.json');
    const blockedFile = path.join(temp, 'blocked.json');
    fs.writeFileSync(passedFile, `${JSON.stringify(validReport(), null, 2)}\n`);
    fs.writeFileSync(blockedFile, `${JSON.stringify(validReport('environment-limited'), null, 2)}\n`);
    const validate = spawnSync(process.execPath, ['bin/omniconductor.js', 'evidence', 'validate', blockedFile, '--json'], { cwd: root, encoding: 'utf8' });
    assert.strictEqual(validate.status, 0, validate.stderr);
    assert.strictEqual(JSON.parse(validate.stdout).summary.complete, false);
    const pass = spawnSync(process.execPath, ['bin/omniconductor.js', 'evidence', 'check', passedFile], { cwd: root, encoding: 'utf8' });
    assert.strictEqual(pass.status, 0, pass.stderr);
    const incomplete = spawnSync(process.execPath, ['bin/omniconductor.js', 'evidence', 'check', blockedFile], { cwd: root, encoding: 'utf8' });
    assert.strictEqual(incomplete.status, 1, incomplete.stderr);
    assert.match(incomplete.stdout, /Gate: INCOMPLETE/);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('CLI rejects linked reports and malformed JSON with exit 2', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-evidence-unsafe-'));
  try {
    const target = path.join(temp, 'target.json');
    const linked = path.join(temp, 'linked.json');
    fs.writeFileSync(target, `${JSON.stringify(validReport())}\n`);
    fs.symlinkSync(target, linked);
    const unsafe = spawnSync(process.execPath, ['bin/omniconductor.js', 'evidence', 'validate', linked], { cwd: root, encoding: 'utf8' });
    assert.strictEqual(unsafe.status, 2);
    assert.match(unsafe.stderr, /single-link regular JSON file/);
    fs.unlinkSync(linked);
    fs.writeFileSync(linked, '{');
    const malformed = spawnSync(process.execPath, ['bin/omniconductor.js', 'evidence', 'validate', linked], { cwd: root, encoding: 'utf8' });
    assert.strictEqual(malformed.status, 2);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

process.stdout.write(`OK — evidence-contract tests: ${passed}/${passed}\n`);
