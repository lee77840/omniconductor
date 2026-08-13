#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const packager = require('../bin/plugin-packager.js');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [plugin-packager] ${name}\n`);
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-plugin-packager-'));
try {
  test('all seven package metadata contracts validate', () => {
    for (const tool of packager.TOOLS) {
      const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', tool, 'metadata.json'), 'utf8'));
      assert.deepStrictEqual(packager.validateMetadata(metadata), [], tool);
    }
  });

  test('dry-run returns seven plans without writing', () => {
    const output = path.join(sandbox, 'dry-run');
    const result = packager.build(output, packager.TOOLS, { dryRun: true });
    assert.strictEqual(result.packages.length, 7);
    assert(!fs.existsSync(output));
  });

  test('strict-native fails closed before output for fallback adapters', () => {
    const output = path.join(sandbox, 'strict');
    assert.throws(() => packager.build(output, packager.TOOLS, { strictNative: true }), /cursor, windsurf, opencode/);
    assert(!fs.existsSync(output));
  });

  test('all packages preserve native/fallback boundaries and integrity inventory', () => {
    const output = path.join(sandbox, 'packages');
    const result = packager.build(output, packager.TOOLS);
    assert.strictEqual(result.packages.length, 7);
    const manifests = {
      claude: '.claude-plugin/plugin.json',
      copilot: 'plugin.json',
      gemini: 'gemini-extension.json',
      codex: '.codex-plugin/plugin.json',
    };
    for (const tool of packager.TOOLS) {
      const root = path.join(output, `conductor-${tool}`);
      const contract = JSON.parse(fs.readFileSync(path.join(root, 'PACKAGE-CONTRACT.json'), 'utf8'));
      assert.strictEqual(contract.contains_mcp_server, false);
      assert.strictEqual(contract.contains_remote_connector, false);
      assert.strictEqual(contract.contains_executable_hook, false);
      for (const skill of ['plan-change', 'verify-change', 'review-change']) {
        assert(fs.existsSync(path.join(root, 'skills', skill, 'SKILL.md')), `${tool}:${skill}`);
      }
      assert(fs.existsSync(path.join(root, 'optional-skills', 'propose-skill', 'SKILL.md')));
      assert(fs.existsSync(path.join(root, 'optional-skills', 'coordinate-work', 'SKILL.md')));
      assert(!fs.existsSync(path.join(root, 'skills', 'propose-skill')), `${tool}: opt-in skill became active`);
      assert(!fs.existsSync(path.join(root, 'skills', 'coordinate-work')), `${tool}: opt-in coordination skill became active`);
      assert.deepStrictEqual(contract.inactive_optional_skills, ['propose-skill', 'coordinate-work']);
      assert(!contract.files.some((entry) => entry.path.endsWith('.sh')), `${tool}: executable hook source entered package`);
      if (manifests[tool]) {
        assert.strictEqual(contract.mode, 'native-partial');
        assert(fs.existsSync(path.join(root, manifests[tool])));
      } else {
        assert.strictEqual(contract.mode, 'direct-fallback');
        assert.strictEqual(contract.native_manifest, null);
        assert(fs.existsSync(path.join(root, 'direct-install')));
      }
      for (const entry of contract.files) {
        const digest = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, entry.path))).digest('hex');
        assert.strictEqual(digest, entry.sha256, `${tool}:${entry.path}`);
      }
    }
  });

  test('existing package output is refused unless force is explicit', () => {
    const output = path.join(sandbox, 'packages');
    assert.throws(() => packager.build(output, ['codex']), /use --force/);
    const result = packager.build(output, ['codex'], { force: true });
    assert.strictEqual(result.packages[0].tool, 'codex');
  });

  test('a directly symlinked output ancestor is refused before compilation or writes', () => {
    const outside = path.join(sandbox, 'symlink-output-target');
    const parent = path.join(sandbox, 'symlink-output-parent');
    fs.mkdirSync(outside);
    fs.mkdirSync(parent);
    fs.symlinkSync(outside, path.join(parent, 'linked'));
    assert.throws(
      () => packager.build(path.join(parent, 'linked', 'packages'), ['codex'], { dryRun: true }),
      /symlinked package output ancestor/,
    );
    assert(!fs.existsSync(path.join(outside, 'packages')));
  });

  process.stdout.write(`OK — plugin-packager tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
