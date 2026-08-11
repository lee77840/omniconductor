#!/usr/bin/env node
'use strict';

/* Typed, evidence-backed, propose-only skill inbox (ADR-061). */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const INBOX_REL = '.conductor/skill-proposals';
const SOURCE_TOOLS = new Set(['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf']);
const TOP_LEVEL_FIELDS = new Set(['schema_version', 'name', 'summary', 'procedure', 'evidence', 'constraints', 'source_tool']);
const EVIDENCE_FIELDS = new Set(['path', 'observation', 'occurrences']);
const STORED_FIELDS = new Set(['schema_version', 'id', 'status', 'applied', 'created_at', 'proposal', 'review']);
const PROPOSAL_FILE_LIMIT = 256 * 1024;

function validateMetadata(metadata) {
  const contract = metadata && metadata.skill_proposals;
  const problems = [];
  if (!contract || typeof contract !== 'object') return ['skill_proposals is required'];
  if (contract.schema_version !== 1) problems.push('schema_version must be 1');
  if (contract.inbox_path !== INBOX_REL) problems.push(`inbox_path must be ${INBOX_REL}`);
  if (contract.recipe !== 'self-improvement') problems.push('recipe must be self-improvement');
  const expectedSkill = metadata.agent_skills
    ? `${metadata.agent_skills.project_path}/propose-skill/SKILL.md`
    : null;
  if (contract.opt_in_skill_path !== expectedSkill) problems.push(`opt_in_skill_path must be ${expectedSkill}`);
  if (contract.application !== 'human-reviewed-separate-change') {
    problems.push('application must be human-reviewed-separate-change');
  }
  if (!['documented', 'manual-fallback', 'verification-required'].includes(contract.native_acceleration)) {
    problems.push('native_acceleration must be documented|manual-fallback|verification-required');
  }
  if (!contract.source || typeof contract.source.url !== 'string' || !/^https:\/\//.test(contract.source.url)) {
    problems.push('source.url must be https');
  }
  if (!contract.source || !/^\d{4}-\d{2}-\d{2}$/.test(contract.source.checked || '')) {
    problems.push('source.checked must be YYYY-MM-DD');
  }
  return problems;
}

function nonEmptyString(value, max) {
  return typeof value === 'string' && value.trim().length > 0 && value.trim().length <= max;
}

function safeRelative(value) {
  if (!nonEmptyString(value, 500) || path.isAbsolute(value) || value.includes('\0')) return false;
  const normalized = path.posix.normalize(value.replace(/\\/g, '/'));
  return normalized !== '..' && !normalized.startsWith('../');
}

function validateInput(input) {
  const problems = [];
  if (!input || typeof input !== 'object' || Array.isArray(input)) return ['proposal must be an object'];
  for (const key of Object.keys(input)) {
    if (!TOP_LEVEL_FIELDS.has(key)) problems.push(`unsupported field: ${key}`);
  }
  if (input.schema_version !== 1) problems.push('schema_version must be 1');
  if (typeof input.name !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(input.name)) {
    problems.push('name must be kebab-case');
  }
  if (!nonEmptyString(input.summary, 240) || input.summary.trim().length < 10) {
    problems.push('summary must be 10-240 characters');
  }
  if (!Array.isArray(input.procedure) || input.procedure.length < 2 || input.procedure.length > 20) {
    problems.push('procedure must contain 2-20 ordered steps');
  } else {
    input.procedure.forEach((step, index) => {
      if (!nonEmptyString(step, 500)) problems.push(`procedure[${index}] must be a non-empty string up to 500 characters`);
    });
  }
  if (!Array.isArray(input.evidence) || !input.evidence.length || input.evidence.length > 20) {
    problems.push('evidence must contain 1-20 entries');
  } else {
    let occurrences = 0;
    input.evidence.forEach((entry, index) => {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
        problems.push(`evidence[${index}] must be an object`);
        return;
      }
      for (const key of Object.keys(entry)) {
        if (!EVIDENCE_FIELDS.has(key)) problems.push(`evidence[${index}] unsupported field: ${key}`);
      }
      if (!safeRelative(entry.path)) problems.push(`evidence[${index}].path must be project-relative`);
      if (!nonEmptyString(entry.observation, 500)) problems.push(`evidence[${index}].observation must be 1-500 characters`);
      if (!Number.isInteger(entry.occurrences) || entry.occurrences < 1 || entry.occurrences > 1000) {
        problems.push(`evidence[${index}].occurrences must be an integer from 1-1000`);
      } else occurrences += entry.occurrences;
    });
    if (occurrences < 2) problems.push('combined evidence occurrences must be at least 2');
  }
  if (input.constraints !== undefined) {
    if (!Array.isArray(input.constraints) || input.constraints.length > 20
        || input.constraints.some((item) => !nonEmptyString(item, 300))) {
      problems.push('constraints must be an array of up to 20 non-empty strings');
    }
  }
  if (input.source_tool !== undefined && !SOURCE_TOOLS.has(input.source_tool)) {
    problems.push(`source_tool must be one of: ${[...SOURCE_TOOLS].join(', ')}`);
  }
  return problems;
}

