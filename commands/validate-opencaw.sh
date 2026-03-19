#!/usr/bin/env bash
set -euo pipefail

./commands/validate-roles.sh
./commands/validate-skills.sh
./commands/validate-commands.sh

echo "OpenCaw validation passed."
