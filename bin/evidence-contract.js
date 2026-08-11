#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const SCHEMA_VERSION = 1;
const MAX_BYTES = 1024 * 1024;
const STATUSES = [
  'passed',
  'failed',
  'blocked',
  'not-run',
  'environment-limited',
  'verification-required',
];
const STATUS_SET = new Set(STATUSES);
const EVIDENCE_KINDS = new Set(['command', 'artifact', 'observation', 'external']);

function nonEmpty(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function exactKeys(value, allowed, where, problems) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) problems.push(`${where}: unknown field '${key}'`);
  }
}

function validateSnapshot(snapshot, problems) {
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
    problems.push('snapshot must be an object');
    return;
  }
  exactKeys(snapshot, new Set(['kind', 'value', 'dirty']), 'snapshot', problems);
  if (!['git-commit', 'git-tree', 'content-digest', 'external-version'].includes(snapshot.kind)) {
    problems.push('snapshot.kind must be git-commit, git-tree, content-digest, or external-version');
  }
  if (!nonEmpty(snapshot.value) || snapshot.value.length > 256) {
    problems.push('snapshot.value must be a non-empty string no longer than 256 characters');
  }
  if (typeof snapshot.dirty !== 'boolean') problems.push('snapshot.dirty must be boolean');
  if (['git-commit', 'git-tree'].includes(snapshot.kind)
      && !/^[0-9a-f]{40,64}$/.test(snapshot.value || '')) {
    problems.push(`snapshot.value must be a 40-64 character lowercase hex ${snapshot.kind} id`);
  }
  if (snapshot.kind === 'content-digest'
      && !/^[a-z0-9][a-z0-9+._-]{1,31}:[A-Za-z0-9._=-]{8,200}$/.test(snapshot.value || '')) {
    problems.push('content-digest snapshot.value must be an algorithm-prefixed digest');
  }
  if (snapshot.dirty === true && snapshot.kind !== 'content-digest') {
    problems.push('a dirty snapshot must use content-digest so uncommitted state is identified');
  }
}

function validateEvidence(item, where, problems) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) {
    problems.push(`${where} must be an object`);
    return;
  }
  exactKeys(item, new Set(['kind', 'ref', 'digest']), where, problems);
  if (!EVIDENCE_KINDS.has(item.kind)) {
    problems.push(`${where}.kind must be command, artifact, observation, or external`);
  }
  if (!nonEmpty(item.ref) || item.ref.length > 2048) {
    problems.push(`${where}.ref must be a non-empty string no longer than 2048 characters`);
  }
  if (item.digest !== undefined && (!nonEmpty(item.digest) || item.digest.length > 256)) {
    problems.push(`${where}.digest must be a non-empty string no longer than 256 characters`);
  }
}

function validateClaim(claim, index, ids, problems) {
  const where = `claims[${index}]`;
  if (!claim || typeof claim !== 'object' || Array.isArray(claim)) {
    problems.push(`${where} must be an object`);
    return;
  }
  exactKeys(claim, new Set([
    'id', 'claim', 'status', 'reason', 'command', 'evidence', 'missing', 'reproducible',
  ]), where, problems);
  if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(claim.id || '')) {
    problems.push(`${where}.id must be a stable lowercase identifier`);
  } else if (ids.has(claim.id)) {
    problems.push(`${where}.id duplicates '${claim.id}'`);
  } else {
    ids.add(claim.id);
  }
  if (!nonEmpty(claim.claim) || claim.claim.length > 2048) {
    problems.push(`${where}.claim must be a non-empty string no longer than 2048 characters`);
  }
  if (!STATUS_SET.has(claim.status)) {
    problems.push(`${where}.status must be one of: ${STATUSES.join(', ')}`);
  }
  if (!nonEmpty(claim.reason) || claim.reason.length > 4096) {
    problems.push(`${where}.reason must be a non-empty string no longer than 4096 characters`);
  }
  if (claim.command !== undefined && (!nonEmpty(claim.command) || claim.command.length > 4096)) {
    problems.push(`${where}.command must be a non-empty string no longer than 4096 characters`);
  }
  if (!Array.isArray(claim.evidence) || claim.evidence.length > 64) {
    problems.push(`${where}.evidence must be an array with at most 64 entries`);
  } else {
    claim.evidence.forEach((item, evidenceIndex) => {
      validateEvidence(item, `${where}.evidence[${evidenceIndex}]`, problems);
    });
  }
  if (claim.missing !== undefined && (!Array.isArray(claim.missing)
      || claim.missing.length > 32
      || claim.missing.some((item) => !nonEmpty(item) || item.length > 512))) {
    problems.push(`${where}.missing must be an array of at most 32 non-empty strings`);
  }
  if (typeof claim.reproducible !== 'boolean') {
    problems.push(`${where}.reproducible must be boolean`);
  }

  const evidenceCount = Array.isArray(claim.evidence) ? claim.evidence.length : 0;
  const missingCount = Array.isArray(claim.missing) ? claim.missing.length : 0;
  if (claim.status === 'passed') {
    if (!evidenceCount) problems.push(`${where}: passed requires at least one evidence entry`);
    if (missingCount) problems.push(`${where}: passed cannot declare missing evidence`);
  }
  if (claim.status === 'failed' && !evidenceCount) {
    problems.push(`${where}: failed requires at least one evidence entry`);
  }
  if (['blocked', 'not-run', 'environment-limited', 'verification-required'].includes(claim.status)
      && !missingCount) {
    problems.push(`${where}: ${claim.status} requires at least one missing requirement`);
  }
}

function validateReport(report) {
  const problems = [];
  if (!report || typeof report !== 'object' || Array.isArray(report)) {
    return ['report must be a JSON object'];
  }
  exactKeys(report, new Set(['schema_version', 'snapshot', 'claims']), 'report', problems);
  if (report.schema_version !== SCHEMA_VERSION) {
    problems.push(`schema_version must be ${SCHEMA_VERSION}`);
  }
  validateSnapshot(report.snapshot, problems);
  if (!Array.isArray(report.claims) || report.claims.length < 1 || report.claims.length > 512) {
    problems.push('claims must contain between 1 and 512 entries');
  } else {
    const ids = new Set();
    report.claims.forEach((claim, index) => validateClaim(claim, index, ids, problems));
  }
  return problems;
}

function summarize(report) {
  const counts = Object.fromEntries(STATUSES.map((status) => [status, 0]));
  for (const claim of report.claims) counts[claim.status] += 1;
  return {
    total: report.claims.length,
    counts,
    complete: report.claims.every((claim) => claim.status === 'passed'),
  };
}

function loadReport(file) {
  const absolute = path.resolve(file);
  const stat = fs.lstatSync(absolute);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > MAX_BYTES) {
    throw new Error('evidence report must be a single-link regular JSON file no larger than 1 MiB');
  }
  return { absolute, report: JSON.parse(fs.readFileSync(absolute, 'utf8')) };
}

function render(summary) {
  return [
    `Verification evidence: ${summary.total} claim(s)`,
    ...STATUSES.filter((status) => summary.counts[status])
      .map((status) => `  ${status}: ${summary.counts[status]}`),
    `Gate: ${summary.complete ? 'PASS' : 'INCOMPLETE'}`,
  ].join('\n');
}

module.exports = {
  EVIDENCE_KINDS,
  MAX_BYTES,
  SCHEMA_VERSION,
  STATUSES,
  loadReport,
  render,
  summarize,
  validateReport,
};
