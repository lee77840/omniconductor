'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const usage = require('../bin/opencode-usage.js');
assert.strictEqual(usage.canonicalProject('.', 'C:\\Projects\\App'), 'c:/projects/app');
assert.strictEqual(usage.canonicalProject('..\\App', 'C:\\Projects\\Other'), 'c:/projects/app');
assert.strictEqual(usage.canonicalProject('.', '\\\\Server\\Share\\App'), '//server/share/app');
const dir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'conductor-opencode-usage-'));
const database = path.join(dir, 'snapshot.db');
const python = ['python3', 'python'].find(c => spawnSync(c, ['-c', 'import sqlite3']).status === 0);
assert(python, 'Python 3/sqlite3 required for snapshot regression');
const make = spawnSync(python, ['-c', `
import sqlite3,json,sys
c=sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE session(id TEXT PRIMARY KEY,directory TEXT,parent_id TEXT)')
c.execute('CREATE TABLE message(id TEXT PRIMARY KEY,session_id TEXT,time_created INTEGER,data TEXT)')
for row in [('root','C:\\Project',None),('child','c:/project','root'),('grandchild','C:/PROJECT','child'),('second','C:/Project',None),('outside','C:/Other',None)]:
 c.execute('INSERT INTO session VALUES(?,?,?)',row)
for mid,sid,cost in [('m1','root',0),('m2','grandchild',None),('m3','second',2),('m4','outside',3)]:
 data={'role':'assistant','providerID':'github-copilot','modelID':'test-model','agent':'builder','cost':cost,'tokens':{'input':100,'output':10,'reasoning':50,'cache':{'read':100000,'write':0}},'text':'PRIVATE_TRANSCRIPT_SENTINEL'}
 c.execute('INSERT INTO message VALUES(?,?,?,?)',(mid,sid,1000,json.dumps(data)))
c.commit();c.close()
`, database], { encoding: 'utf8' });
assert.strictEqual(make.status, 0, make.stderr);
const before = fs.readFileSync(database);
const r = usage.audit({ database, project: 'c:/project' });
assert.strictEqual(r.cohort.calls, 3);
assert.strictEqual(r.cohort.tasks, 2);
assert.strictEqual(r.cohort_median.calls_per_task, 1.5);
assert.strictEqual(r.cohort_median.provider_cost_per_task, 2);
assert.strictEqual(r.cohort_median.tasks_with_complete_cost, 1);
assert.strictEqual(r.large_input.percent, 100);
assert.strictEqual(r.groups.find(g => g.kind === 'subagent').calls, 1);
assert.strictEqual(r.groups.find(g => g.kind === 'main').reasoning, 100);
assert.strictEqual(r.groups.find(g => g.kind === 'main').calls_with_reasoning, 2);
assert.strictEqual(r.billing_credits, null);
assert.strictEqual(r.realized_savings, null);
assert.match(usage.render(r), /root-session proxies, not verified completed work/);
assert.match(usage.render(r), /date filters can truncate sessions/);
assert(!JSON.stringify(r).includes('PRIVATE_TRANSCRIPT_SENTINEL'));
assert.deepStrictEqual(fs.readFileSync(database), before);
assert.deepStrictEqual(fs.readdirSync(dir), ['snapshot.db']);
assert.strictEqual(usage.audit({ database, project: 'C:/PROJECT', session: 'root' }).cohort.calls, 2);
assert.strictEqual(usage.audit({ database, project: 'C:/PROJECT', session: 'child' }).cohort.calls, 1);
assert.strictEqual(usage.audit({ database, project: 'C:/PROJECT', since: '2026-01-01' }).cohort.calls, 0);
assert.throws(() => usage.audit({ database, project: 'C:/PROJECT', since: 'invalid' }), /invalid/);
console.log('PASS: Windows path normalization, observed schema, transitive parents, cohort medians, unknown cost, privacy and source noninterference');
spawnSync(python, ['-c', "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute('ALTER TABLE message RENAME COLUMN time_created TO created_at');c.commit();c.close()", database]);
assert.throws(() => usage.audit({ database, project: 'C:/Project' }), /unsupported OpenCode schema/);
console.log('PASS: historical incorrect schema fails closed instead of inventing metrics');
const walTest = spawnSync(python, ['-c', `
import sqlite3,sys,subprocess,json,pathlib,hashlib
db=pathlib.Path(sys.argv[1]); c=sqlite3.connect(str(db))
c.execute('ALTER TABLE message RENAME COLUMN created_at TO time_created');c.commit()
c.execute('PRAGMA journal_mode=WAL');c.execute('PRAGMA wal_autocheckpoint=0')
c.execute("UPDATE message SET time_created=2000 WHERE id='m1'");c.commit()
def hashes():
 return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in db.parent.iterdir() if p.is_file()}
before=hashes()
r=subprocess.run([sys.executable,sys.argv[2],str(db)],capture_output=True,text=True)
assert r.returncode==0,r.stderr
assert hashes()==before,'source DB/WAL/SHM changed'
data=json.loads(r.stdout);assert next(r for r in data['rows'] if r['id']=='m1')['time_created']==2000
c.close()
`, database, path.resolve(__dirname, 'opencode-snapshot.py')], { encoding: 'utf8', timeout: 30000 });
assert.strictEqual(walTest.status, 0, walTest.stderr);
console.log('PASS: uncheckpointed WAL data is visible while original DB/WAL/SHM hashes remain unchanged');
const link = path.join(dir, 'linked.db');
if (process.platform !== 'win32') {
  fs.symlinkSync(database, link);
  assert.throws(() => usage.audit({ database: link }), /symbolic links/);
}
const base = { parent_attribution_available: false, rows: [{ id: 'm', session: 's', directory: '/project', time_created: 1, input: null, cache_read: null, cache_write: null, cost: null }] };
const unknown = usage.analyze(base, { project: '/project' });
assert.strictEqual(unknown.cohort.tasks, 0);
assert.strictEqual(unknown.large_input.percent, null);
assert.strictEqual(unknown.cohort_median.calls_per_task, null);
assert(unknown.warnings.length >= 3);
const cli = spawnSync(process.execPath, [path.resolve(__dirname, '../bin/omniconductor.js'), 'audit', 'opencode', '--unknown'], { encoding: 'utf8' });
assert.strictEqual(cli.status, 2);
console.log('PASS: unsafe sources, unknown attribution/counters and invalid CLI options are explicit');
