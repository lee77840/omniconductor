#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const installerPlatform = require('../bin/installer-platform.js');
const { bashPath } = require('./run-bash.js');

const ROOT = path.resolve(__dirname, '..');
const HELPER = path.join(ROOT, 'tools', 'manifest-safety.sh');
const BASH = (installerPlatform.resolveBash() || { command: 'bash' }).command;
const VOCABULARY = ['read', 'search', 'test', 'edit-code', 'edit-docs', 'shell', 'delegate', 'mcp'];
const EXPECTED = {
  planner: ['read', 'search'],
  reviewer: ['read', 'search'],
  'code-reviewer': ['read', 'search', 'test'],
  builder: ['read', 'search', 'test', 'edit-code', 'edit-docs', 'shell'],
  helper: ['read', 'search', 'test', 'edit-code', 'edit-docs', 'shell'],
  designer: ['read', 'search', 'test', 'edit-code', 'edit-docs', 'shell'],
  scribe: ['read', 'search', 'edit-docs'],
  utility: ['read', 'search', 'edit-code', 'edit-docs'],
  reflector: ['read', 'search'],
};

let passed = 0;
let failed = 0;

function check(name, fn) {
  try {
    fn();
    passed += 1;
    process.stdout.write(`OK   [role-capabilities] ${name}\n`);
  } catch (error) {
    failed += 1;
    process.stderr.write(`FAIL [role-capabilities] ${name}: ${error.stack || error.message}\n`);
  }
}

function frontmatter(file) {
  const text = fs.readFileSync(file, 'utf8');
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  assert(match, `${file}: missing frontmatter`);
  return match[1];
}

function capabilities(file) {
  const match = frontmatter(file).match(/^capabilities:\s*\[([^\]]*)\]\s*$/m);
  assert(match, `${file}: missing capabilities`);
  return match[1].split(',').map((item) => item.trim()).filter(Boolean);
}

function helper(name, file, argument = '') {
  return spawnSync(BASH, [
    '-c',
    'source "$1"; "$2" "$3" "$4"',
    'role-capabilities',
    bashPath(HELPER),
    name,
    bashPath(file),
    argument,
  ], { cwd: ROOT, encoding: 'utf8' });
}

function fixture(dir, name, declaration) {
  const file = path.join(dir, `${name}.md`);
  fs.writeFileSync(file, `---\nrole: fixture\ndifficulty_tier: 3\n${declaration}\n---\n# Fixture\n`);
  return file;
}

check('all baseline roles and Reflector use the exact portable allocations', () => {
  for (const [role, expected] of Object.entries(EXPECTED)) {
    const file = path.join(ROOT, 'core', 'roles', `${role}.md`);
    assert.deepStrictEqual(capabilities(file), expected, role);
  }
});

check('shared shell compiler returns the source order and a complete deny set', () => {
  for (const [role, expected] of Object.entries(EXPECTED)) {
    const file = path.join(ROOT, 'core', 'roles', `${role}.md`);
    const compiled = helper('conductor_role_capabilities', file);
    assert.strictEqual(compiled.status, 0, `${role}: ${compiled.stderr}`);
    assert.strictEqual(compiled.stdout, expected.join(' '), role);

    const contract = helper('conductor_role_capability_contract', file);
    assert.strictEqual(contract.status, 0, `${role}: ${contract.stderr}`);
    for (const capability of VOCABULARY) {
      assert.match(contract.stdout, new RegExp(`\\b${capability.replace('-', '\\-')}\\b`), `${role}: ${capability}`);
    }
  }
});

check('unknown, duplicate, missing, and empty declarations fail closed', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-role-capabilities-'));
  const invalid = [
    fixture(dir, 'unknown', 'capabilities: [read, network]'),
    fixture(dir, 'duplicate', 'capabilities: [read, read]'),
    fixture(dir, 'empty', 'capabilities: []'),
    fixture(dir, 'missing', 'purpose: "no authority declaration"'),
  ];
  for (const file of invalid) {
    const result = helper('conductor_role_capabilities', file);
    assert.notStrictEqual(result.status, 0, file);
    assert.match(result.stderr, /capabilit|allowlist/i, file);
  }
});

check('portable test never implies shell authority', () => {
  const file = path.join(ROOT, 'core', 'roles', 'code-reviewer.md');
  assert.strictEqual(helper('conductor_role_has_capability', file, 'test').status, 0);
  assert.strictEqual(helper('conductor_role_has_capability', file, 'shell').status, 1);
});

check('baseline roles cannot delegate and receive no abstract MCP authority', () => {
  for (const role of Object.keys(EXPECTED).filter((name) => name !== 'reflector')) {
    const file = path.join(ROOT, 'core', 'roles', `${role}.md`);
    assert.strictEqual(helper('conductor_role_has_capability', file, 'delegate').status, 1, role);
    assert.strictEqual(helper('conductor_role_has_capability', file, 'mcp').status, 1, role);
  }
});

check('all adapter metadata declares the exact vocabulary and dated source', () => {
  for (const tool of ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode']) {
    const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', tool, 'metadata.json'), 'utf8'));
    const contract = metadata.role_capabilities;
    assert.strictEqual(contract.schema_version, 1, tool);
    assert.deepStrictEqual(Object.keys(contract.enforcement).sort(), [...VOCABULARY].sort(), tool);
    assert.match(contract.source.url, /^https:\/\//, tool);
    assert.strictEqual(contract.source.checked, '2026-08-27', tool);
  }
});

process.stdout.write(`role capability tests: ${passed} passed, ${failed} failed\n`);
if (failed) process.exitCode = 1;
