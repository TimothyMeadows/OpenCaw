#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/run-comfyui-workflow.sh --workflow FILE --output-dir DIR
       [--workspace PATH] [--timeout N]

Runs one local workflow via structured comfy-cli output, downloads only into
the staging directory, hashes outputs, and writes opencaw-run-receipt.json.
This command never falls back to a cloud backend or promotes outputs.
EOF
}

workflow=""
output_dir=""
workspace=""
timeout_seconds=600
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow) [[ $# -ge 2 ]] || { echo "--workflow requires a file" >&2; exit 1; }; workflow="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || { echo "--output-dir requires a directory" >&2; exit 1; }; output_dir="$2"; shift 2 ;;
    --workspace) [[ $# -ge 2 ]] || { echo "--workspace requires a path" >&2; exit 1; }; workspace="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--timeout must be a positive integer" >&2; exit 1; }; timeout_seconds="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -n "$workflow" && -n "$output_dir" ]] || { usage >&2; exit 1; }
[[ -f "$workflow" ]] || { echo "Workflow not found: $workflow" >&2; exit 1; }

platform="${OPENCAW_PLATFORM_OVERRIDE:-}"
if [[ -z "$platform" ]]; then case "$(uname -s | tr '[:upper:]' '[:lower:]')" in mingw*|msys*|cygwin*) platform=windows ;; darwin*) platform=macos ;; linux*) if grep -Eqi '(microsoft|wsl)' /proc/version 2>/dev/null; then platform=windows; else platform=linux; fi ;; *) platform=unsupported ;; esac; fi
if [[ -z "$workspace" ]]; then
  case "$platform" in windows) workspace="${LOCALAPPDATA:-${USERPROFILE:-.}/AppData/Local}/OpenCaw/ComfyUI" ;; macos) workspace="${HOME:?HOME is required}/Library/Application Support/OpenCaw/ComfyUI" ;; linux) workspace="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}/opencaw/comfyui" ;; *) echo "Unsupported platform: $platform" >&2; exit 1 ;; esac
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for structured workflow execution." >&2; exit 1; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
workflow="$(realpath "$workflow")"
output_dir="$(realpath -m "$output_dir")"
workspace="$(realpath -m "$workspace")"
if [[ -n "${OPENCAW_TEST_COMFY_SCRIPT:-}" ]]; then
  case "$output_dir" in
    "$opencaw_root"/tests/.pipeline-media-runtime-*) [[ "${OPENCAW_TEST_MODE:-0}" == "1" ]] || { echo "Fake comfy execution requires OPENCAW_TEST_MODE=1." >&2; exit 1; } ;;
    *) echo "Fake comfy execution is confined to OpenCaw test runtimes." >&2; exit 1 ;;
  esac
fi
case "$output_dir" in
  /|/mnt|/mnt/|/mnt/[a-zA-Z]|/[a-zA-Z]) echo "Refusing a broad staging directory: $output_dir" >&2; exit 1 ;;
esac
mkdir -p "$output_dir"
[[ ! -L "$output_dir" ]] || { echo "Staging directory must not be a symbolic link." >&2; exit 1; }

workflow_for_native="$workflow"
output_for_native="$output_dir"
workspace_for_native="$workspace"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  workflow_for_native="$(wslpath -w "$workflow")"
  output_for_native="$(wslpath -w "$output_dir")"
  workspace_for_native="$(wslpath -w "$workspace")"
fi

comfy_bin="${OPENCAW_COMFY_BIN:-$workspace/.opencaw/bin/comfy}"
if [[ -z "${OPENCAW_COMFY_BIN:-}" && -z "${OPENCAW_TEST_COMFY_SCRIPT:-}" ]]; then
  [[ "$platform" == "windows" ]] && comfy_bin="$workspace/.opencaw/Scripts/comfy.exe"
  if [[ ! -x "$comfy_bin" ]]; then comfy_bin="$(command -v comfy 2>/dev/null || command -v comfy.exe 2>/dev/null || true)"; fi
