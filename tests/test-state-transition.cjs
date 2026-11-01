'use strict';

// Real confined filesystem fixtures; no model execution or GitHub calls.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const transition = require('../commands/lib/state-transition.cjs');
const media = require('../commands/lib/bubo-media-adapter.cjs');
const promotion = require('../commands/lib/media-pipeline-promotion.cjs');
const ROOT = path.resolve(__dirname, '..');
const parent = path.join(ROOT, '.hephaera/.cache/tasks/hephaera-rename/evidence');
fs.mkdirSync(parent, {recursive:true});
const fixtures = fs.mkdtempSync(path.join(parent, 'state-transition-fixtures-'));
const python = process.env.HEPHAERA_TEST_PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
let checks = 0, linkSkips = 0;
const eq = (a,b) => {assert.deepEqual(a,b);checks++;};
const ok = value => {assert.ok(value);checks++;};
const throws = (fn, pattern = /transition|Legacy|legacy/i) => {assert.throws(fn,pattern);checks++;};
function host(name) {const root=path.join(fixtures,name);fs.mkdirSync(root);return root;}
function write(root,name,bytes) {const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);return file;}
function pythonRun(args) {
  const result=cp.spawnSync(python,['-B','-X','utf8',...args],{cwd:ROOT,encoding:'utf8'});
  if(result.error)throw result.error;
  return result;
}
function pythonInspect(root) {const result=pythonRun(['commands/lib/state_transition.py','inspect','--root',root]);eq(result.status,0);return JSON.parse(result.stdout);}
function prepare(root) {const result=pythonRun(['commands/lib/state_transition.py','prepare','--root',root]);eq(result.status,0);return JSON.parse(result.stdout);}
function snapshot(root) {
  const found=[];
  function visit(dir) {for(const item of fs.readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))) {
    const file=path.join(dir,item.name),relative=path.relative(root,file);
    if(item.isSymbolicLink())found.push([relative,'link']);
    else if(item.isDirectory()){found.push([relative,'dir']);visit(file);}
    else found.push([relative,fs.readFileSync(file).toString('hex')]);
  }}
  visit(root);return found;
}
function link(target,destination,directory=true) {
  try {fs.mkdirSync(path.dirname(destination),{recursive:true});fs.symlinkSync(target,destination,directory?(process.platform==='win32'?'junction':'dir'):'file');return true;}
  catch(error){if(['EPERM','EACCES','ENOSYS'].includes(error.code)){linkSkips++;return false;}throw error;}
}
try {
  const fresh=host('fresh'),freshBefore=snapshot(fresh);
  eq(transition.inspect(fresh).productionBlocked,false);
  eq(transition.inspect(fresh),pythonInspect(fresh));
  transition.assertProductionAllowed(fresh,'generation');transition.assertIssueWritesAllowed(fresh,'work');transition.assertBootstrapAllowed(fresh);checks+=3;
  eq(prepare(fresh).prepared,false);eq(snapshot(fresh),freshBefore);

  const old=host('legacy');
  const receipt=write(old,'.opencaw/.cache/tasks/work/operations/create-issue.json','{"operation":"original-identity","state":"pending"}\n');
  const consent=write(old,'.opencaw/.cache/retained-reference.txt','controlled fixture bytes; no recording\n');
  const oldBefore=snapshot(old);
  eq(transition.inspect(old).productionBlocked,true);eq(transition.inspect(old),pythonInspect(old));eq(snapshot(old),oldBefore);
  throws(()=>transition.assertProductionAllowed(old,'generation'));
  throws(()=>transition.assertBootstrapAllowed(old),/Prepare the state transition/);
  eq(pythonRun(['commands/lib/task-execution.py','--root',old,'create-task','work','Local repair','--no-issue']).status,2);
  eq(snapshot(old),oldBefore);
  throws(()=>transition.assertIssueWritesAllowed(old,'work'));
  transition.assertIssueWritesAllowed(old,'new-unrelated-task');checks++;
  const prepared=prepare(old);eq(prepared.prepared,true);eq(prepared.markerPresent,true);
  eq(fs.readFileSync(receipt,'utf8'),'{"operation":"original-identity","state":"pending"}\n');
  eq(fs.readFileSync(consent,'utf8'),'controlled fixture bytes; no recording\n');
  const marker=path.join(old,'.hephaera/.cache/STATE_TRANSITION.json'),markerBytes=fs.readFileSync(marker);
  eq(prepare(old).prepared,true);eq(fs.readFileSync(marker),markerBytes);
  throws(()=>transition.assertIssueWritesAllowed(old,'new-unrelated-task'));

  // Inspection may read bounded bootstrap text, never legacy receipt/media bytes.
  const read=fs.readFileSync,opened=[];
  fs.readFileSync=function(file,...args){opened.push(String(file));return read.call(this,file,...args);};
  try{transition.inspect(old);}finally{fs.readFileSync=read;}
  eq(opened.filter(file=>file.includes(path.join('.opencaw','.cache'))),[]);

  const preserved=path.join(old,'preserved-history');fs.renameSync(path.join(old,'.opencaw'),preserved);
  eq(transition.inspect(old).legacyPresent,false);eq(transition.inspect(old).productionBlocked,true);
  throws(()=>transition.assertProductionAllowed(old,'generation'));
  write(old,'.hephaera/.cache/STATE_TRANSITION.json','not-json');
  eq(prepare(old).productionBlocked,true);eq(fs.readFileSync(marker,'utf8'),'not-json');
  throws(()=>transition.assertProductionAllowed(old,'generation'));

  const oldBootstrapText='custom text\n<!-- OPENCAW_BOOTSTRAP_START -->\nRead old instructions.\n<!-- OPENCAW_BOOTSTRAP_END -->\n';
  const bootstrap=host('old-bootstrap'),agents=write(bootstrap,'AGENTS.md',oldBootstrapText);
  const bootstrapBefore=snapshot(bootstrap);eq(transition.inspect(bootstrap).legacyBootstrap,true);
  throws(()=>transition.assertBootstrapAllowed(bootstrap));eq(snapshot(bootstrap),bootstrapBefore);
  eq(prepare(bootstrap).markerPresent,true);eq(fs.readFileSync(agents,'utf8'),oldBootstrapText);
  const oversized=host('oversized-bootstrap');write(oversized,'AGENTS.md',Buffer.alloc(1048577));throws(()=>transition.inspect(oversized),/bound/);

  const collision=host('collision');write(collision,'.opencaw','file');throws(()=>transition.inspect(collision),/collid/);eq(pythonRun(['commands/lib/state_transition.py','inspect','--root',collision]).status,2);
  const linked=host('linked'),foreign=host('foreign');
  if(link(foreign,path.join(linked,'.opencaw'))){throws(()=>transition.inspect(linked),/link/);eq(pythonRun(['commands/lib/state_transition.py','prepare','--root',linked]).status,2);eq(fs.readdirSync(foreign),[]);}
  const markerLink=host('marker-link');write(markerLink,'.hephaera/.cache/sentinel','x');
  if(link(path.join(old,'.hephaera/.cache'),path.join(markerLink,'.hephaera/.cache/STATE_TRANSITION.json'))){throws(()=>transition.inspect(markerLink),/link/);eq(pythonRun(['commands/lib/state_transition.py','prepare','--root',markerLink]).status,2);}

  // Production hooks must fail before reading a manifest, claiming attempts or copying assets.
  const gated=host('production-gate');write(gated,'.hephaera/.cache/STATE_TRANSITION.json','{}');const beforeGate=snapshot(gated);
  for(const [operation,extra] of [['generate',[]],['setup',[['execute','true']]],['inspect',[['load','true']]]])
    throws(()=>media.contextFor(operation,new Map([['root',gated],['task','work'],...extra]),{}));
  throws(()=>media.bindSharedState({root:gated,sharedBinding:{approvalSha256:'a'.repeat(64)}}));
  throws(()=>promotion.promote({root:gated,stateFile:'missing',authorization:'missing',validate(){throw new Error('Validation must not run');}}));
  throws(()=>promotion.recover({root:gated,stateFile:'missing',authorization:'missing',validate(){throw new Error('Validation must not run');}}));
  const nativeScript="const host=require(process.argv[1]);host.execute(process.argv[3],process.argv[4],new Map(),{root:process.argv[2],stateRoot:'.hephaera/.cache/tasks/work/native',context:{policy:{purpose:'unreviewed'}}},{},false).then(()=>{console.error('Native operation was not fenced');process.exitCode=1;},error=>{if(!/State transition blocks/.test(error.message)){console.error(error.message);process.exitCode=1;}else console.log('native-operation-blocked-before-state-or-process');});";
  for(const [workflow,operation] of [['model-to-animation','author'],['blender-inspection','inspect']]) {
    const result=cp.spawnSync(process.execPath,['-e',nativeScript,path.join(ROOT,'commands/lib/bubo-host-adapter.cjs'),gated,workflow,operation],{encoding:'utf8'});
    eq(result.status,0);ok(result.stdout.includes('native-operation-blocked-before-state-or-process'));
  }
  eq(snapshot(gated),beforeGate);

  // Python tasks remain local-only usable; a fenced issue stops before repository/API lookup.
  const script=`import importlib.util,pathlib,sys\np=pathlib.Path(sys.argv[1])\ns=importlib.util.spec_from_file_location('task_execution',p)\nm=importlib.util.module_from_spec(s);s.loader.exec_module(m)\nr=pathlib.Path(sys.argv[2])\nm.create_task(r,'work','Local fixture',no_issue=True)\ndef forbidden(*a,**k):raise AssertionError('External path entered')\nm.repository=forbidden\ntry:m.create_issue(r,'work')\nexcept m.TaskError as e:\n assert 'State transition blocks' in str(e)\nelse:raise AssertionError('Issue was not fenced')\nprint('local-task-allowed; issue-write-blocked-before-api')\n`;
  const result=pythonRun(['-c',script,path.join(ROOT,'commands/lib/task-execution.py'),gated]);
  eq(result.status,0);ok(result.stdout.includes('issue-write-blocked-before-api'));
  eq(fs.existsSync(path.join(gated,'.hephaera/.cache/tasks/work/operations/create-issue.json')),false);
  eq(fs.existsSync(path.join(gated,'.hephaera/.cache/tasks/work/TASK.md')),true);
  console.log(`State transition: ${checks} checks passed (${linkSkips} unavailable link cases; confined fixtures, no GitHub/model/private-media execution).`);
} finally {
  const intended=path.resolve(parent),target=path.resolve(fixtures);
  if(!target.startsWith(intended+path.sep))throw new Error('Unsafe state transition fixture cleanup target.');
  fs.rmSync(target,{recursive:true,force:true});
}
