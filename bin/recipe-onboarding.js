'use strict';

const fs = require('fs');
const path = require('path');

const CATALOG = [
  { id: 'debugging', policy: 'automatic', summary: 'root-cause-first debugging instead of guess-and-check' },
  { id: 'loop-engineering', policy: 'automatic', summary: 'bounded, externally verified agent loops' },
  { id: 'coding-conventions', policy: 'recommended', detector: 'typescript', summary: 'TypeScript naming, type-safety, and error conventions' },
  { id: 'database-discipline', policy: 'recommended', detector: 'database', summary: 'migration, access-control, seed, and drift discipline' },
  { id: 'design-system', policy: 'recommended', detector: 'designTokens', summary: 'design tokens instead of scattered literals' },
  { id: 'i18n', policy: 'recommended', detector: 'i18n', summary: 'all-locale key and artifact synchronization' },
  { id: 'monorepo', policy: 'recommended', detector: 'monorepo', summary: 'shared-package and stable workspace structure' },
  { id: 'non-vacuous-testing', policy: 'recommended', detector: 'tests', summary: 'prove tests detect the defect they claim to guard' },
  { id: 'release-provenance', policy: 'recommended', detector: 'policyMaterial', summary: 'source, license, authority, and release evidence' },
  { id: 'tdd', policy: 'recommended', detector: 'tests', summary: 'red-green-refactor as the team workflow' },
  { id: 'visual-baseline-integrity', policy: 'recommended', detector: 'visualTests', summary: 'pinned and reviewable visual regression evidence' },
  { id: 'web-mobile-parity', policy: 'recommended', detector: 'webMobile', summary: 'paired web/mobile feature and bug handling' },
  { id: 'auto-mock-data', policy: 'consent', detector: 'database', summary: 'automatically maintain mock/seed data on schema changes' },
  { id: 'branch-strategy', policy: 'consent', detector: 'git', summary: 'adopt CONDUCTOR’s three-branch deployment workflow' },
  { id: 'database-change-assurance', policy: 'consent', detector: 'database', summary: 'strict approval/evidence envelope for high-risk database writes' },
  { id: 'git-hygiene', policy: 'consent', detector: 'git', summary: 'strong branch, worktree, push, and cleanup obligations' },
  { id: 'self-improvement', policy: 'consent', detector: 'always', summary: 'collect local trajectory pointers and run propose-only reflection' },
];
const IDS = new Set(CATALOG.map((item) => item.id));

function exists(root, rel) { return fs.existsSync(path.join(root, rel)); }
function readPackage(root) {
  const file = path.join(root, 'package.json');
  try {
    if (fs.statSync(file).size > 1024 * 1024) return {};
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch { return {}; }
}
function projectSignals(root) {
  const pkg = readPackage(root);
  const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
  const depNames = Object.keys(deps);
  const has = (pattern) => depNames.some((name) => pattern.test(name));
  const dirs = (() => { try { return fs.readdirSync(root); } catch { return []; } })();
  const names = new Set(dirs.map((name) => name.toLowerCase()));
  const git = exists(root, '.git');
  const database = exists(root, 'prisma/schema.prisma') || exists(root, 'migrations')
    || exists(root, 'db/migrations') || exists(root, 'supabase/migrations')
    || has(/^(prisma|drizzle-|sequelize|typeorm|knex|pg|mysql|sqlite)/i);
  const tests = has(/(jest|vitest|mocha|playwright|cypress|pytest)/i)
    || dirs.some((name) => /(^|\.)(test|spec)s?(\.|$)/i.test(name)) || exists(root, 'tests');
  return {
    always: true,
    git,
    database,
    typescript: exists(root, 'tsconfig.json') || has(/^typescript$/i),
    monorepo: Array.isArray(pkg.workspaces) || Boolean(pkg.workspaces) || exists(root, 'pnpm-workspace.yaml')
      || exists(root, 'turbo.json') || exists(root, 'nx.json'),
    i18n: names.has('locales') || names.has('i18n') || exists(root, 'src/locales') || has(/i18n|formatjs|lingui/i),
    designTokens: exists(root, 'tokens') || exists(root, 'design-tokens') || exists(root, 'src/tokens')
      || has(/style-dictionary|design-token/i),
    tests,
    visualTests: has(/playwright|cypress|storybook|loki|chromatic/i) || exists(root, 'tests/visual')
      || exists(root, '__snapshots__'),
    webMobile: (exists(root, 'apps/web') && (exists(root, 'apps/mobile') || exists(root, 'android') || exists(root, 'ios')))
      || (has(/react-native|expo/i) && (has(/next|vite|react-dom/i) || exists(root, 'web'))),
    policyMaterial: exists(root, 'docs/legal') || exists(root, 'LICENSE') || exists(root, 'LICENSE.md')
      || names.has('assets') || names.has('licenses'),
  };
}

function normalizeRecipes(value) {
  const list = Array.isArray(value) ? value : String(value || '').split(',');
  const normalized = [...new Set(list.map((item) => item.trim()).filter(Boolean))];
  const unknown = normalized.filter((id) => !IDS.has(id));
  if (unknown.length) throw new Error(`unknown recipe(s): ${unknown.join(', ')}`);
  return normalized;
}

function currentSelections(root, targets) {
  const result = {};
  for (const tool of targets) {
    const file = path.join(root, '.conductor', 'manifests', `${tool}.json`);
    if (!fs.existsSync(file)) { result[tool] = null; continue; }
    try {
      const st = fs.lstatSync(file);
      if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) throw new Error('unsafe manifest');
      const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
      result[tool] = normalizeRecipes(manifest.recipes_enabled || []);
    } catch (error) {
      throw new Error(`cannot preserve ${tool} recipes from ${file}: ${error.message}`);
    }
  }
  return result;
}

