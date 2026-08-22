#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-opencode-'));
let passed = 0;

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: options.cwd || ROOT,
    env: { ...process.env, ...(options.env || {}) },
    encoding: 'utf8',
  });
}

function test(name, fn) {
  return Promise.resolve().then(fn).then(() => {
    passed += 1;
    process.stdout.write(`OK   ${name}\n`);
  }, (error) => {
    process.stderr.write(`FAIL ${name}: ${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

function install(target, ...args) {
  return run(process.execPath, [CLI, 'init', '--target=opencode', target,
    '--no-prompt', '--accept-model-defaults', ...args]);
}

async function main() {
  await test('OpenCode install emits v1-native surfaces without claiming the root AGENTS.md', () => {
    const target = path.join(TMP, 'fresh');
    fs.mkdirSync(target, { recursive: true });
    const result = install(target, '--recipes=tdd,self-improvement');
    assert.strictEqual(result.status, 0, result.stderr || result.stdout);
    assert(!fs.existsSync(path.join(target, 'AGENTS.md')));
    const config = JSON.parse(fs.readFileSync(path.join(target, 'opencode.json'), 'utf8'));
    assert.deepStrictEqual(config.instructions,
      ['.opencode/rules/conductor-kernel.md']);
    assert(!fs.existsSync(path.join(target, '.opencode', 'rules', 'recipes', 'tdd.md')));
    assert(fs.existsSync(path.join(target, '.opencode', 'conductor', 'recipes', 'tdd.md')));
    assert(fs.existsSync(path.join(target, '.opencode', 'conductor', 'rules', 'workflow.md')));
    assert(!fs.existsSync(path.join(target, '.opencode', 'rules', 'workflow.md')));
    for (const role of ['planner', 'reviewer', 'code-reviewer', 'builder', 'helper', 'designer', 'scribe', 'utility']) {
      assert(fs.existsSync(path.join(target, '.opencode', 'agents', `${role}.md`)), role);
    }
    assert(fs.existsSync(path.join(target, '.opencode', 'plugins', 'conductor-guards.js')));
    assert(fs.existsSync(path.join(target, '.opencode', 'commands', 'reflect.md')));
  });

  await test('semantic config merge is idempotent and uninstall restores exact user bytes', () => {
    const target = path.join(TMP, 'merge');
    fs.mkdirSync(target, { recursive: true });
    const original = '{\n    "$schema": "https://opencode.ai/config.json",\n    "theme": "custom",\n    "instructions": ["docs/local.md"]\n}\n';
    fs.writeFileSync(path.join(target, 'opencode.json'), original);
    for (let pass = 0; pass < 2; pass += 1) {
      const result = install(target, '--recipes=tdd');
      assert.strictEqual(result.status, 0, result.stderr || result.stdout);
      const config = JSON.parse(fs.readFileSync(path.join(target, 'opencode.json'), 'utf8'));
      assert.strictEqual(config.theme, 'custom');
      assert.deepStrictEqual(config.instructions,
        ['docs/local.md', '.opencode/rules/conductor-kernel.md']);
    }
    const uninstall = install(target, '--uninstall');
    assert.strictEqual(uninstall.status, 0, uninstall.stderr || uninstall.stdout);
    assert.strictEqual(fs.readFileSync(path.join(target, 'opencode.json'), 'utf8'), original);
  });

  await test('JSONC ambiguity fails during adapter preflight before model routing or output writes', () => {
    const target = path.join(TMP, 'jsonc');
    fs.mkdirSync(target, { recursive: true });
    const original = '{ // user comments\n}\n';
    fs.writeFileSync(path.join(target, 'opencode.jsonc'), original);
    const result = install(target);
    assert.strictEqual(result.status, 2, result.stderr || result.stdout);
    assert.match(result.stderr, /opencode\.jsonc already exists/);
    assert.strictEqual(fs.readFileSync(path.join(target, 'opencode.jsonc'), 'utf8'), original);
    assert.deepStrictEqual(fs.readdirSync(target), ['opencode.jsonc']);
  });

  await test('v1 native commit plugin blocks missing evidence and permits staged policy evidence', async () => {
    const target = path.join(TMP, 'plugin');
    fs.mkdirSync(path.join(target, 'src'), { recursive: true });
    fs.mkdirSync(path.join(target, 'tests'), { recursive: true });
    fs.mkdirSync(path.join(target, 'docs'), { recursive: true });
    assert.strictEqual(run('git', ['init', '-q'], { cwd: target }).status, 0);
    fs.writeFileSync(path.join(target, 'src', 'feature.js'), 'export const value = 1;\n');
    fs.writeFileSync(path.join(target, 'docs', 'CURRENT_WORK.md'), '# Work\nStatus: IN_PROGRESS\n');
    assert.strictEqual(run('git', ['add', 'src/feature.js'], { cwd: target }).status, 0);

    const moduleFile = path.join(target, 'conductor-guards.mjs');
    fs.copyFileSync(path.join(ROOT, 'adapters', 'opencode', 'conductor-guards.js'), moduleFile);
    const pluginModule = await import(`${pathToFileURL(moduleFile).href}?v=${Date.now()}`);
    const hooks = await pluginModule.ConductorGuards({ worktree: target });
    await assert.rejects(
      hooks['tool.execute.before']({ tool: 'bash' }, { args: { command: 'git commit -m test' } }),
      /CURRENT_WORK/,
    );

    fs.writeFileSync(path.join(target, 'tests', 'feature.test.js'), 'export const covered = true;\n');
    assert.strictEqual(run('git', ['add', 'docs/CURRENT_WORK.md', 'tests/feature.test.js'], { cwd: target }).status, 0);
    await hooks['tool.execute.before']({ tool: 'bash' }, { args: { command: 'git commit -m test' } });
    await hooks['tool.execute.before']({ tool: 'bash' }, { args: { command: `git -C ${target} commit -m test` } });
  });

  await test('metadata is honest about stable v1 support and beta v2 non-compatibility', () => {
    const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', 'opencode', 'metadata.json'), 'utf8'));
    assert.strictEqual(metadata.live_verification.status, 'verified');
    assert.strictEqual(metadata.live_verification.date, '2026-08-13');
    assert.match(metadata.live_verification.note, /5\/5 rules/);
    assert.match(metadata.runtime_contract.product.note, /stable v1/);
    assert.match(metadata.runtime_contract.product.note, /v2.*not claimed/i);
    assert.deepStrictEqual(metadata.hook_compiler.native_policies.sort(),
      ['commit-current-work', 'commit-test-coverage']);
    assert.deepStrictEqual(metadata.hook_compiler.fallback_policies, ['review-before-stop']);
    assert.strictEqual(metadata.tier, 'T2');
    assert.strictEqual(metadata.capabilities.conductor_emitted.reflector_loop,
      'recipe-manual-command');
  });

  process.stdout.write(`PASS: OpenCode adapter ${passed}/5\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
