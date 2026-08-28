#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const bootstrap = require('../bin/bootstrap-contract.js');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-bootstrap-'));
let passed = 0;

function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [bootstrap-contract] ${name}\n`);
}

function writeManifest(target, value) {
  fs.mkdirSync(path.join(target, '.conductor'), { recursive: true });
  fs.writeFileSync(path.join(target, bootstrap.MANIFEST_REL), `${JSON.stringify(value, null, 2)}\n`);
}

function manifest(overrides = {}) {
  return {
    schema_version: 1,
    copy_allowlist: ['config/local.defaults.json'],
    setup_steps: [{ id: 'install', cwd: '.', argv: ['npm', 'ci'] }],
    ...overrides,
  };
}

function fixture(name, overrides) {
  const root = path.join(sandbox, name);
  const source = path.join(root, 'source');
  const target = path.join(root, 'target');
  fs.mkdirSync(path.join(source, 'config'), { recursive: true });
  fs.mkdirSync(path.join(target, 'config'), { recursive: true });
  fs.writeFileSync(path.join(source, 'config', 'local.defaults.json'), '{"mode":"local"}\n');
  writeManifest(target, manifest(overrides));
  return { root, source, target };
}

function treeDigest(root) {
  const digest = crypto.createHash('sha256');
  function walk(current) {
    for (const name of fs.readdirSync(current).sort()) {
      const absolute = path.join(current, name);
      const relative = path.relative(root, absolute).replace(/\\/g, '/');
      const stat = fs.lstatSync(absolute);
      digest.update(`${relative}\0${stat.mode}\0${stat.size}\0`);
      if (stat.isSymbolicLink()) digest.update(fs.readlinkSync(absolute));
      else if (stat.isDirectory()) walk(absolute);
      else digest.update(fs.readFileSync(absolute));
    }
  }
  walk(root);
  return digest.digest('hex');
}

function run(args) {
  return spawnSync(process.execPath, [CLI, ...args], { cwd: ROOT, encoding: 'utf8' });
}

try {
  test('valid plan is deterministic, read-only, and never executes setup argv', () => {
    const item = fixture('valid');
    const marker = path.join(item.root, 'executed');
    const markerScript = path.join(item.target, 'must-not-run.js');
    fs.writeFileSync(markerScript, `require('fs').writeFileSync(${JSON.stringify(marker)}, 'bad');\n`);
    const file = path.join(item.target, bootstrap.MANIFEST_REL);
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    data.setup_steps = [{ id: 'must-not-run', cwd: '.', argv: [process.execPath, 'must-not-run.js'] }];
    fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
    const beforeSource = treeDigest(item.source);
    const beforeTarget = treeDigest(item.target);
    const first = bootstrap.inspect(item.target, { source: item.source });
    const second = bootstrap.inspect(item.target, { source: item.source });
    assert.deepStrictEqual(first, second);
    assert.strictEqual(first.read_only, true);
    assert.strictEqual(first.commands_executed, false);
    assert.strictEqual(first.files_copied, false);
    assert.strictEqual(first.copy_plan[0].status, 'would-copy');
    assert.strictEqual(fs.existsSync(marker), false);
    assert.strictEqual(treeDigest(item.source), beforeSource);
    assert.strictEqual(treeDigest(item.target), beforeTarget);
  });

  test('secret-bearing paths are denied by default', () => {
    const denied = ['.env', '.env.local', '.env.example', '.ENV', '.ssh/id_rsa', '.aws/credentials', '.npmrc', 'keys/private.pem', 'config/secrets.json', 'config/my-api_key.txt', 'service-account.json', '.git/config', '.conductor/model-routing.json'];
    for (const [index, relative] of denied.entries()) {
      const item = fixture(`secret-path-${index}`, { copy_allowlist: [relative] });
      assert.throws(() => bootstrap.inspect(item.target, { source: item.source }), /never eligible|credential|secret|private-key|service-account/);
    }
  });

  test('credential-shaped content is refused without returning the value', () => {
    const item = fixture('secret-content');
    const literal = 'super-private-bootstrap-token';
    fs.writeFileSync(path.join(item.source, 'config', 'local.defaults.json'), `token=${literal}\n`);
    let error;
    try { bootstrap.inspect(item.target, { source: item.source }); } catch (caught) { error = caught; }
    assert(error);
    assert.match(error.message, /credential-like assignment/);
    assert.strictEqual(error.message.includes(literal), false);

    const urlItem = fixture('credential-url-content');
    const password = 'hunter2-bootstrap-password';
    fs.writeFileSync(path.join(urlItem.source, 'config', 'local.defaults.json'), `url=https://user:${password}@example.test/archive\n`);
    error = undefined;
    try { bootstrap.inspect(urlItem.target, { source: urlItem.source }); } catch (caught) { error = caught; }
    assert(error);
    assert.match(error.message, /credential-bearing URL/);
    assert.strictEqual(error.message.includes(password), false);

    const placeholderItem = fixture('credential-url-placeholder');
    fs.writeFileSync(path.join(placeholderItem.source, 'config', 'local.defaults.json'), 'url=https://user:${LOCAL_PASSWORD}@example.test/archive\n');
    assert.strictEqual(bootstrap.inspect(placeholderItem.target, { source: placeholderItem.source }).copy_plan[0].status, 'would-copy');
  });

  test('manifest traversal, absolute paths, backslashes, duplicates, and unknown fields fail closed', () => {
    const cases = [
      { copy_allowlist: ['../outside'] },
      { copy_allowlist: [path.resolve(sandbox, 'outside')] },
      { copy_allowlist: ['config\\local.json'] },
      { copy_allowlist: ['safe.txt', 'safe.txt'] },
      { copy_allowlist: Array.from({ length: 129 }, (_, item) => `config/safe-${item}.txt`) },
      { authority: 'execute' },
    ];
    for (const [index, overrides] of cases.entries()) {
      const item = fixture(`invalid-schema-${index}`, overrides);
      assert.throws(() => bootstrap.inspect(item.target, { source: item.source }), /relative|absolute|unsafe|duplicates|unknown field|portable|at most 128/);
    }
  });

  test('manifest and source symlinks or hardlinks are rejected before reading', () => {
    const linkedManifest = fixture('linked-manifest');
    const file = path.join(linkedManifest.target, bootstrap.MANIFEST_REL);
    const outsideManifest = path.join(linkedManifest.root, 'outside-manifest.json');
    fs.renameSync(file, outsideManifest);
    fs.symlinkSync(outsideManifest, file);
    assert.throws(() => bootstrap.inspect(linkedManifest.target, { source: linkedManifest.source }), /symbolic link/);

    const hardManifest = fixture('hard-manifest');
    const hardFile = path.join(hardManifest.target, bootstrap.MANIFEST_REL);
    fs.linkSync(hardFile, path.join(hardManifest.root, 'manifest-alias.json'));
    assert.throws(() => bootstrap.inspect(hardManifest.target, { source: hardManifest.source }), /single-link regular file/);

    const linkedSource = fixture('linked-source');
    const sourceFile = path.join(linkedSource.source, 'config', 'local.defaults.json');
    const sourceOutside = path.join(linkedSource.root, 'outside-source.json');
    fs.renameSync(sourceFile, sourceOutside);
    fs.symlinkSync(sourceOutside, sourceFile);
    assert.throws(() => bootstrap.inspect(linkedSource.target, { source: linkedSource.source }), /symbolic link/);

    const linkedSourceParent = fixture('linked-source-parent');
    const sourceParent = path.join(linkedSourceParent.source, 'config');
    const outsideParent = path.join(linkedSourceParent.root, 'outside-config');
    fs.renameSync(sourceParent, outsideParent);
    fs.symlinkSync(outsideParent, sourceParent);
    assert.throws(() => bootstrap.inspect(linkedSourceParent.target, { source: linkedSourceParent.source }), /symbolic link/);

    const hardSource = fixture('hard-source');
    const hardSourceFile = path.join(hardSource.source, 'config', 'local.defaults.json');
    fs.linkSync(hardSourceFile, path.join(hardSource.root, 'source-alias.json'));
    assert.throws(() => bootstrap.inspect(hardSource.target, { source: hardSource.source }), /single-link regular file/);
  });

  test('destination links and non-identical existing files fail; identical files are idempotent', () => {
    const linked = fixture('linked-destination');
    const outside = path.join(linked.root, 'outside-destination.json');
    fs.writeFileSync(outside, 'outside\n');
    fs.symlinkSync(outside, path.join(linked.target, 'config', 'local.defaults.json'));
    assert.throws(() => bootstrap.inspect(linked.target, { source: linked.source }), /symbolic link/);

    const conflict = fixture('conflict-destination');
    fs.writeFileSync(path.join(conflict.target, 'config', 'local.defaults.json'), 'different\n');
    assert.throws(() => bootstrap.inspect(conflict.target, { source: conflict.source }), /different content/);

    const same = fixture('same-destination');
    fs.copyFileSync(path.join(same.source, 'config', 'local.defaults.json'), path.join(same.target, 'config', 'local.defaults.json'));
    assert.strictEqual(bootstrap.inspect(same.target, { source: same.source }).copy_plan[0].status, 'already-present');
  });

  test('setup schema rejects shells, wrappers, eval forms, credentials, unsafe cwd, and unknown fields', () => {
    const cases = [
      [{ id: 'shell', cwd: '.', argv: [`ba${'sh'}`, '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'shell-exe', cwd: '.', argv: ['bash.exe', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'sh-exe', cwd: '.', argv: ['sh.exe', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'zsh-exe', cwd: '.', argv: ['zsh.exe', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'fish-exe', cwd: '.', argv: ['fish.exe', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'posix-shell-path', cwd: '.', argv: ['/usr/local/bin/bash', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'windows-shell-path', cwd: '.', argv: ['C:\\Windows\\System32\\cmd.exe', '/c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'wsl', cwd: '.', argv: ['wsl.exe', 'sh', '-c', 'npm ci'] }, /shell interpreters/],
      [{ id: 'env-wrapper', cwd: '.', argv: ['/usr/bin/env', 'sh', '-c', 'npm ci'] }, /indirect command wrappers/],
      [{ id: 'xargs-wrapper', cwd: '.', argv: ['xargs', 'sh'] }, /indirect command wrappers/],
      [{ id: 'busybox-wrapper', cwd: '.', argv: ['busybox.exe', 'sh', '-c', 'npm ci'] }, /indirect command wrappers/],
      [{ id: 'node-eval', cwd: '.', argv: ['node.exe', '--eval', 'process.exit()'] }, /JavaScript evaluation flags/],
      [{ id: 'deno-eval', cwd: '.', argv: ['deno', '--quiet', 'eval', 'Deno.exit()'] }, /Deno eval subcommand/],
      [{ id: 'python-eval', cwd: '.', argv: ['python3.12', '-c', 'print(1)'] }, /Python evaluation flags/],
      [{ id: 'perl-eval', cwd: '.', argv: ['perl', '-e', 'exit'] }, /interpreter evaluation flags/],
      [{ id: 'ruby-eval', cwd: '.', argv: ['ruby.exe', '-e', 'exit'] }, /interpreter evaluation flags/],
      [{ id: 'php-eval', cwd: '.', argv: ['php.exe', '-r', 'exit;'] }, /PHP evaluation flags/],
      [{ id: 'secret', cwd: '.', argv: ['tool', '--token=literal-value'] }, /literal credential/],
      [{ id: 'shaped-secret', cwd: '.', argv: ['tool', 'ghp_123456789012345678901234567890'] }, /credential-shaped literal/],
      [{ id: 'credential-url', cwd: '.', argv: ['tool', 'https://user:password@example.test/archive'] }, /credential-bearing URL/],
      [{ id: 'escape', cwd: '../outside', argv: ['npm', 'ci'] }, /unsafe|relative/],
      [{ id: 'env', cwd: '.', argv: ['npm', 'ci'], env: { TOKEN: 'x' } }, /unknown field/],
    ];
    for (const [index, [step, expected]] of cases.entries()) {
      const item = fixture(`invalid-setup-${index}`, { copy_allowlist: [], setup_steps: [step] });
      assert.throws(() => bootstrap.inspect(item.target), expected);
    }
  });

  test('CLI check and plan are machine-readable dry-runs and require a source for copies', () => {
    const item = fixture('cli');
    let result = run(['workspace', 'bootstrap', 'check', item.target, `--source=${item.source}`, '--json']);
    assert.strictEqual(result.status, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.strictEqual(report.commands_executed, false);
    assert.strictEqual(report.files_copied, false);

    result = run(['workspace', 'bootstrap', 'plan', item.target, `--source=${item.source}`]);
    assert.strictEqual(result.status, 0, result.stderr);
    assert.match(result.stdout, /DRY-RUN ONLY/);
    assert.match(result.stdout, /argv="npm" "ci"/);

    result = run(['workspace', 'bootstrap', 'plan', item.target]);
    assert.strictEqual(result.status, 2);
    assert.match(result.stderr, /explicit --source/);
  });

  process.stdout.write(`OK — bootstrap-contract tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
