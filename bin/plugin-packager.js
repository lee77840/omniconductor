#!/usr/bin/env node
'use strict';

/* Optional provider package compiler (ADR-062). */

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TOOLS = ['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf'];
const BASELINE_ROLES = ['planner', 'reviewer', 'code-reviewer', 'builder', 'helper', 'designer', 'scribe', 'utility'];
const BASELINE_SKILLS = ['plan-change', 'verify-change', 'review-change'];
const OPTIONAL_SKILLS = ['propose-skill', 'coordinate-work'];
const DIRECT_INSTALL_COMPONENTS = new Set([
  'skills', 'roles', 'rules', 'guard-hooks', 'reflector', 'model-routing',
  'work-coordination', 'reversible-ownership',
]);

function safeRelative(value) {
  if (typeof value !== 'string' || !value || path.isAbsolute(value) || value.includes('\0')) return false;
  const normalized = path.posix.normalize(value.replace(/\\/g, '/'));
  return normalized !== '..' && !normalized.startsWith('../');
}

function validateMetadata(metadata) {
  const contract = metadata && metadata.plugin_packaging;
  const problems = [];
  if (!contract || typeof contract !== 'object') return ['plugin_packaging is required'];
  if (contract.schema_version !== 1) problems.push('schema_version must be 1');
  if (!['native-partial', 'direct-fallback'].includes(contract.mode)) {
    problems.push('mode must be native-partial|direct-fallback');
  }
  if (contract.mode === 'native-partial') {
    if (!safeRelative(contract.manifest_path)) problems.push('native-partial needs a safe manifest_path');
  } else if (contract.manifest_path !== null) {
    problems.push('direct-fallback manifest_path must be null');
  }
  for (const field of ['native_components', 'inactive_reference_components', 'direct_install_required_for']) {
    if (!Array.isArray(contract[field])) problems.push(`${field} must be an array`);
    else if (contract[field].some((value) => typeof value !== 'string' || !value)) problems.push(`${field} must contain non-empty strings`);
    else if (new Set(contract[field]).size !== contract[field].length) problems.push(`${field} must not contain duplicates`);
  }
  if (!Array.isArray(contract.direct_install_required_for) || !contract.direct_install_required_for.length) {
    problems.push('direct_install_required_for must be non-empty');
  } else {
    for (const component of contract.direct_install_required_for) {
      if (!DIRECT_INSTALL_COMPONENTS.has(component)) problems.push(`unknown direct-install component: ${component}`);
    }
    if (!contract.direct_install_required_for.includes('work-coordination')) {
      problems.push('direct_install_required_for must include work-coordination');
    }
  }
  if (!contract.source || typeof contract.source.url !== 'string' || !/^https:\/\//.test(contract.source.url)) {
    problems.push('source.url must be https');
  }
  if (!contract.source || !/^\d{4}-\d{2}-\d{2}$/.test(contract.source.checked || '')) {
    problems.push('source.checked must be YYYY-MM-DD');
  }
  return problems;
}

function loadMetadata(tool) {
  const file = path.join(ROOT, 'adapters', tool, 'metadata.json');
  const metadata = JSON.parse(fs.readFileSync(file, 'utf8'));
  const problems = validateMetadata(metadata);
  if (problems.length) throw new Error(`${tool} metadata: ${problems.join('; ')}`);
  return metadata;
}

function readVersion() {
  return JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')).version;
}