function normalizedInput(input) {
  const normalized = {
    schema_version: 1,
    name: input.name.trim(),
    summary: input.summary.trim(),
    procedure: input.procedure.map((item) => item.trim()),
    evidence: input.evidence.map((entry) => ({
      path: path.posix.normalize(entry.path.replace(/\\/g, '/')),
      observation: entry.observation.trim(),
      occurrences: entry.occurrences,
    })),
  };
  if (input.constraints) normalized.constraints = input.constraints.map((item) => item.trim());
  if (input.source_tool) normalized.source_tool = input.source_tool;
  return normalized;
}

function proposalId(input) {
  return crypto.createHash('sha256').update(JSON.stringify(input)).digest('hex').slice(0, 16);
}

function safeTargetDirectory(targetDir) {
  const targetAbs = path.resolve(targetDir);
  if (!fs.existsSync(targetAbs)) throw new Error(`target directory does not exist: ${targetAbs}`);
  const stat = fs.lstatSync(targetAbs);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`target must be a real directory, not a symlink or special file: ${targetAbs}`);
  }
  return fs.realpathSync(targetAbs);
}

function safeProposalFile(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > PROPOSAL_FILE_LIMIT) {
    throw new Error(`unsafe proposal file: ${file}`);
  }
  return stat;
}

function assertSafeInbox(targetAbs) {
  const conductor = path.join(targetAbs, '.conductor');
  const inbox = path.join(targetAbs, INBOX_REL);
  for (const candidate of [conductor, inbox]) {
    if (!fs.existsSync(candidate)) continue;
    const stat = fs.lstatSync(candidate);
    if (stat.isSymbolicLink()) throw new Error(`refusing symlinked proposal path: ${candidate}`);
    if (!stat.isDirectory()) throw new Error(`proposal path is not a directory: ${candidate}`);
  }
  return inbox;
}

