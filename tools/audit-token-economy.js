#!/usr/bin/env node
'use strict';

/*
 * Read-only Claude session audit for output-cap reach, prompt-cache reuse, and
 * role dispatch. It reports observed local evidence only; it never uploads or
 * rewrites a transcript.
 */

const fs = require('fs');
const path = require('path');

function usage() {
  process.stderr.write('Usage: node tools/audit-token-economy.js --sessions=<jsonl-file-or-directory> [--since=<ISO-8601>] [--thresholds=3000,4000,6000,8000,12000] [--json]\n');
}

function parseArgs(argv) {
  const options = { sessions: '', since: null, thresholds: [3000, 4000, 6000, 8000, 12000], json: false };
  for (const arg of argv) {
    if (arg === '--json') options.json = true;
    else if (arg.startsWith('--sessions=')) options.sessions = arg.slice('--sessions='.length);
    else if (arg.startsWith('--since=')) options.since = arg.slice('--since='.length);
    else if (arg.startsWith('--thresholds=')) {
      options.thresholds = arg.slice('--thresholds='.length).split(',').map(Number);
    } else if (arg === '--help' || arg === '-h') return null;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!options.sessions) throw new Error('--sessions is required');
  if (options.since && !Number.isFinite(Date.parse(options.since))) throw new Error('--since must be ISO-8601');
  if (!options.thresholds.length || options.thresholds.some((value) => !Number.isSafeInteger(value) || value <= 0)) {
    throw new Error('--thresholds must be a comma-separated list of positive integers');
  }
  options.thresholds = [...new Set(options.thresholds)].sort((a, b) => a - b);
  return options;
}

function sessionFiles(inputPath) {
  const resolved = path.resolve(inputPath);
  if (!fs.existsSync(resolved)) throw new Error(`sessions path does not exist: ${resolved}`);
  if (fs.statSync(resolved).isFile()) {
    if (!resolved.endsWith('.jsonl')) throw new Error('sessions file must end in .jsonl');
    return [resolved];
  }
  const found = [];
  const walk = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const child = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(child);
      else if (entry.isFile() && entry.name.endsWith('.jsonl')) found.push(child);
    }
  };
  walk(resolved);
  return found.sort();
}

function resultText(content) {
  if (typeof content === 'string') return content;
  try { return JSON.stringify(content == null ? '' : content); }
  catch { return ''; }
}

