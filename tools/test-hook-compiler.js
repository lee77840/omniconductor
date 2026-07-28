#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const {
  ADAPTERS,
  composeConfig,
  readRegistry,
  writeAtomic,
} = require('../bin/hook-config');

const ROOT = path.resolve(__dirname, '..');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-hook-compiler-'));
let passed = 0;

function test(name, fn) {
  try {
    fn();
    passed += 1;
    process.stdout.write(`OK   ${name}\n`);
  } catch (error) {
    process.stderr.write(`FAIL ${name}: ${error.stack || error.message}\n`);
    process.exitCode = 1;
  }
}

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: options.cwd || ROOT,
    env: { ...process.env, ...(options.env || {}) },
    input: options.input,
    encoding: 'utf8',
  });
}

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
}

function containsExactString(value, expected) {
  if (value === expected) return true;
  if (Array.isArray(value)) return value.some((item) => containsExactString(item, expected));
  if (value && typeof value === 'object') {
    return Object.values(value).some((item) => containsExactString(item, expected));
  }
  return false;
}

function configFixture(adapter) {
  if (['claude', 'gemini', 'codex'].includes(adapter)) {
    return {
      customSetting: { keep: true },
      hooks: {
        CustomEvent: [{
          matcher: 'custom',
          label: 'preserve-group',
          hooks: [{ type: 'command', command: 'user-owned-hook', extra: 7 }],
        }],
      },
    };
  }
  return {
    version: 1,
    customSetting: { keep: true },
    hooks: {
      customEvent: [{ command: 'user-owned-hook', extra: 7 }],
    },
  };
}

function adapterInstallArgs(adapter, target, uninstall = false) {
  const args = [`adapters/${adapter}/transform.sh`, target];
  if (uninstall) return [...args, '--uninstall'];
  if (adapter === 'windsurf') {
    return [...args, '--mode=reflector-only', '--no-prompt', '--accept-model-defaults'];
  }
  return [...args, '--no-prompt', '--accept-model-defaults'];
}

const registry = readRegistry();

test('registry validates all six first-class adapters', () => {
  assert.deepStrictEqual(Object.keys(registry.adapters).sort(), [...ADAPTERS].sort());
  assert(registry.registrations.some((item) => item.id === 'commit-current-work'));
  assert(registry.registrations.some((item) => item.id === 'commit-test-coverage'));
  assert(registry.registrations.some((item) => item.id === 'review-before-stop'));
});

test('flat configs preserve arbitrary keys, events, and user handlers', () => {
  const input = configFixture('cursor');
  const output = composeConfig(registry, 'cursor', input, ['baseline'], 'cursor-fixture');
  assert.deepStrictEqual(input, configFixture('cursor'));
  assert.deepStrictEqual(output.customSetting, { keep: true });
  assert.deepStrictEqual(output.hooks.customEvent, [{ command: 'user-owned-hook', extra: 7 }]);
  assert(output.hooks.stop.some((entry) => /stop-r6-review-check/.test(entry.command)));
});

test('nested configs preserve arbitrary keys, groups, and user handlers', () => {
  const input = configFixture('gemini');
  const output = composeConfig(registry, 'gemini', input, ['baseline', 'output-cap'], 'gemini-fixture');
  assert.deepStrictEqual(input, configFixture('gemini'));
  assert.deepStrictEqual(output.customSetting, { keep: true });
  assert.deepStrictEqual(output.hooks.CustomEvent[0].hooks[0],
    { type: 'command', command: 'user-owned-hook', extra: 7 });
  assert(output.hooks.AfterAgent.some((group) =>
    group.hooks.some((entry) => /stop-r6-review-check/.test(entry.command))));
});

test('owned handlers are replaced without duplicating user handlers', () => {
  const once = composeConfig(registry, 'codex', configFixture('codex'), ['baseline'], 'codex-fixture');
  const twice = composeConfig(registry, 'codex', once, ['baseline'], 'codex-fixture');
  assert.deepStrictEqual(twice, once);
  assert.strictEqual(twice.hooks.CustomEvent[0].hooks.filter((entry) =>
    entry.command === 'user-owned-hook').length, 1);
});

