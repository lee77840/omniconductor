#!/usr/bin/env node
'use strict';

// Cross-platform, one-use proof that an adapter was launched by this package's
// CLI. The proof lives only in the OS temp directory and is consumed before an
// adapter may enter its implementation. It replaces the Unix-specific
// /dev/fd/3 inode comparison, which is not a portable Windows/MSYS2 contract.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CLI = path.join(ROOT, 'bin', 'omniconductor.js');
const PREFIX = 'omniconductor-dispatch-';
const MAX_AGE_MS = 60_000;
const TOOLS = new Set(['claude', 'cursor', 'copilot', 'gemini', 'codex', 'windsurf']);

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function safeFile(file, maxBytes) {
  const stat = fs.lstatSync(file);
  return stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1 && stat.size <= maxBytes;
}

function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code === 'EPERM'; }
}

function cleanupProof(file) {
  if (!file || typeof file !== 'string') return;
  const dir = path.dirname(file);
  for (const candidate of [file, `${file}.consumed`]) {
    try { fs.unlinkSync(candidate); } catch { /* already consumed or absent */ }
  }
  try { fs.rmdirSync(dir); } catch { /* never remove a non-empty/unexpected directory */ }
}

function createProof(tool, targetAbs) {
  if (!TOOLS.has(tool)) throw new Error(`unknown adapter dispatch target: ${tool}`);
  if (!path.isAbsolute(targetAbs)) throw new Error('adapter dispatch target must be absolute');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), PREFIX));
  try { fs.chmodSync(dir, 0o700); } catch { /* Windows ACLs remain authoritative */ }
  const file = path.join(dir, 'proof.json');
  const nonce = crypto.randomBytes(32).toString('hex');
  const proof = {
    schema_version: 1,
    tool,
    target: targetAbs,
    parent_pid: process.pid,
    nonce,
    cli_sha256: sha256(CLI),
    created_at: new Date().toISOString(),
  };
  fs.writeFileSync(file, `${JSON.stringify(proof)}\n`, { flag: 'wx', mode: 0o600 });
  return {
    env: {
      CONDUCTOR_CLI_DISPATCH: '2',
      CONDUCTOR_CLI_DISPATCH_PROOF: file,
      CONDUCTOR_CLI_DISPATCH_NONCE: nonce,
      CONDUCTOR_CLI_DISPATCH_TARGET: targetAbs,
    },
    file,
    cleanup: () => cleanupProof(file),
  };
}

function verifyAndConsume(tool, env = process.env) {
  if (!TOOLS.has(tool) || env.CONDUCTOR_CLI_DISPATCH !== '2') return false;
  const file = env.CONDUCTOR_CLI_DISPATCH_PROOF;
  const nonce = env.CONDUCTOR_CLI_DISPATCH_NONCE;
  const target = env.CONDUCTOR_CLI_DISPATCH_TARGET;
  if (!file || !path.isAbsolute(file) || !/^[a-f0-9]{64}$/.test(nonce || '') || !path.isAbsolute(target || '')) return false;
  const dir = path.dirname(file);
  if (path.dirname(dir) !== path.resolve(os.tmpdir())
    || !path.basename(dir).startsWith(PREFIX)
    || path.basename(file) !== 'proof.json') return false;

  let proof;
  try {
    const dirStat = fs.lstatSync(dir);
    if (!dirStat.isDirectory() || dirStat.isSymbolicLink() || !safeFile(file, 4096)) return false;
    const names = fs.readdirSync(dir);
    if (names.length !== 1 || names[0] !== 'proof.json') return false;
    proof = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch { return false; }

  const created = Date.parse(proof && proof.created_at);
  const expectedNonce = Buffer.from(nonce, 'utf8');
  const actualNonce = Buffer.from(typeof proof.nonce === 'string' ? proof.nonce : '', 'utf8');
  if (!proof || proof.schema_version !== 1 || proof.tool !== tool || proof.target !== target
    || proof.cli_sha256 !== sha256(CLI) || !Number.isFinite(created)
    || Date.now() - created < 0 || Date.now() - created > MAX_AGE_MS
    || expectedNonce.length !== actualNonce.length
    || !crypto.timingSafeEqual(expectedNonce, actualNonce)
    || !processIsAlive(proof.parent_pid)) return false;

  const consumed = `${file}.consumed`;
  try {
    fs.renameSync(file, consumed);
    fs.unlinkSync(consumed);
    fs.rmdirSync(dir);
    return true;
  } catch {
    cleanupProof(file);
    return false;
  }
}

if (require.main === module) {
  const [command, tool] = process.argv.slice(2);
  if (command !== 'verify' || !verifyAndConsume(tool)) process.exitCode = 2;
}

module.exports = { MAX_AGE_MS, createProof, verifyAndConsume };
