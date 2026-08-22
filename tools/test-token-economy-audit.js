'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { audit } = require('./audit-token-economy.js');
const { bashPath, runBash } = require('./run-bash.js');

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
      { type: 'tool_result', content: 'small …[CONDUCTOR] output truncated — 123 tokens elided; re-run scoped…' },
      { type: 'tool_use', name: 'Agent', input: { subagent_type: 'utility' } },
    ] } },
  ];
  fs.writeFileSync(path.join(temp, 'session.jsonl'), `${records.map(JSON.stringify).join('\n')}\n`);
  const report = audit({ sessions: temp, since: '2026-07-28T00:00:00Z', thresholds: [3000, 4000, 6000] });
  assert.strictEqual(report.files_matched, 1);
  assert.strictEqual(report.tool_results, 2);
  assert.strictEqual(report.conductor_truncation_markers, 1);
  assert.strictEqual(report.observed_declared_elided_tokens, 123);
  assert.strictEqual(report.model_calls_with_usage, 1);
  assert.strictEqual(report.cache_read_share_percent, 89.55);
  assert.strictEqual(report.cache_reuse_percent, 89.55);
  assert.deepStrictEqual(report.role_dispatches, { 'code-reviewer': 1, utility: 1 });
  assert.deepStrictEqual(report.branches, { 'feature/old': 2 });
  assert.deepStrictEqual(report.thresholds, [
    { threshold_tokens: 3000, results_over_threshold: 1, estimated_elidable_tokens: 2000 },
    { threshold_tokens: 4000, results_over_threshold: 1, estimated_elidable_tokens: 1000 },
    { threshold_tokens: 6000, results_over_threshold: 0, estimated_elidable_tokens: 0 },
  ]);
  assert.deepStrictEqual(report.findings, []);

  const measured = runBash('tools/measure-tokens.sh', [`--session=${bashPath(path.join(temp, 'session.jsonl'))}`], {
    cwd: path.resolve(__dirname, '..'), encoding: 'utf8', stdio: 'pipe',
  });
  assert.strictEqual(measured.status, 0, measured.stderr || measured.stdout);
  assert.match(measured.stdout, /Cache-read token share\s+: 89\.6%/);

  const hook = runBash('core/hooks/stop-cache-hit-baseline-check.sh.template', [], {
    cwd: path.resolve(__dirname, '..'), encoding: 'utf8', stdio: 'pipe',
    env: {
      CONDUCTOR_CACHE_TEST_FIXTURE: bashPath(path.join(temp, 'session.jsonl')),
      CONDUCTOR_CACHE_TOTAL_FLOOR: '1',
      CONDUCTOR_CACHE_HIT_FLOOR_PERCENT: '95',
    },
  });
  assert.strictEqual(hook.status, 0, hook.stderr || hook.stdout);
  assert.match(hook.stderr, /cache-read token share: 89\.6%/);

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
  process.stdout.write('PASS: token-economy session audit and three-reporter cache formula parity\n');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
