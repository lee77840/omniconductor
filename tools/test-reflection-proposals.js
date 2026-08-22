'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { appendProposals, parseEnvelope } = require('../core/reflector/reflection-proposals.js');

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`PASS: ${name}\n`);
}
function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reflection-proposals-'));
  process.chdir(dir);
  return dir;
}
function envelope(overrides = {}) {
  const proposal = {
    op: 'ADD',
    target: 'feedback_lesson-read-before-edit.md',
    lesson: 'Read the owned contract before editing.',
    why: 'Two sessions failed after assumptions.',
    how_to_apply: 'Open the relevant instruction and status files first.',
    provenance: ['session:s-1', 'commit:abc123'],
    ...overrides,
  };
  return `<conductor-reflection-proposals>${JSON.stringify({ schema_version: 1, proposals: [proposal] })}</conductor-reflection-proposals>`;
}
function rejects(fn, pattern) { assert.throws(fn, pattern); }

test('valid typed output appends once and remains idempotent', () => {
  const dir = fixture();
  const proposals = parseEnvelope(envelope());
  assert.strictEqual(appendProposals(proposals, 'docs/REFLECTION-PROPOSALS.md').appended, 1);
  assert.strictEqual(appendProposals(proposals, 'docs/REFLECTION-PROPOSALS.md').appended, 0);
  const text = fs.readFileSync(path.join(dir, 'docs/REFLECTION-PROPOSALS.md'), 'utf8');
  assert.match(text, /\*\*\[ADD\]\*\*/);
  assert.strictEqual((text.match(/conductor:reflection-proposal/g) || []).length, 1);
});

test('schema rejects missing provenance, unsafe targets, and unknown fields', () => {
  rejects(() => parseEnvelope(envelope({ provenance: [] })), /provenance/);
  rejects(() => parseEnvelope(envelope({ target: '../escape.md' })), /target/);
  rejects(() => parseEnvelope(envelope({ surprise: true })), /unsupported field/);
});

test('parser rejects malformed, duplicate, and oversized envelopes', () => {
  rejects(() => parseEnvelope('{}'), /exactly one/);
  rejects(() => parseEnvelope(`${envelope()}${envelope()}`), /exactly one/);
  rejects(() => parseEnvelope('x'.repeat(1024 * 1024 + 1)), /exceeds/);
});

test('writer refuses path escape, symlink target, and hard-linked target', () => {
  const dir = fixture();
  const proposals = parseEnvelope(envelope());
  rejects(() => appendProposals(proposals, 'other.md'), /target is fixed/);
  fs.mkdirSync('docs');
  fs.writeFileSync('outside.md', 'keep');
  fs.symlinkSync(path.join(dir, 'outside.md'), 'docs/REFLECTION-PROPOSALS.md');
  rejects(() => appendProposals(proposals, 'docs/REFLECTION-PROPOSALS.md'), /regular single-link/);
  fs.unlinkSync('docs/REFLECTION-PROPOSALS.md');
  fs.linkSync('outside.md', 'docs/REFLECTION-PROPOSALS.md');
  rejects(() => appendProposals(proposals, 'docs/REFLECTION-PROPOSALS.md'), /regular single-link/);
  assert.strictEqual(fs.readFileSync('outside.md', 'utf8'), 'keep');
});

test('dry-run is byte-free even when docs does not exist', () => {
  fixture();
  const result = appendProposals(parseEnvelope(envelope()), 'docs/REFLECTION-PROPOSALS.md', true);
  assert.strictEqual(result.appended, 1);
  assert.strictEqual(fs.existsSync('docs'), false);
});

test('untrusted markdown metacharacters are escaped', () => {
  const dir = fixture();
  appendProposals(parseEnvelope(envelope({ lesson: '<!-- forged -->' })), 'docs/REFLECTION-PROPOSALS.md');
  const text = fs.readFileSync(path.join(dir, 'docs/REFLECTION-PROPOSALS.md'), 'utf8');
  assert.match(text, /&lt;!-- forged --&gt;/);
  assert.strictEqual((text.match(/<!--/g) || []).length, 1);
});

process.stdout.write(`PASS: reflection proposal contract ${passed}/${passed}\n`);