test('atomic write failure leaves original bytes and no temporary file', () => {
  const dir = path.join(TMP, 'atomic');
  const file = path.join(dir, 'hooks.json');
  fs.mkdirSync(dir, { recursive: true });
  const original = '{"custom":"byte-identical"}\n';
  fs.writeFileSync(file, original);
  process.env.CONDUCTOR_HOOK_COMPILER_FAIL_STAGE = 'before-rename';
  assert.throws(() => writeAtomic(file, '{"changed":true}\n'), /injected failure/);
  delete process.env.CONDUCTOR_HOOK_COMPILER_FAIL_STAGE;
  assert.strictEqual(fs.readFileSync(file, 'utf8'), original);
  assert.deepStrictEqual(fs.readdirSync(dir), ['hooks.json']);
});

for (const adapter of ['cursor', 'copilot', 'gemini', 'codex', 'windsurf']) {
  test(`${adapter} install/uninstall restores an existing hook config byte-for-byte`, () => {
    const target = path.join(TMP, `restore-${adapter}`);
    const rel = registry.adapters[adapter].config_path;
    const file = path.join(target, rel);
    const original = `${JSON.stringify(configFixture(adapter), null, adapter === 'cursor' ? 4 : 2)}\n`;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, original);
    const install = run('bash', adapterInstallArgs(adapter, target));
    assert.strictEqual(install.status, 0, install.stderr || install.stdout);
    const merged = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert.deepStrictEqual(merged.customSetting, { keep: true });
    const uninstall = run('bash', adapterInstallArgs(adapter, target, true));
    assert.strictEqual(uninstall.status, 0, uninstall.stderr || uninstall.stdout);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), original);
  });

  test(`${adapter} rejects an invalid config before any managed file is emitted`, () => {
    const target = path.join(TMP, `invalid-${adapter}`);
    const rel = registry.adapters[adapter].config_path;
    const file = path.join(target, rel);
    const original = '{"custom":"keep","hooks":[]}\n';
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, original);
    const install = run('bash', adapterInstallArgs(adapter, target));
    assert.strictEqual(install.status, 1, install.stderr || install.stdout);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), original);
    const files = [];
    const visit = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const absolute = path.join(dir, entry.name);
        if (entry.isDirectory()) visit(absolute);
        else files.push(path.relative(target, absolute));
      }
    };
    visit(target);
    assert.deepStrictEqual(files.sort(), ['.conductor/model-routing.json', rel].sort());
  });
}

test('native hook-directory user handlers survive install, reinstall, and uninstall', () => {
  const fixtures = {
    copilot: {
      script: '.github/hooks/conductor/my-lint-gate.sh',
      command: 'bash "$(git rev-parse --show-toplevel)/.github/hooks/conductor/my-lint-gate.sh"',
      config(command) {
        return { version: 1, owner: 'user', hooks: { preToolUse: [{ type: 'command', bash: command, timeoutSec: 17 }] } };
      },
    },
    gemini: {
      script: '.gemini/hooks/my-lint-gate.sh',
      command: 'bash "$GEMINI_PROJECT_DIR"/.gemini/hooks/my-lint-gate.sh',
      config(command) {
        return {
          owner: 'user',
          hooks: { BeforeTool: [{ matcher: 'run_shell_command', hooks: [{ type: 'command', command, timeout: 17000 }] }] },
        };
      },
    },
    codex: {
      script: '.codex/hooks/my-lint-gate.sh',
      command: 'bash "$(git rev-parse --show-toplevel)/.codex/hooks/my-lint-gate.sh"',
      config(command) {
        return {
          owner: 'user',
          hooks: { PreToolUse: [{ matcher: '^Bash$', hooks: [{ type: 'command', command, timeout: 17 }] }] },
        };
      },
    },
  };

  for (const [adapter, fixture] of Object.entries(fixtures)) {
    const target = path.join(TMP, `native-user-hook-${adapter}`);
    const configFile = path.join(target, registry.adapters[adapter].config_path);
    const scriptFile = path.join(target, fixture.script);
    const original = `${JSON.stringify(fixture.config(fixture.command), null, 2)}\n`;
    fs.mkdirSync(path.dirname(configFile), { recursive: true });
    writeExecutable(scriptFile, '#!/bin/sh\nexit 0\n');
    fs.writeFileSync(configFile, original);

    for (let pass = 0; pass < 2; pass += 1) {
      const install = run('bash', adapterInstallArgs(adapter, target));
      assert.strictEqual(install.status, 0, `${adapter} pass ${pass + 1}: ${install.stderr || install.stdout}`);
      const merged = JSON.parse(fs.readFileSync(configFile, 'utf8'));
      assert(containsExactString(merged, fixture.command), `${adapter} removed the user hook registration`);
      assert(fs.existsSync(scriptFile), `${adapter} removed the user hook script`);
    }

    const uninstall = run('bash', adapterInstallArgs(adapter, target, true));
    assert.strictEqual(uninstall.status, 0, uninstall.stderr || uninstall.stdout);
    assert.strictEqual(fs.readFileSync(configFile, 'utf8'), original, adapter);
    assert(fs.existsSync(scriptFile), `${adapter} removed the user hook script on uninstall`);
  }
});

