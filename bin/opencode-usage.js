'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
function canonicalProject(value, cwd = process.cwd()) {
  const windows = /^[A-Za-z]:[\\/]/.test(value) || value.startsWith('\\\\')
    || /^[A-Za-z]:[\\/]/.test(cwd) || cwd.startsWith('\\\\');
  // Relative project arguments (including the default '.') must use the same
  // normalization as the database's absolute Windows directory.
  return windows ? path.win32.resolve(cwd, value).replace(/\\/g, '/').replace(/\/$/, '').toLowerCase()
    : path.resolve(cwd, value).replace(/\/$/, '');
}
function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b), mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}
function analyze(snapshot, options) {
  const since = options.since ? Date.parse(options.since) : -Infinity;
  const until = options.until ? Date.parse(options.until) : Infinity;
  if (Number.isNaN(since) || Number.isNaN(until) || since >= until) throw new Error('invalid --since/--until interval');
  const project = canonicalProject(options.project || '.');
  const scoped = snapshot.rows.filter(r => typeof r.directory === 'string' && r.directory.length > 0 && canonicalProject(r.directory) === project);
  const parents = new Map((snapshot.sessions || scoped).filter(r => typeof r.directory === 'string' && r.directory.length > 0
    && canonicalProject(r.directory) === project).map(r => [r.session, r.parent]));
  function owner(row) {
    let id = row.session; const seen = new Set();
    while (parents.get(id)) {
      if (seen.has(id)) throw new Error('cyclic session parent graph');
      seen.add(id); id = parents.get(id);
    }
    return parents.has(id) ? id : null;
  }
  function descendsFrom(row, ancestor) {
    let id = row.session; const seen = new Set();
    while (id) {
      if (id === ancestor) return true;
      if (seen.has(id)) throw new Error('cyclic session parent graph');
      seen.add(id); id = parents.get(id);
    }
    return false;
  }
  if (options.session && !parents.has(options.session)) throw new Error('--session is not present in the selected project');
  const records = scoped.filter(r => r.time_created != null && r.time_created >= since && r.time_created < until
    && (!options.session || descendsFrom(r, options.session)));
  if (records.some(r => !r.id || !r.session)) throw new Error('message/session identities are missing or unsupported');
  const seen = new Set(), unique = [];
  for (const row of records) { const key = JSON.stringify([row.session, row.id]); if (!seen.has(key)) { seen.add(key); unique.push(row); } }
  const complete = unique.filter(r => ['input', 'cache_read', 'cache_write'].every(k => r[k] != null));
  const large = complete.filter(r => r.input + r.cache_read + r.cache_write >= 100000).length;
  const groups = new Map(), tasks = new Map();
  for (const r of unique) {
    const kind = snapshot.parent_attribution_available ? (r.parent ? 'subagent' : 'main') : 'unknown';
    const key = JSON.stringify([kind, r.role, r.provider, r.model]);
    if (!groups.has(key)) groups.set(key, { kind, role: r.role, provider: r.provider, model: r.model, calls: 0,
      input: 0, output: 0, reasoning: 0, calls_with_reasoning: 0, cache_read: 0, cache_write: 0, known_provider_cost: 0, calls_with_cost: 0, incomplete_token_calls: 0 });
    const g = groups.get(key); g.calls++;
    for (const field of ['input', 'output', 'reasoning', 'cache_read', 'cache_write']) g[field] += r[field] || 0;
    if (r.reasoning != null) g.calls_with_reasoning++;
    if (['input', 'output', 'cache_read', 'cache_write'].some(k => r[k] == null)) g.incomplete_token_calls++;
    if (r.cost != null) { g.known_provider_cost += r.cost; g.calls_with_cost++; }
    const id = snapshot.parent_attribution_available ? owner(r) : null;
    if (id == null) continue;
    if (!tasks.has(id)) tasks.set(id, { session: id, calls: 0, known_provider_cost: 0, missing_cost_calls: 0 });
    const t = tasks.get(id); t.calls++;
    if (r.cost == null) t.missing_cost_calls++; else t.known_provider_cost += r.cost;
  }
  const warnings = [];
  if (!unique.length) warnings.push('No matching assistant calls; this is not evidence of zero usage.');
  if (scoped.some(r => r.time_created == null)) warnings.push('Some messages lack valid creation times and were excluded.');
  if (complete.length !== unique.length) warnings.push('Large-input share excludes calls with unknown input/cache counters.');
  if (!snapshot.parent_attribution_available) warnings.push('This schema has no parent_id; main/subagent and terminal-task attribution are unverified.');
  if (snapshot.parent_attribution_available && unique.some(r => owner(r) == null)) warnings.push('Some parent sessions are outside the project or missing; their terminal-task attribution is excluded.');
  if (unique.some(r => !r.provider || !r.model)) warnings.push('Some calls lack provider/model attribution.');
  if (large) warnings.push('Large contexts observed: narrow reads, shorten active continuity notes, and start a new session at a completed phase boundary.');
  const values = [...tasks.values()];
  return { schema_version: 1, target: 'opencode', schema_fingerprint: snapshot.schema_fingerprint,
    schema: snapshot.schema, source_contract: 'observed OpenCode message(time_created,data) schema; verified per snapshot, not a universal version claim',
    cohort: { since: options.since || null, until: options.until || null, session: options.session || null,
      selection: 'exact normalized project directory; assistant messages; inclusive since/exclusive until; session filter includes descendants; tasks are root-session proxies, not verified completed work; intervals can truncate sessions',
      calls: unique.length, tasks: values.length, excluded_other_project_calls: snapshot.rows.length - scoped.length },
    large_input: { threshold: 100000, calls: large, calls_with_known_input: complete.length,
      percent: complete.length ? Number((large / complete.length * 100).toFixed(2)) : null },
    groups: [...groups.values()], terminal_tasks: values,
    cohort_median: { calls_per_task: median(values.map(t => t.calls)),
      provider_cost_per_task: median(values.filter(t => !t.missing_cost_calls).map(t => t.known_provider_cost)),
      tasks_with_complete_cost: values.filter(t => !t.missing_cost_calls).length },
    warnings, billing_credits: null, realized_savings: null,
    note: 'No transcript text, telemetry, model call, or credit conversion. Cost is the DB numeric cost field, not a Copilot invoice. Input excludes cache; output excludes separately reported reasoning under the observed OpenCode convention. Token sums include known counters only; missing values are disclosed.' };
}
function audit(options) {
  if (!options.database) throw new Error('--database=<OpenCode SQLite file> is required');
  // Resolve a normal executable, never a shell string or an arbitrary interpreter
  // snippet supplied by the caller. Python's standard library is the only dependency.
  let result;
  for (const command of ['python3', 'python']) {
    const probe = spawnSync(command, ['-c', 'import sqlite3,sys; sys.exit(0 if sys.version_info[0] == 3 else 1)'], { encoding: 'utf8', timeout: 5000, windowsHide: true });
    if (probe.status !== 0) continue;
    result = spawnSync(command, [path.join(__dirname, '../tools/opencode-snapshot.py'), path.resolve(options.database)],
      { encoding: 'utf8', timeout: 30000, maxBuffer: 32 * 1024 * 1024, windowsHide: true });
    break;
  }
  if (!result) throw new Error('Python 3 with sqlite3 is required; install Python 3 and retry. No model/provider access is needed.');
  if (result.error || result.status !== 0) throw new Error(result.error ? 'OpenCode snapshot timed out or exceeded its output budget' : result.stderr.trim());
  return analyze(JSON.parse(result.stdout), options);
}
function render(r) {
  return ['CONDUCTOR OpenCode usage audit (local-only)',
    `Schema: ${r.schema_fingerprint}`, `Matching calls: ${r.cohort.calls}; root-session proxies: ${r.cohort.tasks}`,
    `Input ≥100K: ${r.large_input.calls}/${r.large_input.calls_with_known_input} (${r.large_input.percent == null ? 'unknown' : r.large_input.percent + '%'})`,
    `Median calls/root-session proxy: ${r.cohort_median.calls_per_task ?? 'unknown'}`,
    'Task groups are root-session proxies, not verified completed work; date filters can truncate sessions.',
    ...r.groups.map(g => `${g.kind} ${g.role || 'unknown-role'} ${g.provider || '?'}/${g.model || '?'}: ${g.calls} calls; known input/output/reasoning/cache-read/cache-write=${g.input}/${g.output}/${g.reasoning}/${g.cache_read}/${g.cache_write}; reasoning known for ${g.calls_with_reasoning}/${g.calls}; ${g.incomplete_token_calls} incomplete input/output/cache records; DB cost=${g.known_provider_cost} (known for ${g.calls_with_cost}/${g.calls}, not billed credits)`),
    ...r.warnings.map(w => `WARN: ${w}`), r.note].join('\n');
}
module.exports = { audit, analyze, render, canonicalProject, median };
