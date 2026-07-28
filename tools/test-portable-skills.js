#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const {
  CONTRACTS,
  SKILL_NAMES,
  validateAgentSkillsMetadata,
  validateInstalled,
  validateSourceRoot,
} = require('../bin/portable-skills.js');

const ROOT = path.resolve(__dirname, '..');
const SOURCE_ROOT = path.join(ROOT, 'core', 'skills');
const TOOLS = Object.keys(CONTRACTS);
let passed = 0;

function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [portable-skills] ${name}\n`);
}

function run(args, options = {}) {
  const result = spawnSync(args[0], args.slice(1), {
    cwd: ROOT,
    encoding: 'utf8',
    env: { ...process.env, ...(options.env || {}) },
  });
  if (options.expect !== undefined) {
    assert.strictEqual(
      result.status,
      options.expect,
      `${args.join(' ')} exited ${result.status}\n${result.stdout}\n${result.stderr}`,
    );
  } else {
    assert.strictEqual(
      result.status,
      0,
      `${args.join(' ')} failed\n${result.stdout}\n${result.stderr}`,
    );
  }
  return result;
}

function init(tool, target, mode = 'minimal') {
  run([
    process.execPath,
    'bin/omniconductor.js',
    'init',
    `--target=${tool}`,
    target,
    `--mode=${mode}`,
    '--no-prompt',
    '--accept-model-defaults',
  ]);
}

function uninstall(tool, target) {
  run([
    process.execPath,
    'bin/omniconductor.js',
    'init',
    `--target=${tool}`,
    target,
    '--uninstall',
  ]);
}

function skillPath(target, tool, name) {
  return path.join(target, CONTRACTS[tool].projectPath, name, 'SKILL.md');
}

function manifest(target, tool) {
  return JSON.parse(fs.readFileSync(path.join(target, '.conductor', 'manifests', `${tool}.json`), 'utf8'));
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-portable-skills-'));

try {
  test('three instruction-only core sources satisfy the shared schema', () => {
    assert.deepStrictEqual(validateSourceRoot(SOURCE_ROOT), []);
    assert.deepStrictEqual(fs.readdirSync(SOURCE_ROOT).sort(), [...SKILL_NAMES].sort());
  });

  test('review and verification skills preserve snapshot-scoped economy', () => {
    const review = fs.readFileSync(path.join(SOURCE_ROOT, 'review-change', 'SKILL.md'), 'utf8');
    const verify = fs.readFileSync(path.join(SOURCE_ROOT, 'verify-change', 'SKILL.md'), 'utf8');
    assert.match(review, /snapshot identity/);
    assert.match(review, /unreviewed delta/);
    assert.match(verify, /full project gates once on the final stable snapshot/);
    assert.match(verify, /reuse it/);
  });

  test('all six metadata contracts agree with their emitted roots', () => {
    for (const tool of TOOLS) {
      const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', tool, 'metadata.json'), 'utf8'));
      assert.deepStrictEqual(validateAgentSkillsMetadata(metadata), [], tool);
    }
  });

  test('minimal install emits byte-identical skills and manifest ownership for every adapter', () => {
    for (const tool of TOOLS) {
      const target = path.join(sandbox, `minimal-${tool}`);
      fs.mkdirSync(target, { recursive: true });
      init(tool, target);
      assert.deepStrictEqual(validateInstalled(target, tool, SOURCE_ROOT), [], tool);
      const owned = new Set(manifest(target, tool).emitted_files.map((entry) => entry.path));
      for (const name of SKILL_NAMES) {
        assert(owned.has(`${CONTRACTS[tool].projectPath}/${name}/SKILL.md`), `${tool}:${name}`);
      }
    }
  });

  test('five shared-path adapters coexist without backup chains and uninstall by final owner', () => {
    const target = path.join(sandbox, 'shared-owners');
    fs.mkdirSync(target, { recursive: true });
    const sharedTools = ['cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
    for (const tool of sharedTools) init(tool, target);
    for (const name of SKILL_NAMES) {
      assert(fs.existsSync(skillPath(target, 'codex', name)));
      for (const tool of sharedTools) {
        const entry = manifest(target, tool).emitted_files.find(
          (item) => item.path === `.agents/skills/${name}/SKILL.md`,
        );
        assert(entry, `${tool} must own ${name}`);
        assert.strictEqual(entry.backup_path, '');
      }
    }
    const backups = [];
    function walk(dir) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const child = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(child);
        else if (entry.name.includes('.conductor-backup-')) backups.push(child);
      }
    }
    walk(path.join(target, '.agents'));
    assert.deepStrictEqual(backups, []);
    for (const tool of sharedTools.slice(0, -1)) {
      uninstall(tool, target);
      assert(fs.existsSync(skillPath(target, 'windsurf', 'plan-change')));
    }
    uninstall(sharedTools.at(-1), target);
    for (const name of SKILL_NAMES) assert(!fs.existsSync(skillPath(target, 'codex', name)));
  });

  test('full install restores an original user skill on uninstall', () => {
    const target = path.join(sandbox, 'restore-user-skill');
    const original = 'ORIGINAL USER SKILL\n';
    const file = skillPath(target, 'cursor', 'plan-change');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, original);
    init('cursor', target, 'full');
    assert.notStrictEqual(fs.readFileSync(file, 'utf8'), original);
    const entry = manifest(target, 'cursor').emitted_files.find(
      (item) => item.path === '.agents/skills/plan-change/SKILL.md',
    );
    assert(entry && entry.backup_path);
    uninstall('cursor', target);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), original);
  });

  test('uninstall preserves a user-modified emitted skill', () => {
    const target = path.join(sandbox, 'preserve-edited-skill');
    fs.mkdirSync(target, { recursive: true });
    init('cursor', target);
    const file = skillPath(target, 'cursor', 'plan-change');
    fs.appendFileSync(file, '\nUSER EDIT\n');
    uninstall('cursor', target);
    assert(fs.readFileSync(file, 'utf8').includes('USER EDIT'));
  });

  test('strict mode rejects a conflicting skill before adapter output', () => {
    const target = path.join(sandbox, 'strict-conflict');
    const file = skillPath(target, 'cursor', 'plan-change');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'USER CONFLICT\n');
    run([
      'bash',
      'adapters/cursor/transform.sh',
      target,
      '--mode=strict',
      '--no-prompt',
      '--accept-model-defaults',
    ], { expect: 3, env: { CONDUCTOR_CLI_DISPATCH: '0' } });
    assert.strictEqual(fs.readFileSync(file, 'utf8'), 'USER CONFLICT\n');
    assert(!fs.existsSync(path.join(target, '.conductor', 'project.json')));
    assert(!fs.existsSync(path.join(target, '.conductor', 'manifests')));
    assert(!fs.existsSync(path.join(target, '.cursor')));
  });

  test('a non-directory skill root fails before baseline output in every install mode', () => {
    const target = path.join(sandbox, 'structural-conflict');
    fs.mkdirSync(path.join(target, '.agents'), { recursive: true });
    fs.writeFileSync(path.join(target, '.agents', 'skills'), 'NOT A DIRECTORY\n');
    run([
      'bash',
      'adapters/cursor/transform.sh',
      target,
      '--mode=minimal',
      '--no-prompt',
      '--accept-model-defaults',
    ], { expect: 1, env: { CONDUCTOR_CLI_DISPATCH: '0' } });
    assert.strictEqual(fs.readFileSync(path.join(target, '.agents', 'skills'), 'utf8'), 'NOT A DIRECTORY\n');
    assert(!fs.existsSync(path.join(target, '.conductor', 'project.json')));
    assert(!fs.existsSync(path.join(target, '.conductor', 'manifests')));
    assert(!fs.existsSync(path.join(target, '.cursor')));
  });

  test('strict mode rejects extra entries beside an identical skill', () => {
    const target = path.join(sandbox, 'strict-extra-entry');
    const file = skillPath(target, 'cursor', 'plan-change');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.copyFileSync(path.join(SOURCE_ROOT, 'plan-change', 'SKILL.md'), file);
    fs.writeFileSync(path.join(path.dirname(file), 'unmanaged.txt'), 'KEEP\n');
    run([
      'bash',
      'adapters/cursor/transform.sh',
      target,
      '--mode=strict',
      '--no-prompt',
      '--accept-model-defaults',
    ], { expect: 3, env: { CONDUCTOR_CLI_DISPATCH: '0' } });
    assert.strictEqual(fs.readFileSync(path.join(path.dirname(file), 'unmanaged.txt'), 'utf8'), 'KEEP\n');
    assert(!fs.existsSync(path.join(target, '.conductor', 'project.json')));
    assert(!fs.existsSync(path.join(target, '.cursor')));
  });

  process.stdout.write(`OK — portable-skills tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
