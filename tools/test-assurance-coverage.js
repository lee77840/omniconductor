#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const coverage = require('../bin/assurance-coverage.js');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [assurance-coverage] ${name}\n`);
}

test('report is deterministic and covers every artifact across seven adapters', () => {
  const first = coverage.buildReport();
  const second = coverage.buildReport();
  assert.deepStrictEqual(first, second);
  assert.deepStrictEqual(first.adapters, coverage.TOOLS);
  assert(first.records.length >= 35, `unexpectedly small inventory: ${first.records.length}`);
  for (const record of first.records) {
    assert.deepStrictEqual(Object.keys(record.adapters), coverage.TOOLS);
    for (const tool of coverage.TOOLS) {
      assert(coverage.LEVELS.includes(record.adapters[tool].level));
      assert(record.adapters[tool].evidence.length > 0);
    }
  }
});

test('live verification is not incorrectly inherited by individual policies', () => {
  const report = coverage.buildReport();
  assert.strictEqual(report.records.find((item) => item.id === 'adapter-load:claude').adapters.claude.level, 'live-verified');
  assert.strictEqual(report.records.find((item) => item.id === 'adapter-load:cursor').adapters.cursor.level, 'emit-verified');
  assert.strictEqual(report.records.find((item) => item.id === 'rule:workflow').adapters.claude.level, 'emit-verified');
  assert.strictEqual(report.records.find((item) => item.id === 'hook:review-before-stop').adapters.cursor.level, 'native-contract-tested');
  assert.strictEqual(report.records.find((item) => item.id === 'hook:commit-current-work').adapters.cursor.level, 'instruction-only');
});

test('comparison detects downgrade and disappearance but accepts additive coverage', () => {
  const current = coverage.buildReport();
  const previous = JSON.parse(JSON.stringify(current));
  const workflow = previous.records.find((item) => item.id === 'rule:workflow');
  workflow.adapters.claude.level = 'live-verified';
  previous.records.push({
    id: 'removed:test',
    adapters: Object.fromEntries(coverage.TOOLS.map((tool) => [tool, { level: 'emit-verified' }])),
  });
  const regressions = coverage.compare(current, previous);
  assert(regressions.some((item) => item.includes('rule:workflow/claude')));
  assert(regressions.some((item) => item.includes('removed:test')));
  assert.deepStrictEqual(coverage.compare(current, current), []);
});

test('comparison rejects malformed or adapter-incomplete baselines', () => {
  const current = coverage.buildReport();
  const incomplete = JSON.parse(JSON.stringify(current));
  delete incomplete.records[0].adapters.codex;
  assert.throws(() => coverage.compare(current, incomplete), /invalid codex coverage/);
  const duplicate = JSON.parse(JSON.stringify(current));
  duplicate.records.push(JSON.parse(JSON.stringify(duplicate.records[0])));
  assert.throws(() => coverage.compare(current, duplicate), /duplicate artifact id/);
});

test('CLI JSON and comparison exit codes are stable', () => {
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-assurance-'));
  try {
    const baseline = path.join(sandbox, 'baseline.json');
    fs.writeFileSync(baseline, `${JSON.stringify(coverage.buildReport(), null, 2)}\n`);
    let result = spawnSync(process.execPath, ['bin/omniconductor.js', 'eval', 'coverage', '--json', `--compare=${baseline}`], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(JSON.parse(result.stdout).schema_version, 1);
    const degraded = JSON.parse(fs.readFileSync(baseline, 'utf8'));
    degraded.records.find((item) => item.id === 'rule:workflow').adapters.codex.level = 'live-verified';
    fs.writeFileSync(baseline, JSON.stringify(degraded));
    result = spawnSync(process.execPath, ['bin/omniconductor.js', 'eval', 'coverage', `--compare=${baseline}`], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 1);
    assert.match(result.stderr, /coverage regression/);
  } finally {
    fs.rmSync(sandbox, { recursive: true, force: true });
  }
});

test('generated coverage documents match source evidence', () => {
  const result = spawnSync(process.execPath, ['tools/generate-assurance-coverage.js', '--check'], { cwd: ROOT, encoding: 'utf8' });
  assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

process.stdout.write(`OK — assurance-coverage tests: ${passed}/${passed}\n`);
