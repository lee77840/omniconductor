#!/usr/bin/env node
'use strict';

function parseStable(version, label) {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(String(version || ''));
  if (!match) throw new Error(`${label} must be a stable x.y.z version: ${version || '(empty)'}`);
  return match.slice(1).map(Number);
}

function compareStable(left, right) {
  const a = parseStable(left, 'candidate version');
  const b = parseStable(right, 'registry latest version');
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] > b[index] ? 1 : -1;
  }
  return 0;
}

function assertPublishable(candidate, latest, publishedVersions) {
  parseStable(candidate, 'candidate version');
  parseStable(latest, 'registry latest version');
  if (!Array.isArray(publishedVersions) || publishedVersions.some((item) => typeof item !== 'string')) {
    throw new Error('registry versions must be a JSON array of version strings');
  }
  if (publishedVersions.includes(candidate)) {
    throw new Error(`candidate ${candidate} is already published; npm versions are immutable`);
  }
  if (compareStable(candidate, latest) <= 0) {
    throw new Error(`candidate ${candidate} must be greater than registry latest ${latest}`);
  }
}

if (require.main === module) {
  const [candidate, latest, versionsJson] = process.argv.slice(2);
  try {
    assertPublishable(candidate, latest, JSON.parse(versionsJson || ''));
    process.stdout.write(`release version guard: PASS (${latest} -> ${candidate})\n`);
  } catch (error) {
    process.stderr.write(`release version guard: FAIL — ${error.message}\n`);
    process.exit(1);
  }
}

module.exports = { assertPublishable, compareStable };
