#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const trust = require('../bin/extension-trust.js');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write(`OK   [extension-trust] ${name}\n`);
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-extension-trust-'));
try {
  test('all six metadata contracts validate', () => {
    for (const tool of trust.TOOLS) {
      const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', tool, 'metadata.json'), 'utf8'));
      assert.deepStrictEqual(trust.validateExtensionTrustMetadata(metadata), []);
    }
  });

  test('clean project reports no risk and remains byte-identical', () => {
    fs.mkdirSync(path.join(sandbox, '.claude'), { recursive: true });
    const file = path.join(sandbox, '.mcp.json');
    fs.writeFileSync(file, JSON.stringify({ mcpServers: { safe: { command: 'server-bin', env: { API_KEY: '${SAFE_API_KEY}' } } } }, null, 2));
    const before = fs.readFileSync(file);
    const report = trust.audit(sandbox, ['claude']);
    assert.strictEqual(report.summary.high, 0);
    assert.strictEqual(report.summary.warnings, 1); // protocol boundary is intentionally unverified
    assert.deepStrictEqual(fs.readFileSync(file), before);
  });

  test('literal secret is detected but never returned', () => {
    const literal = 'super-secret-value-for-test';
    fs.writeFileSync(path.join(sandbox, '.mcp.json'), JSON.stringify({
      mcpServers: { unsafe: { command: 'npx', args: ['unsafe-package'], env: { API_KEY: literal } } },
    }));
    const report = trust.audit(sandbox, ['claude']);
    const serialized = JSON.stringify(report);
    assert(report.adapters[0].findings.some((item) => item.code === 'INLINE_SECRET'));
    assert(report.adapters[0].findings.some((item) => item.code === 'UNPINNED_EXECUTOR'));
    assert(!serialized.includes(literal));
  });

  test('plaintext URL, legacy SSE, and shell command strings are classified', () => {
    fs.writeFileSync(path.join(sandbox, '.mcp.json'), JSON.stringify({
      mcpServers: {
        remote: { url: 'http://example.test/sse', transport: 'sse' },
        shell: { command: 'bash', args: ['-c', 'run-server'] },
      },
    }));
    const codes = new Set(trust.audit(sandbox, ['claude']).adapters[0].findings.map((item) => item.code));
    assert(codes.has('PLAINTEXT_REMOTE_URL'));
    assert(codes.has('LEGACY_SSE_TRANSPORT'));
    assert(codes.has('SHELL_COMMAND_STRING'));
  });

  test('symlinked configuration is not followed', () => {
    const outside = path.join(os.tmpdir(), `conductor-secret-${process.pid}.json`);
    fs.writeFileSync(outside, JSON.stringify({ token: 'must-not-be-read' }));
    fs.rmSync(path.join(sandbox, '.mcp.json'), { force: true });
    fs.symlinkSync(outside, path.join(sandbox, '.mcp.json'));
    const report = trust.audit(sandbox, ['claude']);
    assert(report.adapters[0].findings.some((item) => item.code === 'SYMLINK_SKIPPED'));
    assert(!JSON.stringify(report).includes('must-not-be-read'));
    fs.unlinkSync(outside);
  });

  test('symlinked target roots and hard-linked configuration are not followed', () => {
    const realTarget = path.join(sandbox, 'real-target');
    const linkedTarget = path.join(sandbox, 'linked-target');
    fs.mkdirSync(realTarget);
    fs.writeFileSync(path.join(realTarget, '.mcp.json'), JSON.stringify({ token: 'must-not-be-read' }));
    fs.symlinkSync(realTarget, linkedTarget);
    assert.throws(() => trust.audit(linkedTarget, ['claude']), /target must be a real directory/);

    const hardSource = path.join(sandbox, 'hard-source.json');
    const hardTarget = path.join(sandbox, 'hard-target');
    fs.writeFileSync(hardSource, JSON.stringify({ token: 'must-not-be-read-either' }));
    fs.mkdirSync(hardTarget);
    fs.linkSync(hardSource, path.join(hardTarget, '.mcp.json'));
    const report = trust.audit(hardTarget, ['claude']);
    assert(report.adapters[0].findings.some((item) => item.code === 'HARDLINK_SKIPPED'));
    assert(!JSON.stringify(report).includes('must-not-be-read-either'));
  });

  test('CLI JSON is machine-readable and exits non-zero on HIGH findings', () => {
    fs.rmSync(path.join(sandbox, '.mcp.json'), { force: true });
    fs.writeFileSync(path.join(sandbox, '.mcp.json'), '{"token":"literal"}\n');
    const result = spawnSync(process.execPath, [
      path.join(ROOT, 'bin', 'omniconductor.js'), 'audit', 'extensions', sandbox, '--target=claude', '--json',
    ], { encoding: 'utf8' });
    assert.strictEqual(result.status, 1);
    assert.strictEqual(JSON.parse(result.stdout).summary.high, 1);
  });

  process.stdout.write(`OK — extension-trust tests: ${passed}/${passed}\n`);
} finally {
  fs.rmSync(sandbox, { recursive: true, force: true });
}
