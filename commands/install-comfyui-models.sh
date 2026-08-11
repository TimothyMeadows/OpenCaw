#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/install-comfyui-models.sh --pack <name|all> [--workspace PATH]
       [--accept-license ID]... [--execute]

Reviewed packs: flux-schnell-fp8, stable-audio-open, all.
Dry-run prints source, revision, size, checksum, destination, and license.
Downloads require every matching --accept-license value. Gated downloads use
HF_API_TOKEN from the environment and never persist it.
EOF
}

pack=""
workspace=""
execute=0
accepted=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pack) [[ $# -ge 2 ]] || { echo "--pack requires a value" >&2; exit 1; }; pack="$2"; shift 2 ;;
    --workspace) [[ $# -ge 2 ]] || { echo "--workspace requires a path" >&2; exit 1; }; workspace="$2"; shift 2 ;;
    --accept-license) [[ $# -ge 2 ]] || { echo "--accept-license requires an ID" >&2; exit 1; }; accepted+=("$2"); shift 2 ;;
    --execute) execute=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -n "$pack" ]] || { usage >&2; exit 1; }

platform="${OPENCAW_PLATFORM_OVERRIDE:-}"
if [[ -z "$platform" ]]; then
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in mingw*|msys*|cygwin*) platform=windows ;; darwin*) platform=macos ;; linux*) if grep -Eqi '(microsoft|wsl)' /proc/version 2>/dev/null; then platform=windows; else platform=linux; fi ;; *) platform=unsupported ;; esac
fi
if [[ -z "$workspace" ]]; then
  case "$platform" in
    windows) workspace="${LOCALAPPDATA:-${USERPROFILE:-.}/AppData/Local}/OpenCaw/ComfyUI" ;;
    macos) workspace="${HOME:?HOME is required}/Library/Application Support/OpenCaw/ComfyUI" ;;
    linux) workspace="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}/opencaw/comfyui" ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
  esac
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
manifest="$opencaw_root/.styles/.pipelines/local/model-packs.json"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to read model packs." >&2; exit 1; }
manifest_for_node="$manifest"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then manifest_for_node="$(wslpath -w "$manifest")"; fi
if [[ -n "${OPENCAW_TEST_DISK_BYTES:-}${OPENCAW_TEST_GPU_KIND:-}${OPENCAW_TEST_VRAM_BYTES:-}" ]]; then
  workspace_real="$(realpath -m "$workspace")"
  case "$workspace_real" in
    "$opencaw_root"/tests/.pipeline-media-runtime-*) [[ "${OPENCAW_TEST_MODE:-0}" == "1" ]] || { echo "Media probe fixtures require OPENCAW_TEST_MODE=1." >&2; exit 1; } ;;
    *) echo "Media probe fixtures are confined to OpenCaw test runtimes." >&2; exit 1 ;;
  esac
fi
workspace_for_node="$(realpath -m "$workspace")"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then workspace_for_node="$(wslpath -w "$workspace_for_node")"; fi

mapfile -t selected < <("$node_bin" - "$manifest_for_node" "$pack" <<'NODE'
const m=require(process.argv[2]); const requested=process.argv[3];
if (requested === 'all') Object.keys(m.packs).sort().forEach(x=>console.log(x));
else if (m.packs[requested]) console.log(requested);
else { console.error(`Unknown model pack: ${requested}`); process.exit(1); }
NODE
)

if [[ $execute -eq 1 ]]; then
  read -r required_bytes minimum_vram < <("$node_bin" - "$manifest_for_node" "${selected[@]}" <<'NODE'
const fs=require('fs'), path=require('path'); const m=require(process.argv[2]);
let bytes=0, vram=0;
for(const name of process.argv.slice(3)){ const p=m.packs[name]; vram=Math.max(vram,p.minimumVramBytes||0); for(const x of [...p.files,p.workflow]) bytes+=x.sizeBytes; }
console.log(`${bytes} ${vram}`);
NODE
  )
  disk_bytes="${OPENCAW_TEST_DISK_BYTES:-$("$node_bin" - "$workspace_for_node" <<'NODE'
const fs=require('fs'),path=require('path'); let p=path.resolve(process.argv[2]);
while(!fs.existsSync(p)&&path.dirname(p)!==p)p=path.dirname(p);
const s=fs.statfsSync(p); console.log(s.bavail*s.bsize);
NODE
  )}"
  [[ "$disk_bytes" =~ ^[0-9]+$ ]] || { echo "Unable to determine available disk space." >&2; exit 1; }
  [[ "$disk_bytes" -ge "$required_bytes" ]] || { echo "Insufficient disk space: need $required_bytes bytes, have $disk_bytes." >&2; exit 1; }

  gpu_kind="${OPENCAW_TEST_GPU_KIND:-}"
  vram_bytes="${OPENCAW_TEST_VRAM_BYTES:-}"
  if [[ -z "$gpu_kind" ]]; then
    nvidia_bin="$(command -v nvidia-smi 2>/dev/null || command -v nvidia-smi.exe 2>/dev/null || true)"
    if [[ -n "$nvidia_bin" ]]; then
      gpu_kind=nvidia
      mib="$($nvidia_bin --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')"
      [[ "$mib" =~ ^[0-9]+$ ]] && vram_bytes=$((mib * 1024 * 1024))
    elif [[ "$platform" == macos ]]; then gpu_kind=apple-unified
    elif command -v rocminfo >/dev/null 2>&1; then gpu_kind=amd-rocm
    else gpu_kind=unsupported
    fi
  fi
  case "$gpu_kind" in nvidia|amd-rocm|apple-unified) ;; *) echo "Unsupported local generation hardware; use the configured cloud/session path." >&2; exit 1 ;; esac
  if [[ -n "$vram_bytes" && "$vram_bytes" =~ ^[0-9]+$ && "$vram_bytes" -lt "$minimum_vram" ]]; then
    echo "Insufficient VRAM: selected pack requires $minimum_vram bytes, detected $vram_bytes." >&2
    exit 1
  fi
