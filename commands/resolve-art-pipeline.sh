#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/resolve-art-pipeline.sh [--style STYLE.md] [--override PIPELINE] [--json] [--evidence FILE]

Resolves an explicit task prompt override before the primary pipeline in STYLE.md.
An evidence file must be stored below the resolved project .ai/tasks directory.
EOF
}

style_file=''
override=''
json=0
evidence=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --style) [[ $# -ge 2 ]] || { echo "--style requires a path" >&2; exit 1; }; style_file="$2"; shift 2 ;;
    --override) [[ $# -ge 2 ]] || { echo "--override requires a pipeline" >&2; exit 1; }; override="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --evidence) [[ $# -ge 2 ]] || { echo "--evidence requires a path" >&2; exit 1; }; evidence="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/art-pipeline-common.sh"
opencaw_resolve_paths
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
style_file="${style_file:-$host_root/STYLE.md}"
[[ -f "$style_file" ]] || { echo "Missing STYLE.md: $style_file" >&2; exit 1; }
bash "$script_dir/validate-style-contract.sh" "$style_file" >/dev/null

if [[ -n "$override" ]]; then
  pipeline="$(art_pipeline_normalize "$override")" || { echo "Unknown art pipeline override: $override" >&2; exit 1; }
  selection_source='prompt'
else
  pipeline="$(awk '/^Primary OpenCaw art pipeline:/ { read=1; next } /^Allowed OpenCaw art pipelines:/ { read=0 } read && /^- / { sub(/^- /, ""); sub(/\r$/, ""); print; exit }' "$style_file")"
  [[ -n "$pipeline" ]] || { echo "STYLE.md has no primary art pipeline." >&2; exit 1; }
  selection_source='style'
fi

style_sha256="$(art_pipeline_sha256_file "$style_file")"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to serialize art pipeline evidence." >&2; exit 1; }
node_host_root="$host_root"
node_style="$style_file"
node_evidence="$evidence"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_host_root="$(wslpath -w "$host_root")"
  node_style="$(wslpath -w "$style_file")"
  [[ -z "$evidence" ]] || node_evidence="$(wslpath -w "$evidence")"
fi

serialized="$("$node_bin" - "$node_host_root" "$node_style" "$pipeline" "$selection_source" "$style_sha256" <<'NODE'
const path = require('path');
const [root, style, pipeline, source, sha] = process.argv.slice(2);
const rel = path.relative(path.resolve(root), path.resolve(style)).split(path.sep).join('/');
if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('STYLE.md must stay inside the project root.');
process.stdout.write(JSON.stringify({
  schemaVersion: 1,
  pipeline,
  selectionSource: source,
  styleContract: rel,
  styleSha256: sha,
  fallbackPolicy: 'stop',
  resolvedAt: new Date().toISOString()
}, null, 2) + '\n');
NODE
)"

if [[ -n "$evidence" ]]; then
  "$node_bin" - "$node_host_root" "$node_evidence" "$serialized" <<'NODE'
const fs = require('fs');
const path = require('path');
const [rootArg, outputArg, serialized] = process.argv.slice(2);
const root = fs.realpathSync(rootArg);
const tasks = fs.realpathSync(path.join(root, '.ai', 'tasks'));
const output = path.resolve(outputArg);
const rel = path.relative(tasks, output);
if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('Evidence output must stay below .ai/tasks.');
const parent = path.dirname(output);
let ancestor = parent;
while (!fs.existsSync(ancestor)) {
  const next = path.dirname(ancestor);
  if (next === ancestor) throw new Error('Evidence output has no safe existing parent.');
  ancestor = next;
}
const realAncestor = fs.realpathSync(ancestor);
if (realAncestor !== tasks && !realAncestor.startsWith(tasks + path.sep)) throw new Error('Evidence parent escapes .ai/tasks.');
fs.mkdirSync(parent, { recursive: true });
const realParent = fs.realpathSync(parent);
if (realParent !== tasks && !realParent.startsWith(tasks + path.sep)) throw new Error('Evidence parent escapes .ai/tasks.');
if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) throw new Error('Evidence output must not be a symbolic link.');
fs.writeFileSync(output, serialized, { encoding: 'utf8', flag: 'w' });
NODE
fi

if [[ $json -eq 1 ]]; then
  printf '%s\n' "$serialized"
else
  echo "ART_PIPELINE=$pipeline"
  echo "SELECTION_SOURCE=$selection_source"
  echo "STYLE_SHA256=$style_sha256"
  [[ -z "$evidence" ]] || echo "EVIDENCE_FILE=$evidence"
fi