async function yesNo(ask, question, defaultYes) {
  const answer = String(await ask(`${question} ${defaultYes ? '[Y/n]' : '[y/N]'}: `)).trim().toLowerCase();
  if (!answer) return defaultYes;
  return answer === 'y' || answer === 'yes';
}

function printGroup(output, title, items) {
  output.write(`\n${title}\n`);
  items.forEach((item, index) => output.write(`  ${index + 1}. ${item.id} — ${item.summary}\n`));
}

async function chooseFresh({ root, interactive, ask, output }) {
  const signals = projectSignals(root);
  const automatic = CATALOG.filter((item) => item.policy === 'automatic');
  const recommended = CATALOG.filter((item) => item.policy === 'recommended' && signals[item.detector]);
  const consent = CATALOG.filter((item) => item.policy === 'consent' && signals[item.detector]);
  const selected = automatic.map((item) => item.id);
  printGroup(output, 'Automatic safe defaults (enabled; use --recipes= for an exact override):', automatic);
  if (!interactive) return selected;
  if (recommended.length) {
    printGroup(output, 'Detected project recommendations:', recommended);
    if (await yesNo(ask, 'Enable all detected recommendations?', true)) selected.push(...recommended.map((item) => item.id));
  }
  if (consent.length) {
    printGroup(output, 'Explicit-consent capabilities (default: none):', consent);
    const answer = String(await ask('Enable any? Enter numbers comma-separated, or press Enter for none: ')).trim();
    if (answer) {
      for (const token of answer.split(',').map((item) => item.trim()).filter(Boolean)) {
        if (!/^\d+$/.test(token) || Number(token) < 1 || Number(token) > consent.length) {
          throw new Error(`invalid explicit-consent selection: ${token}`);
        }
        selected.push(consent[Number(token) - 1].id);
      }
    }
  }
  return [...new Set(selected)];
}

async function resolveRecipePlan(options) {
  const { targetAbs, targets, mode, explicitRecipes, noPrompt, dryRun, ask, output } = options;
  if (!['full', 'strict'].includes(mode)) return { byTool: Object.fromEntries(targets.map((tool) => [tool, null])), resolved: false };
  if (explicitRecipes !== null) {
    const exact = normalizeRecipes(explicitRecipes);
    return { byTool: Object.fromEntries(targets.map((tool) => [tool, exact])), resolved: true, source: 'explicit' };
  }
  const current = currentSelections(targetAbs, targets);
  const existing = targets.filter((tool) => current[tool] !== null);
  const fresh = targets.filter((tool) => current[tool] === null);
  const byTool = {};
  for (const tool of existing) byTool[tool] = current[tool];

  let reconfigure = false;
  const interactive = !noPrompt && !dryRun;
  if (existing.length && interactive) {
    printGroup(output, 'Existing selections (preserved by default):', existing.map((tool) => ({ id: tool, summary: current[tool].join(', ') || '(none)' })));
    reconfigure = !(await yesNo(ask, 'Keep the existing recipe selection?', true));
  }
  if (reconfigure) {
    const chosen = await chooseFresh({ root: targetAbs, interactive, ask, output });
    for (const tool of targets) byTool[tool] = chosen;
  } else if (fresh.length) {
    const chosen = await chooseFresh({ root: targetAbs, interactive, ask, output });
    for (const tool of fresh) byTool[tool] = chosen;
  }
  return { byTool, resolved: true, source: reconfigure ? 'reconfigured' : existing.length ? 'preserved' : 'onboarding' };
}

module.exports = { CATALOG, currentSelections, normalizeRecipes, projectSignals, resolveRecipePlan };
