#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
// Windows maps a bare `bash` to the WSL relay, which spawns and then exits
// non-zero when no distribution provides /bin/bash. Resolve the same shell the
// installer uses so this suite is runnable on Windows, not only POSIX.
const BASH = (require('../bin/installer-platform.js').resolveBash() || { command: 'bash' }).command;
const { assertPublishable, compareStable } = require('./check-release-version');

const packageMetadata = require('../package.json');
const packageVersion = packageMetadata.version;

assert(Array.isArray(packageMetadata.keywords));
assert.strictEqual(new Set(packageMetadata.keywords).size, packageMetadata.keywords.length);
assert(packageMetadata.keywords.length <= 64, 'npm keyword inventory must stay at or below 64');
for (const keyword of packageMetadata.keywords) assert.match(keyword, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
for (const requiredKeyword of [
  'coding-agent', 'agent-framework', 'governance', 'guardrails', 'policy-as-code',
  'agentic-workflow', 'token-optimization', 'token-savings', 'model-context-protocol',
  'devin', 'openai-codex', 'cli', 'cross-platform',
]) assert(packageMetadata.keywords.includes(requiredKeyword), requiredKeyword);
for (const duplicateVariant of ['sub-agents', 'spec-driven']) {
  assert(!packageMetadata.keywords.includes(duplicateVariant), duplicateVariant);
}
assert.match(packageMetadata.description, /governance and guardrails/);
assert.match(packageMetadata.description, /token optimization/);

assert.strictEqual(compareStable('1.2.0', '1.1.2'), 1);
assert.strictEqual(compareStable('1.1.2', '1.1.2'), 0);
assert.strictEqual(compareStable('1.1.1', '1.1.2'), -1);
assert.doesNotThrow(() => assertPublishable('1.2.0', '1.1.2', ['1.1.1', '1.1.2']));
assert.throws(
  () => assertPublishable('1.1.2', '1.1.2', ['1.1.1', '1.1.2']),
  /already published/,
);
assert.throws(
  () => assertPublishable('1.1.1', '1.1.2', ['1.1.1', '1.1.2']),
  /already published/,
);
assert.throws(
  () => assertPublishable('1.1.3', '1.2.0', ['1.1.2', '1.2.0']),
  /must be greater/,
);
assert.throws(
  () => assertPublishable('next', '1.1.2', ['1.1.2']),
  /stable x\.y\.z/,
);
assert.throws(
  () => assertPublishable('1.2.0', '1.1.2', '1.1.2'),
  /JSON array/,
);

const root = path.resolve(__dirname, '..');
const releaseGateSource = fs.readFileSync(path.join(root, 'tools/release-verify-local.sh'), 'utf8');
for (const requiredGovernanceAsset of [
  'bin/adapter-dispatch.js',
  'bin/assurance-coverage.js',
  'bin/evidence-contract.js',
  'bin/extension-trust.js',
  'bin/plugin-packager.js',
  'bin/skill-proposals.js',
  'bin/work-contract.js',
  'bin/workspace-contract.js',
  'bin/bootstrap-contract.js',
  'bin/installer-platform.js',
  'bin/opencode-config.js',
  'bin/recipe-onboarding.js',
  'bin/install-conflicts.js',
  'bin/instruction-footprint.js',
  'bin/user-token-savings.js',
  'bin/instruction-exposure.js',
  'bin/opencode-usage.js',
  'tools/opencode-snapshot.py',
  'tools/test-opencode-usage.js',
  'core/reflector/runner.js',
  'adapters/opencode/transform.sh',
  'adapters/opencode/metadata.json',
  'adapters/opencode/conductor-guards.js',
  'adapters/opencode/README.md',
  'adapters/opencode/SUPPORTED-FEATURES.md',
  'adapters/opencode/transform-spec.md',
  'core/skills/coordinate-work/SKILL.md',
  'core/skills/propose-skill/SKILL.md',
  'core/reflector/reflection-proposals.js',
  'core/runtime-kernel.md',
  'docs/AGENT-EVAL-COVERAGE.json',
  'docs/AGENT-EVAL-COVERAGE.md',
  'docs/PARALLEL-WORK.md',
  'docs/TOKEN-ECONOMY-KO.md',
  'docs/VERIFICATION-EVIDENCE.md',
  'docs/WORKSPACE-FEDERATION.md',
  'tools/generate-assurance-coverage.js',
  'tools/test-assurance-coverage.js',
  'tools/test-evidence-contract.js',
  'tools/test-assurance-recipes.sh',
  'tools/test-extension-trust.js',
  'tools/test-installer-platform.js',
  'tools/run-bash.js',
  'tools/test-install-modes-all.js',
  'tools/test-hook-python-runtime.js',
  'tools/test-opencode-adapter.js',
  'tools/test-plugin-packager.js',
  'tools/test-skill-proposals.js',
  'tools/test-work-contract.js',
  'tools/test-workspace-contract.js',
  'tools/test-bootstrap-contract.js',
  'tools/test-windows-installer.js',
  'tools/check-recipe-docs.js',
  'tools/test-recipe-docs.js',
  'tools/test-recipe-onboarding.js',
  'tools/test-install-conflicts.js',
  'tools/test-reflection-proposals.js',
  'tools/test-reflector-runner.js',
  'tools/test-instruction-footprint.js',
  'tools/test-user-token-savings.js',
]) {
  assert(
    releaseGateSource.includes(requiredGovernanceAsset),
    `release gate must require tracked governance asset: ${requiredGovernanceAsset}`,
  );
}
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-release-baseline-'));
const fakeBin = path.join(fixture, 'bin');
const npmLog = path.join(fixture, 'npm.log');
fs.mkdirSync(fakeBin);
fs.writeFileSync(path.join(fakeBin, 'npm'), `#!/bin/sh
printf '%s\\t%s\\n' "\${npm_config_cache:-}" "$*" >> "$CONDUCTOR_TEST_NPM_LOG"
if [ "$1" = "view" ] && [ "$2" = "omniconductor" ] && [ "$3" = "version" ]; then
  printf '1.2.1\\n'
elif [ "$1" = "view" ] && [ "$2" = "omniconductor" ] && [ "$3" = "versions" ]; then
  printf '["1.2.1","${packageVersion}"]\\n'
else
  exit 97
fi
`);
fs.chmodSync(path.join(fakeBin, 'npm'), 0o755);

for (let run = 0; run < 2; run += 1) {
  const fixtureEnv = {
    ...process.env,
    PATH: `${fakeBin}:${process.env.PATH}`,
    TMPDIR: fixture,
    CONDUCTOR_TEST_NPM_LOG: npmLog,
  };
  // The complete release gate can be run with a caller-supplied, already
  // verified registry snapshot. This fixture must still exercise its own fake
  // registry and fresh-cache contract rather than silently inheriting that
  // parent state.
  delete fixtureEnv.CONDUCTOR_REGISTRY_LATEST_VERSION;
  delete fixtureEnv.CONDUCTOR_REGISTRY_VERSIONS_JSON;
  // A caller-supplied release cache is valid, but this fixture specifically
  // proves the default per-invocation cache contract, not that override.
  delete fixtureEnv.CONDUCTOR_NPM_CACHE;
  const result = spawnSync(BASH, ['tools/release-verify-local.sh'], {
    cwd: root,
    encoding: 'utf8',
    env: fixtureEnv,
  });
  assert.notStrictEqual(result.status, 0);
  assert(`${result.stdout}\n${result.stderr}`.includes(`${packageVersion} is already published`));
}

const registryCalls = fs.readFileSync(npmLog, 'utf8').trim().split('\n')
  .map((line) => {
    const [cache, args] = line.split('\t');
    return { cache, args };
  });
assert.strictEqual(registryCalls.length, 4);
assert.strictEqual(registryCalls[0].cache, registryCalls[1].cache);
assert.strictEqual(registryCalls[2].cache, registryCalls[3].cache);
assert.notStrictEqual(registryCalls[0].cache, registryCalls[2].cache);
for (const call of registryCalls) {
  assert(call.cache.includes(`/conductor-release-${packageVersion}.`));
  assert(call.cache.endsWith('/npm-cache'));
  assert.match(call.args, /--prefer-online/);
}
fs.rmSync(fixture, { recursive: true, force: true });

console.log('PASS: release candidate must be new and greater than npm latest');
console.log('PASS: release registry baseline uses a fresh revalidated cache per run');
console.log('PASS: release gate tracks every governance runtime, skill, document, generator, and suite');
console.log('PASS: npm discovery metadata stays focused, duplicate-free, and feature-accurate');
