#!/usr/bin/env node
'use strict';

// Privacy-preserving, local-only per-user savings report. It deliberately keeps
// observed output elision separate from structural context estimates and never
// turns provider caching into a CONDUCTOR-attributed saving.

const instructionFootprint = require('./instruction-footprint.js');
const sessionEconomy = require('../tools/audit-token-economy.js');

function assertSubject(subject) {
  if (subject == null) return null;
  if (typeof subject !== 'string' || !subject.length || subject.length > 80 || /[\u0000-\u001f\u007f]/u.test(subject)) {
    throw new Error('--subject must be 1-80 characters without control characters');
  }
  return subject;
}

function create(options) {
  const target = options.target;
  if (!instructionFootprint.ADAPTERS.includes(target)) {
    throw new Error(`--target must be one of: ${instructionFootprint.ADAPTERS.join(', ')}`);
  }
  const subject = assertSubject(options.subject);
  if (options.since && !Number.isFinite(Date.parse(options.since))) throw new Error('--since must be ISO-8601');
  if (options.thresholds && (!Array.isArray(options.thresholds) || !options.thresholds.length
    || options.thresholds.some((value) => !Number.isSafeInteger(value) || value < 1))) {
    throw new Error('--thresholds must contain positive integers');
  }
  let observed = null;
  let inferredRequests = null;
  if (options.sessions) {
    if (target !== 'claude') {
      throw new Error('session-derived observed savings currently support --target=claude only; use --requests for other adapters');
    }
    const session = sessionEconomy.audit({
      sessions: options.sessions,
      since: options.since || null,
      thresholds: options.thresholds ? [...new Set(options.thresholds)].sort((a, b) => a - b) : [3000, 4000, 6000, 8000, 12000],
    });
    if (!options.requests && session.request_count_status !== 'identity-deduplicated') {
      throw new Error('session usage lacks reliable identities/counters; provide a verified --requests=N instead of inferring model calls');
    }
    inferredRequests = session.model_calls_with_usage;
    observed = {
      source_kind: 'local-claude-jsonl',
      files_scanned: session.files_scanned,
      files_matched: session.files_matched,
      model_calls_with_usage: session.model_calls_with_usage,
      request_count_status: session.request_count_status,
      duplicate_usage_records: session.duplicate_usage_records,
      truncation_markers: session.conductor_truncation_markers,
      output_tokens_elided_lower_bound: session.observed_declared_elided_tokens,
      cache_read_share_percent: session.cache_read_share_percent,
      cache_attribution: 'reported as health context only; not attributed to CONDUCTOR savings',
    };
  }
  const requests = options.requests || inferredRequests;
  if (!requests) throw new Error('provide --requests=N, or Claude --sessions containing at least one usage-bearing model call');
  if (!Number.isSafeInteger(requests) || requests < 1 || requests > 1000000000) {
    throw new Error('--requests must be an integer from 1 to 1000000000');
  }
  const footprint = instructionFootprint.audit(options.project || '.', { requests, adapters: [target] });
  const item = footprint.adapters[0];
  if (!item) throw new Error(`no ${target} CONDUCTOR manifest found in the project`);
  return {
    schema_version: 1,
    subject,
    generated_from: 'local files only; no telemetry or external transmission',
    target,
    request_count: requests,
    request_count_basis: options.requests ? 'user-supplied' : 'identity-deduplicated Claude model calls in selected sessions',
    observed_output_savings: observed,
    estimated_instruction_context_savings: {
      comparison: item.comparison,
      always_active_tokens: item.estimated_always_active_tokens,
      avoided_context_tokens_per_request: item.estimated_avoided_context_tokens_per_request,
      avoided_context_tokens_for_requests: item.estimated_avoided_context_tokens_for_requests,
      estimate_method: 'installed byte footprint / 4 heuristic; logical context, not billing or money',
      savings_status: item.savings_status,
      known_project_instruction_bytes: item.project_exposure.bytes_lower_bound,
    },
    total_savings: null,
    total_note: 'No grand total: observed output elision and estimated input-context avoidance have different evidence strength; provider caching is excluded.',
    problems: item.problems,
    warnings: item.project_exposure.warnings,
    unmeasured_scope: item.project_exposure.scope,
  };
}

function render(report) {
  const who = report.subject ? ` for ${report.subject}` : '';
  const lines = [`CONDUCTOR personal token-savings report${who}`, '', `Adapter: ${report.target}`, `Requests measured: ${report.request_count.toLocaleString()} (${report.request_count_basis})`];
  if (report.observed_output_savings) {
    lines.push('', 'Observed output savings (lower bound)',
      `  Tokens explicitly marked elided: ${report.observed_output_savings.output_tokens_elided_lower_bound.toLocaleString()}`,
      `  Truncation markers: ${report.observed_output_savings.truncation_markers.toLocaleString()}`,
      `  Cache-read token share: ${report.observed_output_savings.cache_read_share_percent == null ? 'unknown' : report.observed_output_savings.cache_read_share_percent.toFixed(2) + '%'} (health only; not credited as savings)`);
  } else {
    lines.push('', 'Observed output savings: unavailable for this report (no compatible local session evidence supplied)');
  }
  const estimate = report.estimated_instruction_context_savings;
  lines.push('', 'Estimated bounded-kernel context avoidance',
    `  Per request: ≈${(estimate.avoided_context_tokens_per_request || 0).toLocaleString()} tokens`,
    `  Selected requests: ≈${(estimate.avoided_context_tokens_for_requests || 0).toLocaleString()} tokens`,
    `  Basis: ${estimate.comparison}`,
    '', report.total_note,
    report.generated_from);
  for (const problem of report.problems) lines.push(`PROBLEM: ${problem}`);
  for (const warning of report.warnings) lines.push(`WARNING: ${warning}`);
  lines.push('Estimate applies to the initial managed baseline. Loaded references and repeated history can reduce or reverse this avoidance.');
  return lines.join('\n');
}

module.exports = { create, render };
