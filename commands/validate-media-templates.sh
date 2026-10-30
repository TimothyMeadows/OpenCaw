#!/usr/bin/env bash
set -euo pipefail

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate media templates." >&2; exit 1; }
[[ ! -e ".media" ]] || { echo "Legacy .media directory must not exist." >&2; exit 1; }
[[ ! -e ".styles/.gpu" ]] || { echo "Legacy .styles/.gpu directory must not exist." >&2; exit 1; }

for asset in cloud/PIPELINE.md local/PIPELINE.md _shared/media-generation-manifest.schema.json; do
  [[ -f ".styles/.pipelines/$asset" ]] || { echo "Missing generated-media pipeline asset: .styles/.pipelines/$asset" >&2; exit 1; }
done

"$node_bin" <<'NODE'
const fs=require('fs');
for(const file of ['commands/bubo-media.sh','commands/install-bubo-media.sh','commands/inspect-local-media-host.sh','commands/lib/bubo-media-adapter.cjs','commands/lib/bubo-media-host.cjs','skills/use-bubo-local-generation/SKILL.md'])
  if(!fs.statSync(file).isFile()) throw new Error(`Missing Bubo LOCAL host entrypoint: ${file}`);
for(const file of ['commands/install-comfyui-local.sh','commands/install-comfyui-models.sh','commands/run-comfyui-workflow.sh','.styles/.pipelines/local/toolchain.json','.styles/.pipelines/local/model-packs.json','skills/use-comfyui-local-generation/SKILL.md'])
  if(fs.existsSync(file)) throw new Error(`Retired active integration remains: ${file}`);
const lock=JSON.parse(fs.readFileSync('runtime/bubo.lock.json','utf8'));
if(lock.schemaVersion!==1||lock.path!=='runtime/bubo'||lock.apiVersion!==1||!/^[a-f0-9]{40}$/.test(lock.revision)||!/^[a-f0-9]{64}$/.test(lock.resourceCatalogSha256)) throw new Error('Invalid pinned Bubo media execution boundary.');
// Policy validation remains usable before dependency initialization. Native
// production separately verifies the exact source/build/catalog on every call.
const policy=fs.readFileSync('.styles/.pipelines/local/PIPELINE.md','utf8');
if(!/Bubo/.test(policy)) throw new Error('LOCAL policy does not identify the pinned runtime.');
const schema=JSON.parse(fs.readFileSync('.styles/.pipelines/_shared/media-generation-manifest.schema.json','utf8'));
for(const field of ['backend','modality','model','workflow','generation','inputs','outputs','runtime','review']) if(!schema.required.includes(field)) throw new Error(`Manifest schema omits ${field}`);
NODE

echo "Media templates validation passed."