function audit(options) {
  const cutoff = options.since ? Date.parse(options.since) : -Infinity;
  const files = sessionFiles(options.sessions);
  const resultTokens = [];
  const branches = new Map();
  const roles = new Map();
  const usageByMessage = new Map();
  const seenTools = new Set();
  const usageKeys = ['cache_read_input_tokens', 'cache_creation_input_tokens', 'input_tokens', 'output_tokens'];
  const totals = {
    files_scanned: files.length, files_matched: 0, records: 0, tool_results: 0,
    conductor_truncation_markers: 0, observed_declared_elided_tokens: 0, cache_read_tokens: 0,
    cache_write_tokens: 0, uncached_input_tokens: 0, output_tokens: 0, model_calls_with_usage: 0,
    usage_records: 0, duplicate_usage_records: 0, unidentifiable_usage_records: 0,
    synthetic_usage_records: 0, invalid_usage_fields: 0, malformed_records: 0,
  };

  for (const file of files) {
    let matched = false;
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      if (!line) continue;
      let record;
      try { record = JSON.parse(line); } catch { totals.malformed_records++; continue; }
      if (!record || typeof record !== 'object' || Array.isArray(record)) { totals.malformed_records++; continue; }
      const timestamp = Date.parse(record.timestamp || '');
      if (options.since && !(timestamp >= cutoff)) continue;
      matched = true;
      totals.records++;
      if (record.gitBranch) branches.set(record.gitBranch, (branches.get(record.gitBranch) || 0) + 1);
      const message = record.message || {};
      const tokenUsage = message.usage || {};
      if (usageKeys.some((key) => Object.hasOwn(tokenUsage, key))) {
        totals.usage_records++;
        if (message.model === '<synthetic>' || record.isSynthetic === true) {
          totals.synthetic_usage_records++;
        } else {
          // A streamed response can persist one usage snapshot per content block.
          // UUID identifies a row, NOT a model call. Prefer message identity, then
          // request identity; never deduplicate distinct calls by their contents.
          const identity = [message.id, record.requestId, record.request_id].find(x => typeof x === 'string' && x.length > 0 && x.length <= 512);
          if (!identity) totals.unidentifiable_usage_records++;
          const key = JSON.stringify([record.sessionId || record.session_id || '', identity || `${file}:${totals.records}`]);
          const previous = usageByMessage.get(key);
          if (previous) totals.duplicate_usage_records++;
          const counters = previous || Object.fromEntries(usageKeys.map((key) => [key, 0]));
          for (const field of usageKeys) {
            const value = tokenUsage[field];
            if (value == null) continue;
            if (!Number.isSafeInteger(value) || value < 0) { totals.invalid_usage_fields++; continue; }
            counters[field] = Math.max(counters[field], value);
          }
          usageByMessage.set(key, counters);
        }
      }
      const content = Array.isArray(message.content) ? message.content : [];
      for (const item of content) {
        if (!item || typeof item !== 'object') continue;
        const toolIdentity = item.type === 'tool_result' ? item.tool_use_id : item.type === 'tool_use' ? item.id : null;
        if (toolIdentity) {
          const key = JSON.stringify([record.sessionId || record.session_id || '', item.type, toolIdentity]);
          if (seenTools.has(key)) continue;
          seenTools.add(key);
        }
        if (item.type === 'tool_result') {
          totals.tool_results++;
          const text = resultText(item.content);
          resultTokens.push(Math.ceil(text.length / 4));
          if (text.includes('[CONDUCTOR] output truncated')) totals.conductor_truncation_markers++;
          for (const match of text.matchAll(/\[CONDUCTOR\] output truncated[^\n]*?([0-9][0-9,]*) tokens elided/g)) {
            totals.observed_declared_elided_tokens += Number(match[1].replace(/,/g, ''));
          }
        }
        if (item.type === 'tool_use' && item.name === 'Agent') {
          const input = item.input || {};
          const role = input.subagent_type || input.agent_type || '(unknown)';
          roles.set(role, (roles.get(role) || 0) + 1);
        }
      }
    }
    if (matched) totals.files_matched++;
  }

  totals.model_calls_with_usage = usageByMessage.size;
  for (const usage of usageByMessage.values()) {
    totals.cache_read_tokens += usage.cache_read_input_tokens;
    totals.cache_write_tokens += usage.cache_creation_input_tokens;
    totals.uncached_input_tokens += usage.input_tokens;
    totals.output_tokens += usage.output_tokens;
  }

  const denominator = totals.cache_read_tokens + totals.cache_write_tokens + totals.uncached_input_tokens;
  const cacheReadShare = denominator ? Number((totals.cache_read_tokens / denominator * 100).toFixed(2)) : null;
  const thresholdAnalysis = options.thresholds.map((threshold) => ({
    threshold_tokens: threshold,
    results_over_threshold: resultTokens.filter((value) => value > threshold).length,
    estimated_elidable_tokens: resultTokens.reduce((sum, value) => sum + Math.max(0, value - threshold), 0),
  }));
  const findings = [];
  if (totals.unidentifiable_usage_records || totals.invalid_usage_fields || totals.malformed_records) findings.push({
    code: 'USAGE_IDENTITY_GAP', severity: 'WARN',
    detail: 'Some usage records lack stable message/request identity or valid counters. Counts are diagnostic only; supply a verified --requests count for personal estimates.',
  });
  const highestThreshold = thresholdAnalysis[thresholdAnalysis.length - 1];
  if (highestThreshold.results_over_threshold > 0 && totals.conductor_truncation_markers === 0) {
    findings.push({
      code: 'CAP_MARKER_GAP', severity: 'WARN',
      detail: `${highestThreshold.results_over_threshold} result(s) exceeded ${highestThreshold.threshold_tokens} tokens but no CONDUCTOR truncation marker was observed; verify the hook on the branch where sessions ran.`,
    });
  }
  const roleDispatchCount = [...roles.values()].reduce((sum, value) => sum + value, 0);
  if (roleDispatchCount > 0 && !['helper', 'scribe', 'utility'].some((role) => roles.has(role))) {
    findings.push({
      code: 'LOW_COST_ROLE_GAP', severity: 'INFO',
      detail: `${roleDispatchCount} role dispatch(es) used none of helper, scribe, or utility; review representative tasks before claiming model-routing savings.`,
    });
  }
  return {
    source: path.resolve(options.sessions),
    since: options.since,
    ...totals,
    cache_read_share_percent: cacheReadShare,
    request_count_status: totals.unidentifiable_usage_records || totals.invalid_usage_fields || totals.malformed_records ? 'unverified' : 'identity-deduplicated',
    usage_method: 'maximum nonnegative integer counter per session/message identity; synthetic records excluded; not provider billing',
    // Compatibility alias. It now uses the canonical all-input denominator.
    cache_reuse_percent: cacheReadShare,
    branches: Object.fromEntries([...branches.entries()].sort()),
    role_dispatches: Object.fromEntries([...roles.entries()].sort()),
    thresholds: thresholdAnalysis,
    findings,
    estimate_note: 'Tool-result tokens use ceil(serialized characters / 4); savings exclude marker/shape overhead and are directional, not billing totals.',
  };
}

