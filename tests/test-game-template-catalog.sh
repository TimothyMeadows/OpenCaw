#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.template-catalog-runtime-XXXXXX")"
project="$runtime_dir/project"
mkdir -p "$project"
cleanup() {
  case "$runtime_dir" in "$repo_root"/tests/.template-catalog-runtime-*) rm -rf -- "$runtime_dir" ;; esac
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
project_command() { OPENCAW_PROJECT_ROOT="$project" "$@"; }

echo '[1/4] checking architecture and style catalog consistency'
grep -Fq 'bash ./tests/test-game-template-catalog.sh' commands/validate-opencaw.sh || fail 'integrated validation omits game template tests'
for catalog in .architecture .styles; do
  while IFS= read -r name; do
    [[ -f "$catalog/$name.md" ]] || fail "$catalog advertises missing template $name"
  done < <(sed -nE 's/\r$//; s/^- ([A-Z][A-Z0-9_]+)$/\1/p' "$catalog/INDEX.md")
  for file in "$catalog"/*.md; do
    name="$(basename "$file" .md)"
    case "$name" in INDEX|LANGUAGE_SUPPORT) continue ;; esac
    awk -v expected="- $name" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$catalog/INDEX.md" || fail "$file is absent from the catalog"
  done
done
while IFS= read -r name; do
  [[ -f ".architecture/$name.md" || -f ".engine/$name.md" ]] || fail "language matrix references missing template $name"
done < <(sed -nE 's/^\| ([A-Z][A-Z0-9_]+) \|.*/\1/p' .architecture/LANGUAGE_SUPPORT.md)

echo '[2/4] generating retained mixed and inline architecture contracts'
project_command bash commands/generate-architecture.sh DOTNET THREEJS COLYSEUS SPA >/dev/null
for name in DOTNET THREEJS COLYSEUS SPA; do
  grep -Fq "/.architecture/$name.md" "$project/ARCHITECTURE.md" || fail "missing architecture directive $name"
done
project_command bash commands/generate-architecture.sh --inline DOTNET NODE >/dev/null
grep -Fq '<!-- BEGIN TEMPLATE: DOTNET -->' "$project/ARCHITECTURE.md" || fail 'inline architecture omitted DOTNET'

echo '[3/4] generating retained game styles without changing pipeline defaults'
project_command bash commands/generate-style.sh TACTICAL_UI_HUD VECTOR_UI >/dev/null
project_command bash commands/validate-style-contract.sh >/dev/null
grep -Fq '/.styles/TACTICAL_UI_HUD.md' "$project/STYLE.md" || fail 'missing game style directive'
project_command bash commands/generate-style.sh --inline --pipeline CODE PIXEL_ART >/dev/null
project_command bash commands/validate-style-contract.sh >/dev/null
grep -Fq '<!-- BEGIN ART PIPELINE: CODE -->' "$project/STYLE.md" || fail 'inline style omitted CODE'

echo '[4/4] rejecting retired selections without overwriting existing contracts'
for pair in 'architecture AZURE' 'architecture AZURE_DEVOPS' 'architecture DATABRICKS' 'architecture EMBEDDED_FIRMWARE' 'architecture SOLIDITY' 'architecture REACT' 'architecture NEXTJS' 'architecture ANGULAR' 'architecture VUE' 'style WEB_ATMOSPHERIC' 'style WEB_DARK_GLASS' 'style WEB_EDITORIAL' 'style WEB_LIGHT_PAPER' 'style WEB_SKEUOMORPHIC' 'style WEB_TECHNICAL_GRID'; do
  read -r kind name <<< "$pair"
  if [[ "$kind" == architecture ]]; then target="$project/ARCHITECTURE.md"; valid=DOTNET; else target="$project/STYLE.md"; valid=PIXEL_ART; fi
  before="$(sha256sum "$target")"
  if project_command bash "commands/generate-$kind.sh" "$valid" "$name" > "$runtime_dir/rejected.log" 2>&1; then
    fail "accepted retired $kind template $name"
  fi
  grep -Fq 'Missing' "$runtime_dir/rejected.log" || fail 'missing-template failure was not explained'
  [[ "$(sha256sum "$target")" == "$before" ]] || fail "rejected $name changed the existing contract"
done

echo 'Game template catalog tests passed.'