function atomicWrite(file, value, { exclusive = false } = {}) {
  const temp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`);
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  try {
    if (exclusive) {
      try { fs.linkSync(temp, file); }
      catch (error) {
        if (error.code === 'EEXIST') throw new Error(`proposal already exists: ${path.basename(file, '.json')}`);
        throw error;
      }
      fs.unlinkSync(temp);
    } else {
      fs.renameSync(temp, file);
    }
  } finally {
    if (fs.existsSync(temp)) fs.unlinkSync(temp);
  }
}

function create(targetDir, input, { dryRun = false, now = new Date() } = {}) {
  const problems = validateInput(input);
  if (problems.length) throw new Error(`invalid proposal: ${problems.join('; ')}`);
  const targetAbs = safeTargetDirectory(targetDir);
  const payload = normalizedInput(input);
  const id = proposalId(payload);
  const proposal = {
    schema_version: 1,
    id,
    status: 'pending',
    applied: false,
    created_at: now.toISOString(),
    proposal: payload,
    review: null,
  };
  const inbox = assertSafeInbox(targetAbs);
  const file = path.join(inbox, `${id}.json`);
  if (dryRun) return { created: false, dry_run: true, file, proposal };
  fs.mkdirSync(inbox, { recursive: true, mode: 0o700 });
  assertSafeInbox(targetAbs);
  if (fs.existsSync(file)) {
    safeProposalFile(file);
    let existing;
    try { existing = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch { throw new Error(`invalid stored proposal JSON: ${file}`); }
    validateStored(existing, file);
    if (existing.id === id && JSON.stringify(existing.proposal) === JSON.stringify(payload)) {
      return { created: false, dry_run: false, file, proposal: existing };
    }
    throw new Error(`proposal id collision: ${id}`);
  }
  atomicWrite(file, proposal, { exclusive: true });
  return { created: true, dry_run: false, file, proposal };
}

function validateStored(proposal, file) {
  if (!proposal || typeof proposal !== 'object' || Array.isArray(proposal)
      || proposal.schema_version !== 1 || !/^[0-9a-f]{16}$/.test(proposal.id || '')) {
    throw new Error(`invalid stored proposal: ${file}`);
  }
  const unknown = Object.keys(proposal).filter((key) => !STORED_FIELDS.has(key));
  if (unknown.length) throw new Error(`invalid stored proposal fields in ${file}: ${unknown.join(', ')}`);
  if (!['pending', 'accepted', 'rejected'].includes(proposal.status) || proposal.applied !== false) {
    throw new Error(`invalid proposal state: ${file}`);
  }
  const problems = validateInput(proposal.proposal);
  if (problems.length) throw new Error(`invalid stored proposal ${file}: ${problems.join('; ')}`);
  const canonical = normalizedInput(proposal.proposal);
  if (proposalId(canonical) !== proposal.id) throw new Error(`proposal content-address mismatch: ${file}`);
  if (typeof proposal.created_at !== 'string' || !Number.isFinite(Date.parse(proposal.created_at))) {
    throw new Error(`invalid proposal creation time: ${file}`);
  }
  if (proposal.status === 'pending' && proposal.review !== null) throw new Error(`pending proposal has review state: ${file}`);
  if (proposal.status !== 'pending') {
    const expectedDecision = proposal.status === 'accepted' ? 'accept' : 'reject';
    if (!proposal.review || proposal.review.decision !== expectedDecision || proposal.review.applied !== false
        || !Number.isFinite(Date.parse(proposal.review.reviewed_at || ''))) {
      throw new Error(`invalid proposal review state: ${file}`);
    }
  }
  return proposal;
}

function list(targetDir) {
  const targetAbs = safeTargetDirectory(targetDir);
  const inbox = assertSafeInbox(targetAbs);
  if (!fs.existsSync(inbox)) return [];
  const proposals = [];
  for (const entry of fs.readdirSync(inbox, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (!/^[0-9a-f]{16}\.json$/.test(entry.name)) continue;
    const file = path.join(inbox, entry.name);
    safeProposalFile(file);
    let proposal;
    try { proposal = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch { throw new Error(`invalid stored proposal JSON: ${file}`); }
    proposals.push(validateStored(proposal, file));
  }
  return proposals;
}

function review(targetDir, id, decision, note, { now = new Date() } = {}) {
  if (!/^[0-9a-f]{16}$/.test(id || '')) throw new Error('proposal id must be 16 lowercase hexadecimal characters');
  if (!['accept', 'reject'].includes(decision)) throw new Error('decision must be accept|reject');
  if (note !== undefined && !nonEmptyString(note, 500)) throw new Error('review note must be 1-500 characters');
  const targetAbs = safeTargetDirectory(targetDir);
  const inbox = assertSafeInbox(targetAbs);
  const file = path.join(inbox, `${id}.json`);
  if (!fs.existsSync(file)) throw new Error(`proposal not found: ${id}`);
  safeProposalFile(file);
  let stored;
  try { stored = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error(`invalid stored proposal JSON: ${file}`); }
  const proposal = validateStored(stored, file);
  if (proposal.status !== 'pending') throw new Error(`proposal already reviewed: ${proposal.status}`);
  proposal.status = decision === 'accept' ? 'accepted' : 'rejected';
  proposal.review = {
    decision,
    reviewed_at: now.toISOString(),
    note: note ? note.trim() : '',
    applied: false,
  };
  atomicWrite(file, proposal);
  return proposal;
}

function render(proposals) {
  if (!proposals.length) return 'No skill proposals.';
  return proposals.map((item) => (
    `${item.id}  ${item.status.padEnd(8)}  ${item.proposal.name} — ${item.proposal.summary}`
  )).join('\n');
}

module.exports = {
  INBOX_REL,
  create,
  list,
  render,
  review,
  validateInput,
  validateMetadata,
};
