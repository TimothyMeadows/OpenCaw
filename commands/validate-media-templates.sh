#!/usr/bin/env bash
set -euo pipefail

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate media templates." >&2; exit 1; }

for backend in CLOUD_SESSION COMFYUI_LOCAL; do
  file=".media/$backend.md"
  [[ -f "$file" ]] || { echo "Missing media backend template: $file" >&2; exit 1; }
  grep -Fqx "# $backend.md" "$file" || { echo "Invalid media template heading: $file" >&2; exit 1; }
done

"$node_bin" <<'NODE'
const fs=require('fs');
for(const file of ['.media/toolchain.json','.media/model-packs.json','.media/media-generation-manifest.schema.json']){
  try { JSON.parse(fs.readFileSync(file,'utf8')); } catch(e){ console.error(`Invalid JSON in ${file}: ${e.message}`); process.exit(1); }
}
const t=JSON.parse(fs.readFileSync('.media/toolchain.json','utf8'));
if(t.comfyCli.version!=='1.12.0'||t.comfyUI.version!=='0.28.0') throw new Error('Local media toolchain versions are not pinned.');
if(!/^\d+\.\d+\.\d+$/.test(t.comfyCli.version)||!/^\d+\.\d+\.\d+$/.test(t.comfyUI.version)) throw new Error('Toolchain versions must be exact semantic versions.');
const packs=JSON.parse(fs.readFileSync('.media/model-packs.json','utf8')).packs;
for(const [name,p] of Object.entries(packs)){
  if(!p.licenses.length||!p.files.length||!p.workflow) throw new Error(`${name} is incomplete`);
  if(!Number.isInteger(p.minimumVramBytes)||p.minimumVramBytes<=0) throw new Error(`${name} has no VRAM viability floor`);
  const destinations=new Set();
  for(const x of [...p.files,p.workflow]){
    if(!/^[a-f0-9]{64}$/.test(x.sha256)||!Number.isInteger(x.sizeBytes)||x.sizeBytes<=0||!x.revision) throw new Error(`${name} has unpinned content`);
    if(!/^[a-f0-9]{40}$/.test(x.revision)||!x.source.includes(x.revision)) throw new Error(`${name} source is not revision-pinned`);
    if(!/^https:\/\/(huggingface\.co|raw\.githubusercontent\.com)\//.test(x.source)) throw new Error(`${name} uses an unreviewed source host`);
    if(pathIsUnsafe(x.destination)||destinations.has(x.destination)) throw new Error(`${name} has an unsafe or duplicate destination`);
    destinations.add(x.destination);
  }
  if(p.workflow.coreNodesOnly!==true) throw new Error(`${name} workflow is not marked core-only`);
}
function pathIsUnsafe(value){ return typeof value!=='string'||value.startsWith('/')||value.startsWith('\\')||value.split(/[\\/]/).includes('..'); }
const schema=JSON.parse(fs.readFileSync('.media/media-generation-manifest.schema.json','utf8'));
for(const field of ['backend','modality','model','workflow','generation','inputs','outputs','runtime','review']) if(!schema.required.includes(field)) throw new Error(`Manifest schema omits ${field}`);
NODE

echo "Media templates validation passed."
