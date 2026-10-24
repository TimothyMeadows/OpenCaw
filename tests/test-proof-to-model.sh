#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dotnet run --project "$repo_root/commands/lib/proof-to-model/Tests/RuntimeTests.csproj" --no-launch-profile
