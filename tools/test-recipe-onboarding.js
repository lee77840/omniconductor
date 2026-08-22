'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const onboarding = require('../bin/recipe-onboarding.js');

const root = path.resolve(__dirname, '..');
let passed = 0;
async function test(name, fn) {
  await fn();
  passed += 1;
  process.stdout.write(`PASS: ${name}\n`);
}
function fixture() { return fs.mkdtempSync(path.join(os.tmpdir(), 'recipe-onboarding-')); }
function sink() { return { chunks: [], write(value) { this.chunks.push(String(value)); } }; }
function manifest(dir, tool, recipes) {
  const target = path.join(dir, '.conductor', 'manifests');
  fs.mkdirSync(target, { recursive: true });
  fs.writeFileSync(path.join(target, `${tool}.json`), JSON.stringify({ recipes_enabled: recipes }));
}

(async () => {
  await test('catalog is an exact, duplicate-free inventory of every recipe source', async () => {
    const disk = fs.readdirSync(path.join(root, 'core', 'recipes'))
      .filter((name) => name.endsWith('.md') && name !== 'README.md').map((name) => name.slice(0, -3)).sort();
    const ids = onboarding.CATALOG.map((item) => item.id).sort();
    assert.deepStrictEqual(ids, disk);
    assert.strictEqual(new Set(ids).size, ids.length);
    assert.ok(onboarding.CATALOG.every((item) => ['automatic', 'recommended', 'consent'].includes(item.policy)));
    const byPolicy = (policy) => onboarding.CATALOG.filter((item) => item.policy === policy).map((item) => item.id).sort();
    assert.deepStrictEqual(byPolicy('automatic'), ['debugging', 'loop-engineering']);
    assert.deepStrictEqual(byPolicy('consent'), [
      'auto-mock-data', 'branch-strategy', 'database-change-assurance', 'git-hygiene', 'self-improvement',
    ]);
    assert.strictEqual(byPolicy('recommended').length, 10);
  });

  await test('fresh non-interactive installs receive only safe automatic defaults', async () => {
    const dir = fixture();
    const plan = await onboarding.resolveRecipePlan({
      targetAbs: dir, targets: ['claude', 'opencode'], mode: 'full', explicitRecipes: null,
      noPrompt: true, dryRun: false, ask: async () => { throw new Error('must not prompt'); }, output: sink(),
    });
    assert.deepStrictEqual(plan.byTool.claude, ['debugging', 'loop-engineering']);
    assert.deepStrictEqual(plan.byTool.opencode, plan.byTool.claude);
  });

  await test('project recommendations are detected once and consent defaults to none', async () => {
    const dir = fixture();
    fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({
      workspaces: ['apps/*'], devDependencies: { typescript: '1', vitest: '1', playwright: '1' },
      dependencies: { prisma: '1', 'react-native': '1', next: '1' },
    }));
    fs.mkdirSync(path.join(dir, '.git'));
    fs.mkdirSync(path.join(dir, 'prisma')); fs.writeFileSync(path.join(dir, 'prisma', 'schema.prisma'), 'model X {}');
    fs.mkdirSync(path.join(dir, 'apps'), { recursive: true }); fs.mkdirSync(path.join(dir, 'apps', 'web')); fs.mkdirSync(path.join(dir, 'apps', 'mobile'));
    const answers = ['y', ''];
    let asks = 0;
    const plan = await onboarding.resolveRecipePlan({
      targetAbs: dir, targets: ['claude', 'cursor', 'opencode'], mode: 'full', explicitRecipes: null,
      noPrompt: false, dryRun: false, ask: async () => { asks += 1; return answers.shift(); }, output: sink(),
    });
    assert.strictEqual(asks, 2, 'recommendation and consent must be grouped, not asked per adapter/recipe');
    assert.ok(plan.byTool.claude.includes('coding-conventions'));
    assert.ok(plan.byTool.claude.includes('database-discipline'));
    assert.ok(plan.byTool.claude.includes('web-mobile-parity'));
    assert.ok(!plan.byTool.claude.includes('self-improvement'));
    assert.deepStrictEqual(plan.byTool.cursor, plan.byTool.claude);
  });

  await test('updates preserve each adapter selection by default without adding new defaults', async () => {
    const dir = fixture();
    manifest(dir, 'claude', []);
    manifest(dir, 'opencode', ['self-improvement']);
    const plan = await onboarding.resolveRecipePlan({
      targetAbs: dir, targets: ['claude', 'opencode'], mode: 'full', explicitRecipes: null,
      noPrompt: true, dryRun: false, ask: async () => { throw new Error('must not prompt'); }, output: sink(),
    });
    assert.deepStrictEqual(plan.byTool.claude, []);
    assert.deepStrictEqual(plan.byTool.opencode, ['self-improvement']);
  });

  await test('explicit list is exact and explicit empty disables every recipe', async () => {
    const dir = fixture();
    let plan = await onboarding.resolveRecipePlan({
      targetAbs: dir, targets: ['claude'], mode: 'full', explicitRecipes: 'tdd,self-improvement',
      noPrompt: true, dryRun: false, ask: async () => '', output: sink(),
    });
    assert.deepStrictEqual(plan.byTool.claude, ['tdd', 'self-improvement']);
    plan = await onboarding.resolveRecipePlan({
      targetAbs: dir, targets: ['claude'], mode: 'full', explicitRecipes: '',
      noPrompt: true, dryRun: false, ask: async () => '', output: sink(),
    });
    assert.deepStrictEqual(plan.byTool.claude, []);
    assert.throws(() => onboarding.normalizeRecipes('not-real'), /unknown recipe/);
  });

  await test('invalid onboarding fails before model or adapter state is written', async () => {
    const dir = fixture();
    const run = childProcess.spawnSync(process.execPath, [
      path.join(root, 'bin', 'omniconductor.js'), 'init', '--target=claude', dir,
      '--no-prompt', '--accept-model-defaults', '--recipes=not-real',
    ], { encoding: 'utf8' });
    assert.strictEqual(run.status, 2, run.stderr);
    assert.match(run.stderr, /recipe onboarding failed before installation: unknown recipe/);
    assert.ok(!fs.existsSync(path.join(dir, '.conductor', 'model-routing.json')));
    assert.ok(!fs.existsSync(path.join(dir, '.conductor', 'manifests', 'claude.json')));
  });

  process.stdout.write(`PASS: recipe onboarding contract ${passed}/${passed}\n`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
