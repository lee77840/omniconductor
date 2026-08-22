#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ADAPTERS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf', 'opencode'];
const KERNEL_BUDGET = 12 * 1024;
const ACTIVE_BUDGET = 16 * 1024;

function safeFile(file) {
  if (!fs.existsSync(file)) return false;
  const stat = fs.lstatSync(file);
  return stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1;
}

function regularFiles(root, directOnly = false) {
  if (!fs.existsSync(root)) return [];
  const stat = fs.lstatSync(root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) return [];
  const out = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const absolute = path.join(root, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isFile()) out.push(absolute);
    else if (entry.isDirectory() && !directOnly) out.push(...regularFiles(absolute));
  }
  return out.sort();
}

function sum(files) {
  return files.reduce((total, file) => total + fs.statSync(file).size, 0);
}

function pointerFiles(target, adapter, metadata) {
  const root = metadata.instruction_loading.recipe_pointer_root;
  if (!root) return [];
  const files = regularFiles(path.join(target, root), true).filter((file) => /\.(md|mdc)$/.test(file));
  return files.filter((file) => !/conductor-kernel\.(md|mdc)$/.test(file));
}

function referenceFiles(target, metadata) {
  return metadata.instruction_loading.reference_roots.flatMap((root) => regularFiles(path.join(target, root)));
}

function eagerFiles(target, metadata) {
  const alternatives = metadata.instruction_loading.eager_alternatives;
  if (Array.isArray(alternatives) && alternatives.length) {
    for (const group of alternatives) {
      const files = group.map((file) => path.join(target, file));
      if (files.length && files.every(safeFile)) return files;
    }
  }
  return metadata.instruction_loading.eager.map((file) => path.join(target, file));
}

function integrityProblems(target, adapter, metadata, manifest) {
  const problems = [];
  const [ruleRoot, recipeRoot] = metadata.instruction_loading.reference_roots;
  if (['full', 'minimal', 'strict'].includes(manifest.mode)) {
    for (const rule of ['workflow', 'spec-as-you-go', 'quality-gates', 'operations', 'meta-discipline']) {
      const source = path.join(ROOT, 'core', 'universal-rules', `${rule}.md`);
      const installed = path.join(target, ruleRoot, `${rule}.md`);
      if (!safeFile(installed)) problems.push(`${ruleRoot}/${rule}.md is missing or unsafe`);
      else if (!fs.readFileSync(source).equals(fs.readFileSync(installed))) problems.push(`${ruleRoot}/${rule}.md differs from core`);
    }
  }
  for (const recipe of manifest.recipes_enabled || []) {
    const source = path.join(ROOT, 'core', 'recipes', `${recipe}.md`);
    const installed = path.join(target, recipeRoot, `${recipe}.md`);
    if (!safeFile(installed)) problems.push(`${recipeRoot}/${recipe}.md is missing or unsafe`);
    else if (!fs.readFileSync(source).equals(fs.readFileSync(installed))) problems.push(`${recipeRoot}/${recipe}.md differs from core`);
  }
  return problems;
}

function auditAdapter(target, adapter, options = {}) {
  const manifestFile = path.join(target, '.conductor', 'manifests', `${adapter}.json`);
  if (!safeFile(manifestFile)) return null;
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'adapters', adapter, 'metadata.json'), 'utf8'));
  if (!metadata.instruction_loading) throw new Error(`${adapter} metadata lacks instruction_loading`);
  const expectedEagerFiles = eagerFiles(target, metadata);
  const baselineMode = ['full', 'minimal', 'strict'].includes(manifest.mode);
  const missingEager = baselineMode ? expectedEagerFiles.filter((file) => !safeFile(file)) : [];
  const validEager = baselineMode ? expectedEagerFiles.filter(safeFile) : [];
  const pointers = pointerFiles(target, adapter, metadata);
  const references = referenceFiles(target, metadata);
  const eagerBytes = sum(validEager);
  const pointerBytes = sum(pointers);
  const pointersAlwaysActive = ['windsurf', 'opencode'].includes(adapter);
  const activeBytes = eagerBytes + (pointersAlwaysActive ? pointerBytes : 0);
  const counterfactualEagerBytes = sum(references);
  const avoidedBytes = baselineMode ? Math.max(0, counterfactualEagerBytes - activeBytes) : null;
  const avoidedTokens = avoidedBytes === null ? null : Math.floor(avoidedBytes / 4);
  const problems = [
    ...missingEager.map((file) => `${path.relative(target, file)} is missing or unsafe`),
    ...integrityProblems(target, adapter, metadata, manifest),
  ];
  if (baselineMode && eagerBytes > KERNEL_BUDGET) problems.push(`kernel ${eagerBytes} bytes exceeds ${KERNEL_BUDGET}-byte budget`);
  if (baselineMode && activeBytes > ACTIVE_BUDGET) problems.push(`always-active instructions ${activeBytes} bytes exceed ${ACTIVE_BUDGET}-byte budget`);
  return {
    adapter,
    strategy: metadata.instruction_loading.strategy,
    mode: manifest.mode,
    measurement_status: baselineMode ? 'measured' : 'a-la-carte-managed-content-only',
    recipes: manifest.recipes_enabled || [],
    eager_bytes: eagerBytes,
    scoped_pointer_bytes: pointersAlwaysActive ? 0 : pointerBytes,
    always_active_pointer_bytes: pointersAlwaysActive ? pointerBytes : 0,
    always_active_bytes: activeBytes,
    estimated_always_active_tokens: Math.ceil(activeBytes / 4),
    complete_reference_bytes: sum(references),
    comparison: 'same installed policy set loaded eagerly at request start',
    estimated_avoided_eager_bytes_per_request: avoidedBytes,
    estimated_avoided_context_tokens_per_request: avoidedTokens,
    estimated_avoided_context_tokens_for_requests: options.requests && avoidedTokens !== null ? avoidedTokens * options.requests : null,
    budgets: { kernel_bytes: KERNEL_BUDGET, always_active_bytes: ACTIVE_BUDGET },
    problems,
  };
}