test('fresh uninstall removes native guard directories without touching saved routing', () => {
  const hookDirs = {
    cursor: '.cursor/hooks',
    copilot: '.github/hooks/conductor',
    codex: '.codex/hooks',
  };
  for (const [adapter, hookDir] of Object.entries(hookDirs)) {
    const target = path.join(TMP, `fresh-uninstall-${adapter}`);
    fs.mkdirSync(target, { recursive: true });
    const install = run('bash', adapterInstallArgs(adapter, target));
    assert.strictEqual(install.status, 0, install.stderr || install.stdout);
    assert(fs.existsSync(path.join(target, hookDir)), adapter);
    const uninstall = run('bash', adapterInstallArgs(adapter, target, true));
    assert.strictEqual(uninstall.status, 0, uninstall.stderr || uninstall.stdout);
    assert(!fs.existsSync(path.join(target, hookDir)), adapter);
    assert(fs.existsSync(path.join(target, '.conductor/model-routing.json')), adapter);
  }
});

test('Copilot camelCase PreToolUse payload emits a native ask decision', () => {
  const repo = path.join(TMP, 'copilot-pretool');
  fs.mkdirSync(repo, { recursive: true });
  assert.strictEqual(run('git', ['init', '-q'], { cwd: repo }).status, 0);
  assert.strictEqual(run('git', ['config', 'user.email', 'test@example.invalid'], { cwd: repo }).status, 0);
  assert.strictEqual(run('git', ['config', 'user.name', 'CONDUCTOR test'], { cwd: repo }).status, 0);
  for (const name of ['one.ts', 'two.ts', 'three.ts']) fs.writeFileSync(path.join(repo, name), 'export {};\n');
  assert.strictEqual(run('git', ['add', '.'], { cwd: repo }).status, 0);
  const payload = JSON.stringify({ toolName: 'bash', toolArgs: { command: 'git commit -m fixture' } });
  const result = run('bash', [path.join(ROOT, 'core/hooks/pretool-commit-current-work-check.sh.template')], {
    cwd: repo,
    env: { CONDUCTOR_HOOK_DIALECT: 'copilot' },
    input: payload,
  });
  assert.strictEqual(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout);
  assert.strictEqual(output.permissionDecision, 'ask');
  assert(/CURRENT_WORK/.test(output.permissionDecisionReason));
});

test('Codex PreToolUse payload emits additionalContext without blocking', () => {
  const repo = path.join(TMP, 'codex-pretool');
  fs.mkdirSync(repo, { recursive: true });
  assert.strictEqual(run('git', ['init', '-q'], { cwd: repo }).status, 0);
  fs.writeFileSync(path.join(repo, 'feature-service.ts'), 'export {};\n');
  assert.strictEqual(run('git', ['add', '.'], { cwd: repo }).status, 0);
  const payload = JSON.stringify({ tool_name: 'Bash', tool_input: { command: 'git commit -m fixture' } });
  const result = run('bash', [path.join(ROOT, 'core/hooks/pretool-commit-test-coverage-check.sh.template')], {
    cwd: repo,
    env: { CONDUCTOR_HOOK_DIALECT: 'codex' },
    input: payload,
  });
  assert.strictEqual(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout);
  assert.strictEqual(output.hookSpecificOutput.hookEventName, 'PreToolUse');
  assert(/test-coverage-check/.test(output.hookSpecificOutput.additionalContext));
  assert.strictEqual(output.hookSpecificOutput.permissionDecision, undefined);
});

