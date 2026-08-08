'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { audit } = require('./audit-token-economy.js');

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'conductor-token-audit-'));
try {
  const records = [
    { timestamp: '2026-07-27T23:59:00Z', message: { content: [{ type: 'tool_result', content: 'x'.repeat(80000) }] } },
    { timestamp: '2026-07-28T01:00:00Z', gitBranch: 'feature/old', message: {
      usage: { cache_read_input_tokens: 900, cache_creation_input_tokens: 100, input_tokens: 5, output_tokens: 7 },
      content: [
        { type: 'tool_result', content: 'x'.repeat(20000) },
        { type: 'tool_use', name: 'Agent', input: { subagent_type: 'code-reviewer' } },
      ],
    } },
    { timestamp: '2026-07-28T02:00:00Z', gitBranch: 'feature/old', message: { content: [
      { type: 'tool_result', content: 'small …[CONDUCTOR] output truncated; re-run scoped…' },
      { type: 'tool_use', name: 'Agent', input: { subagent_type: 'utility' } },
    ] } },
  ];
  fs.writeFileSync(path.join(temp, 'session.jsonl'), `${records.map(JSON.stringify).join('\n')}\n`);
  const report = audit({ sessions: temp, since: '2026-07-28T00:00:00Z', thresholds: [3000, 4000, 6000] });
  assert.strictEqual(report.files_matched, 1);
  assert.strictEqual(report.tool_results, 2);
  assert.strictEqual(report.conductor_truncation_markers, 1);
  assert.strictEqual(report.cache_reuse_percent, 90);
  assert.deepStrictEqual(report.role_dispatches, { 'code-reviewer': 1, utility: 1 });
  assert.deepStrictEqual(report.branches, { 'feature/old': 2 });
  assert.deepStrictEqual(report.thresholds, [
    { threshold_tokens: 3000, results_over_threshold: 1, estimated_elidable_tokens: 2000 },
    { threshold_tokens: 4000, results_over_threshold: 1, estimated_elidable_tokens: 1000 },
    { threshold_tokens: 6000, results_over_threshold: 0, estimated_elidable_tokens: 0 },
  ]);
  assert.deepStrictEqual(report.findings, []);

  const gapFile = path.join(temp, 'gap.jsonl');
  fs.writeFileSync(gapFile, `${JSON.stringify({
    timestamp: '2026-07-28T03:00:00Z',
    message: { content: [
      { type: 'tool_result', content: 'z'.repeat(20000) },
      { type: 'tool_use', name: 'Agent', input: { subagent_type: 'code-reviewer' } },
    ] },
  })}\n`);
  const gapReport = audit({ sessions: gapFile, since: '2026-07-28T00:00:00Z', thresholds: [4000] });
  assert.deepStrictEqual(gapReport.findings.map((finding) => finding.code), ['CAP_MARKER_GAP', 'LOW_COST_ROLE_GAP']);
  process.stdout.write('PASS: token-economy session audit\n');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
