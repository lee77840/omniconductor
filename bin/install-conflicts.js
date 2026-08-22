'use strict';

const fs = require('fs');
const path = require('path');
const recipeOnboarding = require('./recipe-onboarding.js');

// These are instruction/runtime surfaces that a first full/minimal install may
// replace or populate with CONDUCTOR-owned names. Structurally merged JSON
// configuration is deliberately absent: it is not a replacement conflict.
const SURFACES = Object.freeze({
  claude: ['CLAUDE.md', '.claude/rules', '.claude/agents'],
  cursor: ['.cursor/rules', '.cursor/agents'],
  copilot: ['.github/copilot-instructions.md', '.github/instructions', '.github/agents'],
  gemini: ['GEMINI.md', '.gemini/styleguide.md', '.gemini/agents'],
  codex: ['AGENTS.md', '.codex/conductor', '.codex/agents'],
  windsurf: ['.devin/rules', '.windsurf/workflows'],
  opencode: ['.opencode/rules', '.opencode/agents', '.opencode/plugins/conductor-guards.js', '.opencode/commands/reflect.md', '.opencode/skills'],
});

const POLICIES = new Set(['replace', 'recipes-only', 'abort']);

function ownedInstall(root, tool) {
  const scoped = path.join(root, '.conductor', 'manifests', `${tool}.json`);
  if (fs.existsSync(scoped)) return true;
  const legacy = path.join(root, '.conductor-manifest.json');
  try {
    const parsed = JSON.parse(fs.readFileSync(legacy, 'utf8'));
    return parsed && parsed.adapter === tool && parsed.manifest_scope !== 'aggregate';
  } catch { return false; }
}

function scan(root, targets) {
  const conflicts = [];
  for (const tool of targets) {
    if (ownedInstall(root, tool)) continue;
    for (const relative of SURFACES[tool] || []) {
      if (fs.existsSync(path.join(root, ...relative.split('/')))) conflicts.push({ tool, path: relative });
    }
  }
  return conflicts;
}

function render(output, conflicts) {
  output.write(`\nExisting unmanaged instruction surfaces detected (${conflicts.length}):\n`);
  for (const item of conflicts) output.write(`  - ${item.tool}: ${item.path}\n`);
  output.write('\nCONDUCTOR will not guess how to merge Markdown instructions. JSON/hook configs with a verified structural merger remain lossless.\n');
}

async function resolve(options) {
  const {
    targetAbs, targets, mode, modeExplicit, policy, explicitRecipes,
    noPrompt, dryRun, ask, output,
  } = options;
  if (policy !== null && !POLICIES.has(policy)) {
    throw new Error(`unknown --conflict-policy '${policy}' (use replace, recipes-only, or abort)`);
  }
  const conflicts = scan(targetAbs, targets);
  if (!conflicts.length) return { mode, explicitRecipes, conflicts, source: 'none' };
  render(output, conflicts);
  if (dryRun) {
    output.write('Dry-run only: no file will be changed. A real install must choose an explicit conflict policy.\n');
    return { mode, explicitRecipes, conflicts, source: 'dry-run' };
  }

  if (policy === 'abort') throw new Error('installation cancelled by --conflict-policy=abort');
  if (policy === 'replace') {
    if (modeExplicit && !['full', 'minimal'].includes(mode)) {
      throw new Error('--conflict-policy=replace is only compatible with --mode=full or --mode=minimal');
    }
    return { mode, explicitRecipes, conflicts, source: 'explicit-replace' };
  }
  if (policy === 'recipes-only') {
    const recipes = recipeOnboarding.normalizeRecipes(explicitRecipes === null ? '' : explicitRecipes);
    if (!recipes.length) throw new Error('--conflict-policy=recipes-only requires a non-empty --recipes=A,B list');
    return { mode: 'recipes-only', explicitRecipes: recipes.join(','), conflicts, source: 'explicit-recipes-only' };
  }

  // An explicit mode is itself an explicit policy. This preserves scripted
  // compatibility while making the formerly implicit default fail closed.
  if (modeExplicit) {
    if (['recipes-only', 'reflector-only'].includes(mode)) return { mode, explicitRecipes, conflicts, source: 'explicit-separated' };
    if (mode === 'strict') return { mode, explicitRecipes, conflicts, source: 'explicit-strict' };
    if (['full', 'minimal'].includes(mode)) return { mode, explicitRecipes, conflicts, source: 'explicit-replace' };
  }

  if (noPrompt || typeof ask !== 'function') {
    throw new Error('existing unmanaged instructions require an explicit choice before any write; use --mode=full to back up and replace, --mode=recipes-only --recipes=A,B to preserve them, or --conflict-policy=abort');
  }

  output.write('\nChoose installation behavior:\n');
  output.write('  1. Preserve existing instructions; install selected recipes only (recommended)\n');
  output.write('  2. Back up existing files and install the full CONDUCTOR baseline\n');
  output.write('  3. Cancel without writing\n');
  const answer = String(await ask('Selection [1-3]: ')).trim();
  if (answer === '2') return { mode: 'full', explicitRecipes, conflicts, source: 'interactive-replace' };
  if (answer === '3') throw new Error('installation cancelled; no project file was written');
  if (answer !== '1') throw new Error(`invalid conflict selection: ${answer || '(empty)'}`);
  const recipeAnswer = String(await ask('Recipes to install (comma-separated; required): ')).trim();
  const recipes = recipeOnboarding.normalizeRecipes(recipeAnswer);
  if (!recipes.length) throw new Error('recipes-only preservation selected without any recipe; no project file was written');
  return { mode: 'recipes-only', explicitRecipes: recipes.join(','), conflicts, source: 'interactive-recipes-only' };
}

module.exports = { POLICIES, SURFACES, ownedInstall, resolve, scan };
