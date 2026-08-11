#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const TOP_LEVEL_DOCS = ['README.md', 'VISION.md', 'ROADMAP.md'];
const EXCLUDED_DOCS = new Set([
  'CONDUCTOR-V0.2-DESIGN.md',
  'DESIGN-DECISIONS.md',
  'GO-TO-MARKET.md',
  'KPI.md',
]);

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function recipeNames(root) {
  const recipeRoot = path.join(root, 'core', 'recipes');
  return fs.readdirSync(recipeRoot)
    .filter((name) => name.endsWith('.md') && name !== 'README.md')
    .map((name) => name.slice(0, -3))
    .sort();
}

function walkLivingFiles(root, relativeRoot) {
  const start = path.join(root, relativeRoot);
  if (!fs.existsSync(start)) return [];
  const result = [];
  const stack = [start];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(absolute);
      } else if (/\.(?:md|sh|template|json)$/.test(entry.name) && entry.name !== 'metadata.json') {
        result.push(absolute);
      }
    }
  }
  return result;
}

function livingFiles(root) {
  const files = TOP_LEVEL_DOCS
    .map((name) => path.join(root, name))
    .filter((file) => fs.existsSync(file));
  const docsRoot = path.join(root, 'docs');
  if (fs.existsSync(docsRoot)) {
    for (const entry of fs.readdirSync(docsRoot, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;
      if (EXCLUDED_DOCS.has(entry.name) || entry.name.startsWith('LAUNCH-')) continue;
      files.push(path.join(docsRoot, entry.name));
    }
  }
  files.push(...walkLivingFiles(root, 'core'), ...walkLivingFiles(root, 'adapters'));
  return [...new Set(files)].sort();
}

function sortedUnique(values) {
  return [...new Set(values)].sort();
}

function compareCatalog(label, actual, expected, errors) {
  const normalized = sortedUnique(actual);
  const duplicates = normalized.filter((name) => actual.filter((item) => item === name).length > 1);
  if (JSON.stringify(normalized) !== JSON.stringify(expected) || duplicates.length > 0) {
    const missing = expected.filter((name) => !normalized.includes(name));
    const extra = normalized.filter((name) => !expected.includes(name));
    errors.push(`${label} recipe catalog drift (missing: ${missing.join(', ') || 'none'}; extra: ${extra.join(', ') || 'none'}; duplicate: ${duplicates.join(', ') || 'none'})`);
  }
}

function backtickedNames(line) {
  return [...line.matchAll(/`([a-z0-9-]+)`/g)].map((match) => match[1]);
}

function validateRecipeDocs(root) {
  const expected = recipeNames(root);
  const count = expected.length;
  const errors = [];

  const countPatterns = [
    { regex: /\b(\d+)\s+(?:strictly\s+)?opt-in recipes\b/gi, expected: count, label: 'opt-in recipe count' },
    { regex: /\b(\d+)개\s+recipe\b/gi, expected: count, label: 'Korean recipe count' },
    { regex: /\brecipes from the (\d+)\b/gi, expected: count, label: 'recipe option count' },
    { regex: /\*\*Recipe names\*\*\s*\((\d+)\)/g, expected: count, label: 'recipe names count' },
    { regex: /^## The (\d+) recipes$/gm, expected: count, label: 'recipe catalog heading count' },
    { regex: /\b5 universal rule bundles and the other (\d+) recipes are stack-agnostic\b/gi, expected: Math.max(0, count - 1), label: 'non-TypeScript recipe count' },
  ];

  for (const file of livingFiles(root)) {
    const content = readText(file);
    const relative = path.relative(root, file);
    for (const rule of countPatterns) {
      for (const match of content.matchAll(rule.regex)) {
        const actual = Number(match[1]);
        if (actual !== rule.expected) {
          const line = content.slice(0, match.index).split('\n').length;
          errors.push(`${relative}:${line} ${rule.label} is ${actual}; expected ${rule.expected} from core/recipes/*.md`);
        }
      }
    }
  }

  const readme = readText(path.join(root, 'README.md'));
  const catalogSection = readme.match(/## Recipes catalog\n([\s\S]*?)\n#### Decision tree/);
  if (!catalogSection) {
    errors.push('README.md recipe catalog section is missing or malformed');
  } else {
    const names = [...catalogSection[1].matchAll(/^\| `([a-z0-9-]+)` \|/gm)].map((match) => match[1]);
    compareCatalog('README.md main table', names, expected, errors);
  }

  const namesLine = readme.match(/^\*\*Recipe names\*\*[^\n]*$/m);
  if (!namesLine) {
    errors.push('README.md recipe names reference line is missing');
  } else {
    compareCatalog('README.md recipe names reference', backtickedNames(namesLine[0]), expected, errors);
  }

  const troubleshootingLine = readme.match(/^Check recipe name spelling\. Available:[^\n]*$/m);
  if (!troubleshootingLine) {
    errors.push('README.md troubleshooting recipe list is missing');
  } else {
    compareCatalog('README.md troubleshooting list', backtickedNames(troubleshootingLine[0]), expected, errors);
  }

  const coreCatalog = readText(path.join(root, 'core', 'recipes', 'README.md'));
  const coreNames = [...coreCatalog.matchAll(/^\| `([a-z0-9-]+)\.md` \|/gm)].map((match) => match[1]);
  compareCatalog('core/recipes/README.md table', coreNames, expected, errors);

  return { count, expected, errors };
}

if (require.main === module) {
  const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
  try {
    const result = validateRecipeDocs(root);
    if (result.errors.length > 0) {
      for (const error of result.errors) console.error(`FAIL[recipe-docs] ${error}`);
      process.exit(1);
    }
    console.log(`OK  [recipe-docs] public counts and catalogs match ${result.count} recipe sources`);
  } catch (error) {
    console.error(`ERROR[recipe-docs] ${error.message}`);
    process.exit(2);
  }
}

module.exports = { validateRecipeDocs };
