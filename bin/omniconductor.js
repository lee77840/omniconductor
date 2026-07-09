#!/usr/bin/env node
'use strict';

/*
 * omniconductor — thin dispatcher to the per-tool adapter transform scripts.
 *
 * Usage:
 *   omniconductor init --target=<tool> [target-dir] [--recipes=a,b] [--dry-run] [--no-prompt]
 *   omniconductor init --target=<tool> [target-dir] --uninstall [--force]
 *   omniconductor doctor [target-dir] [--json]
 *   omniconductor list
 *   omniconductor --help | --version
 *
 * It does NOT reimplement any install logic. It locates this repo's
 * adapters/<tool>/transform.sh and runs it with `bash`, forwarding all flags
 * and inheriting stdio. The shell adapters remain the single source of truth
 * (ADR-002/023/025 — the bash adapters are the validated implementation).
 * `doctor` (ADR-041) is read-only: it inspects an install, never changes it.
 */

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];

function readVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).version || 'unknown';
  } catch {
    return 'unknown';
  }
}

function usage() {
  return `omniconductor ${readVersion()} — install CONDUCTOR's workflow into an AI coding tool

Usage:
  omniconductor init --target=<tool> [target-dir] [options]   Install into target-dir (default: .)
  omniconductor doctor [target-dir] [--json]                  Health-check an existing install (read-only)
  omniconductor list                                          List available tool adapters
  omniconductor --help | --version

Tools: ${TOOLS.join(', ')}

Common options (forwarded to the adapter):
  --recipes=a,b,c     Opt-in recipes to install
  --dry-run           Preview only — write nothing
  --no-prompt         Skip interactive prompts (CI-safe)
  --uninstall         Revert a previous install (manifest-based)
  --force             Bypass uninstall safety checks

Examples:
  omniconductor init --target=claude ./my-app --recipes=tdd,debugging
  omniconductor init --target=cursor ./my-app --dry-run
  omniconductor init --target=codex . --uninstall
  omniconductor doctor ./my-app --json

Run:  npx omniconductor init --target=<tool> <dir>`;
}

function fail(msg) {
  process.stderr.write(`omniconductor: ${msg}\n\n`);
  process.stderr.write(usage() + '\n');
  process.exit(2);
}

function main(argv) {
  const args = argv.slice(2);

  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    process.stdout.write(usage() + '\n');
    return 0;
  }
  if (args.includes('--version') || args.includes('-v')) {
    process.stdout.write(readVersion() + '\n');
    return 0;
  }

  const cmd = args[0];

  if (cmd === 'list') {
    process.stdout.write('Available adapters:\n');
    for (const t of TOOLS) {
      const present = fs.existsSync(path.join(ROOT, 'adapters', t, 'transform.sh'));
      process.stdout.write(`  ${t.padEnd(9)} ${present ? '✅ transform.sh' : '⏳ not implemented'}\n`);
    }
    return 0;
  }

  if (cmd === 'doctor') {
    const rest = args.slice(1);
    const jsonOut = rest.includes('--json');
    const dir = rest.find((a) => !a.startsWith('-')) || '.';
    return require('./doctor.js').run(dir, { json: jsonOut });
  }

  if (cmd !== 'init') {
    fail(`unknown command '${cmd}'. Expected 'init', 'doctor', or 'list'.`);
  }

  // Parse `init` args: extract --target, the positional target-dir, forward the rest.
  let target = null;
  let targetDir = null;
  const passthrough = [];
  for (const a of args.slice(1)) {
    if (a.startsWith('--target=')) {
      target = a.slice('--target='.length);
    } else if (a === '--target') {
      fail('use --target=<tool> (with =), e.g. --target=claude');
    } else if (a.startsWith('-')) {
      passthrough.push(a);
    } else if (targetDir === null) {
      targetDir = a;
    } else {
      passthrough.push(a);
    }
  }

  if (!target) fail('missing --target=<tool>');
  if (!TOOLS.includes(target)) fail(`unknown target '${target}'. One of: ${TOOLS.join(', ')}`);

  const transform = path.join(ROOT, 'adapters', target, 'transform.sh');
  if (!fs.existsSync(transform)) {
    fail(`the '${target}' adapter has no transform.sh yet (manual install — see docs/MANUAL-INSTALL.md).`);
  }

  const dir = targetDir || '.';
  const cmdline = ['bash', transform, dir, ...passthrough];
  process.stderr.write(`omniconductor → ${cmdline.slice(1).join(' ')}\n`);

  const res = spawnSync('bash', [transform, dir, ...passthrough], { stdio: 'inherit' });
  if (res.error) {
    process.stderr.write(`omniconductor: failed to run adapter: ${res.error.message}\n`);
    return 1;
  }
  return res.status === null ? 1 : res.status;
}

process.exit(main(process.argv));
