#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-media-generation-manifest.sh MANIFEST

Validates a version-1 generated-media manifest, staged hashes, rights/consent,
runtime budgets, rejection metadata, and human-reviewed promotion state.
EOF
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
[[ $# -eq 1 ]] || { usage >&2; exit 1; }
[[ -f "$1" ]] || { echo "Manifest not found: $1" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate media manifests." >&2; exit 1; }
manifest_for_node="$(realpath "$1")"
schema_for_node="$opencaw_root/.styles/.pipelines/_shared/media-generation-manifest.schema.json"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  manifest_for_node="$(wslpath -w "$manifest_for_node")"
  schema_for_node="$(wslpath -w "$schema_for_node")"
fi

"$node_bin" - "$manifest_for_node" "$schema_for_node" <<'NODE'
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const manifestPath=path.resolve(process.argv[2]);
let d; try { d=JSON.parse(fs.readFileSync(manifestPath,'utf8')); } catch(e) { console.error(`Invalid manifest JSON: ${e.message}`); process.exit(1); }
let schema; try { schema=JSON.parse(fs.readFileSync(process.argv[3],'utf8')); } catch(e) { console.error(`Invalid bundled manifest schema: ${e.message}`); process.exit(1); }
if(!d||typeof d!=='object'||Array.isArray(d)){ console.error('Manifest must be a JSON object.'); process.exit(1); }
const errors=[];
const required=(obj,fields,where)=>{ if(!obj || typeof obj!=='object' || Array.isArray(obj)){errors.push(`${where} must be an object`);return;} for(const f of fields) if(!(f in obj)) errors.push(`${where}.${f} is required`); };
const only=(obj,fields,where)=>{ if(obj&&typeof obj==='object'&&!Array.isArray(obj)) for(const f of Object.keys(obj)) if(!fields.includes(f)) errors.push(`${where}.${f} is not allowed`); };
const unavailable=v=>v && typeof v==='object' && v.unavailable===true && typeof v.reason==='string' && v.reason.trim();
const value=v=>typeof v==='string'&&v.trim() || unavailable(v);
const topLevel=['schemaVersion','runId','createdAt','backend','modality','model','workflow','generation','inputs','outputs','runtime','review'];
required(d,topLevel,'manifest'); only(d,topLevel,'manifest');
if(d.schemaVersion!==schema.properties.schemaVersion.const) errors.push(`schemaVersion must be ${schema.properties.schemaVersion.const}`);
for(const f of ['runId','createdAt']) if(typeof d[f]!=='string'||!d[f].trim()) errors.push(`${f} is required`);
if(typeof d.createdAt==='string'&&Number.isNaN(Date.parse(d.createdAt))) errors.push('createdAt must be an ISO date-time');
required(d.backend,['kind','provider','capability','toolVersion'],'backend');
only(d.backend,['kind','provider','capability','toolVersion'],'backend');
if(d.backend && !['cloud-session','local'].includes(d.backend.kind)) errors.push('backend.kind must be cloud-session or local');
for(const f of ['provider','capability']) if(d.backend&&(typeof d.backend[f]!=='string'||!d.backend[f].trim())) errors.push(`backend.${f} is required`);
if(d.backend && !value(d.backend.toolVersion)) errors.push('backend.toolVersion requires a value or unavailable marker');
if(!['image','music','sfx','voice'].includes(d.modality)) errors.push('modality must be image, music, sfx, or voice');
required(d.model,['name','revision','digest','license'],'model');
only(d.model,['name','revision','digest','license'],'model');
for(const f of ['name','revision','digest','license']) if(d.model && !value(d.model[f])) errors.push(`model.${f} requires a value or unavailable marker`);
required(d.workflow,['name','revision','digest'],'workflow');
only(d.workflow,['name','revision','digest'],'workflow');
for(const f of ['name','revision','digest']) if(d.workflow && !value(d.workflow[f])) errors.push(`workflow.${f} requires a value or unavailable marker`);
required(d.generation,['prompt','negativePrompt','parameters','seed'],'generation');
only(d.generation,['prompt','negativePrompt','parameters','seed'],'generation');
if(d.generation && (typeof d.generation.prompt!=='string'||!d.generation.prompt.trim())) errors.push('generation.prompt is required');
if(d.generation && !value(d.generation.negativePrompt)) errors.push('generation.negativePrompt requires a value or unavailable marker');
if(d.generation && !(Number.isInteger(d.generation.seed)||unavailable(d.generation.seed))) errors.push('generation.seed requires an integer or unavailable marker');
if(d.generation && !(d.generation.parameters && typeof d.generation.parameters==='object' && !Array.isArray(d.generation.parameters))) errors.push('generation.parameters requires an object or unavailable marker');
if(!Array.isArray(d.inputs)||!d.inputs.length) errors.push('inputs must contain at least one record');
else d.inputs.forEach((x,i)=>{required(x,['description','source','rights','consent'],`inputs[${i}]`); only(x,['description','source','rights','consent'],`inputs[${i}]`); for(const f of ['description','source','rights']) if(typeof x[f]!=='string'||!x[f].trim()) errors.push(`inputs[${i}].${f} is required`); if(x.consent==='not-confirmed') errors.push(`inputs[${i}].consent is not confirmed`); if(!['not-applicable','confirmed','not-confirmed'].includes(x.consent)) errors.push(`inputs[${i}].consent is invalid`);});
if(!Array.isArray(d.outputs)||!d.outputs.length) errors.push('outputs must contain at least one staged file');
else d.outputs.forEach((x,i)=>{
  required(x,['stagedPath','sha256','status','runtimeTarget'],`outputs[${i}]`);
  only(x,['stagedPath','sha256','status','runtimeTarget','rejectionReason'],`outputs[${i}]`);
  if(typeof x.stagedPath!=='string'||!x.stagedPath.trim()) errors.push(`outputs[${i}].stagedPath is required`);
  if(!value(x.runtimeTarget)) errors.push(`outputs[${i}].runtimeTarget requires a value or unavailable marker`);
  if(!/^[a-f0-9]{64}$/.test(x.sha256||'')) errors.push(`outputs[${i}].sha256 is invalid`);
  if(!['staged','accepted','rejected','promoted'].includes(x.status)) errors.push(`outputs[${i}].status is invalid`);
  if(x.status==='rejected' && !(typeof x.rejectionReason==='string'&&x.rejectionReason.trim())) errors.push(`outputs[${i}] rejected output needs rejectionReason`);
  const file=path.resolve(path.dirname(manifestPath),x.stagedPath||'');
  const base=fs.realpathSync.native ? fs.realpathSync.native(path.dirname(manifestPath)) : fs.realpathSync(path.dirname(manifestPath));
  if(file!==base && !file.startsWith(base+path.sep)) errors.push(`outputs[${i}].stagedPath escapes the manifest directory`);
  else if(!fs.existsSync(file)||!fs.statSync(file).isFile()) errors.push(`outputs[${i}] staged file is missing`);
  else if(fs.lstatSync(file).isSymbolicLink()) errors.push(`outputs[${i}] staged file must not be a symbolic link`);
  else { const real=fs.realpathSync(file); if(real!==base&&!real.startsWith(base+path.sep)) errors.push(`outputs[${i}] staged file resolves outside the manifest directory`); const hash=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); if(hash!==x.sha256) errors.push(`outputs[${i}] hash mismatch`); }
});
required(d.runtime,['destination','budgets'],'runtime');
only(d.runtime,['destination','budgets'],'runtime');
if(d.runtime && !value(d.runtime.destination)) errors.push('runtime.destination requires a value or unavailable marker');
if(d.runtime && (!d.runtime.budgets||typeof d.runtime.budgets!=='object'||Array.isArray(d.runtime.budgets)||!Object.keys(d.runtime.budgets).length)) errors.push('runtime.budgets must not be empty');
required(d.review,['status','reviewer','reviewedAt','notes'],'review');
only(d.review,['status','reviewer','reviewedAt','notes'],'review');
if(d.review && !['pending','accepted','rejected'].includes(d.review.status)) errors.push('review.status is invalid');
if(d.review && (!value(d.review.reviewer)||!value(d.review.reviewedAt))) errors.push('review requires reviewer and reviewedAt values or explicit unavailable markers');
if(d.review && typeof d.review.notes!=='string') errors.push('review.notes must be a string');
if(d.review && d.review.status!=='pending' && (unavailable(d.review.reviewer)||unavailable(d.review.reviewedAt))) errors.push('completed review requires available reviewer and reviewedAt values');
if(Array.isArray(d.outputs)&&d.outputs.some(x=>x.status==='promoted') && (!d.review||d.review.status!=='accepted')) errors.push('promoted outputs require accepted human review');
const serialized=JSON.stringify(d);
if(/(api[_-]?key|access[_-]?token|hf[_-]?token)"?\s*:\s*"[^"{]{8,}/i.test(serialized)) errors.push('manifest appears to contain a persisted credential');
if(errors.length){ errors.sort().forEach(x=>console.error(x)); process.exit(1); }
console.log(`Media generation manifest validation passed (${d.modality}, ${d.outputs.length} output(s)).`);
NODE