fi

has_acceptance() { local wanted="$1" item; for item in "${accepted[@]:-}"; do [[ "$item" == "$wanted" ]] && return 0; done; return 1; }
sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$file" | awk '{print $1}'
  else "$node_bin" -e "const fs=require('fs'),c=require('crypto'); const h=c.createHash('sha256'); h.update(fs.readFileSync(process.argv[1])); console.log(h.digest('hex'))" "$file"
  fi
}

comfy_bin="${OPENCAW_COMFY_BIN:-$workspace/.opencaw/bin/comfy}"
[[ "$platform" == "windows" && -z "${OPENCAW_COMFY_BIN:-}" ]] && comfy_bin="$workspace/.opencaw/Scripts/comfy.exe"
if [[ ! -x "$comfy_bin" ]]; then comfy_bin="$(command -v comfy 2>/dev/null || command -v comfy.exe 2>/dev/null || true)"; fi
workspace_for_comfy="$workspace"
if [[ "$comfy_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then workspace_for_comfy="$(wslpath -w "$(realpath -m "$workspace")")"; fi

for name in "${selected[@]}"; do
  echo "Model pack: $name"
  while IFS=$'\t' read -r id license_name url; do
    echo "- license: $id ($license_name)"
    echo "  $url"
    if [[ $execute -eq 1 ]] && ! has_acceptance "$id"; then
      echo "License acceptance required: --accept-license $id" >&2
      exit 1
    fi
  done < <("$node_bin" - "$manifest_for_node" "$name" <<'NODE'
const p=require(process.argv[2]).packs[process.argv[3]];
for (const x of p.licenses) console.log([x.id,x.name,x.url].join('\t'));
NODE
)

  while IFS=$'\t' read -r kind source revision size digest destination gated; do
    echo "- $kind source: $source"
    echo "  revision: $revision"
    echo "  size: $size bytes"
    echo "  sha256: $digest"
    echo "  destination: $workspace/$destination"
    [[ $execute -eq 1 ]] || continue
    target="$workspace/$destination"
    mkdir -p "$(dirname "$target")"
    if [[ -f "$target" ]]; then
      actual="$(sha256_file "$target")"
      [[ "$actual" == "$digest" ]] && { echo "  already verified"; continue; }
      echo "Checksum mismatch for existing file: $target" >&2
      exit 1
    fi
    [[ -n "$comfy_bin" ]] || { echo "comfy-cli is missing; run install-comfyui-local.sh --execute first." >&2; exit 1; }
    [[ "$gated" != "true" || -n "${HF_API_TOKEN:-}" ]] || { echo "HF_API_TOKEN is required for gated download: $source" >&2; exit 1; }
    if [[ "$kind" == "model" ]]; then
      if [[ "$comfy_bin" == *.exe && -n "${HF_API_TOKEN:-}" && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
        WSLENV="${WSLENV:+$WSLENV:}HF_API_TOKEN" "$comfy_bin" --workspace "$workspace_for_comfy" model download --url "$source" --relative-path "$(dirname "$destination")"
      else
        "$comfy_bin" --workspace "$workspace_for_comfy" model download --url "$source" --relative-path "$(dirname "$destination")"
      fi
    else
      curl_bin="$(command -v curl 2>/dev/null || command -v curl.exe 2>/dev/null || true)"
      [[ -n "$curl_bin" ]] || { echo "curl is required to download pinned workflow templates." >&2; exit 1; }
      "$curl_bin" --fail --location --output "$target.part" "$source"
      mv "$target.part" "$target"
    fi
    [[ -f "$target" ]] || { echo "Download did not create expected file: $target" >&2; exit 1; }
    actual="$(sha256_file "$target")"
    [[ "$actual" == "$digest" ]] || { echo "Checksum mismatch for downloaded file: $target" >&2; exit 1; }
    echo "  verified"
  done < <("$node_bin" - "$manifest_for_node" "$name" <<'NODE'
const p=require(process.argv[2]).packs[process.argv[3]];
for (const x of p.files) console.log(['model',x.source,x.revision,x.sizeBytes,x.sha256,x.destination,String(x.gated)].join('\t'));
const w=p.workflow; console.log(['workflow',w.source,w.revision,w.sizeBytes,w.sha256,w.destination,'false'].join('\t'));
NODE
)
done

if [[ $execute -eq 0 ]]; then echo "Dry-run complete. Supply all listed --accept-license values and --execute to download."; else echo "Selected model packs installed and verified."; fi