fi
[[ -n "$comfy_bin" || -n "${OPENCAW_TEST_COMFY_SCRIPT:-}" ]] || { echo "comfy-cli is missing; run install-comfyui-local.sh --execute first." >&2; exit 1; }
comfy_for_native="$comfy_bin"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" && -e "$comfy_bin" ]]; then comfy_for_native="$(wslpath -w "$comfy_bin")"; fi
test_comfy_script_for_native="${OPENCAW_TEST_COMFY_SCRIPT:-}"
if [[ -n "$test_comfy_script_for_native" && "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then test_comfy_script_for_native="$(wslpath -w "$test_comfy_script_for_native")"; fi
runner_script_for_native="${OPENCAW_COMFY_RUNNER_SCRIPT:-}"
if [[ -n "$runner_script_for_native" && "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then runner_script_for_native="$(wslpath -w "$runner_script_for_native")"; fi
node_for_native="$node_bin"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then node_for_native="$(wslpath -w "$node_bin")"; fi
if [[ -n "$test_comfy_script_for_native" ]]; then comfy_for_native="$node_for_native"; fi
[[ -z "$test_comfy_script_for_native" ]] || runner_script_for_native="$test_comfy_script_for_native"

if [[ "${OPENCAW_ASSUME_SERVER_RUNNING:-0}" != "1" ]]; then
  server_up=0
  if command -v curl >/dev/null 2>&1 && curl --silent --fail --max-time 1 http://127.0.0.1:8188/system_stats >/dev/null 2>&1; then server_up=1; fi
  if [[ $server_up -eq 0 ]]; then
    "$comfy_bin" --workspace "$workspace_for_native" --json launch --background -- --listen 127.0.0.1 --disable-api-nodes
  fi
fi

raw_output="$output_dir/.opencaw-comfy-run.json"
set +e
raw_output_for_native="$raw_output"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then raw_output_for_native="$(wslpath -w "$raw_output")"; fi
"$node_bin" - "$timeout_seconds" "$raw_output_for_native" "$comfy_for_native" "$workspace_for_native" "$workflow_for_native" "$runner_script_for_native" <<'NODE'
const fs=require('fs'), cp=require('child_process');
const timeout=Number(process.argv[2])*1000, out=process.argv[3], bin=process.argv[4], workspace=process.argv[5], workflow=process.argv[6], fixture=process.argv[7];
const argv=[...(fixture?[fixture]:[]),'--workspace',workspace,'--json','run','--workflow',workflow,'--wait','--timeout',String(Math.max(1,Math.floor(timeout/1000)))];
const r=cp.spawnSync(bin,argv,{encoding:'utf8',windowsHide:true,timeout,killSignal:'SIGTERM'});
fs.writeFileSync(out,r.stdout || '', 'utf8');
if (r.stderr) process.stderr.write(r.stderr);
if (r.error && r.error.code === 'ETIMEDOUT') { process.stderr.write(`Workflow exceeded wall-clock timeout of ${timeout/1000}s\n`); process.exit(124); }
if (r.error) process.stderr.write(`Unable to start comfy-cli: ${r.error.message}\n`);
process.exit(Number.isInteger(r.status) ? r.status : 1);
NODE
run_status=$?
set -e
[[ $run_status -eq 0 ]] || { echo "Local ComfyUI workflow failed with status $run_status; no cloud fallback was attempted." >&2; exit $run_status; }

prompt_id="$("$node_bin" - "$raw_output_for_native" <<'NODE'
const fs=require('fs'); let d;
try { d=JSON.parse(fs.readFileSync(process.argv[2],'utf8')); } catch(e) { console.error(`Malformed comfy-cli JSON: ${e.message}`); process.exit(1); }
if (!d || d.ok !== true || !d.data || d.data.status !== 'completed' || !d.data.prompt_id) { console.error('comfy-cli did not report a completed workflow with a prompt_id.'); process.exit(1); }
if (d.data.node_errors && Object.keys(d.data.node_errors).length) { console.error('ComfyUI reported node errors.'); process.exit(1); }
process.stdout.write(d.data.prompt_id);
NODE
)" || exit 1

download_output="$output_dir/.opencaw-comfy-download.json"
download_output_for_native="$download_output"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then download_output_for_native="$(wslpath -w "$download_output")"; fi
"$node_bin" - "$download_output_for_native" "$comfy_for_native" "$workspace_for_native" "$prompt_id" "$output_for_native" "$runner_script_for_native" <<'NODE'
const fs=require('fs'),cp=require('child_process'); const out=process.argv[2],bin=process.argv[3],fixture=process.argv[7];
const argv=[...(fixture?[fixture]:[]),'--workspace',process.argv[4],'--json','download',process.argv[5],'--out-dir',process.argv[6],'--where','local'];
const r=cp.spawnSync(bin,argv,{encoding:'utf8',windowsHide:true,timeout:120000});
fs.writeFileSync(out,r.stdout||'','utf8'); if(r.stderr)process.stderr.write(r.stderr); process.exit(Number.isInteger(r.status)?r.status:1);
NODE
"$node_bin" - "$download_output_for_native" <<'NODE'
const fs=require('fs'); let d;
try { d=JSON.parse(fs.readFileSync(process.argv[2],'utf8')); } catch(e) { console.error(`Malformed comfy-cli download JSON: ${e.message}`); process.exit(1); }
if (!d || d.ok !== true) { console.error('comfy-cli output download failed.'); process.exit(1); }
NODE

receipt="$output_dir/opencaw-run-receipt.json"
"$node_bin" - "$output_for_native" "$workflow_for_native" "$workspace_for_native" "$prompt_id" <<'NODE' > "$receipt.tmp"
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const root=fs.realpathSync(process.argv[2]);
function walk(dir){ let out=[]; for(const e of fs.readdirSync(dir,{withFileTypes:true})){ const p=path.join(dir,e.name); if(e.isSymbolicLink()) throw new Error(`symbolic link in staging: ${p}`); if(e.isDirectory()) out=out.concat(walk(p)); else out.push(p); } return out; }
const ignored=new Set(['.opencaw-comfy-run.json','.opencaw-comfy-download.json','opencaw-run-receipt.json','opencaw-run-receipt.json.tmp']);
const outputs=walk(root).filter(p=>!ignored.has(path.basename(p))).map(p=>({path:path.relative(root,p).split(path.sep).join('/'),sha256:crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'),sizeBytes:fs.statSync(p).size}));
if (!outputs.length) { console.error('Workflow produced no downloaded outputs.'); process.exit(1); }
console.log(JSON.stringify({schemaVersion:1,pipeline:'LOCAL',provider:'comfy-cli',promptId:process.argv[5],workflow:{path:process.argv[3],sha256:crypto.createHash('sha256').update(fs.readFileSync(process.argv[3])).digest('hex')},workspace:process.argv[4],stagingDirectory:root,outputs,promotionStatus:'pending-human-review'},null,2));
NODE
mv "$receipt.tmp" "$receipt"
echo "Local workflow completed."
echo "Receipt: $receipt"
echo "Promotion status: pending human review."
