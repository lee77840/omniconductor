'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const conflicts = require('../bin/install-conflicts.js');

const root = path.resolve(__dirname, '..');
let passed = 0;
function fixture() { return fs.mkdtempSync(path.join(os.tmpdir(), 'install-conflicts-')); }
function sink() { return { chunks: [], write(value) { this.chunks.push(String(value)); } }; }
async function test(name, fn) { await fn(); passed += 1; process.stdout.write(`PASS: ${name}\n`); }
function cli(target, ...args) {
  let tool = 'claude';
  if (args[0] && args[0].startsWith('tool:')) tool = args.shift().slice('tool:'.length);
  return childProcess.spawnSync(process.execPath, [path.join(root, 'bin', 'omniconductor.js'), 'init', `--target=${tool}`, target, ...args], { encoding: 'utf8' });
}

(async () => {
  await test('scanner reports unmanaged surfaces but ignores structurally merged config', async () => {
    const dir = fixture();
    fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
    fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), '{}\n');
    assert.deepStrictEqual(conflicts.scan(dir, ['claude']), [{ tool: 'claude', path: 'CLAUDE.md' }]);
  });

  await test('existing hook registries and handler directories remain safe-merge inputs', async () => {
    const dir = fixture();
    fs.mkdirSync(path.join(dir, '.github', 'hooks'), { recursive: true });
    fs.writeFileSync(path.join(dir, '.github', 'hooks', 'user-handler.sh'), 'exit 0\n');
    fs.writeFileSync(path.join(dir, '.github', 'hooks', 'hooks.json'), '{}\n');
    assert.deepStrictEqual(conflicts.scan(dir, ['copilot']), []);
  });

  await test('authoritative adapter manifest marks the same surface as an update', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'managed\n');
    fs.mkdirSync(path.join(dir, '.conductor', 'manifests'), { recursive: true });
    fs.writeFileSync(path.join(dir, '.conductor', 'manifests', 'claude.json'), '{}\n');
    assert.deepStrictEqual(conflicts.scan(dir, ['claude']), []);
  });

  await test('non-interactive implicit full fails before every project write', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
    const before = fs.readFileSync(path.join(dir, 'CLAUDE.md'), 'utf8');
    const run = cli(dir, '--no-prompt', '--accept-model-defaults');
    assert.strictEqual(run.status, 2, run.stderr);
    assert.match(run.stderr, /existing unmanaged instructions require an explicit choice before any write/);
    assert.strictEqual(fs.readFileSync(path.join(dir, 'CLAUDE.md'), 'utf8'), before);
    assert.deepStrictEqual(fs.readdirSync(dir), ['CLAUDE.md']);
  });

  await test('explicit full remains an auditable backup-and-replace decision', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
    const run = cli(dir, '--no-prompt', '--accept-model-defaults', '--mode=full', '--recipes=');
    assert.strictEqual(run.status, 0, run.stderr);
    assert.notStrictEqual(fs.readFileSync(path.join(dir, 'CLAUDE.md'), 'utf8'), 'KEEP\n');
    const backups = fs.readdirSync(dir).filter((name) => name.startsWith('CLAUDE.md.conductor-backup-'));
    assert.strictEqual(backups.length, 1);
    assert.strictEqual(fs.readFileSync(path.join(dir, backups[0]), 'utf8'), 'KEEP\n');
  });

  await test('explicit recipes-only preserves the baseline byte-for-byte', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
    const run = cli(dir, '--no-prompt', '--conflict-policy=recipes-only', '--recipes=debugging');
    assert.strictEqual(run.status, 0, run.stderr);
    assert.strictEqual(fs.readFileSync(path.join(dir, 'CLAUDE.md'), 'utf8'), 'KEEP\n');
    assert.ok(fs.existsSync(path.join(dir, '.claude', 'rules', 'debugging.md')));
  });

  await test('recipes-only without a recipe and explicit abort both fail byte-free', async () => {
    for (const args of [
      ['--no-prompt', '--conflict-policy=recipes-only'],
      ['--no-prompt', '--conflict-policy=abort'],
    ]) {
      const dir = fixture();
      fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
      const run = cli(dir, ...args);
      assert.strictEqual(run.status, 2, run.stderr);
      assert.deepStrictEqual(fs.readdirSync(dir), ['CLAUDE.md']);
    }
  });

  await test('malformed and unknown conflict policies fail before every write', async () => {
    for (const args of [
      ['--no-prompt', '--conflict-policy'],
      ['--no-prompt', '--conflict-policy=merge-markdown'],
    ]) {
      const dir = fixture();
      fs.writeFileSync(path.join(dir, 'CLAUDE.md'), 'KEEP\n');
      const run = cli(dir, ...args);
      assert.strictEqual(run.status, 2, run.stderr);
      assert.deepStrictEqual(fs.readdirSync(dir), ['CLAUDE.md']);
    }
  });

  await test('interactive resolver offers preservation and validates the exact recipe list', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'AGENTS.md'), 'KEEP\n');
    const answers = ['1', 'debugging,tdd'];
    const output = sink();
    const plan = await conflicts.resolve({
      targetAbs: dir, targets: ['codex'], mode: 'full', modeExplicit: false,
      policy: null, explicitRecipes: null, noPrompt: false, dryRun: false,
      ask: async () => answers.shift(), output,
    });
    assert.strictEqual(plan.mode, 'recipes-only');
    assert.strictEqual(plan.explicitRecipes, 'debugging,tdd');
    assert.match(output.chunks.join(''), /Preserve existing instructions/);
  });

  await test('all seven adapters have an explicit unmanaged-surface contract', async () => {
    assert.deepStrictEqual(Object.keys(conflicts.SURFACES).sort(), ['claude', 'codex', 'copilot', 'cursor', 'gemini', 'opencode', 'windsurf']);
    assert.ok(Object.values(conflicts.SURFACES).every((items) => items.length > 0));
  });

  await test('all seven implicit installs reject their native unmanaged baseline byte-free', async () => {
    for (const tool of Object.keys(conflicts.SURFACES)) {
      const dir = fixture();
      const relative = conflicts.SURFACES[tool][0];
      const target = path.join(dir, ...relative.split('/'));
      if (path.extname(target) || path.basename(target).startsWith('.')) {
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, 'KEEP\n');
      } else {
        fs.mkdirSync(target, { recursive: true });
        fs.writeFileSync(path.join(target, 'keep.txt'), 'KEEP\n');
      }
      const run = cli(dir, `tool:${tool}`, '--no-prompt', '--accept-model-defaults');
      assert.strictEqual(run.status, 2, `${tool}: ${run.stderr}`);
      assert.ok(!fs.existsSync(path.join(dir, '.conductor')), `${tool}: conflict check must precede all state`);
    }
  });

  process.stdout.write(`PASS: install conflict contract ${passed}/${passed}\n`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
