#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token_file="$(cd "$script_dir/.." && pwd)/.styles/.pipelines/css3/art-tokens.css"
[[ -f "$token_file" ]] || { echo "Missing CSS3 art tokens: $token_file" >&2; exit 1; }
cat "$token_file"

echo "Printed CSS art token template."
echo "Use consistent token naming to keep vector art portable across components."
