#!/usr/bin/env bash
set -euo pipefail

root=".styles/.pipelines"
[[ -d "$root" ]] || { echo "Missing art pipeline directory: $root" >&2; exit 1; }
[[ -f "$root/INDEX.md" ]] || { echo "Missing art pipeline index." >&2; exit 1; }
[[ ! -e ".styles/.gpu" ]] || { echo "Legacy .styles/.gpu directory must not exist." >&2; exit 1; }
[[ ! -e ".media" ]] || { echo "Legacy .media directory must not exist." >&2; exit 1; }

declare -A paths=(
  [CLOUD]="cloud/PIPELINE.md"
  [LOCAL]="local/PIPELINE.md"
  [CSS3]="css3/PIPELINE.md"
  [CODE]="code/PIPELINE.md"
  [BLENDER]="blender/PIPELINE.md"
)
for pipeline in CLOUD LOCAL CSS3 CODE BLENDER; do
  file="$root/${paths[$pipeline]}"
  [[ -f "$file" ]] || { echo "Missing art pipeline contract: $file" >&2; exit 1; }
  heading="$(head -n 1 "$file" | tr -d '\r')"
  [[ "$heading" == "# $pipeline Art Pipeline" ]] || { echo "Invalid art pipeline heading: $file" >&2; exit 1; }
  for section in "## Intent" "## Inputs" "## Production Rules" "## Output Contract" "## Acceptance Checks" "## Role Fit"; do
    awk -v expected="$section" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$file" || { echo "$file is missing $section" >&2; exit 1; }
  done
  grep -Fq -- "- \`$pipeline\`" "$root/INDEX.md" || { echo "Art pipeline is not indexed: $pipeline" >&2; exit 1; }
  grep -Eiq 'never (switch|fall back)|never.*silently' "$file" || { echo "$file lacks a no-silent-fallback boundary" >&2; exit 1; }
done

grep -Fq 'Blender 4.5 LTS' "$root/blender/PIPELINE.md" || { echo "BLENDER contract must pin Blender 4.5 LTS." >&2; exit 1; }
grep -Eiq 'immutable source|preserve.*source' "$root/blender/PIPELINE.md" || { echo "BLENDER contract lacks immutable-source protection." >&2; exit 1; }
grep -Eiq 'never install|do not install' "$root/blender/PIPELINE.md" || { echo "BLENDER contract lacks the no-install boundary." >&2; exit 1; }

for asset in _shared/media-generation-manifest.schema.json local/toolchain.json local/model-packs.json css3/art-tokens.css code/code-model-manifest.schema.json; do
  [[ -f "$root/$asset" ]] || { echo "Missing art pipeline support asset: $root/$asset" >&2; exit 1; }
done

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate art pipeline assets." >&2; exit 1; }
"$node_bin" <<'NODE'
const fs = require('fs');
const files = [
  '.styles/.pipelines/_shared/media-generation-manifest.schema.json',
  '.styles/.pipelines/local/toolchain.json',
  '.styles/.pipelines/local/model-packs.json',
  '.styles/.pipelines/code/code-model-manifest.schema.json'
];
for (const file of files) JSON.parse(fs.readFileSync(file, 'utf8'));
const code = JSON.parse(fs.readFileSync(files[3], 'utf8'));
const required = ['schemaVersion','modelId','intent','pipelineSelection','inputs','target','renderer','runtime','budgets','reviewPolicy','passes'];
for (const key of required) if (!code.required.includes(key)) throw new Error(`Code model schema omits ${key}`);
const css = fs.readFileSync('.styles/.pipelines/css3/art-tokens.css', 'utf8');
if (!css.includes(':root') || !css.includes('--art-')) throw new Error('CSS3 token asset is incomplete.');
if (/url\s*\(|canvas|webgl|data:image/i.test(css)) throw new Error('CSS3 token asset contains a prohibited raster or rendering dependency.');
NODE

bash commands/validate-media-templates.sh
echo "Art pipeline validation passed."
