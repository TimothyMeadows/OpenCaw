#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/inspect-local-media-host.sh [--workspace PATH] [--json]

Inspects local image/audio generation readiness without changing the host.
EOF
}

workspace=""
json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) [[ $# -ge 2 ]] || { echo "--workspace requires a path" >&2; exit 1; }; workspace="$2"; shift 2 ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

platform="${OPENCAW_PLATFORM_OVERRIDE:-}"
if [[ -z "$platform" ]]; then
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    mingw*|msys*|cygwin*) platform="windows" ;;
    darwin*) platform="macos" ;;
    linux*) if grep -Eqi '(microsoft|wsl)' /proc/version 2>/dev/null; then platform="windows"; else platform="linux"; fi ;;
    *) platform="unsupported" ;;
  esac
fi

if [[ -z "$workspace" ]]; then
  case "$platform" in
    windows) workspace="${LOCALAPPDATA:-${USERPROFILE:-.}/AppData/Local}/OpenCaw/ComfyUI" ;;
    macos) workspace="${HOME:?HOME is required}/Library/Application Support/OpenCaw/ComfyUI" ;;
    linux) workspace="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}/opencaw/comfyui" ;;
    *) workspace="" ;;
  esac
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for structured host inspection." >&2; exit 1; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
packs_manifest="$opencaw_root/.styles/.gpu/model-packs.json"

workspace_for_node="$workspace"
packs_manifest_for_node="$packs_manifest"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  workspace_for_node="$(wslpath -w "$(realpath -m "$workspace")")"
  packs_manifest_for_node="$(wslpath -w "$packs_manifest")"
fi
"$node_bin" - "$platform" "$workspace_for_node" "$json" "$packs_manifest_for_node" <<'NODE'
const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');
const platform = process.argv[2];
const workspace = path.resolve(process.argv[3] || '.');
const packDefinitions = JSON.parse(fs.readFileSync(process.argv[5], 'utf8')).packs;
function which(names) {
  const probe = platform === 'windows' ? 'where.exe' : 'which';
  for (const name of names) {
    const r = cp.spawnSync(probe, [name], {encoding:'utf8', windowsHide:true});
    if (r.status === 0 && r.stdout.trim()) return r.stdout.trim().split(/\r?\n/)[0];
  }
  return null;
}
function version(bin, args=['--version']) {
  if (!bin) return null;
  const r = cp.spawnSync(bin, args, {encoding:'utf8', windowsHide:true, timeout:5000});
  return r.status === 0 ? (r.stdout || r.stderr).trim().split(/\r?\n/)[0] : null;
}
function exists(rel) { return fs.existsSync(path.join(workspace, ...rel.split('/'))); }
function packReady(name) { return packDefinitions[name].files.every(file => exists(file.destination)); }
function modalityReady(name, gpu, comfy) {
  const pack = packDefinitions[name];
  return packReady(name) && !!comfy && ['nvidia','amd-rocm','apple-unified'].includes(gpu.kind) &&
    (!gpu.vramBytes || gpu.vramBytes >= pack.minimumVramBytes);
}
const comfyCandidates = [
  path.join(workspace, '.opencaw', platform === 'windows' ? 'Scripts/comfy.exe' : 'bin/comfy'),
  which(platform === 'windows' ? ['comfy.exe','comfy'] : ['comfy'])
].filter(Boolean);
const comfy = comfyCandidates.find(p => fs.existsSync(p)) || null;
let gpu = {kind:'none', name:null, vramBytes:null};
const nvidia = which(platform === 'windows' ? ['nvidia-smi.exe','nvidia-smi'] : ['nvidia-smi']);
if (nvidia) {
  const r = cp.spawnSync(nvidia, ['--query-gpu=name,memory.total','--format=csv,noheader,nounits'], {encoding:'utf8', windowsHide:true, timeout:5000});
  if (r.status === 0 && r.stdout.trim()) {
    const [name, mib] = r.stdout.trim().split(/\r?\n/)[0].split(',').map(x => x.trim());
    gpu = {kind:'nvidia', name, vramBytes:Number(mib) * 1024 * 1024};
  }
} else if (platform === 'macos') {
  gpu = {kind:'apple-unified', name:'Apple unified memory', vramBytes:null};
} else if (which(['rocminfo'])) {
  gpu = {kind:'amd-rocm', name:'AMD ROCm device', vramBytes:null};
}
let diskFreeBytes = null, diskProbe = workspace;
while (!fs.existsSync(diskProbe) && path.dirname(diskProbe) !== diskProbe) diskProbe = path.dirname(diskProbe);
try { const stat=fs.statfsSync(diskProbe); diskFreeBytes = stat.bavail * stat.bsize; } catch {}
const imagePackReady = packReady('flux-schnell-fp8');
const audioPackReady = packReady('stable-audio-open');
const doc = {
  schemaVersion: 1,
  platform,
  supportedPlatform: ['windows','linux','macos'].includes(platform),
  workspace,
  diskFreeBytes,
  memoryBytes: os.totalmem(),
  gpu,
  tools: {
    python: version(which(platform === 'windows' ? ['python.exe','py.exe','python'] : ['python3','python'])),
    ffmpeg: version(which(platform === 'windows' ? ['ffmpeg.exe','ffmpeg'] : ['ffmpeg']), ['-version']),
    comfyCli: version(comfy),
    comfyCliPath: comfy
  },
  comfyUI: {installed: exists('main.py') || exists('ComfyUI/main.py')},
  packs: {
    'flux-schnell-fp8': {ready: imagePackReady},
    'stable-audio-open': {ready: audioPackReady}
  },
  modalities: {
    image: modalityReady('flux-schnell-fp8', gpu, comfy),
    audio: modalityReady('stable-audio-open', gpu, comfy)
  }
};
if (process.argv[4] === '1') console.log(JSON.stringify(doc, null, 2));
else {
  console.log(`Platform: ${doc.platform}${doc.supportedPlatform ? '' : ' (unsupported)'}`);
  console.log(`Workspace: ${doc.workspace}`);
  console.log(`GPU: ${gpu.kind}${gpu.name ? ` - ${gpu.name}` : ''}${gpu.vramBytes ? ` (${Math.round(gpu.vramBytes/1048576)} MiB)` : ''}`);
  console.log(`Python: ${doc.tools.python || 'missing'}`);
  console.log(`FFmpeg: ${doc.tools.ffmpeg || 'missing'}`);
  console.log(`comfy-cli: ${doc.tools.comfyCli || 'missing'}`);
  console.log(`ComfyUI: ${doc.comfyUI.installed ? 'installed' : 'missing'}`);
  console.log(`Image pack: ${doc.packs['flux-schnell-fp8'].ready ? 'ready' : 'not ready'}`);
  console.log(`Audio pack: ${doc.packs['stable-audio-open'].ready ? 'ready' : 'not ready'}`);
}
NODE
