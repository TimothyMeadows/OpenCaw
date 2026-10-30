'use strict';

// Owned configuration/metadata fixtures only: no runtime/model/audio access.
const assert = require('assert/strict'), fs = require('fs'), path = require('path'), cp = require('child_process');
const contracts = require('../commands/lib/media-pipeline-contract.cjs');
const runtime = require('../commands/lib/bubo-runtime.cjs');
const cache = path.basename(contracts.BASE) === '.opencaw' ? path.join(contracts.BASE, '.cache') : path.join(contracts.BASE, '.opencaw/.cache');
const evidence = path.join(cache, 'tasks/opencaw-media-pipeline-domains/evidence/contract-tests');
fs.mkdirSync(evidence, { recursive: true });
const root = fs.mkdtempSync(path.join(evidence, 'owned-'));
let assertions = 0; const skips = [];
function check(value, message) { assert(value, message); assertions++; }
function rejects(action, pattern, message) { assert.throws(action, pattern, message); assertions++; }
function write(relative, value) {
  const full = path.join(root, relative); fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n'); return full;
}
function snapshot() {
  const entries = [];
  function visit(folder) {
    for (const name of fs.readdirSync(folder).sort()) {
      const full = path.join(folder, name), stat = fs.lstatSync(full), rel = path.relative(root, full);
      entries.push([rel, stat.isSymbolicLink() ? 'link' : stat.isDirectory() ? 'directory' : runtime.hash(full)]);
      if (stat.isDirectory() && !stat.isSymbolicLink()) visit(full);
    }
  }
  visit(root); return JSON.stringify(entries);
}
function cli(operation, args = [], expected = 0, script = path.join(contracts.BASE, 'commands/lib/media-pipeline-contract.cjs')) {
  const result = cp.spawnSync(process.execPath, [script, operation, '--root', root, ...args], { encoding: 'utf8' });
  check(result.status === expected, 'CLI status: ' + JSON.stringify({args, ...result}));
  return expected === 0 ? JSON.parse(result.stdout) : result.stderr;
}
function copy(relative, destination = relative) {
  const target = path.join(root, destination); fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(path.join(contracts.BASE, relative), target);
}
try {
  const before = snapshot(), absent = contracts.resolveAll({ root, visual: true });
  check(snapshot() === before, 'aggregate discovery creates no files');
  check(!absent.contexts.visual.configured && absent.contexts.visual.pipeline === null, 'absent visual contract is not selected');
  for (const domain of contracts.DOMAINS) {
    const context = absent.contexts[domain.toLowerCase()];
    check(context.domain === domain && !context.configured && !context.executionAvailable && context.media === null, 'independent absent ' + domain);
    check(context.nativeReadiness === 'unverified', 'native readiness never inferred');
  }
  for (const [modality, domain, canonical] of [
    ['sfx','AUDIO','sfx'], ['sound-effect','AUDIO','sfx'], ['ambience','AUDIO','ambience'], ['ambiance','AUDIO','ambience'],
    ['instrumental','MUSIC','instrumental'], ['song','MUSIC','supplied-lyrics'], ['supplied-lyrics','MUSIC','supplied-lyrics'],
    ['preset-speech','VOICE','preset-speech'], ['tts','VOICE','preset-speech'], ['voice-clone','VOICE','consented-cloning'], ['consented-cloning','VOICE','consented-cloning']
  ]) {
    const result = contracts.resolve({root, modality});
    check(result.domain === domain && result.modality === canonical, 'explicit modality route ' + modality);
  }
  for (const domain of contracts.DOMAINS) check(contracts.resolve({root,domain:domain.toLowerCase()+'_pipeline'}).domain === domain, 'domain alias ' + domain);
  rejects(() => contracts.resolve({root,domain:'AUDIO',modality:'song'}), /conflict/, 'contradictory mode fails');
  rejects(() => contracts.resolve({root,modality:'image'}), /modality/, 'visual is not a nonvisual modality');
  rejects(() => contracts.resolve({root,domain:'CLOUD'}), /domain/, 'provider is not a domain');
  rejects(() => contracts.resolve({root}), /Select/, 'missing single selection is explicit');
  rejects(() => contracts.resolve({root,domain:'AUDIO',contract:'missing.md'}), /missing/, 'explicit missing contract fails');
  rejects(() => contracts.resolve({root,domain:'AUDIO',media:'missing.md'}), /missing/, 'explicit missing MEDIA fails');
  rejects(() => contracts.resolveAll({root,domain:'AUDIO'}), /Aggregate/, 'aggregate/single conflict');
  rejects(() => contracts.resolveAll({root,style:'STYLE.md'}), /visual/, 'unrequested visual override rejected');

  for (const domain of contracts.DOMAINS) {
    const generated = cli('generate', [domain, '--inline']);
    check(generated.created && generated.mode === 'inline' && generated.domain === domain, 'actual generated domain ' + domain);
    const initialHash = runtime.hash(path.join(root, domain + '.md')), repeated = contracts.generate({root,domain,inline:true});
    check(!repeated.created && runtime.hash(path.join(root, domain + '.md')) === initialHash, 'idempotent contract ' + domain);
    check(cli('validate',[domain]).domain === domain, 'actual validation ' + domain);
    check(contracts.resolve({root,domain}).configured && !contracts.resolve({root,domain}).executionAvailable, 'configured declaration has no executable workflow ' + domain);
  }
  check(!fs.existsSync(path.join(root,'MEDIA.md')) && !fs.existsSync(path.join(root,'ENGINE.md')) && !fs.existsSync(path.join(root,'STYLE.md')), 'configuration invents no shared provider/engine/style contract');
  const initial = contracts.resolveAll({root});
  fs.appendFileSync(path.join(root,'VOICE.md'),'\n## Private Project Policy\n\nReferences remain private.\n');
  const voiceChanged = contracts.resolveAll({root});
  check(initial.contexts.audio.policySha256 === voiceChanged.contexts.audio.policySha256, 'VOICE contract change preserves AUDIO fingerprint');
  check(initial.contexts.music.policySha256 === voiceChanged.contexts.music.policySha256, 'VOICE contract change preserves MUSIC fingerprint');
  check(initial.contexts.voice.policySha256 !== voiceChanged.contexts.voice.policySha256, 'VOICE contract change invalidates VOICE');
  const preserved = fs.readFileSync(path.join(root,'VOICE.md'),'utf8');
  rejects(() => contracts.generate({root,domain:'VOICE',inline:true}), /differs/, 'generator preserves customized contract');
  check(fs.readFileSync(path.join(root,'VOICE.md'),'utf8') === preserved, 'customized contract unchanged');
  write('MEDIA.md', '# MEDIA.md\nOwned fixture policy, not generation authorization.\n');
  const mediaAdded = contracts.resolveAll({root});
  for (const domain of contracts.DOMAINS) check(mediaAdded.contexts[domain.toLowerCase()].policySha256 !== voiceChanged.contexts[domain.toLowerCase()].policySha256, 'shared MEDIA affects ' + domain);
  fs.appendFileSync(path.join(root,'MEDIA.md'), '\nShared policy changed.\n');
  const mediaChanged = contracts.resolveAll({root});
  for (const domain of contracts.DOMAINS) check(mediaAdded.contexts[domain.toLowerCase()].policySha256 !== mediaChanged.contexts[domain.toLowerCase()].policySha256, 'shared MEDIA mutation invalidates ' + domain);
  check(contracts.resolve({root,domain:'AUDIO',contract:path.join(root,'AUDIO.md'),media:path.join(root,'MEDIA.md')}).policySha256 === contracts.resolve({root,domain:'AUDIO'}).policySha256, 'canonical relative/absolute reference identity');
  const stable = snapshot(); cli('resolve',['--all']); check(snapshot() === stable, 'configured discovery writes nothing');
  cli('resolve',['--domain','AUDIO','--modality','instrumental'],1);
  cli('resolve',['AUDIO','--domain','VOICE'],1);
  cli('resolve',['--all','--contract','AUDIO.md'],1);
  cli('resolve',['--root',root],1);
  cli('resolve',['--execute'],1);
  cli('generate',['AUDIO','--output','different.md','--all'],1);
  const audio = fs.readFileSync(path.join(root,'AUDIO.md'),'utf8');
  write('stale.md', audio.replace('AUDIO owns game/effect sounds','AUDIO owns changed fixture sounds'));
  rejects(() => contracts.validate({root,domain:'AUDIO',contract:'stale.md'}), /stale/, 'stale inline definition rejected');
  write('mixed.md',audio.replace('- AUDIO','- AUDIO\n- MUSIC'));
  rejects(() => contracts.validate({root,domain:'AUDIO',contract:'mixed.md'}), /only its own/, 'multiple domains cannot occupy one contract');
  write('wrong.md',audio.replace('domain=AUDIO','domain=VOICE'));
  rejects(() => contracts.validate({root,domain:'AUDIO',contract:'wrong.md'}), /identity/, 'wrong-domain marker rejected');
  write('unsafe-policy.md',audio.replace('explicit promotion authorization','automatic promotion'));
  rejects(() => contracts.validate({root,domain:'AUDIO',contract:'unsafe-policy.md'}), /boundaries/, 'promotion boundary mandatory');
  for (const argument of ['../outside.md','.git/config','inputs/../AUDIO.md']) rejects(() => contracts.resolve({root,domain:'AUDIO',contract:argument}), /Traversal|escapes|reserved/, 'path guard ' + argument);
  if (process.platform === 'win32') for (const argument of ['AUDIO.md.','CON.md','AUDIO.md:stream']) rejects(() => contracts.resolve({root,domain:'AUDIO',contract:argument}), /alias|Colon/, 'Windows alias ' + argument);
  fs.mkdirSync(path.join(root,'real-policy'));
  try {
    fs.symlinkSync(path.join(root,'real-policy'),path.join(root,'linked-policy'),process.platform === 'win32' ? 'junction' : 'dir');
    rejects(() => contracts.generate({root,domain:'AUDIO',inline:true,output:'linked-policy/AUDIO.md'}), /symbolic links|junctions/, 'linked destination rejected');
    rejects(() => contracts.resolve({root,domain:'AUDIO',media:'linked-policy/MEDIA.md'}), /symbolic links|junctions/, 'linked missing policy rejected');
  } catch (error) { if (!['EPERM','EACCES','ENOTSUP'].includes(error.code)) throw error; skips.push('Directory-link fixture unavailable: '+error.code); }

  // Real cloned-baseline module placement, no native dependency needed.
  for (const file of ['media-pipeline-contract.cjs','bubo-runtime.cjs','style-contract.cjs','engine-contract.cjs']) copy('commands/lib/'+file,'.opencaw/commands/lib/'+file);
  copy('.media/pipelines/registry.json','.opencaw/.media/pipelines/registry.json');
  for (const domain of contracts.DOMAINS) for (const file of ['PIPELINE.md','CONTRACT.md']) copy('.media/pipelines/'+domain.toLowerCase()+'/'+file,'.opencaw/.media/pipelines/'+domain.toLowerCase()+'/'+file);
  const host = require(path.join(root,'.opencaw/commands/lib/media-pipeline-contract.cjs'));
  const hostAudio = host.resolve({root,domain:'AUDIO'}), hostMusic = host.resolve({root,domain:'MUSIC'});
  const registryPath=path.join(root,'.opencaw/.media/pipelines/registry.json');
  const data=JSON.parse(fs.readFileSync(registryPath,'utf8'));data.domains.MUSIC.aliases.push('music-score');fs.writeFileSync(registryPath,JSON.stringify(data));
  check(host.resolve({root,domain:'AUDIO'}).policySha256===hostAudio.policySha256,'unrelated registry entry does not invalidate AUDIO');
  check(host.resolve({root,domain:'MUSIC'}).policySha256!==hostMusic.policySha256,'selected registry entry invalidates MUSIC');
  check(host.generate({root,domain:'AUDIO',output:'linked-audio.md'}).mode==='link','host link-mode generation references installed declaration');
  check(host.validate({root,domain:'AUDIO',contract:'linked-audio.md'}).mode==='link','host link-mode validation');
  const linkText=fs.readFileSync(path.join(root,'linked-audio.md'),'utf8');
  write('wrong-link.md',linkText.replace('audio/PIPELINE.md','music/PIPELINE.md'));
  rejects(()=>host.validate({root,domain:'AUDIO',contract:'wrong-link.md'}),/selected shared declaration/,'cross-domain directive rejected');
  write('escape-link.md',linkText.replace('./.opencaw/.media/pipelines/audio/PIPELINE.md','../outside/PIPELINE.md'));
  rejects(()=>host.validate({root,domain:'AUDIO',contract:'escape-link.md'}),/Traversal|escapes|reserved/,'read-directive traversal rejected');
  fs.appendFileSync(path.join(root,'.opencaw/.media/pipelines/voice/PIPELINE.md'),'\nChanged declaration fixture.\n');
  check(host.resolve({root,domain:'AUDIO'}).policySha256===hostAudio.policySha256,'unrelated declaration change does not invalidate AUDIO');
  rejects(()=>host.resolve({root,domain:'VOICE'}),/stale/,'selected declaration change invalidates inline host definition');

  // Existing visual resolver remains the visual owner for every primary.
  copy('.media/pipelines/voice/PIPELINE.md','.opencaw/.media/pipelines/voice/PIPELINE.md');
  for (const file of ['.styles/INDEX.md','.styles/CEL_SHADED_COMIC.md','.styles/.pipelines/INDEX.md']) copy(file,'.opencaw/'+file);
  for (const directory of ['cloud','local','proof-to-model','code','blender']) copy('.styles/.pipelines/'+directory+'/PIPELINE.md','.opencaw/.styles/.pipelines/'+directory+'/PIPELINE.md');
  const sourceStyle=fs.readFileSync(path.join(contracts.BASE,'STYLE.md'),'utf8');
  write('STYLE.md',sourceStyle);
  copy('.engine/registry.json','.opencaw/.engine/registry.json');copy('.engine/THREEJS.md','.opencaw/.engine/THREEJS.md');
  write('ENGINE.md',fs.readFileSync(path.join(contracts.BASE,'ENGINE.md'),'utf8').replaceAll('./.engine/','./.opencaw/.engine/'));
  for (const primary of ['CLOUD','LOCAL','PROOF_TO_MODEL','CODE','BLENDER']) {
    write('STYLE.md',sourceStyle.replace('Primary OpenCaw art pipeline:\r\n- PROOF_TO_MODEL','Primary OpenCaw art pipeline:\r\n- '+primary).replace('Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL','Primary OpenCaw art pipeline:\n- '+primary));
    const aggregate=host.resolveAll({root,visual:true});
    check(aggregate.contexts.visual.pipeline===primary,'visual primary remains owned by existing resolver: '+primary);
    check(aggregate.contexts.audio.domain==='AUDIO' && aggregate.contexts.music.domain==='MUSIC' && aggregate.contexts.voice.domain==='VOICE','four contexts coexist under '+primary);
  }
  const bash=process.env.OPENCAW_BASH || (process.platform==='win32' ? path.join(process.env.ProgramFiles || 'C:/Program Files','Git/bin/bash.exe') : 'bash');
  for (const command of ['generate-media-pipeline-contract','validate-media-pipeline-contract','resolve-media-pipeline']) {
    const script=path.join(contracts.BASE,'commands',command+'.sh').replace(/\\/g,'/');
    const help=cp.spawnSync(bash,[script,'--help'],{cwd:root,encoding:'utf8'});
    check(help.status===0 && /Independent media contracts/.test(help.stdout),'real Bash wrapper help outside initialized host: '+command);
  }
  for (const [command,args,expectedDomain] of [
    ['generate-media-pipeline-contract',['MUSIC','--inline','--output','wrapper-music.md'],'MUSIC'],
    ['validate-media-pipeline-contract',['MUSIC','--contract','wrapper-music.md'],'MUSIC'],
    ['resolve-media-pipeline',['--modality','ambience'],'AUDIO']
  ]) {
    const result=cp.spawnSync(bash,[path.join(contracts.BASE,'commands',command+'.sh').replace(/\\/g,'/'),...args,'--root',root],{cwd:root,encoding:'utf8'});
    check(result.status===0 && JSON.parse(result.stdout).domain===expectedDomain,'real Bash wrapper operation: '+command+' '+result.stderr);
  }
  const report={schemaVersion:1,assertions,skips,scope:'model-free owned contract/CLI/path/identity fixtures; no inference or acoustic/native readiness claim'};
  fs.writeFileSync(path.join(evidence,'latest.json'),JSON.stringify(report,null,2)+'\n');
  console.log('Media pipeline contract checks passed: '+assertions+' assertions; '+skips.length+' explicit skips.');
} finally {
  if (!runtime.within(evidence,root) || path.dirname(root)!==evidence || !path.basename(root).startsWith('owned-')) throw new Error('Refusing unsafe fixture cleanup.');
  fs.rmSync(root,{recursive:true,force:true});
}