function audit(targetDir, options = {}) {
  const target = path.resolve(targetDir);
  const selected = options.adapters || ADAPTERS;
  if (!Array.isArray(selected) || !selected.length || selected.some((adapter) => !ADAPTERS.includes(adapter))) {
    throw new Error(`adapters must be one or more of: ${ADAPTERS.join(', ')}`);
  }
  const adapters = selected.map((adapter) => auditAdapter(target, adapter, options)).filter(Boolean);
  if (!adapters.length) throw new Error('no CONDUCTOR adapter manifests found');
  const problemCount = adapters.reduce((n, item) => n + item.problems.length, 0);
  return {
    schema_version: 1,
    target,
    requests: options.requests || null,
    token_estimate: 'bytes / 4 heuristic; context avoided, not provider billing or monetary savings',
    adapters,
    summary: {
      adapters: adapters.length,
      problems: problemCount,
      aggregation_note: adapters.length > 1
        ? 'adapter estimates are alternatives, not a per-user total; select the adapter actually used'
        : 'single-adapter estimate',
    },
  };
}

function render(report) {
  const lines = ['CONDUCTOR instruction footprint', ''];
  for (const item of report.adapters) {
    const avoided = item.estimated_avoided_context_tokens_per_request === null ? 'n/a (à la carte)' : `≈${item.estimated_avoided_context_tokens_per_request} tokens/request`;
    lines.push(`${item.adapter.padEnd(9)} active=${String(item.always_active_bytes).padStart(5)} B (~${String(item.estimated_always_active_tokens).padStart(4)} tokens)  avoided=${avoided}  ${item.problems.length ? 'FAIL' : 'OK'}`);
    if (report.requests && item.estimated_avoided_context_tokens_for_requests !== null) lines.push(`          ${report.requests.toLocaleString()} requests: ≈${item.estimated_avoided_context_tokens_for_requests.toLocaleString()} context tokens avoided`);
    for (const problem of item.problems) lines.push(`  - ${problem}`);
  }
  lines.push('', `Summary: ${report.summary.adapters} adapters, ${report.summary.problems} problems`);
  return lines.join('\n');
}

module.exports = { ACTIVE_BUDGET, ADAPTERS, KERNEL_BUDGET, audit, auditAdapter, render };

if (require.main === module) {
  try {
    const args = process.argv.slice(2);
    const json = args.includes('--json');
    const target = args.find((arg) => !arg.startsWith('-')) || '.';
    const requestArg = args.find((arg) => arg.startsWith('--requests='));
    const requests = requestArg ? Number(requestArg.slice('--requests='.length)) : null;
    if (requestArg && (!Number.isSafeInteger(requests) || requests < 1 || requests > 1000000000)) throw new Error('--requests must be an integer from 1 to 1000000000');
    const report = audit(target, { requests });
    process.stdout.write(json ? `${JSON.stringify(report, null, 2)}\n` : `${render(report)}\n`);
    process.exitCode = report.summary.problems ? 1 : 0;
  } catch (error) {
    process.stderr.write(`instruction footprint: ${error.message}\n`);
    process.exitCode = 2;
  }
}
