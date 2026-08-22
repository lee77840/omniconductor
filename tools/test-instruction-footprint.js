#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const footprint = require('../bin/instruction-footprint.js');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
let passed = 0;

function run(args) {
  return spawnSync(process.execPath, [CLI, ...args], { cwd: ROOT, encoding: 'utf8' });
}

function test(name, fn) {
  try { fn(); passed += 1; process.stdout.write(`PASS: ${name}\n`); }
  catch (error) { process.stderr.write(`FAIL: ${name}: ${error.stack || error.message}\n`); process.exitCode = 1; }
}

const target = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-instruction-footprint-'));
const install = run(['init', '--target=all', target, '--no-prompt', '--accept-model-defaults', '--recipes=debugging,loop-engineering']);
assert.strictEqual(install.status, 0, install.stderr || install.stdout);

test('all seven adapters use bounded kernels within fail-closed budgets', () => {
  const report = footprint.audit(target);
  assert.strictEqual(report.adapters.length, 7);
  assert.strictEqual(report.summary.problems, 0, JSON.stringify(report, null, 2));
  for (const item of report.adapters) {
    assert.strictEqual(item.strategy, 'bounded-kernel+complete-references');
    assert(item.eager_bytes <= footprint.KERNEL_BUDGET, `${item.adapter}: ${item.eager_bytes}`);
    assert(item.always_active_bytes <= footprint.ACTIVE_BUDGET, `${item.adapter}: ${item.always_active_bytes}`);
    assert(item.complete_reference_bytes > item.always_active_bytes, item.adapter);
  }
});

test('complete rule and selected-recipe references are byte-identical', () => {
  const report = footprint.audit(target, { requests: 100 });
  for (const item of report.adapters) assert.deepStrictEqual(item.problems, [], item.adapter);
  for (const item of report.adapters) {
    assert(item.estimated_avoided_context_tokens_per_request > 0, item.adapter);
    assert.strictEqual(item.estimated_avoided_context_tokens_for_requests, item.estimated_avoided_context_tokens_per_request * 100);
  }
});

test('legacy eager universal-rule files are absent from fresh output', () => {
  for (const relative of [
    '.claude/rules/workflow.md', '.cursor/rules/workflow.mdc',
    '.github/instructions/workflow.instructions.md', '.devin/rules/workflow.md',
    '.opencode/rules/workflow.md',
  ]) assert(!fs.existsSync(path.join(target, relative)), relative);
});

test('path-scoped adapters retain compact selected-recipe pointers', () => {
  for (const relative of [
    '.claude/rules/debugging.md', '.cursor/rules/debugging.mdc',
    '.github/instructions/debugging.instructions.md',
  ]) {
    const file = path.join(target, relative);
    assert(fs.statSync(file).size < 2048, relative);
    assert.match(fs.readFileSync(file, 'utf8'), /complete|Complete|mandatory selected recipe/);
  }
  for (const relative of [
    '.devin/rules/debugging.md',
    '.opencode/rules/recipes/debugging.md',
  ]) assert(!fs.existsSync(path.join(target, relative)), relative);
});

test('always-active-pointer adapters emit compact pointers only in a-la-carte mode', () => {
  for (const adapter of ['windsurf', 'opencode']) {
    const fixture = fs.mkdtempSync(path.join(os.tmpdir(), `conductor-${adapter}-recipes-only-`));
    const result = run(['init', `--target=${adapter}`, fixture, '--mode=recipes-only', '--recipes=debugging', '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr || result.stdout);
    const relative = adapter === 'windsurf' ? '.devin/rules/debugging.md' : '.opencode/rules/recipes/debugging.md';
    const file = path.join(fixture, relative);
    assert(fs.statSync(file).size < 2048, relative);
    assert.match(fs.readFileSync(file, 'utf8'), /complete|Complete|mandatory selected recipe/);
  }
});

test('Copilot per-rule kernel alternative is measured without a false missing-file error', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-copilot-per-rule-'));
  const result = run(['init', '--target=copilot', fixture, '--no-prompt', '--accept-model-defaults', '--recipes=debugging', '--per-rule']);
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  assert(!fs.existsSync(path.join(fixture, '.github', 'copilot-instructions.md')));
  assert(fs.existsSync(path.join(fixture, '.github', 'instructions', 'conductor-kernel.instructions.md')));
  assert.deepStrictEqual(footprint.audit(fixture, { adapters: ['copilot'] }).adapters[0].problems, []);
});

test('fresh dry-run previews every bounded-kernel adapter without writing', () => {
  for (const adapter of footprint.ADAPTERS) {
    const fixture = fs.mkdtempSync(path.join(os.tmpdir(), `conductor-${adapter}-fresh-dry-run-`));
    const before = fs.readdirSync(fixture);
    const result = run(['init', `--target=${adapter}`, fixture, '--dry-run', '--no-prompt', '--accept-model-defaults', '--recipes=debugging']);
    assert.strictEqual(result.status, 0, `${adapter}: ${result.stderr || result.stdout}`);
    assert.deepStrictEqual(fs.readdirSync(fixture), before, `${adapter} dry-run wrote to disk`);
  }
});

test('reference drift is detected and makes the CLI audit non-zero', () => {
  const file = path.join(target, '.gemini', 'conductor', 'rules', 'workflow.md');
  fs.appendFileSync(file, '\nTAMPERED\n');
  const report = footprint.audit(target);
  assert(report.adapters.find((item) => item.adapter === 'gemini').problems.some((p) => /differs from core/.test(p)));
  const cli = run(['audit', 'instructions', target, '--json']);
  assert.strictEqual(cli.status, 1, cli.stderr || cli.stdout);
});

if (!process.exitCode) process.stdout.write(`PASS: instruction footprint contract ${passed}/8\n`);
