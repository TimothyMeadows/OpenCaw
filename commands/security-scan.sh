#!/usr/bin/env bash
set -euo pipefail

echo "Run security scanning workflow (preferred order)"
echo "1) Veracode policy scan"
./commands/veracode-scan.sh

echo "2) Snyk dependency/container/IaC scan"
./commands/snyk-scan.sh

echo "3) StackHawk DAST scan"
./commands/stackhawk-scan.sh

echo "4) Supplemental checks (optional)"
echo "- dependency-check.sh"
echo "- secret-scan.sh"
echo "- audit-logs.sh"
