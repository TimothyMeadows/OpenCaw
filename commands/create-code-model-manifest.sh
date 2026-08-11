#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-code-model-manifest.sh MODEL_ID --brief TEXT [options]

Options:
  --style STYLE.md                 Style contract (default: resolved project STYLE.md)
  --prompt-override               Select CODE for this task when STYLE.md uses another primary
  --output FILE                   Manifest below .ai/tasks (default: .ai/tasks/MODEL_ID/code-model.json)
  --source FILE                   Host source target (default: src/models/MODEL_ID.ts)
  --title TEXT                    Human-readable title
  --intended-use TEXT             Runtime use
  --factory NAME                  Factory export name
  --interface TEXT               Documented host interface (default: CodeModelInstance)
  --coordinates TEXT             Host coordinate convention
  --part NAME                     Repeatable semantic part (default: body)
  --anchor NAME                   Repeatable pivot/anchor (default: origin)
  --reference FILE                Repeatable authorized reference image
  --reference-rights TEXT         Rights basis for all reference images
  --reference-consent VALUE       confirmed or not-applicable
  --planar                        Require only a front review view
  --seed INTEGER                  Deterministic procedural seed (default: 1)
  --triangles N                   Triangle budget (default: 60000)
  --draw-calls N                  Draw-call budget (default: 64)
  --materials N                   Material budget (default: 16)
  --textures N                    Texture budget (default: 0)
  --max-attempts-per-pass N       Default: 3
  --max-attempts-total N          Default: 12
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
style_file="$host_root/STYLE.md"
prompt_override=0
args=("$@")
for ((index=0; index<${#args[@]}; index++)); do
  case "${args[$index]}" in
    --style)
      (( index + 1 < ${#args[@]} )) || { echo "--style requires a path" >&2; exit 1; }
      style_file="${args[$((index + 1))]}"
      ;;
    --prompt-override) prompt_override=1 ;;
  esac
done
bash "$script_dir/validate-style-contract.sh" "$style_file" >/dev/null
resolve_args=(--style "$style_file" --json)
[[ $prompt_override -eq 0 ]] || resolve_args+=(--override CODE)
selection="$(bash "$script_dir/resolve-art-pipeline.sh" "${resolve_args[@]}")"
selected_pipeline="$(printf '%s' "$selection" | sed -n 's/^[[:space:]]*"pipeline": "\([A-Z0-9]*\)",*$/\1/p')"
[[ "$selected_pipeline" == 'CODE' ]] || {
  echo "STYLE.md selects $selected_pipeline. Use --prompt-override to select CODE for this task without rewriting STYLE.md." >&2
  exit 1
}

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-model manifests." >&2; exit 1; }
node_root="$host_root"
node_cli="$script_dir/lib/code-model-cli.cjs"
node_style="$style_file"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$host_root")"
  node_cli="$(wslpath -w "$node_cli")"
  node_style="$(wslpath -w "$style_file")"
fi
"$node_bin" "$node_cli" create "$node_root" "$@" --resolved-style "$node_style" --selection-json "$selection"