function copyTree(source, destination) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) throw new Error(`refusing symlinked package source: ${source}`);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const entry of fs.readdirSync(source).sort()) copyTree(path.join(source, entry), path.join(destination, entry));
    return;
  }
  if (!stat.isFile()) throw new Error(`unsupported package source: ${source}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
  fs.chmodSync(destination, 0o644);
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o644 });
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value.endsWith('\n') ? value : `${value}\n`, { mode: 0o644 });
}

function compileAdapter(tool) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), `conductor-package-${tool}-`));
  const result = spawnSync(process.execPath, [
    path.join(ROOT, 'bin', 'omniconductor.js'),
    'init',
    `--target=${tool}`,
    temp,
    '--mode=full',
    '--no-prompt',
    '--accept-model-defaults',
  ], { cwd: ROOT, encoding: 'utf8' });
  if (result.status !== 0) {
    fs.rmSync(temp, { recursive: true, force: true });
    throw new Error(`${tool} adapter compilation failed: ${result.stderr || result.stdout}`);
  }
  return temp;
}

function copyBaselineSkills(compiled, metadata, packageRoot) {
  const skillRoot = path.join(compiled, metadata.agent_skills.project_path);
  for (const skill of BASELINE_SKILLS) {
    copyTree(path.join(skillRoot, skill), path.join(packageRoot, 'skills', skill));
  }
  for (const skill of OPTIONAL_SKILLS) {
    copyTree(
      path.join(ROOT, 'core', 'skills', skill),
      path.join(packageRoot, 'optional-skills', skill),
    );
  }
}

function copyReferences(packageRoot) {
  for (const file of fs.readdirSync(path.join(ROOT, 'core', 'universal-rules')).sort()) {
    if (file.endsWith('.md')) copyTree(
      path.join(ROOT, 'core', 'universal-rules', file),
      path.join(packageRoot, 'references', 'universal-rules', file),
    );
  }
  copyTree(
    path.join(ROOT, 'core', 'hooks', 'registry.json'),
    path.join(packageRoot, 'references', 'hook-registry.json'),
  );
}

function copyNativeAgents(tool, compiled, packageRoot) {
  const roots = {
    claude: '.claude/agents',
    copilot: '.github/agents',
    gemini: '.gemini/agents',
  };
  if (roots[tool]) copyTree(path.join(compiled, roots[tool]), path.join(packageRoot, 'agents'));
  if (tool === 'codex') copyTree(path.join(compiled, '.codex/agents'), path.join(packageRoot, 'references', 'agents'));
}

function copyFallbackPayload(tool, compiled, packageRoot) {
  const paths = tool === 'cursor'
    ? ['.cursor/rules', '.cursor/agents', '.agents/skills']
    : ['.windsurfrules', '.devin/rules', '.windsurf/workflows', '.agents/skills'];
  for (const relative of paths) {
    const source = path.join(compiled, relative);
    if (fs.existsSync(source)) copyTree(source, path.join(packageRoot, 'direct-install', relative));
  }
}

function emitNativeManifest(tool, packageRoot, version) {
  const common = {
    name: 'omniconductor',
    version,
    description: 'Portable CONDUCTOR workflow skills and role profiles.',
  };
  if (tool === 'claude') {
    writeJson(path.join(packageRoot, '.claude-plugin', 'plugin.json'), {
      ...common,
      author: { name: 'LFamily Labs LLC' },
      homepage: 'https://github.com/lee77840/omniconductor',
      license: 'Apache-2.0',
    });
  } else if (tool === 'copilot') {
    writeJson(path.join(packageRoot, 'plugin.json'), {
      ...common,
      agents: './agents',
      skills: './skills',
    });
  } else if (tool === 'gemini') {
    writeJson(path.join(packageRoot, 'gemini-extension.json'), {
      ...common,
      contextFileName: 'GEMINI.md',
    });
  } else if (tool === 'codex') {
    writeJson(path.join(packageRoot, '.codex-plugin', 'plugin.json'), {
      ...common,
      author: { name: 'LFamily Labs LLC' },
      license: 'Apache-2.0',
      skills: './skills/',
    });
  }
}

function inventory(packageRoot) {
  const files = [];
  const walk = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.isFile()) {
        const relative = path.relative(packageRoot, absolute).replace(/\\/g, '/');
        if (relative === 'PACKAGE-CONTRACT.json') continue;
        const digest = crypto.createHash('sha256').update(fs.readFileSync(absolute)).digest('hex');
        files.push({ path: relative, sha256: digest });
      }
    }
  };
  walk(packageRoot);
  return files;
}

function packageReadme(tool, metadata) {
  const contract = metadata.plugin_packaging;
  const modeText = contract.mode === 'native-partial'
    ? `This directory has a provider-native manifest at \`${contract.manifest_path}\`.`
    : 'No provider-native manifest is emitted because the public package schema is not verified. Use the direct installer.';
  return `# OMNICONDUCTOR package — ${metadata.display_name}

${modeText}

The active package contains the three baseline instruction-only skills. Provider
components listed in \`PACKAGE-CONTRACT.json\` are the only native claims. Universal
rules and the hook registry are inert references; no MCP server, connector, secret,
remote connector endpoint, or executable hook is bundled.

The \`optional-skills/propose-skill\` and \`optional-skills/coordinate-work\` sources
are intentionally inactive. Install them through the \`self-improvement\` and
\`git-hygiene\` recipes when wanted.

For complete project-scoped rules, model routing, guard hooks, ownership manifests,
and reversible uninstall, use:

\`npx omniconductor init --target=${tool} <project>\`

Do not combine native and direct-install copies in the same project without first
removing one owner; duplicated skills, roles, or hooks can run twice.
`;
}

