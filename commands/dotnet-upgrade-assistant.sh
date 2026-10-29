#!/usr/bin/env bash
set -euo pipefail

cd ..

if [[ $# -lt 1 ]]; then
  echo "Usage: ./commands/dotnet-upgrade-assistant.sh <solution-or-project-path> [extra upgrade-assistant args...]" >&2
  exit 1
fi

target="$1"
shift || true

tool_cmd=""

if command -v upgrade-assistant >/dev/null 2>&1; then
  tool_cmd="upgrade-assistant"
elif [[ -x "$HOME/.dotnet/tools/upgrade-assistant" ]]; then
  tool_cmd="$HOME/.dotnet/tools/upgrade-assistant"
else
  echo "Installing or updating upgrade-assistant global tool..."
  dotnet tool update -g upgrade-assistant >/dev/null 2>&1 || dotnet tool install -g upgrade-assistant >/dev/null 2>&1

  if command -v upgrade-assistant >/dev/null 2>&1; then
    tool_cmd="upgrade-assistant"
  elif [[ -x "$HOME/.dotnet/tools/upgrade-assistant" ]]; then
    tool_cmd="$HOME/.dotnet/tools/upgrade-assistant"
  else
    echo "Unable to locate upgrade-assistant. Ensure ~/.dotnet/tools is on PATH and retry." >&2
    exit 1
  fi
fi

echo "Running upgrade-assistant for: $target"
"$tool_cmd" upgrade "$target" "$@"