function printReport(report) {
  process.stdout.write('===== CONDUCTOR token-economy audit =====\n');
  process.stdout.write(`Sessions: ${report.source}\n`);
  if (report.since) process.stdout.write(`Since: ${report.since}\n`);
  process.stdout.write(`Files matched / scanned       : ${report.files_matched.toLocaleString()} / ${report.files_scanned.toLocaleString()}\n`);
  process.stdout.write(`Tool results                  : ${report.tool_results.toLocaleString()}\n`);
  process.stdout.write(`CONDUCTOR truncation markers  : ${report.conductor_truncation_markers.toLocaleString()}\n`);
  process.stdout.write(`Observed declared elision     : ${report.observed_declared_elided_tokens.toLocaleString()} tokens (marker lower bound)\n`);
  process.stdout.write(`Cache-read token share        : ${report.cache_read_share_percent == null ? 'unknown' : report.cache_read_share_percent.toFixed(2) + '%'} (read / (read + write + uncached))\n`);
  process.stdout.write(`Cache tokens (read/write/raw) : ${report.cache_read_tokens.toLocaleString()} / ${report.cache_write_tokens.toLocaleString()} / ${report.uncached_input_tokens.toLocaleString()}\n`);
  process.stdout.write(`Role dispatches               : ${JSON.stringify(report.role_dispatches)}\n`);
  process.stdout.write(`Observed branches             : ${JSON.stringify(report.branches)}\n\n`);
  process.stdout.write('Threshold reach (heuristic)\n');
  for (const row of report.thresholds) {
    process.stdout.write(`  ${String(row.threshold_tokens).padStart(6)} tokens : ${String(row.results_over_threshold).padStart(5)} result(s), ~${row.estimated_elidable_tokens.toLocaleString()} tokens elidable\n`);
  }
  if (report.findings.length) {
    process.stdout.write('\nFindings\n');
    for (const finding of report.findings) process.stdout.write(`  ${finding.severity} ${finding.code}: ${finding.detail}\n`);
  }
  process.stdout.write(`\n${report.estimate_note}\n`);
  process.stdout.write('(zero telemetry — local reads only; no external transmission)\n');
}

if (require.main === module) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (!options) { usage(); process.exitCode = 0; }
    else {
      const report = audit(options);
      if (options.json) process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
      else printReport(report);
    }
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    usage();
    process.exitCode = 2;
  }
}

module.exports = { audit, parseArgs, resultText, sessionFiles };
