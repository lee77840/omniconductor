#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const savings = require('../bin/user-token-savings.js');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-user-savings-'));
const project = path.join(fixture, 'project');
fs.mkdirSync(project);

const install = spawnSync(process.execPath, [CLI, 'init', '--target=all', project, '--no-prompt', '--accept-model-defaults', '--recipes='], { cwd: ROOT, encoding: 'utf8' });
assert.strictEqual(install.status, 0, install.stderr || install.stdout);
const sessions = path.join(fixture, 'sessions');
fs.mkdirSync(sessions);
const records = [
  { timestamp: '2026-08-20T10:00:00Z', message: { id: 'one', usage: { input_tokens: 10, output_tokens: 5 }, content: [] } },
  { timestamp: '2026-08-20T10:01:00Z', message: { id: 'two', usage: { cache_read_input_tokens: 80, cache_creation_input_tokens: 10, input_tokens: 10 }, content: [
    { type: 'tool_result', content: '[CONDUCTOR] output truncated — 321 tokens elided; re-run scoped' },
  ] } },
];
fs.writeFileSync(path.join(sessions, 'one.jsonl'), `${records.map(JSON.stringify).join('\n')}\n`);

const report = savings.create({ project, target: 'claude', sessions, subject: 'local-user' });
assert.strictEqual(report.request_count, 2);
assert.strictEqual(report.observed_output_savings.output_tokens_elided_lower_bound, 321);
assert(report.estimated_instruction_context_savings.avoided_context_tokens_for_requests > 0);
assert.strictEqual(report.total_savings, null);
assert(!JSON.stringify(report).includes('[CONDUCTOR] output truncated'));
console.log('PASS: Claude local sessions produce separated observed and estimated personal savings');

const estimatedOnly = savings.create({ project, target: 'opencode', requests: 5 });
assert.strictEqual(estimatedOnly.observed_output_savings, null);
assert.strictEqual(estimatedOnly.request_count_basis, 'user-supplied');
assert(estimatedOnly.estimated_instruction_context_savings.avoided_context_tokens_for_requests > 0);
console.log('PASS: explicit request counts support zero-telemetry estimate-only reports');

assert.throws(() => savings.create({ project, target: 'codex', sessions }), /support --target=claude only/);
assert.throws(() => savings.create({ project, target: 'claude', requests: 0 }), /provide --requests/);
assert.throws(() => savings.create({ project, target: 'claude', requests: 1, subject: 'bad\nname' }), /subject/);
assert.throws(() => savings.create({ project, target: 'claude', sessions, since: 'not-a-date' }), /ISO-8601/);
console.log('PASS: incompatible evidence, empty measurement, and unsafe labels fail closed');

const cli = spawnSync(process.execPath, [CLI, 'audit', 'savings', project, '--target=claude', `--sessions=${sessions}`, '--json'], { cwd: ROOT, encoding: 'utf8' });
assert.strictEqual(cli.status, 0, cli.stderr || cli.stdout);
assert.strictEqual(JSON.parse(cli.stdout).observed_output_savings.output_tokens_elided_lower_bound, 321);
console.log('PASS: packaged CLI path returns machine-readable local evidence');

fs.appendFileSync(path.join(sessions, 'one.jsonl'), JSON.stringify(records[0]) + '\n');
assert.strictEqual(savings.create({ project, target: 'claude', sessions }).request_count, 2);
fs.appendFileSync(path.join(sessions, 'one.jsonl'), JSON.stringify({ message: { usage: { input_tokens: 5 } } }) + '\n');
assert.throws(() => savings.create({ project, target: 'claude', sessions }), /verified --requests/);
assert.strictEqual(savings.create({ project, target: 'claude', sessions, requests: 3 }).request_count, 3);
console.log('PASS: duplicate records do not multiply estimates; unknown identities require explicit evidence');
console.log('PASS: personal token-savings contract 5/5');
