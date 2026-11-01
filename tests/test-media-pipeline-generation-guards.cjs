'use strict';

// Owned fake installation data only. --native-runtime additionally exercises
// the actual pinned HostExecutionContext API, never a model or GPU worker.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert/strict');
const runtime=require('../commands/lib/bubo-runtime.cjs'),adapter=require('../commands/lib/bubo-media-adapter.cjs');
const native=process.argv.slice(2).includes('--native-runtime');
if(process.argv.slice(2).some(arg=>arg!=='--native-runtime'))throw new Error('Unsupported guard-test option.');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-voice-pipeline/evidence/generation-guard-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-generation-guards',workspace='.hephaera/.cache/owned-media',observations=[];
const check=(value,label)=>{assert(value,label);observations.push(label);};
const rejects=(action,pattern,label)=>{assert.throws(action,pattern,label);observations.push(label);};
function write(name,value){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>({path:name,sha256:runtime.hash(path.join(root,name))});
function directory(name){fs.mkdirSync(path.join(root,name),{recursive:true});return name;}
const media='# MEDIA.md\nGenerated from Hephaera media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'+['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(heading=>'## '+heading+'\n').join('\n')+'\nImage/music/sound-effect SFX/voice separate. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md',media);
const rights=ref(write('inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned fixture only',promptRightsConfirmed:true,generationAllowed:true}));
const license=ref(write('inputs/license.json',{fixture:'No actual license acceptance'}));
const python=ref(write(workspace+'/tools/environment/python-owned.bin','Owned nonexecutable tool bytes'));
const modelDirectory=directory(workspace+'/tools/models/owned');
const installation=ref(write(workspace+'/receipts/owned.json',{schemaVersion:'bubo-media-installation/v1',backend:'stable-audio-open',modelDirectory,licenses:[license],python}));
write('inputs/request.json',{schemaVersion:'bubo-media-request/v1',task,requestId:'owned-policy-check',backend:'stable-audio-open',outputDirectory:workspace+'/staging/owned-policy-check',rights,installation,
  settings:{device:'cuda:0',precision:'float16',offload:'none'},budget:{maximumOutputs:1,maximumBytesPerOutput:4096,maximumTotalBytes:4096,maximumPixels:4096,maximumAudioSeconds:1},
  items:[{id:'owned',prompt:'Owned synthetic input',negativePrompt:'',seed:1,steps:1,guidance:1,seconds:1,loopCandidate:false}]});
const info={capability:{mediaBackends:[{id:'stable-audio-open',modality:'sfx'}]}};
const options=adapter.parse(['--root',root,'--task',task,'--manifest','inputs/request.json','--workspace',workspace,'--media-state','.hephaera/.cache/shared-allowance']);
const source=ref(write('inputs/local-use-source.txt','Owned synthetic human source, no actual user permission'));
const use=ref(write('inputs/local-use.json',{fixture:'Host-only purpose assertion',sourceEvidence:source}));
const hostContract=ref(write('VOICE.md','# Owned synthetic selected-domain contract\n'));
const prepare=refs=>adapter.contextFor('generate',options,info,{policyReferences:refs});
const admitted=prepare([use,source,hostContract,rights]);
for(const value of [use,source,hostContract])check(admitted.context.references.some(record=>record.path===value.path&&record.sha256===value.sha256&&record.kind==='policy'),'Host-only native policy identity retained: '+value.path);
check(admitted.context.references.find(value=>value.path===rights.path).kind==='rights','Existing native authority kind is preserved instead of replaced with policy');
check(!Object.hasOwn(admitted.request,'policyReferences'),'Internal guard identities never alter the native request DTO');
const bytes=fs.readFileSync(path.join(root,source.path));write(source.path,'Owned source revocation');
rejects(()=>prepare([use,source]),/hash changed/,'Changed declared source hash fails admission rather than rebinding current bytes');
fs.writeFileSync(path.join(root,source.path),bytes);
rejects(()=>prepare([{...source,kind:'consent'}]),/Exact internal/,'A caller cannot inject native authority kinds through policy references');
rejects(()=>prepare([python]),/alias an executable/,'Host policy cannot alias a registered executable/module');
rejects(()=>prepare([ref(write(workspace+'/staging/owned.json',{fixture:true}))]),/mutable/,'Host policy cannot overlap mutable staging');
rejects(()=>prepare([ref(write('.hephaera/.cache/tasks/'+task+'/bubo-media/owned.json',{fixture:true}))]),/mutable/,'Host policy cannot overlap native execution state');
rejects(()=>prepare(new Array(257).fill(source)),/Bounded/,'Additional policy references have a finite count bound');
rejects(()=>adapter.parse(['--policy-references','inputs/override.json']),/Unknown|protected/,'No public CLI policy-reference override is introduced');
write('inputs/native-context.json',admitted.context);
let nativeEvidence=null;
if(native){
  const verified=runtime.verified(),assembly=path.join(verified.folder,'Bubo.Host.dll');
  const receipt=JSON.parse(fs.readFileSync(path.join(verified.folder,'build-info.json'),'utf8'));
  check(runtime.hash(assembly)===receipt.capabilities.build.assemblies['Bubo.Host.dll'],'Actual harness assembly matches the verified pinned native receipt');
  const project=path.join(root,'native-harness');fs.mkdirSync(project);
  const xml=value=>value.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  fs.writeFileSync(path.join(project,'GuardHarness.csproj'),'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings><NuGetAudit>false</NuGetAudit><UseSharedCompilation>false</UseSharedCompilation></PropertyGroup><ItemGroup><Reference Include="Bubo.Host"><HintPath>'+xml(assembly)+'</HintPath><Private>true</Private></Reference></ItemGroup></Project>');
  fs.writeFileSync(path.join(project,'NuGet.Config'),'<configuration><packageSources><clear /></packageSources></configuration>');
  fs.writeFileSync(path.join(project,'Program.cs'),`using Bubo.Host;
var root=args[0];var context=Bubo.Host.HostExecutionContext.Load(root,args[1]);context.ValidateFresh();var checks=0;
foreach(var relative in args.Skip(2)){
  context.RequireReference(relative);var file=Path.Combine(root,relative);var original=File.ReadAllBytes(file);
  try{File.WriteAllText(file,"Owned changed purpose/source bytes");var rejected=false;
    try{context.ValidateFresh();}catch(InvalidOperationException error){rejected=error.Message.Contains("Host reference hash changed",StringComparison.Ordinal);}
    if(!rejected)throw new InvalidOperationException("Native policy mutation was accepted");checks++;
  }finally{File.WriteAllBytes(file,original);}
  context.ValidateFresh();
}
Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{checks,scope="Actual pinned native policy freshness only; no process/model/GPU execution"}));`);
  const logs=[];
  function dotnet(args){const result=cp.spawnSync('dotnet',args,{cwd:project,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:16777216,env:{...process.env,DOTNET_CLI_TELEMETRY_OPTOUT:'1',DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE:'1'}});logs.push({args,status:result.status,stdout:result.stdout,stderr:result.stderr});fs.writeFileSync(path.join(root,'native-build-log.json'),JSON.stringify(logs,null,2)+'\n');if(result.status!==0)throw new Error('Owned native harness failed: '+result.stdout+'\n'+result.stderr);return result.stdout;}
  const isolated=['-p:ImportDirectoryBuildProps=false','-p:ImportDirectoryBuildTargets=false'];
  dotnet(['restore','GuardHarness.csproj','--configfile','NuGet.Config','--packages',path.join(project,'packages'),...isolated]);
  dotnet(['build','GuardHarness.csproj','-c','Release','--no-restore','--nologo',...isolated]);
  const result=JSON.parse(dotnet([path.join(project,'bin/Release/net10.0/GuardHarness.dll'),root,'inputs/native-context.json',use.path,source.path,hostContract.path]).trim());
  check(result.checks===3,'Actual pinned native context rejects each changed host-only policy/source and accepts exact restoration on the same object');
  nativeEvidence={...result,sourceRevision:receipt.sourceRevision,assemblySha256:runtime.hash(assembly),networkPackageSources:[],modelExecution:false};
}
const result={assertions:observations.length,observations,root,nativeEvidence,limits:['Owned synthetic metadata and nonexecutable tool bytes only','No recording/private media/model/generation/rights or human acceptance','Direct native freshness plus existing queued CPU fixture are composed evidence; this harness does not execute a queued GPU policy mutation']};
fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({assertions:observations.length,native:Boolean(nativeEvidence),evidence:path.join(root,'results.json'),limits:result.limits}));
