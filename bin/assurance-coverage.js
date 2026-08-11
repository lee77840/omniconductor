#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const LEVELS = [
  'unsupported',
  'instruction-only',
  'emit-verified',
  'native-contract-tested',
  'live-verified',
  'adversarially-verified',
];
const LEVEL_RANK = new Map(LEVELS.map((level, index) => [level, index]));

function relativeFile(file) {
  const absolute = path.resolve(ROOT, file);
  const relative = path.relative(ROOT, absolute).split(path.sep).join('/');
  if (!relative || relative.startsWith('../') || path.isAbsolute(relative)) {
    throw new Error(`evidence path escapes repository: ${file}`);
  }
  const stat = fs.lstatSync(absolute);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(`evidence must be a regular repository file: ${relative}`);
  }
  return relative;
}

function metadata(tool) {
  const file = `adapters/${tool}/metadata.json`;
  const value = JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));
  if (value.tool !== tool) throw new Error(`${file} tool must be '${tool}'`);
  return { file, value };
}

function matrixEntry(level, reason, evidence) {
  if (!LEVEL_RANK.has(level)) throw new Error(`unknown assurance level '${level}'`);
  return {
    level,
    reason,
    evidence: [...new Set(evidence.map(relativeFile))].sort(),
  };
}

function allTools(level, reason, evidence) {
  return Object.fromEntries(TOOLS.map((tool) => [tool, matrixEntry(level, reason, evidence(tool))]));
}

function discoverMarkdown(dir, excluded = new Set()) {
  return fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md') && !excluded.has(entry.name))
    .map((entry) => entry.name.replace(/\.md$/, ''))
    .sort();
}

