#!/usr/bin/env bash
set -euo pipefail

echo "Run dependency vulnerability checks (Snyk-first)"
./commands/snyk-scan.sh

echo "Optional supplemental dependency checks can run after Snyk"
echo "- Implement repository-specific supplemental scanners as needed."