function buildTool(tool, outputAbs, { force = false } = {}) {
  const metadata = loadMetadata(tool);
  const contract = metadata.plugin_packaging;
  const packageRoot = path.join(outputAbs, `conductor-${tool}`);
  if (fs.existsSync(packageRoot)) {
    const stat = fs.lstatSync(packageRoot);
    if (stat.isSymbolicLink()) throw new Error(`refusing symlinked package destination: ${packageRoot}`);
    if (!force) throw new Error(`package destination exists (use --force): ${packageRoot}`);
    fs.rmSync(packageRoot, { recursive: true, force: true });
  }
  fs.mkdirSync(packageRoot, { recursive: true });
  const compiled = compileAdapter(tool);
  try {
    copyBaselineSkills(compiled, metadata, packageRoot);
    copyReferences(packageRoot);
    if (contract.mode === 'native-partial') {
      copyNativeAgents(tool, compiled, packageRoot);
      if (tool === 'gemini') copyTree(path.join(compiled, 'GEMINI.md'), path.join(packageRoot, 'GEMINI.md'));
      emitNativeManifest(tool, packageRoot, readVersion());
    } else {
      copyFallbackPayload(tool, compiled, packageRoot);
    }
    writeText(path.join(packageRoot, 'README.md'), packageReadme(tool, metadata));
    const result = {
      schema_version: 1,
      tool,
      display_name: metadata.display_name,
      conductor_version: readVersion(),
      mode: contract.mode,
      native_manifest: contract.manifest_path,
      native_components: contract.native_components,
      inactive_reference_components: contract.inactive_reference_components,
      inactive_optional_skills: [...OPTIONAL_SKILLS],
      direct_install_required_for: contract.direct_install_required_for,
      contains_mcp_server: false,
      contains_remote_connector: false,
      contains_executable_hook: false,
      trust_audit_command: `omniconductor audit extensions <project> --target=${tool}`,
      direct_install_command: `omniconductor init --target=${tool} <project>`,
      source: contract.source,
      files: inventory(packageRoot),
    };
    writeJson(path.join(packageRoot, 'PACKAGE-CONTRACT.json'), result);
    return { tool, directory: packageRoot, mode: contract.mode, files: result.files.length + 1 };
  } catch (error) {
    fs.rmSync(packageRoot, { recursive: true, force: true });
    throw error;
  } finally {
    fs.rmSync(compiled, { recursive: true, force: true });
  }
}

function assertOutput(outputDir) {
  const outputAbs = path.resolve(outputDir);
  const parsed = path.parse(outputAbs);
  if (outputAbs === parsed.root) throw new Error('refusing filesystem root as package output');
  let existing = outputAbs;
  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) break;
    existing = parent;
  }
  if (fs.existsSync(existing)) {
    const existingStat = fs.lstatSync(existing);
    if (existingStat.isSymbolicLink()) throw new Error(`refusing symlinked package output ancestor: ${existing}`);
    if (!existingStat.isDirectory()) throw new Error(`package output ancestor is not a directory: ${existing}`);
  }
  if (fs.existsSync(outputAbs) && fs.lstatSync(outputAbs).isSymbolicLink()) {
    throw new Error(`refusing symlinked output directory: ${outputAbs}`);
  }
  return outputAbs;
}

function plan(outputDir, tools) {
  const outputAbs = assertOutput(outputDir);
  return tools.map((tool) => {
    const metadata = loadMetadata(tool);
    return {
      tool,
      directory: path.join(outputAbs, `conductor-${tool}`),
      mode: metadata.plugin_packaging.mode,
      manifest: metadata.plugin_packaging.manifest_path,
    };
  });
}

function build(outputDir, tools = TOOLS, options = {}) {
  const outputAbs = assertOutput(outputDir);
  const planned = plan(outputAbs, tools);
  if (options.strictNative) {
    const fallbacks = planned.filter((item) => item.mode !== 'native-partial');
    if (fallbacks.length) throw new Error(`strict-native refused fallback adapters: ${fallbacks.map((item) => item.tool).join(', ')}`);
  }
  if (options.dryRun) return { dry_run: true, output: outputAbs, packages: planned };
  for (const item of planned) {
    if (!fs.existsSync(item.directory)) continue;
    if (fs.lstatSync(item.directory).isSymbolicLink()) {
      throw new Error(`refusing symlinked package destination: ${item.directory}`);
    }
    if (!options.force) throw new Error(`package destination exists (use --force): ${item.directory}`);
  }
  fs.mkdirSync(outputAbs, { recursive: true });
  const staging = fs.mkdtempSync(path.join(outputAbs, '.conductor-package-staging-'));
  try {
    const staged = tools.map((tool) => buildTool(tool, staging));
    const packages = [];
    for (const item of staged) {
      const destination = path.join(outputAbs, `conductor-${item.tool}`);
      if (fs.existsSync(destination)) fs.rmSync(destination, { recursive: true, force: true });
      fs.renameSync(item.directory, destination);
      packages.push({ ...item, directory: destination });
    }
    return { dry_run: false, output: outputAbs, packages };
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}

module.exports = {
  TOOLS,
  build,
  plan,
  validateMetadata,
};
