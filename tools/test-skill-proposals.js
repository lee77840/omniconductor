#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const proposals = require('../bin/skill-proposals.js');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [skill-proposals] ${name}\n`);
}

function validInput() {
  return {
    schema_version: 1,
    name: 'verify-release-notes',
    summary: 'Verify release notes against the exact package snapshot.',
    procedure: ['Record the package snapshot identity.', 'Compare every release claim with that snapshot.'],
    evidence: [
      { path: 'docs/CURRENT_WORK.md', observation: 'The same verification was needed in two releases.', occurrences: 2 },
    ],
    constraints: ['Never publish automatically.'],
    source_tool: 'codex',
  };
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-skill-proposals-'));
try {
  test('schema requires repeated evidence and rejects executable fields', () => {
    const input = validInput();
    input.evidence[0].occurrences = 1;
    input.command = 'do-not-store';
    const problems = proposals.validateInput(input);
    assert(problems.some((item) => item.includes('at least 2')));
    assert(problems.some((item) => item.includes('unsupported field: command')));
  });

  test('create writes one pending typed item and duplicate creation is idempotent', () => {
    const first = proposals.create(sandbox, validInput(), { now: new Date('2026-08-10T12:00:00Z') });
    const second = proposals.create(sandbox, validInput(), { now: new Date('2026-08-10T13:00:00Z') });
    assert(first.created);
    assert(!second.created);
    assert.strictEqual(proposals.list(sandbox).length, 1);
    assert.strictEqual(first.proposal.status, 'pending');
    assert.strictEqual(first.proposal.applied, false);
  });

  test('human decision is recorded without creating a live skill', () => {
    const [item] = proposals.list(sandbox);
    const reviewed = proposals.review(sandbox, item.id, 'accept', 'Promote in a separate reviewed change.', {
      now: new Date('2026-08-10T14:00:00Z'),
    });
    assert.strictEqual(reviewed.status, 'accepted');
    assert.strictEqual(reviewed.applied, false);
    assert.strictEqual(reviewed.review.applied, false);
    assert(!fs.existsSync(path.join(sandbox, '.agents', 'skills', reviewed.proposal.name)));
    assert.throws(() => proposals.review(sandbox, item.id, 'reject'), /already reviewed/);
  });

  test('dry-run performs no write', () => {
    const target = path.join(sandbox, 'dry-run');
    fs.mkdirSync(target);
    const result = proposals.create(target, validInput(), { dryRun: true });
    assert(result.dry_run);
    assert(!fs.existsSync(path.join(target, proposals.INBOX_REL)));
  });

  test('symlinked inbox is refused', () => {
    const target = path.join(sandbox, 'symlink');
    const outside = path.join(sandbox, 'outside');
    fs.mkdirSync(path.join(target, '.conductor'), { recursive: true });
    fs.mkdirSync(outside);
    fs.symlinkSync(outside, path.join(target, proposals.INBOX_REL));
    assert.throws(() => proposals.create(target, validInput()), /symlinked proposal path/);
  });

  test('target symlinks, proposal symlinks, hardlinks, and content-address drift fail closed', () => {
    const realTarget = path.join(sandbox, 'real-target');
    const linkedTarget = path.join(sandbox, 'linked-target');
    fs.mkdirSync(realTarget);
    fs.symlinkSync(realTarget, linkedTarget);
    assert.throws(() => proposals.create(linkedTarget, validInput()), /target must be a real directory/);

    const driftTarget = path.join(sandbox, 'content-drift');
    fs.mkdirSync(driftTarget);
    const created = proposals.create(driftTarget, validInput());
    const stored = JSON.parse(fs.readFileSync(created.file, 'utf8'));
    stored.proposal.summary = 'This tampered summary no longer matches the content-addressed id.';
    fs.writeFileSync(created.file, JSON.stringify(stored));
    assert.throws(() => proposals.list(driftTarget), /content-address mismatch/);

    const unsafeTarget = path.join(sandbox, 'unsafe-files');
    fs.mkdirSync(path.join(unsafeTarget, proposals.INBOX_REL), { recursive: true });
    const id = '0123456789abcdef';
    const outside = path.join(sandbox, 'outside-proposal.json');
    fs.writeFileSync(outside, '{}');
    fs.symlinkSync(outside, path.join(unsafeTarget, proposals.INBOX_REL, `${id}.json`));
    assert.throws(() => proposals.list(unsafeTarget), /unsafe proposal file/);
    fs.unlinkSync(path.join(unsafeTarget, proposals.INBOX_REL, `${id}.json`));
    fs.linkSync(outside, path.join(unsafeTarget, proposals.INBOX_REL, `${id}.json`));
    assert.throws(() => proposals.list(unsafeTarget), /unsafe proposal file/);
  });

  test('CLI propose/list/review round trip is machine-readable', () => {
    const target = path.join(sandbox, 'cli');
    const inputFile = path.join(sandbox, 'proposal-input.json');
    fs.mkdirSync(target);
    fs.writeFileSync(inputFile, JSON.stringify(validInput()));
    const run = (args) => spawnSync(process.execPath, [path.join(ROOT, 'bin', 'omniconductor.js'), ...args], {
      cwd: ROOT, encoding: 'utf8',
    });
    const created = run(['skills', 'propose', target, `--from=${inputFile}`, '--json']);
    assert.strictEqual(created.status, 0, created.stderr);
    const id = JSON.parse(created.stdout).proposal.id;
    const listed = run(['skills', 'list', target, '--json']);
    assert.strictEqual(JSON.parse(listed.stdout)[0].id, id);
    const reviewed = run(['skills', 'review', id, target, '--decision=reject', '--json']);
    assert.strictEqual(JSON.parse(reviewed.stdout).status, 'rejected');
  });

  process.stdout.write(`OK — skill-proposal tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