function discoverSkills() {
  return fs.readdirSync(path.join(ROOT, 'core', 'skills'), { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
}

function buildReport() {
  const records = [];
  const metadataByTool = Object.fromEntries(TOOLS.map((tool) => [tool, metadata(tool)]));

  for (const id of discoverMarkdown('core/universal-rules', new Set(['README.md']))) {
    const source = `core/universal-rules/${id}.md`;
    records.push({
      id: `rule:${id}`,
      kind: 'universal-rule',
      source,
      adapters: allTools('emit-verified', 'emitted and lifecycle-tested in supported install modes',
        (tool) => [source, `adapters/${tool}/metadata.json`, 'tools/test-install-modes.sh']),
    });
  }

  for (const id of discoverMarkdown('core/recipes', new Set(['README.md']))) {
    const source = `core/recipes/${id}.md`;
    records.push({
      id: `recipe:${id}`,
      kind: 'recipe',
      source,
      adapters: allTools('emit-verified', 'opt-in emission and uninstall are exercised by adapter mode tests',
        (tool) => [source, `adapters/${tool}/metadata.json`, 'tools/test-install-modes.sh']),
    });
  }

  for (const id of discoverSkills()) {
    const source = `core/skills/${id}/SKILL.md`;
    records.push({
      id: `skill:${id}`,
      kind: 'portable-skill',
      source,
      adapters: allTools('emit-verified', 'byte identity, manifest ownership, collision, and uninstall are tested',
        (tool) => [source, `adapters/${tool}/metadata.json`, 'tools/test-portable-skills.js']),
    });
  }

  const hookFile = 'core/hooks/registry.json';
  const hooks = JSON.parse(fs.readFileSync(path.join(ROOT, hookFile), 'utf8'));
  for (const registration of [...hooks.registrations].sort((a, b) => a.id.localeCompare(b.id))) {
    const adapters = {};
    for (const tool of TOOLS) {
      const contract = metadataByTool[tool].value.hook_compiler;
      const isNative = Boolean(registration.targets && registration.targets[tool]);
      if (isNative) {
        adapters[tool] = matrixEntry(
          'native-contract-tested',
          contract && Array.isArray(contract.native_policies) && contract.native_policies.includes(registration.id)
            ? 'portable hook compiler metadata and provider-native registration are regression-tested'
            : 'feature-scoped provider-native registration is regression-tested by the shared hook suite',
          [hookFile, registration.source, metadataByTool[tool].file, 'tools/test-hook-compiler.js'],
        );
      } else if (registration.fallback) {
        adapters[tool] = matrixEntry(
          'instruction-only',
          `no verified native registration; portable fallback is ${registration.fallback}`,
          [hookFile, registration.source, metadataByTool[tool].file],
        );
      } else {
        adapters[tool] = matrixEntry(
          'unsupported',
          'no verified native registration or portable fallback',
          [hookFile, registration.source, metadataByTool[tool].file],
        );
      }
    }
    records.push({
      id: `hook:${registration.id}`,
      kind: 'hook-policy',
      source: registration.source,
      adapters,
    });
  }

  for (const tool of TOOLS) {
    const meta = metadataByTool[tool];
    const live = meta.value.live_verification || {};
    const liveLevel = live.status === 'verified' ? 'live-verified' : 'emit-verified';
    const liveReason = live.status === 'verified'
      ? `recorded deterministic instruction-loading probe (${live.date || 'date unavailable'})`
      : 'adapter output is tested but effective instruction loading remains live-pending';
    const liveAdapters = {};
    const runtimeAdapters = {};
    for (const candidate of TOOLS) {
      liveAdapters[candidate] = candidate === tool
        ? matrixEntry(liveLevel, liveReason, [meta.file, 'tools/live-verify.sh'])
        : matrixEntry('unsupported', 'artifact belongs to another adapter runtime', [meta.file]);
      runtimeAdapters[candidate] = candidate === tool
        ? matrixEntry('native-contract-tested', 'offline lifecycle/version/auth contract is regression-tested',
          [meta.file, 'bin/runtime-contract.js', 'tools/test-runtime-contract.js'])
        : matrixEntry('unsupported', 'artifact belongs to another adapter runtime', [meta.file]);
    }
    records.push({
      id: `adapter-load:${tool}`,
      kind: 'adapter-instruction-load',
      source: meta.file,
      adapters: liveAdapters,
    });
    records.push({
      id: `runtime-contract:${tool}`,
      kind: 'runtime-contract',
      source: meta.file,
      adapters: runtimeAdapters,
    });
  }

  records.sort((a, b) => a.id.localeCompare(b.id));
  const summary = Object.fromEntries(TOOLS.map((tool) => [tool,
    Object.fromEntries(LEVELS.map((level) => [level, 0]))]));
  for (const record of records) {
    for (const tool of TOOLS) summary[tool][record.adapters[tool].level] += 1;
  }

  return {
    schema_version: 1,
    generated_from: 'repository-source',
    levels: LEVELS,
    adapters: TOOLS,
    summary,
    records,
  };
}

function compare(current, previous) {
  if (!previous || previous.schema_version !== 1 || !Array.isArray(previous.records)) {
    throw new Error('comparison report must be assurance coverage schema v1');
  }
  if (!Array.isArray(previous.adapters)
      || previous.adapters.length !== TOOLS.length
      || previous.adapters.some((tool, index) => tool !== TOOLS[index])) {
    throw new Error('comparison report must contain the exact six-adapter contract');
  }
  const previousIds = new Set();
  for (const record of previous.records) {
    if (!record || typeof record.id !== 'string' || !record.id || previousIds.has(record.id)) {
      throw new Error('comparison report contains a missing or duplicate artifact id');
    }
    previousIds.add(record.id);
    if (!record.adapters || typeof record.adapters !== 'object') {
      throw new Error(`comparison report is missing adapter coverage for ${record.id}`);
    }
    for (const tool of TOOLS) {
      if (!record.adapters[tool] || !LEVEL_RANK.has(record.adapters[tool].level)) {
        throw new Error(`comparison report has invalid ${tool} coverage for ${record.id}`);
      }
    }
  }
  const now = new Map(current.records.map((record) => [record.id, record]));
  const regressions = [];
  for (const before of previous.records) {
    const after = now.get(before.id);
    if (!after) {
      regressions.push(`${before.id}: artifact disappeared`);
      continue;
    }
    for (const tool of TOOLS) {
      const oldEntry = before.adapters && before.adapters[tool];
      const newEntry = after.adapters && after.adapters[tool];
      if (!newEntry || !LEVEL_RANK.has(newEntry.level)) {
        regressions.push(`${before.id}/${tool}: coverage disappeared`);
      } else if (LEVEL_RANK.get(newEntry.level) < LEVEL_RANK.get(oldEntry.level)) {
        regressions.push(`${before.id}/${tool}: ${oldEntry.level} -> ${newEntry.level}`);
      }
    }
  }
  return regressions;
}

function render(report) {
  const icon = {
    unsupported: '—',
    'instruction-only': 'I',
    'emit-verified': 'E',
    'native-contract-tested': 'N',
    'live-verified': 'L',
    'adversarially-verified': 'A',
  };
  const lines = [
    '# Agent Policy Assurance Coverage',
    '',
    '> Generated from repository evidence. Do not hand-edit. A general adapter live',
    '> probe does not upgrade a specific recipe, skill, or hook without exact evidence.',
    '',
    'Levels: `—` unsupported · `I` instruction-only · `E` emit-verified ·',
    '`N` native-contract-tested · `L` live-verified · `A` adversarially-verified.',
    '',
    '| Artifact | Kind | Claude | Cursor | Copilot | Gemini | Codex | Windsurf |',
    '|---|---|---:|---:|---:|---:|---:|---:|',
  ];
  for (const record of report.records) {
    lines.push(`| \`${record.id}\` | ${record.kind} | ${TOOLS.map((tool) => icon[record.adapters[tool].level]).join(' | ')} |`);
  }
  lines.push('', '## Evidence summary', '');
  lines.push('| Adapter | I | E | N | L | A | Unsupported |');
  lines.push('|---|---:|---:|---:|---:|---:|---:|');
  for (const tool of TOOLS) {
    const item = report.summary[tool];
    lines.push(`| ${tool} | ${item['instruction-only']} | ${item['emit-verified']} | ${item['native-contract-tested']} | ${item['live-verified']} | ${item['adversarially-verified']} | ${item.unsupported} |`);
  }
  lines.push('', 'Machine-readable evidence paths and reasons are in `docs/AGENT-EVAL-COVERAGE.json`.', '');
  return lines.join('\n');
}

module.exports = { LEVELS, TOOLS, buildReport, compare, render };
