#!/usr/bin/env bash
set -euo pipefail

host_root="${OPENCAW_HOST_ROOT:-$(pwd)}"
project=""
grep_pattern=""
headed=0
extra_args=()

usage() {
  cat <<'EOF'
Usage: playwright-test.sh [--project NAME] [--grep PATTERN] [--headed|--headless] [-- EXTRA_ARGS...]

Runs Playwright tests from the host repository. Set OPENCAW_HOST_ROOT to override the working directory.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      shift
      project="${1:-}"
      [[ -n "$project" ]] || { echo "--project requires a value" >&2; exit 1; }
      ;;
    --project=*)
      project="${1#--project=}"
      ;;
    --grep)
      shift
      grep_pattern="${1:-}"
      [[ -n "$grep_pattern" ]] || { echo "--grep requires a value" >&2; exit 1; }
      ;;
    --grep=*)
      grep_pattern="${1#--grep=}"
      ;;
    --headed)
      headed=1
      ;;
    --headless)
      headed=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      extra_args+=("$1")
      ;;
  esac
  shift || true
done

cd "$host_root"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to run Playwright tests." >&2
  exit 1
fi

if [[ ! -f package.json ]]; then
  echo "No package.json found in $host_root. Run this from a Node/Playwright host repository or set OPENCAW_HOST_ROOT." >&2
  exit 1
fi

cmd=(npx playwright test)
if [[ -n "$project" ]]; then
  cmd+=(--project "$project")
fi
if [[ -n "$grep_pattern" ]]; then
  cmd+=(--grep "$grep_pattern")
fi
if [[ "$headed" -eq 1 ]]; then
  cmd+=(--headed)
fi
cmd+=("${extra_args[@]}")

echo "Running from $host_root: ${cmd[*]}"
"${cmd[@]}"
