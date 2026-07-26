#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source commands/lib/platform-common.sh

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo '[1/4] classifying Windows and non-Windows hosts'
WSL_INTEROP='' opencaw_is_windows_host 'MINGW64_NT-10.0' '' || fail 'Git Bash host was not detected as Windows'
WSL_INTEROP='' opencaw_is_windows_host 'MSYS_NT-10.0' '' || fail 'MSYS host was not detected as Windows'
WSL_INTEROP='' opencaw_is_windows_host 'CYGWIN_NT-10.0' '' || fail 'Cygwin host was not detected as Windows'
WSL_INTEROP='' opencaw_is_windows_host 'Linux' 'Linux version with Microsoft WSL2' || fail 'WSL host was not detected as Windows'
if WSL_INTEROP='' opencaw_is_windows_host 'Linux' 'generic Linux kernel'; then fail 'generic Linux was classified as Windows'; fi
if WSL_INTEROP='' opencaw_is_windows_host 'Darwin' 'Darwin kernel'; then fail 'macOS was classified as Windows'; fi

echo '[2/4] generating Windows-only scaffold guidance'
fixture="$temp_root/project"
mkdir -p "$fixture/.codex/commands/lib"
cp commands/create-host-ai-scaffold.sh "$fixture/.codex/commands/create-host-ai-scaffold.sh"
cp commands/install-windows-bash.ps1 "$fixture/.codex/commands/install-windows-bash.ps1"
cp commands/lib/memory-common.sh "$fixture/.codex/commands/lib/memory-common.sh"
cp commands/lib/platform-common.sh "$fixture/.codex/commands/lib/platform-common.sh"
chmod +x "$fixture/.codex/commands/create-host-ai-scaffold.sh"

WSL_INTEROP='fixture' bash "$fixture/.codex/commands/create-host-ai-scaffold.sh" > "$temp_root/scaffold-first.log"
guidance="$fixture/.ai/WINDOWS_BASH.md"
[[ -f "$guidance" ]] || fail 'Windows scaffold guidance was not created'
grep -Fq './.codex/commands/install-windows-bash.ps1' "$guidance" || fail 'mounted installer path is incorrect'
grep -Fq -- '-Provider GitBash -Install' "$guidance" || fail 'native Git Bash install guidance is missing'
grep -Fq -- '-Provider WSL -Install' "$guidance" || fail 'WSL install guidance is missing'
grep -Fq 'never installs software automatically' "$guidance" || fail 'explicit-install safety guidance is missing'

echo '[3/4] preserving scaffold idempotence'
guidance_fingerprint="$(sha256sum "$guidance" | awk '{print $1}')"
WSL_INTEROP='fixture' bash "$fixture/.codex/commands/create-host-ai-scaffold.sh" > "$temp_root/scaffold-second.log"
[[ "$(sha256sum "$guidance" | awk '{print $1}')" == "$guidance_fingerprint" ]] || fail 'Windows guidance changed on an idempotent scaffold run'
[[ "$(grep -c '^# Windows Bash Setup$' "$guidance")" -eq 1 ]] || fail 'Windows guidance was duplicated'

echo '[4/4] validating the native PowerShell bootstrap when available'
powershell_bin=''
if command -v pwsh >/dev/null 2>&1; then
  powershell_bin="$(command -v pwsh)"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell_bin="$(command -v powershell.exe)"
fi

if [[ -n "$powershell_bin" ]]; then
  powershell_test_path="$repo_root/tests/test-windows-bash-bootstrap.ps1"
  if [[ "${powershell_bin,,}" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
    powershell_test_path="$(wslpath -w "$powershell_test_path")"
  fi
  "$powershell_bin" -NoProfile -ExecutionPolicy Bypass -File "$powershell_test_path"
else
  echo 'PowerShell unavailable; runtime PowerShell checks skipped on this non-Windows host.'
fi

echo 'Windows Bash bootstrap tests passed.'
