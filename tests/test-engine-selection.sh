#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for engine selection tests.' >&2; exit 1; }
test_file="$repo_root/tests/test-engine-selection.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then test_file="$(wslpath -w "$test_file")"; fi
"$node_bin" "$test_file"
# Exercise the agnostic pipeline wrapper too, using the same project contract.
fixture="$(mktemp -d "$repo_root/tests/.engine-wrapper-XXXXXX")"
trap 'case "$fixture" in "$repo_root"/tests/.engine-wrapper-*) rm -rf -- "$fixture" ;; esac' EXIT
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/generate-engine.sh" UNITY >/dev/null
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/generate-style.sh" --pipeline CODE PIXEL_ART >/dev/null
before="$(sha256sum "$fixture/ENGINE.md" "$fixture/STYLE.md")"
if HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/resolve-art-pipeline.sh" --json >"$fixture/result.log" 2>&1; then
  echo 'FAIL: UNITY accepted Three.js CODE production through the pipeline wrapper.' >&2; exit 1
fi
grep -Fq 'requires THREEJS' "$fixture/result.log"
[[ "$before" == "$(sha256sum "$fixture/ENGINE.md" "$fixture/STYLE.md")" ]]
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/print-game-art-handoff-template.sh" sample Unity >"$fixture/handoff.md"
grep -Fq 'Target engine/runtime: UNITY' "$fixture/handoff.md"
if HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/print-game-art-handoff-template.sh" sample Godot >/dev/null 2>&1; then
  echo 'FAIL: handoff accepted a second engine selection.' >&2; exit 1
fi
echo 'Engine wrapper compatibility tests passed.'
mkdir -p "$fixture/.hephaera/.cache/tasks/demo"
printf '%s\n' 'Authorized isolated Three.js prototype.' > "$fixture/.hephaera/.cache/tasks/demo/TASK.md"
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/resolve-engine.sh" --override THREEJS --task demo --scope prototypes/three-demo --record-override >/dev/null
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/create-code-model-manifest.sh" demo --brief 'Isolated prototype' --source prototypes/three-demo/model.ts --engine-evidence .hephaera/.cache/tasks/demo/engine-override.json >/dev/null
[[ -f "$fixture/.hephaera/.cache/tasks/demo/code-model.json" && ! -d "$fixture/src" ]]
HEPHAERA_PROJECT_ROOT="$fixture" bash "$repo_root/commands/validate-code-model-manifest.sh" .hephaera/.cache/tasks/demo/code-model.json >/dev/null
echo 'Valid CODE prototype override passed without changing project engine or runtime source.'
