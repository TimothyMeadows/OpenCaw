#!/usr/bin/env bash
set -euo pipefail

roles_dir="./.roles/computer-science"
status=0

if [[ ! -d "$roles_dir" ]]; then
  echo "Missing roles directory: $roles_dir" >&2
  exit 1
fi

has_rg=0
if command -v rg >/dev/null 2>&1; then
  has_rg=1
fi

search_exists() {
  local pattern="$1"
  local target="$2"
  if [[ $has_rg -eq 1 ]]; then
    rg -n -i "$pattern" "$target" >/dev/null
  else
    grep -R -E -i -n "$pattern" "$target" >/dev/null
  fi
}

print_matches() {
  local pattern="$1"
  local target="$2"
  if [[ $has_rg -eq 1 ]]; then
    rg -n -i "$pattern" "$target" >&2 || true
  else
    grep -R -E -i -n "$pattern" "$target" >&2 || true
  fi
}

if [[ ! -f "./.architecture/LANGUAGE_SUPPORT.md" ]]; then
  echo "Missing language support matrix: ./.architecture/LANGUAGE_SUPPORT.md" >&2
  status=1
fi

# Languages explicitly disallowed until a matching architecture template is added.
disallowed_regex='(\bswift\b|\bkotlin\b|\bflutter\b|\bphp\b|\blaravel\b|\blivewire\b|\bjulia\b)'
if search_exists "$disallowed_regex" "$roles_dir"; then
  echo "Role language alignment failed: found disallowed language references without approved architecture template." >&2
  print_matches "$disallowed_regex" "$roles_dir"
  status=1
fi

# Solidity role requires SOLIDITY architecture support.
if search_exists '\bsolidity\b' "$roles_dir/solidity-smart-contract-engineer/ROLE.md"; then
  if [[ ! -f "./.architecture/SOLIDITY.md" ]]; then
    echo "Missing required architecture template for Solidity role: ./.architecture/SOLIDITY.md" >&2
    status=1
  fi
fi

# Embedded role requires embedded firmware architecture support.
if search_exists '^```c$' "$roles_dir/embedded-firmware-engineer/ROLE.md"; then
  if [[ ! -f "./.architecture/EMBEDDED_FIRMWARE.md" ]]; then
    echo "Missing required architecture template for embedded C role: ./.architecture/EMBEDDED_FIRMWARE.md" >&2
    status=1
  fi
fi

# Security roles must prioritize Veracode, Snyk, StackHawk.
for role_file in \
  "$roles_dir/security-engineer/ROLE.md" \
  "$roles_dir/threat-detection-engineer/ROLE.md"; do
  for tool in veracode snyk stackhawk; do
    if ! search_exists "\\b${tool}\\b" "$role_file"; then
      echo "Missing required security tool preference '${tool}' in $role_file" >&2
      status=1
    fi
  done
done

# Skill map must include the preferred security commands.
for map_file in "./.roles/ROLE_SKILL_MAP.md" "./.roles/ROLE_SKILL_MAP.json"; do
  for cmd in commands/veracode-scan.sh commands/snyk-scan.sh commands/stackhawk-scan.sh; do
    if ! search_exists "$cmd" "$map_file"; then
      echo "Missing required security command mapping '$cmd' in $map_file" >&2
      status=1
    fi
  done
done

if [[ $status -eq 0 ]]; then
  echo "Role language/tool alignment validation passed."
fi

exit $status
