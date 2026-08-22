'use strict';

// Trusted, deterministic boundary between a read-only Reflector model and the
// one file it is allowed to propose into. The model emits data; this process
// validates and appends it. No model process receives workspace write access.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const START = '<conductor-reflection-proposals>';
const END = '</conductor-reflection-proposals>';
const MAX_INPUT_BYTES = 1024 * 1024;
const MAX_PROPOSALS = 50;

function fail(message) {
  const error = new Error(message);
  error.exitCode = 2;
  throw error;
}

function scalar(value, field, max = 2000) {
  if (typeof value !== 'string') fail(`${field} must be a string`);
  const normalized = value.trim().replace(/\r\n?/g, '\n');
  if (!normalized || normalized.length > max || normalized.includes('\0')) {
    fail(`${field} must contain 1-${max} safe characters`);
  }
  return normalized;
}

function parseEnvelope(raw) {
  if (Buffer.byteLength(raw, 'utf8') > MAX_INPUT_BYTES) fail('reflector output exceeds 1 MiB');
  const first = raw.indexOf(START);
  const last = raw.indexOf(END);
  if (first < 0 || last < 0 || last < first || raw.indexOf(START, first + START.length) >= 0
      || raw.indexOf(END, last + END.length) >= 0) {
    fail('reflector output must contain exactly one proposal envelope');
  }
  let parsed;
  try { parsed = JSON.parse(raw.slice(first + START.length, last).trim()); }
  catch (error) { fail(`proposal envelope is not valid JSON: ${error.message}`); }
  if (!parsed || Array.isArray(parsed) || parsed.schema_version !== 1
      || !Array.isArray(parsed.proposals) || parsed.proposals.length > MAX_PROPOSALS) {
    fail(`proposal envelope must use schema_version=1 and at most ${MAX_PROPOSALS} proposals`);
  }
  const allowedKeys = new Set(['op', 'target', 'lesson', 'why', 'how_to_apply', 'provenance']);
  return parsed.proposals.map((proposal, index) => {
    if (!proposal || Array.isArray(proposal) || typeof proposal !== 'object') fail(`proposals[${index}] must be an object`);
    for (const key of Object.keys(proposal)) if (!allowedKeys.has(key)) fail(`proposals[${index}] has unsupported field: ${key}`);
    const op = scalar(proposal.op, `proposals[${index}].op`, 10).toUpperCase();
    if (!['ADD', 'UPDATE', 'STALE'].includes(op)) fail(`proposals[${index}].op must be ADD, UPDATE, or STALE`);
    const target = scalar(proposal.target, `proposals[${index}].target`, 120);
    if (!/^feedback_lesson-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/.test(target)) {
      fail(`proposals[${index}].target must be feedback_lesson-<safe-slug>.md`);
    }
    const provenance = proposal.provenance;
    if (!Array.isArray(provenance) || provenance.length < 1 || provenance.length > 20) {
      fail(`proposals[${index}].provenance must contain 1-20 citations`);
    }
    return {
      op,
      target,
      lesson: scalar(proposal.lesson, `proposals[${index}].lesson`),
      why: scalar(proposal.why, `proposals[${index}].why`),
      how_to_apply: scalar(proposal.how_to_apply, `proposals[${index}].how_to_apply`),
      provenance: provenance.map((item, p) => scalar(item, `proposals[${index}].provenance[${p}]`, 500)),
    };
  });
}

function markdown(proposal) {
  const canonical = JSON.stringify(proposal);
  const digest = crypto.createHash('sha256').update(canonical).digest('hex');
  const oneLine = (value) => value.replace(/\s*\n\s*/g, ' ')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return {
    digest,
    text: [
      `<!-- conductor:reflection-proposal ${digest} -->`,
      `- **[${proposal.op}]** target: \`${proposal.target}\``,
      `  - lesson: ${oneLine(proposal.lesson)}`,
      `  - why: ${oneLine(proposal.why)}`,
      `  - how-to-apply: ${oneLine(proposal.how_to_apply)}`,
      `  - provenance: ${proposal.provenance.map(oneLine).join('; ')}`,
      '',
    ].join('\n'),
  };
}

function assertSafeTarget(target, createDocs = true) {
  const root = process.cwd();
  const absolute = path.resolve(root, target);
  if (absolute !== path.join(root, 'docs', 'REFLECTION-PROPOSALS.md')) {
    fail('target is fixed to docs/REFLECTION-PROPOSALS.md under the project root');
  }
  const docs = path.dirname(absolute);
  if (fs.existsSync(docs)) {
    const st = fs.lstatSync(docs);
    if (!st.isDirectory() || st.isSymbolicLink()) fail('docs must be a real directory');
  } else if (createDocs) {
    fs.mkdirSync(docs, { recursive: false });
  }
  if (fs.existsSync(absolute)) {
    const st = fs.lstatSync(absolute);
    if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) fail('proposal target must be a regular single-link file');
  }
  return absolute;
}

function appendProposals(proposals, target, dryRun = false) {
  const absolute = assertSafeTarget(target, !dryRun);
  const existing = fs.existsSync(absolute) ? fs.readFileSync(absolute, 'utf8') : '';
  const additions = proposals.map(markdown).filter(({ digest }) => !existing.includes(`conductor:reflection-proposal ${digest}`));
  if (!additions.length || dryRun) return { accepted: proposals.length, appended: additions.length, target: absolute };
  const heading = existing ? '' : '# Reflection Proposals\n\n> Generated proposals only. No item is applied until a separate, explicit human-approved change.\n\n';
  const next = `${existing}${existing && !existing.endsWith('\n') ? '\n' : ''}${heading}${additions.map((item) => item.text).join('')}`;
  const temp = `${absolute}.conductor-${process.pid}.tmp`;
  try {
    fs.writeFileSync(temp, next, { encoding: 'utf8', mode: 0o644, flag: 'wx' });
    fs.renameSync(temp, absolute);
  } finally {
    try { fs.unlinkSync(temp); } catch { /* rename consumed it */ }
  }
  return { accepted: proposals.length, appended: additions.length, target: absolute };
}

function main(argv) {
  let from = '';
  let target = 'docs/REFLECTION-PROPOSALS.md';
  let dryRun = false;
  for (const arg of argv) {
    if (arg.startsWith('--from=')) from = arg.slice(7);
    else if (arg.startsWith('--target=')) target = arg.slice(9);
    else if (arg === '--dry-run') dryRun = true;
    else fail(`unknown option: ${arg}`);
  }
  const raw = from ? fs.readFileSync(path.resolve(from), 'utf8') : fs.readFileSync(0, 'utf8');
  const result = appendProposals(parseEnvelope(raw), target, dryRun);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(`conductor-reflect: ${error.message}\n`);
    process.exitCode = error.exitCode || 2;
  }
}

module.exports = { appendProposals, markdown, parseEnvelope };
