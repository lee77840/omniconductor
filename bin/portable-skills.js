#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SKILL_NAMES = ['plan-change', 'verify-change', 'review-change'];
const CONTRACTS = {
  claude: {
    projectPath: '.claude/skills',
    pathStatus: 'native',
    activation: 'automatic-and-explicit',
  },
  cursor: {
    projectPath: '.agents/skills',
    pathStatus: 'alias',
    activation: 'automatic-and-explicit',
  },
  copilot: {
    projectPath: '.agents/skills',
    pathStatus: 'documented-alternative',
    activation: 'automatic-and-explicit',
  },
  gemini: {
    projectPath: '.agents/skills',
    pathStatus: 'alias',
    activation: 'automatic-with-consent',
  },
  codex: {
    projectPath: '.agents/skills',
    pathStatus: 'native',
    activation: 'automatic-and-explicit',
  },
  windsurf: {
    projectPath: '.agents/skills',
    pathStatus: 'recommended',
    activation: 'automatic-and-explicit-one-active',
  },
};

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function validateSkillText(text, expectedName) {
  const problems = [];
  const lines = text.split(/\r?\n/);
  if (lines.length > 500) problems.push(`exceeds 500 lines (${lines.length})`);
  if (lines[0] !== '---') {
    problems.push('frontmatter must open on line 1');
    return problems;
  }
  const close = lines.indexOf('---', 1);
  if (close < 2) {
    problems.push('frontmatter closing delimiter missing');
    return problems;
  }

  const fields = new Map();
  for (const line of lines.slice(1, close)) {
    const match = line.match(/^([a-z_]+):\s*(.+)$/);
    if (!match) {
      problems.push(`invalid frontmatter line: ${line}`);
      continue;
    }
    if (fields.has(match[1])) problems.push(`duplicate frontmatter field: ${match[1]}`);
    fields.set(match[1], match[2].trim());
  }
  for (const field of fields.keys()) {
    if (field !== 'name' && field !== 'description') {
      problems.push(`unsupported portable frontmatter field: ${field}`);
    }
  }
  if (fields.get('name') !== expectedName) {
    problems.push(`name must be '${expectedName}'`);
  }
  if (!isNonEmptyString(fields.get('description'))) {
    problems.push('description must be non-empty');
  }
  if (!lines.slice(close + 1).some((line) => /^#\s+\S/.test(line))) {
    problems.push('body must contain a top-level heading');
  }
  return problems;
}

function validateSourceRoot(sourceRoot) {
  const problems = [];
  const allowed = new Set(SKILL_NAMES);
  if (!fs.existsSync(sourceRoot) || !fs.statSync(sourceRoot).isDirectory()) {
    return [`source root missing: ${sourceRoot}`];
  }
  for (const entry of fs.readdirSync(sourceRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || !allowed.has(entry.name)) {
      problems.push(`unexpected source entry: ${entry.name}`);
    }
  }
  for (const name of SKILL_NAMES) {
    const dir = path.join(sourceRoot, name);
    const file = path.join(dir, 'SKILL.md');
    if (!fs.existsSync(file)) {
      problems.push(`${name}: SKILL.md missing`);
      continue;
    }
    const extras = fs.readdirSync(dir).filter((entry) => entry !== 'SKILL.md');
    if (extras.length) problems.push(`${name}: instruction-only skill has extra entries: ${extras.join(', ')}`);
    const text = fs.readFileSync(file, 'utf8');
    for (const problem of validateSkillText(text, name)) {
      problems.push(`${name}: ${problem}`);
    }
    if (/\b(?:Claude|Cursor|Copilot|Gemini|Codex|Windsurf|Devin)\b/i.test(text)) {
      problems.push(`${name}: provider-specific tool name found`);
    }
    if (/\$(?:ARGUMENTS|CODEX_HOME|CLAUDE_PROJECT_DIR)\b/.test(text)) {
      problems.push(`${name}: provider-specific dynamic variable found`);
    }
  }
  return problems;
}

function validateAgentSkillsMetadata(metadata) {
  const problems = [];
  const expected = CONTRACTS[metadata && metadata.tool];
  if (!expected) return [`unknown adapter '${metadata && metadata.tool}'`];
  const contract = metadata.agent_skills;
  if (!contract || typeof contract !== 'object') return ['agent_skills object missing'];
  if (contract.schema_version !== 1) problems.push('agent_skills.schema_version must be 1');
  if (contract.project_path !== expected.projectPath) {
    problems.push(`agent_skills.project_path must be '${expected.projectPath}'`);
  }
  if (contract.path_status !== expected.pathStatus) {
    problems.push(`agent_skills.path_status must be '${expected.pathStatus}'`);
  }
  if (contract.activation !== expected.activation) {
    problems.push(`agent_skills.activation must be '${expected.activation}'`);
  }
  if (!isNonEmptyString(contract.explicit_invocation)) {
    problems.push('agent_skills.explicit_invocation must be a non-empty string');
  }
  if (!contract.source || !isNonEmptyString(contract.source.url)
      || !contract.source.url.startsWith('https://')) {
    problems.push('agent_skills.source.url must be an https URL');
  }
  if (!contract.source || !/^\d{4}-\d{2}-\d{2}$/.test(contract.source.checked || '')) {
    problems.push('agent_skills.source.checked must be YYYY-MM-DD');
  }
  const output = Array.isArray(metadata.outputs)
    ? metadata.outputs.find((item) => item.path === expected.projectPath)
    : null;
  if (!output || output.kind !== 'skills' || output.validated !== true) {
    problems.push('outputs must declare the validated skills project path');
  }
  if (!metadata.capabilities || !metadata.capabilities.tool_native
      || metadata.capabilities.tool_native.skills !== 'yes') {
    problems.push('capabilities.tool_native.skills must be yes');
  }
  if (!metadata.capabilities || !metadata.capabilities.conductor_emitted
      || metadata.capabilities.conductor_emitted.skills !== 'full') {
    problems.push('capabilities.conductor_emitted.skills must be full');
  }
  return problems;
}

function validateInstalled(targetRoot, adapter, sourceRoot) {
  const expected = CONTRACTS[adapter];
  if (!expected) return [`unknown adapter '${adapter}'`];
  const problems = [];
  for (const name of SKILL_NAMES) {
    const source = path.join(sourceRoot, name, 'SKILL.md');
    const installed = path.join(targetRoot, expected.projectPath, name, 'SKILL.md');
    if (!fs.existsSync(installed)) {
      problems.push(`${expected.projectPath}/${name}/SKILL.md missing`);
      continue;
    }
    const installedText = fs.readFileSync(installed, 'utf8');
    for (const problem of validateSkillText(installedText, name)) {
      problems.push(`${expected.projectPath}/${name}/SKILL.md: ${problem}`);
    }
    if (!fs.existsSync(source)
        || !fs.readFileSync(source).equals(fs.readFileSync(installed))) {
      problems.push(`${expected.projectPath}/${name}/SKILL.md differs from core source`);
    }
  }
  return problems;
}

function printProblems(problems) {
  for (const problem of problems) process.stderr.write(`portable-skills: ${problem}\n`);
}

if (require.main === module) {
  let problems;
  if (process.argv[2] === '--metadata') {
    const metadata = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
    problems = validateAgentSkillsMetadata(metadata);
  } else if (process.argv[2] === '--source-root') {
    problems = validateSourceRoot(path.resolve(process.argv[3]));
  } else if (process.argv[2] === '--installed') {
    problems = validateInstalled(
      path.resolve(process.argv[3]),
      process.argv[4],
      path.resolve(process.argv[5]),
    );
  } else {
    process.stderr.write('Usage: portable-skills.js --metadata <file> | --source-root <dir> | --installed <target> <adapter> <source-root>\n');
    process.exit(2);
  }
  if (problems.length) {
    printProblems(problems);
    process.exit(1);
  }
  process.stdout.write('OK — portable Agent Skills contract valid.\n');
}

module.exports = {
  CONTRACTS,
  SKILL_NAMES,
  validateAgentSkillsMetadata,
  validateInstalled,
  validateSkillText,
  validateSourceRoot,
};
