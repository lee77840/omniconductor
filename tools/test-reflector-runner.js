'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const BASH = (require('../bin/installer-platform.js').resolveBash() || { command: 'bash' }).command;

const root = path.resolve(__dirname, '..');
const supported = ['claude', 'codex', 'gemini', 'cursor-agent', 'copilot', 'opencode'];
const expectedArgs = {
  claude: ['--permission-mode', 'plan', '--disallowedTools'],
  codex: ['--sandbox', 'read-only'],
  gemini: ['--approval-mode=plan'],
  'cursor-agent': ['--mode=ask'],
  copilot: ['--available-tools=view,grep,glob', '--deny-tool=write,memory,shell,url'],
  opencode: ['--agent', 'reflector'],
};
const payload = '<conductor-reflection-proposals>{"schema_version":1,"proposals":[{"op":"ADD","target":"feedback_lesson-test.md","lesson":"L","why":"W","how_to_apply":"H","provenance":["session:s1"]}]}</conductor-reflection-proposals>';

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reflector-runner-'));
  const reflect = path.join(dir, '.conductor', 'reflect');
  const bin = path.join(dir, 'fake-bin');
  fs.mkdirSync(reflect, { recursive: true });
  fs.mkdirSync(bin);
  for (const file of ['run-weekly.sh', 'reflect-brief.md', 'reflection-proposals.js']) {
    fs.copyFileSync(path.join(root, 'core', 'reflector', file), path.join(reflect, file));
  }
  fs.mkdirSync(path.join(dir, '.conductor', 'trajectories'));
  fs.writeFileSync(path.join(dir, '.conductor', 'trajectories', 'index.jsonl'), '{"session_id":"s1"}\n');
  return { dir, reflect, bin };
}

function fake(bin, name, body) {
  const file = path.join(bin, name);
  fs.writeFileSync(file, `#!/bin/sh\nprintf '%s\\n' "$@" > "$CONDUCTOR_ARG_LOG"\n${body}\n`);
  fs.chmodSync(file, 0o755);
}

for (const cli of supported) {
  const f = fixture();
  const argLog = path.join(f.dir, 'args.log');
  fake(f.bin, cli, `printf '%s\\n' '${payload}'`);
  const result = spawnSync(BASH, [path.join(f.reflect, 'run-weekly.sh')], {
    cwd: f.dir,
    env: { ...process.env, PATH: `${f.bin}:${process.env.PATH}`, CONDUCTOR_REFLECT_CLI: cli, CONDUCTOR_ARG_LOG: argLog },
    encoding: 'utf8',
  });
  assert.strictEqual(result.status, 0, `${cli}: ${result.stderr}`);
  assert.ok(fs.existsSync(path.join(f.dir, 'docs', 'REFLECTION-PROPOSALS.md')), `${cli}: proposal not imported`);
  const args = fs.readFileSync(argLog, 'utf8');
  for (const expected of expectedArgs[cli]) assert.ok(args.includes(expected), `${cli}: missing ${expected}`);
  process.stdout.write(`PASS: ${cli} uses read-only analysis then trusted import\n`);
}

{
  const f = fixture();
  fake(f.bin, 'devin', `printf '%s\\n' '${payload}'`);
  const result = spawnSync(BASH, [path.join(f.reflect, 'run-weekly.sh')], {
    cwd: f.dir,
    env: { ...process.env, PATH: `${f.bin}:${process.env.PATH}`, CONDUCTOR_REFLECT_CLI: 'devin', CONDUCTOR_ARG_LOG: path.join(f.dir, 'args.log') },
    encoding: 'utf8',
  });
  assert.strictEqual(result.status, 2);
  assert.match(result.stderr, /no verified headless read-only contract/);
  assert.strictEqual(fs.existsSync(path.join(f.dir, 'docs')), false);
  process.stdout.write('PASS: unverified Devin automation fails closed\n');
}

{
  const f = fixture();
  const argLog = path.join(f.dir, 'args.log');
  fake(f.bin, 'codex', `touch MUTATED\nprintf '%s\\n' '${payload}'`);
  spawnSync('git', ['init', '-q'], { cwd: f.dir });
  spawnSync('git', ['add', '.'], { cwd: f.dir });
  const commit = spawnSync('git', [
    '-c', 'user.name=CONDUCTOR', '-c', 'user.email=conductor@example.invalid',
    'commit', '-qm', 'clean-reflector-fixture',
  ], { cwd: f.dir, encoding: 'utf8' });
  assert.strictEqual(commit.status, 0, commit.stderr);
  assert.strictEqual(spawnSync('git', ['status', '--porcelain'], { cwd: f.dir, encoding: 'utf8' }).stdout, '');
  const result = spawnSync(BASH, [path.join(f.reflect, 'run-weekly.sh')], {
    cwd: f.dir,
    env: { ...process.env, PATH: `${f.bin}:${process.env.PATH}`, CONDUCTOR_REFLECT_CLI: 'codex', CONDUCTOR_ARG_LOG: argLog },
    encoding: 'utf8',
  });
  assert.strictEqual(result.status, 2);
  assert.match(result.stderr, /changed the worktree/);
  assert.strictEqual(fs.existsSync(path.join(f.dir, 'docs')), false);
  process.stdout.write('PASS: worktree drift blocks proposal import\n');
}

process.stdout.write('PASS: reflector runner contract 8/8\n');
