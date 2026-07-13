#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const routing = require('../bin/model-routing.js');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
let failures = 0;

function ok(name) { process.stdout.write(`OK   [model-routing] ${name}\n`); }
function bad(name, error) {
  failures++;
  process.stderr.write(`FAIL [model-routing] ${name}: ${error && error.message ? error.message : error}\n`);
}
async function check(name, fn) {
  try { await fn(); ok(name); } catch (error) { bad(name, error); }
}
function temp(name) { return fs.mkdtempSync(path.join(os.tmpdir(), `conductor-model-${name}-`)); }
function run(args, opts = {}) {
  return spawnSync(process.execPath, [CLI, ...args], { cwd: ROOT, encoding: 'utf8', ...opts });
}
function digest(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function files(dir) {
  const out = [];
  function walk(current) {
    for (const item of fs.readdirSync(current, { withFileTypes: true })) {
      const abs = path.join(current, item.name);
      if (item.isDirectory()) walk(abs); else out.push(path.relative(dir, abs));
    }
  }
  walk(dir);
  return out.sort();
}

(async () => {
  await check('model-routing source stays text-only (no embedded NUL bytes)', () => {
    const source = fs.readFileSync(path.join(ROOT, 'bin', 'model-routing.js'));
    assert.strictEqual(source.includes(0), false);
  });

  await check('one confirmation accepts all six recommended mappings', async () => {
    const answers = [''];
    const output = { value: '', write(chunk) { this.value += chunk; } };
    const choices = await routing.collectChoices(routing.TOOLS, async () => answers.shift(), output);
    assert.deepStrictEqual(choices, routing.defaultChoices(routing.TOOLS));
    assert.match(output.value, /Claude Code/);
    assert.match(output.value, /Windsurf/);
  });

  await check('customization asks exactly three immutable Tier values for the selected adapter', async () => {
    const answers = ['customize', 'customize', 'claude-complex', 'claude-routine', 'claude-trivial'];
    let asks = 0;
    const output = { write() {} };
    const choices = await routing.collectChoices(['claude'], async () => { asks++; return answers.shift(); }, output);
    assert.strictEqual(asks, 5);
    assert.deepStrictEqual(choices.claude, { 1: 'claude-complex', 2: 'claude-routine', 3: 'claude-trivial' });
  });

  await check('non-interactive first install fails closed with zero residue', () => {
    const dir = temp('noninteractive');
    const result = run(['init', '--target=claude', dir, '--no-prompt']);
    assert.strictEqual(result.status, 2);
    assert.deepStrictEqual(files(dir), []);
    assert.match(result.stderr, /model setup required/);
  });

  await check('all six direct adapter entry points fail closed through the CLI setup gate', () => {
    for (const tool of routing.TOOLS) {
      const dir = temp(`direct-${tool}`);
      const transform = path.join(ROOT, 'adapters', tool, 'transform.sh');
      const result = spawnSync('bash', [transform, dir, '--no-prompt'], {
        cwd: ROOT, encoding: 'utf8', env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '' },
      });
      assert.strictEqual(result.status, 2, `${tool}: ${result.stderr}`);
      assert.deepStrictEqual(files(dir), [], tool);
      assert.match(result.stderr, /model setup required/, tool);
    }
  });

  await check('forged CLI-dispatch environment and proof fd cannot bypass first-use setup', () => {
    const dir = temp('forged-dispatch-env');
    const transform = path.join(ROOT, 'adapters', 'gemini', 'transform.sh');
    let result = spawnSync('bash', [transform, dir, '--no-prompt'], {
      cwd: ROOT, encoding: 'utf8', env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '1' },
    });
    assert.strictEqual(result.status, 2, result.stderr);
    assert.match(result.stderr, /model setup required/);
    assert.deepStrictEqual(files(dir), []);

    const fdDir = temp('forged-dispatch-fd');
    const proofFd = fs.openSync(path.join(ROOT, 'bin', 'omniconductor.js'), 'r');
    try {
      result = spawnSync('bash', [transform, fdDir, '--no-prompt'], {
        cwd: ROOT,
        encoding: 'utf8',
        env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '1' },
        stdio: ['ignore', 'pipe', 'pipe', proofFd],
      });
    } finally { fs.closeSync(proofFd); }
    assert.strictEqual(result.status, 2, result.stderr);
    assert.match(result.stderr, /model-routing\.json is missing|valid Gemini Tier routing is required/);
    assert.deepStrictEqual(files(fdDir), []);
  });

  await check('direct adapter no-arg and help behavior never defaults to the current directory', () => {
    for (const tool of routing.TOOLS) {
      const dir = temp(`direct-usage-${tool}`);
      const transform = path.join(ROOT, 'adapters', tool, 'transform.sh');
      let result = spawnSync('bash', [transform], {
        cwd: dir, encoding: 'utf8', env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '' },
      });
      assert.strictEqual(result.status, 1, `${tool}: ${result.stderr}`);
      assert.match(result.stderr, /target-project path is required/, tool);
      assert.deepStrictEqual(files(dir), [], tool);
      result = spawnSync('bash', [transform, '--help'], {
        cwd: dir, encoding: 'utf8', env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '' },
      });
      assert.strictEqual(result.status, 0, `${tool}: ${result.stderr}`);
      assert.match(result.stdout, new RegExp(`Usage: bash adapters/${tool}/transform\\.sh`), tool);
      assert.deepStrictEqual(files(dir), [], tool);
    }
  });

  await check('direct adapter preserves spaced argv and returns through one CLI dispatch', () => {
    const parent = temp('direct-argv');
    const dir = path.join(parent, 'project with spaces');
    fs.mkdirSync(dir);
    const transform = path.join(ROOT, 'adapters', 'claude', 'transform.sh');
    const result = spawnSync('bash', [transform, dir, '--no-prompt', '--accept-model-defaults', '--recipes=tdd'], {
      cwd: ROOT, encoding: 'utf8', env: { ...process.env, CONDUCTOR_CLI_DISPATCH: '' },
    });
    assert.strictEqual(result.status, 0, result.stderr);
    assert.ok(fs.existsSync(path.join(dir, '.claude', 'rules', 'tdd.md')));
    assert.ok(fs.existsSync(path.join(dir, '.conductor', 'model-routing.json')));
    assert.ok(fs.existsSync(path.join(dir, '.conductor', 'manifests', 'claude.json')));
  });

  await check('explicit default acceptance saves once and compiled roles match all six mappings', () => {
    const dir = temp('defaults');
    const result = run(['init', '--target=all', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const config = routing.loadConfig(dir);
    assert.deepStrictEqual(routing.missingTargets(config, routing.TOOLS), []);
    assert.strictEqual(config.adapters.claude.tiers['1'].mode, 'family-alias');
    assert.strictEqual(config.adapters.gemini.tiers['1'].mode, 'semantic-alias');
    assert.strictEqual(config.adapters.windsurf.tiers['1'].mode, 'adaptive-session');
    assert.match(fs.readFileSync(path.join(dir, '.claude/agents/planner.md'), 'utf8'), /^model: opus$/m);
    assert.match(fs.readFileSync(path.join(dir, '.claude/agents/utility.md'), 'utf8'), /^model: haiku$/m);
    assert.match(fs.readFileSync(path.join(dir, '.cursor/agents/planner.md'), 'utf8'), /^model: gpt-5\.6-sol$/m);
    assert.match(fs.readFileSync(path.join(dir, '.cursor/agents/utility.md'), 'utf8'), /^model: gpt-5\.6-luna$/m);
    assert.match(fs.readFileSync(path.join(dir, '.github/agents/scribe.agent.md'), 'utf8'), /^model: gpt-5\.6-terra$/m);
    assert.match(fs.readFileSync(path.join(dir, '.github/agents/utility.agent.md'), 'utf8'), /^model: gpt-5\.6-luna$/m);
    assert.match(fs.readFileSync(path.join(dir, '.gemini/agents/helper.md'), 'utf8'), /^model: flash$/m);
    assert.match(fs.readFileSync(path.join(dir, '.gemini/agents/utility.md'), 'utf8'), /^model: flash-lite$/m);
    assert.match(fs.readFileSync(path.join(dir, '.codex/agents/helper.toml'), 'utf8'), /^model = "gpt-5\.6-terra"$/m);
    assert.match(fs.readFileSync(path.join(dir, '.codex/agents/helper.toml'), 'utf8'), /^model_reasoning_effort = "medium"$/m);
    assert.match(fs.readFileSync(path.join(dir, '.codex/agents/utility.toml'), 'utf8'), /^model = "gpt-5\.6-luna"$/m);
    assert.match(fs.readFileSync(path.join(dir, '.codex/agents/utility.toml'), 'utf8'), /^model_reasoning_effort = "low"$/m);
    assert.match(fs.readFileSync(path.join(dir, '.windsurf/workflows/planner.md'), 'utf8'), /select \*\*Adaptive\*\*/);
  });

  await check('repeat install reuses the saved revision without prompting or rewriting config', () => {
    const dir = temp('repeat');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const file = path.join(dir, routing.CONFIG_REL);
    const before = digest(file);
    const revision = routing.loadConfig(dir).config_revision;
    result = run(['init', '--target=claude', dir, '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(digest(file), before);
    assert.strictEqual(routing.loadConfig(dir).config_revision, revision);
  });

  await check('adding another adapter fails closed until only that adapter is configured', async () => {
    const dir = temp('incremental');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    result = run(['init', '--target=gemini', dir, '--no-prompt']);
    assert.strictEqual(result.status, 2);
    assert.ok(!fs.existsSync(path.join(dir, '.gemini')));
    await routing.configure({
      targetAbs: dir, targets: ['gemini'], choices: { gemini: { 1: 'pro', 2: 'flash', 3: 'flash-lite' } }, generatorVersion: 'test',
    });
    result = run(['init', '--target=gemini', dir, '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.deepStrictEqual(routing.missingTargets(routing.loadConfig(dir), ['claude', 'gemini']), []);
  });

  await check('models configure regenerates already-installed native roles and keeps Tier difficulty', async () => {
    const dir = temp('regenerate');
    await routing.configure({
      targetAbs: dir,
      targets: ['claude'],
      choices: { claude: { 1: 'custom-complex', 2: 'custom-routine', 3: 'custom-trivial' } },
      generatorVersion: 'test',
    });
    let result = run(['init', '--target=claude', dir, '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.match(fs.readFileSync(path.join(dir, '.claude/agents/planner.md'), 'utf8'), /^model: custom-complex$/m);
    result = run(['models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults', '--force']);
    assert.strictEqual(result.status, 0, result.stderr);
    const planner = fs.readFileSync(path.join(dir, '.claude/agents/planner.md'), 'utf8');
    assert.match(planner, /^model: opus$/m);
    assert.match(planner, /Tier 1 — conceptual \/ complex/);
    assert.strictEqual(routing.loadConfig(dir).config_revision, 2);
  });

  await check('strict installs can be intentionally regenerated only when their own manifest exists', async () => {
    const dir = temp('strict-regenerate');
    await routing.configure({
      targetAbs: dir, targets: ['claude'],
      choices: { claude: { 1: 'strict-complex', 2: 'strict-routine', 3: 'strict-trivial' } },
      generatorVersion: 'test',
    });
    let result = run(['init', '--target=claude', dir, '--mode=strict', '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
    result = run(['models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.match(fs.readFileSync(path.join(dir, '.claude/agents/planner.md'), 'utf8'), /^model: opus$/m);
    assert.strictEqual(JSON.parse(fs.readFileSync(path.join(dir, '.conductor/manifests/claude.json'), 'utf8')).mode, 'strict');
  });

  await check('Windsurf opt-in Reflector participates in advisory reconfiguration and doctor truth', () => {
    const dir = temp('windsurf-reflector');
    let result = run(['init', '--target=windsurf', dir, '--no-prompt', '--accept-model-defaults', '--recipes=self-improvement']);
    assert.strictEqual(result.status, 0, result.stderr);
    result = run(['models', 'configure', '--target=windsurf', dir, '--no-prompt', '--accept-model-defaults', '--force']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.match(fs.readFileSync(path.join(dir, '.devin/rules/reflector.md'), 'utf8'), /select \*\*Adaptive\*\*/);
    result = run(['doctor', dir, '--json']);
    const report = JSON.parse(result.stdout);
    assert.ok(!report.checks.some((entry) => entry.id === 'D11' && entry.status === 'FAIL'), result.stdout);
  });

  await check('installed-role reconfiguration rolls back config, roles, and manifest on failure', () => {
    const dir = temp('transaction-rollback');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const watched = [routing.CONFIG_REL, '.conductor/manifests/claude.json', ...[
      'planner', 'reviewer', 'code-reviewer', 'builder', 'helper', 'designer', 'scribe', 'utility',
    ].map((role) => `.claude/agents/${role}.md`)];
    const before = Object.fromEntries(watched.map((rel) => [rel, digest(path.join(dir, rel))]));
    const script = `require(${JSON.stringify(path.join(ROOT, 'bin/model-routing.js'))}).configure({`+
      `targetAbs:${JSON.stringify(dir)},targets:['claude'],choices:{claude:{1:'tx-complex',2:'tx-routine',3:'tx-trivial'}},generatorVersion:'test'`+
      `}).then(()=>process.exit(0)).catch(e=>{process.stderr.write(e.message);process.exit(2)})`;
    result = spawnSync(process.execPath, ['-e', script], {
      cwd: ROOT, encoding: 'utf8', env: { ...process.env, CONDUCTOR_TEST_FAIL_MODEL_TRANSACTION_AFTER: '2' },
    });
    assert.strictEqual(result.status, 2, result.stderr);
    assert.match(result.stderr, /injected/);
    for (const rel of watched) assert.strictEqual(digest(path.join(dir, rel)), before[rel], rel);
    assert.strictEqual(fs.existsSync(path.join(dir, '.conductor/model-routing-transaction.json')), false);
    assert.strictEqual(fs.existsSync(path.join(dir, '.conductor/model-routing.lock')), false);
  });

  await check('crash journal and stale lock recover the last complete mapping before retry', () => {
    const dir = temp('transaction-crash');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const configBefore = digest(path.join(dir, routing.CONFIG_REL));
    const plannerBefore = digest(path.join(dir, '.claude/agents/planner.md'));
    const script = `require(${JSON.stringify(path.join(ROOT, 'bin/model-routing.js'))}).configure({`+
      `targetAbs:${JSON.stringify(dir)},targets:['claude'],choices:{claude:{1:'crash-complex',2:'crash-routine',3:'crash-trivial'}},generatorVersion:'test'`+
      `}).then(()=>process.exit(0)).catch(()=>process.exit(2))`;
    result = spawnSync(process.execPath, ['-e', script], {
      cwd: ROOT, encoding: 'utf8', env: { ...process.env, CONDUCTOR_TEST_CRASH_MODEL_TRANSACTION_AFTER: '1' },
    });
    assert.strictEqual(result.status, 86);
    assert.ok(fs.existsSync(path.join(dir, '.conductor/model-routing-transaction.json')));
    const ownerFile = path.join(dir, '.conductor/model-routing.lock/owner.json');
    const owner = JSON.parse(fs.readFileSync(ownerFile, 'utf8'));
    owner.created_at = new Date(Date.now() - 120_000).toISOString();
    fs.writeFileSync(ownerFile, `${JSON.stringify(owner)}\n`);
    result = run(['models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(digest(path.join(dir, routing.CONFIG_REL)), configBefore);
    assert.strictEqual(digest(path.join(dir, '.claude/agents/planner.md')), plannerBefore);
    assert.strictEqual(fs.existsSync(path.join(dir, '.conductor/model-routing-transaction.json')), false);
    assert.strictEqual(fs.existsSync(path.join(dir, '.conductor/model-routing.lock')), false);
  });

  await check('user-modified managed role aborts reconfiguration before every write', () => {
    const dir = temp('role-drift');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const configFile = path.join(dir, routing.CONFIG_REL);
    const manifestFile = path.join(dir, '.conductor/manifests/claude.json');
    const configBefore = digest(configFile);
    const manifestBefore = digest(manifestFile);
    const planner = path.join(dir, '.claude/agents/planner.md');
    fs.appendFileSync(planner, '\nuser customization\n');
    result = run(['models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults', '--force']);
    assert.strictEqual(result.status, 2, result.stderr);
    assert.match(result.stderr, /managed role was modified/);
    assert.strictEqual(digest(configFile), configBefore);
    assert.strictEqual(digest(manifestFile), manifestBefore);
    assert.match(fs.readFileSync(planner, 'utf8'), /user customization/);
  });

  await check('concurrent installed reconfigurations serialize to one fully consistent revision', async () => {
    const dir = temp('installed-concurrent');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const child = (prefix) => new Promise((resolve) => {
      const script = `require(${JSON.stringify(path.join(ROOT, 'bin/model-routing.js'))}).configure({`+
        `targetAbs:${JSON.stringify(dir)},targets:['claude'],choices:{claude:{1:'${prefix}-complex',2:'${prefix}-routine',3:'${prefix}-trivial'}},generatorVersion:'test'`+
        `}).then(()=>process.exit(0)).catch(e=>{process.stderr.write(e.message);process.exit(2)})`;
      const proc = spawn(process.execPath, ['-e', script], { cwd: ROOT, stdio: 'ignore' });
      proc.on('exit', resolve);
    });
    const codes = await Promise.all([child('alpha'), child('beta')]);
    assert.deepStrictEqual(codes, [0, 0]);
    const config = routing.loadConfig(dir);
    assert.strictEqual(config.config_revision, 3);
    const final = config.adapters.claude.tiers['1'].resolved;
    assert.ok(['alpha-complex', 'beta-complex'].includes(final));
    assert.match(fs.readFileSync(path.join(dir, '.claude/agents/planner.md'), 'utf8'), new RegExp(`^model: ${final}$`, 'm'));
    result = run(['doctor', dir, '--json']);
    const report = JSON.parse(result.stdout);
    assert.ok(!report.checks.some((entry) => entry.id === 'D11' && entry.status === 'FAIL'), result.stdout);
  });

  await check('init holds the routing lock through adapter writes while reconfiguration waits', async () => {
    const dir = temp('init-configure-race');
    let result = run(['models', 'configure', '--target=gemini', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);

    const fixture = temp('delayed-bash');
    const marker = path.join(fixture, 'adapter-entered');
    const release = path.join(fixture, 'release-adapter');
    const fakeBin = path.join(fixture, 'bin');
    fs.mkdirSync(fakeBin);
    const fakeBash = path.join(fakeBin, 'bash');
    fs.writeFileSync(fakeBash, `#!/bin/bash\ncase "\${1:-}" in *adapters/gemini/transform.sh) : > ${JSON.stringify(marker)}; while [ ! -e ${JSON.stringify(release)} ]; do sleep 0.01; done ;; esac\nexec /bin/bash "$@"\n`);
    fs.chmodSync(fakeBash, 0o755);

    const waitExit = (child) => new Promise((resolve) => child.on('exit', (code) => resolve(code)));
    const waitForMarker = () => new Promise((resolve, reject) => {
      const deadline = Date.now() + 5000;
      const poll = () => {
        if (fs.existsSync(marker)) return resolve();
        if (Date.now() >= deadline) return reject(new Error('delayed adapter did not start'));
        setTimeout(poll, 10);
      };
      poll();
    });

    const install = spawn(process.execPath, [CLI, 'init', '--target=gemini', dir, '--no-prompt'], {
      cwd: ROOT,
      env: { ...process.env, PATH: `${fakeBin}${path.delimiter}${process.env.PATH || ''}` },
      stdio: 'ignore',
    });
    await waitForMarker();

    const configureScript = `require(${JSON.stringify(path.join(ROOT, 'bin/model-routing.js'))}).configure({`+
      `targetAbs:${JSON.stringify(dir)},targets:['gemini'],choices:{gemini:{1:'race-pro',2:'race-flash',3:'race-lite'}},generatorVersion:'test'`+
      `}).then(()=>process.exit(0)).catch(e=>{process.stderr.write(e.message);process.exit(2)})`;
    let configureExited = false;
    const configure = spawn(process.execPath, ['-e', configureScript], { cwd: ROOT, stdio: 'ignore' });
    configure.on('exit', () => { configureExited = true; });
    await new Promise((resolve) => setTimeout(resolve, 150));
    assert.strictEqual(configureExited, false, 'reconfiguration crossed the active install lock');

    fs.writeFileSync(release, 'go\n');
    assert.strictEqual(await waitExit(install), 0);
    assert.strictEqual(await waitExit(configure), 0);
    const config = routing.loadConfig(dir);
    assert.strictEqual(config.adapters.gemini.tiers['1'].resolved, 'race-pro');
    assert.match(fs.readFileSync(path.join(dir, '.gemini/agents/planner.md'), 'utf8'), /^model: race-pro$/m);
    result = run(['doctor', dir, '--json']);
    const report = JSON.parse(result.stdout);
    assert.ok(!report.checks.some((entry) => entry.id === 'D11' && entry.status === 'FAIL'), result.stdout);
  });

  await check('adapter-specific validation rejects injection and unsupported Windsurf pins before writes', async () => {
    for (const [tool, value] of [
      ['claude', 'bad/model'], ['codex', '$(touch-x)'], ['gemini', 'bad value'],
      ['copilot', 'bad\nmodel'], ['cursor', '../../bad'], ['windsurf', 'gpt-5.6-sol'],
    ]) {
      const dir = temp(`invalid-${tool}`);
      const choices = { [tool]: { 1: value, 2: routing.RECOMMENDED[tool][2], 3: routing.RECOMMENDED[tool][3] } };
      await assert.rejects(() => routing.configure({ targetAbs: dir, targets: [tool], choices, generatorVersion: 'test' }));
      assert.deepStrictEqual(files(dir), []);
    }
    assert.strictEqual(routing.validateModel('cursor', 'model[effort=high]'), null);
  });

  await check('saved schema rejects enforcement and Tier-metadata claims that contradict tool capabilities', async () => {
    const dir = temp('schema-invariants');
    await routing.configure({
      targetAbs: dir,
      targets: ['gemini', 'windsurf'],
      choices: {
        gemini: { 1: 'pro', 2: 'flash', 3: 'flash-lite' },
        windsurf: { 1: 'adaptive', 2: 'adaptive', 3: 'adaptive' },
      },
      generatorVersion: 'test',
    });
    const original = routing.loadConfig(dir);
    const corrupt = (mutate) => {
      const copy = JSON.parse(JSON.stringify(original));
      mutate(copy);
      return routing.validateConfig(copy);
    };
    assert.match(corrupt((c) => { c.adapters.windsurf.enforcement = 'native-agent-model'; }), /enforcement/);
    assert.match(corrupt((c) => { c.adapters.windsurf.tiers['1'].mode = 'exact'; }), /mode/);
    assert.match(corrupt((c) => { c.adapters.gemini.tiers['1'].validation = 'catalog-verified'; }), /validation/);
    assert.match(corrupt((c) => { c.adapters.gemini.tiers['1'].requested = 'different'; }), /requested\/resolved/);
    assert.match(corrupt((c) => { c.adapters.gemini.tiers['1'].validated_at = 'not-a-date'; }), /validated_at/);
  });

  await check('--force never deletes invalid unselected adapter state during a partial repair', async () => {
    const dir = temp('force-partial-repair');
    await routing.configure({
      targetAbs: dir,
      targets: routing.TOOLS,
      choices: routing.defaultChoices(routing.TOOLS),
      generatorVersion: 'test',
    });
    const file = path.join(dir, routing.CONFIG_REL);
    const corrupt = JSON.parse(fs.readFileSync(file, 'utf8'));
    corrupt.adapters.windsurf.enforcement = 'native-agent-model';
    fs.writeFileSync(file, `${JSON.stringify(corrupt, null, 2)}\n`);
    const before = fs.readFileSync(file, 'utf8');
    let result = run(['models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults', '--force']);
    assert.strictEqual(result.status, 2, result.stderr);
    assert.match(result.stderr, /invalid unselected adapter state/);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), before);
    result = run(['models', 'configure', '--target=all', dir, '--no-prompt', '--accept-model-defaults', '--force']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.deepStrictEqual(Object.keys(routing.loadConfig(dir).adapters).sort(), [...routing.TOOLS].sort());
  });

  await check('Cursor catalog validation accepts a supported base model with a native parameter block', async () => {
    const bin = temp('cursor-catalog-bin');
    const target = temp('cursor-catalog-target');
    const agent = path.join(bin, 'agent');
    fs.writeFileSync(agent, '#!/bin/sh\nprintf "claude-opus-4-8\\ninherit\\n"\n');
    fs.chmodSync(agent, 0o755);
    const priorPath = process.env.PATH;
    process.env.PATH = `${bin}${path.delimiter}${priorPath || ''}`;
    try {
      await routing.configure({
        targetAbs: target,
        targets: ['cursor'],
        choices: { cursor: { 1: 'claude-opus-4-8[effort=high,context=300k]', 2: 'claude-opus-4-8', 3: 'inherit' } },
        generatorVersion: 'test',
      });
    } finally {
      process.env.PATH = priorPath;
    }
    const config = routing.loadConfig(target);
    assert.strictEqual(config.adapters.cursor.tiers['1'].validation, 'catalog-base-verified');
    assert.strictEqual(config.adapters.cursor.tiers['1'].resolved, 'claude-opus-4-8[effort=high,context=300k]');
    let result = run(['init', '--target=cursor', target, '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
    result = spawnSync('bash', [path.join(ROOT, 'tools/validate-adapter-output.sh'), target, 'cursor'], { cwd: ROOT, encoding: 'utf8' });
    assert.strictEqual(result.status, 0, result.stdout + result.stderr);
  });

  await check('invalid, symlinked, and hard-linked config files fail safely', () => {
    const dir = temp('unsafe-file');
    fs.mkdirSync(path.join(dir, '.conductor'));
    const outside = path.join(dir, 'outside.json');
    fs.writeFileSync(outside, '{}\n');
    const file = path.join(dir, routing.CONFIG_REL);
    fs.symlinkSync(outside, file);
    assert.throws(() => routing.loadConfig(dir), /regular file/);
    fs.unlinkSync(file);
    fs.linkSync(outside, file);
    assert.throws(() => routing.loadConfig(dir), /hard-linked/);
    assert.strictEqual(fs.readFileSync(outside, 'utf8'), '{}\n');
  });

  await check('concurrent first configuration converges on one valid revision with no lock/temp residue', async () => {
    const dir = temp('concurrent');
    const children = Array.from({ length: 12 }, () => new Promise((resolve) => {
      const child = spawn(process.execPath, [CLI, 'models', 'configure', '--target=claude', dir, '--no-prompt', '--accept-model-defaults'], {
        cwd: ROOT, stdio: 'ignore',
      });
      child.on('exit', (code) => resolve(code));
    }));
    const codes = await Promise.all(children);
    assert.ok(codes.some((code) => code === 0));
    const config = routing.loadConfig(dir);
    assert.strictEqual(config.config_revision, 1);
    assert.deepStrictEqual(routing.missingTargets(config, ['claude']), []);
    const leftovers = fs.readdirSync(path.join(dir, '.conductor')).filter((name) => name.includes('.tmp') || name.endsWith('.lock'));
    assert.deepStrictEqual(leftovers, []);
  });

  await check('a crashed process stale lock is reclaimed without weakening live-lock ownership', async () => {
    const dir = temp('stale-lock');
    const lock = path.join(dir, '.conductor', 'model-routing.lock');
    fs.mkdirSync(lock, { recursive: true });
    fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({
      pid: 2147483647,
      created_at: new Date(Date.now() - 120_000).toISOString(),
    }) + '\n');
    await routing.configure({
      targetAbs: dir,
      targets: ['claude'],
      choices: { claude: { 1: 'opus', 2: 'sonnet', 3: 'haiku' } },
      generatorVersion: 'test',
    });
    assert.ok(routing.loadConfig(dir));
    assert.strictEqual(fs.existsSync(lock), false);
  });

  await check('doctor D11 compares saved routing with real roles and rejects Windsurf model pins', () => {
    const dir = temp('doctor-output');
    let result = run(['init', '--target=all', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const cursorRole = path.join(dir, '.cursor', 'agents', 'planner.md');
    fs.writeFileSync(cursorRole, fs.readFileSync(cursorRole, 'utf8').replace(/^model: .*$/m, 'model: wrong-model'));
    const windsurfRole = path.join(dir, '.windsurf', 'workflows', 'planner.md');
    fs.writeFileSync(windsurfRole, fs.readFileSync(windsurfRole, 'utf8').replace(
      /^description: .*$/m,
      (line) => `${line}\nmodel: gpt-5.6-sol`,
    ));
    result = run(['doctor', dir, '--json']);
    assert.strictEqual(result.status, 2, result.stdout);
    const report = JSON.parse(result.stdout);
    const d11 = report.checks.find((entry) => entry.id === 'D11' && entry.status === 'FAIL');
    assert.ok(d11, result.stdout);
    assert.match(d11.detail, /cursor:planner/);
    assert.match(d11.detail, /windsurf:planner declares unsupported workflow-local model/);
  });

  await check('doctor treats missing routing on a current v1.1 install as a failure', () => {
    const dir = temp('doctor-missing-current-routing');
    let result = run(['init', '--target=gemini', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    fs.unlinkSync(path.join(dir, routing.CONFIG_REL));
    result = run(['doctor', dir, '--json']);
    assert.strictEqual(result.status, 2, result.stdout);
    const report = JSON.parse(result.stdout);
    assert.ok(report.checks.some((entry) => entry.id === 'D11' && entry.status === 'FAIL' && /v1\.1\+/.test(entry.detail)));
  });

  await check('cross-mode recipes-only manifests still require routing when they retain roles', () => {
    const dir = temp('doctor-cross-mode-routing');
    let result = run(['init', '--target=gemini', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    result = run(['init', '--target=gemini', dir, '--mode=recipes-only', '--recipes=tdd']);
    assert.strictEqual(result.status, 0, result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(dir, '.conductor/manifests/gemini.json'), 'utf8'));
    assert.strictEqual(manifest.mode, 'recipes-only');
    assert.ok(manifest.emitted_files.some((entry) => entry.path === '.gemini/agents/planner.md'));
    fs.unlinkSync(path.join(dir, routing.CONFIG_REL));
    result = run(['doctor', dir, '--json']);
    assert.strictEqual(result.status, 2, result.stdout);
    const report = JSON.parse(result.stdout);
    assert.ok(report.checks.some((entry) => entry.id === 'D11' && entry.status === 'FAIL' && /model-routing\.json is missing/.test(entry.detail)), result.stdout);
  });

  await check('uninstall retains adopter model choices for the next install', () => {
    const dir = temp('uninstall');
    let result = run(['init', '--target=claude', dir, '--no-prompt', '--accept-model-defaults']);
    assert.strictEqual(result.status, 0, result.stderr);
    const before = digest(path.join(dir, routing.CONFIG_REL));
    result = run(['init', '--target=claude', dir, '--uninstall']);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.strictEqual(digest(path.join(dir, routing.CONFIG_REL)), before);
    result = run(['init', '--target=claude', dir, '--no-prompt']);
    assert.strictEqual(result.status, 0, result.stderr);
  });

  process.exit(failures ? 1 : 0);
})().catch((error) => {
  bad('suite crashed', error);
  process.exit(1);
});