test('review-stop guard fails open on every runtime retry signal', () => {
  const script = path.join(ROOT, 'core/hooks/stop-r6-review-check.sh.template');
  for (const dialect of ['claude', 'cursor', 'copilot', 'gemini', 'codex']) {
    const payload = dialect === 'cursor'
      ? JSON.stringify({ loop_count: 1, status: 'completed' })
      : JSON.stringify({ stopHookActive: true });
    const result = run('bash', [script], {
      env: { CONDUCTOR_HOOK_DIALECT: dialect },
      input: payload,
    });
    assert.strictEqual(result.status, 0, `${dialect}: ${result.stderr}`);
    assert.strictEqual(result.stdout, '', dialect);
  }
});

test('review-stop guard emits each verified native continuation schema', () => {
  const fixture = path.join(TMP, 'stop-fixture');
  const hooksDir = path.join(fixture, '.fixture', 'hooks');
  const fakeBin = path.join(fixture, 'fake-bin');
  const script = path.join(hooksDir, 'stop-r6-review-check.sh');
  fs.mkdirSync(hooksDir, { recursive: true });
  fs.copyFileSync(path.join(ROOT, 'core/hooks/stop-r6-review-check.sh.template'), script);
  fs.chmodSync(script, 0o755);
  writeExecutable(path.join(fakeBin, 'git'), `#!/bin/sh
case "$1 $2 $3" in
  "rev-parse --abbrev-ref HEAD") echo feature/p2 ;;
  "reflog --date=unix "*) echo "HEAD@{$(date +%s)}: push: fixture" ;;
  "status --porcelain --untracked-files=all") exit 0 ;;
esac
`);
  writeExecutable(path.join(fakeBin, 'gh'), `#!/bin/sh
printf '%s\\n' '[{"url":"https://example.invalid/pr/987654321","number":987654321}]'
`);
  const user = `conductor-hook-test-${process.pid}`;
  const flag = `/tmp/conductor-q2-flag-${user}-987654321`;
  try { fs.unlinkSync(flag); } catch { /* absent */ }
  const expected = {
    claude: ['decision', 'block'],
    cursor: ['followup_message', null],
    copilot: ['decision', 'block'],
    gemini: ['decision', 'deny'],
    codex: ['decision', 'block'],
  };
  for (const [dialect, [key, value]] of Object.entries(expected)) {
    try { fs.unlinkSync(flag); } catch { /* previous dialect */ }
    const result = run('bash', [script], {
      cwd: fixture,
      env: {
        CONDUCTOR_HOOK_DIALECT: dialect,
        CONDUCTOR_COOLDOWN_SECONDS: '0',
        PATH: `${fakeBin}:${process.env.PATH}`,
        USER: user,
      },
      input: dialect === 'cursor'
        ? JSON.stringify({ loop_count: 0, status: 'completed' })
        : JSON.stringify({ stopHookActive: false }),
    });
    assert.strictEqual(result.status, 0, `${dialect}: ${result.stderr}`);
    const output = JSON.parse(result.stdout);
    assert(Object.hasOwn(output, key), dialect);
    if (value !== null) assert.strictEqual(output[key], value, dialect);
    assert(/reviewed snapshot/.test(result.stdout), `${dialect}: missing snapshot reuse guidance`);
    assert(/unreviewed delta/.test(result.stdout), `${dialect}: missing delta-review guidance`);
  }
  try { fs.unlinkSync(flag); } catch { /* cleanup best effort */ }
});

try {
  fs.rmSync(TMP, { recursive: true, force: true });
} catch { /* keep fixture for diagnosis only if the platform refuses cleanup */ }

if (process.exitCode) {
  process.stderr.write(`\nFAIL — hook compiler regression suite (${passed} passed before failure)\n`);
} else {
  process.stdout.write(`\nOK — hook compiler regression suite: ${passed}/${passed}\n`);
}
