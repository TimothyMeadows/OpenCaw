#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/install-comfyui-local.sh [--workspace PATH] [--execute]

Dry-run by default. With --execute, installs an isolated supported Python
environment, comfy-cli 1.12.0, ComfyUI 0.28.0, and FFmpeg where missing.
It never installs GPU drivers, creates accounts, or installs custom nodes.
EOF
}

workspace=""
execute=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) [[ $# -ge 2 ]] || { echo "--workspace requires a path" >&2; exit 1; }; workspace="$2"; shift 2 ;;
    --execute) execute=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

platform="${OPENCAW_PLATFORM_OVERRIDE:-}"
if [[ -z "$platform" ]]; then
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    mingw*|msys*|cygwin*) platform="windows" ;;
    darwin*) platform="macos" ;;
    linux*) if grep -Eqi '(microsoft|wsl)' /proc/version 2>/dev/null; then platform="windows"; else platform="linux"; fi ;;
    *) platform="unsupported" ;;
  esac
fi
case "$platform" in windows|linux|macos) ;; *) echo "Unsupported platform: $platform" >&2; exit 1 ;; esac

if [[ -z "$workspace" ]]; then
  case "$platform" in
    windows) workspace="${LOCALAPPDATA:-${USERPROFILE:-.}/AppData/Local}/OpenCaw/ComfyUI" ;;
    macos) workspace="${HOME:?HOME is required}/Library/Application Support/OpenCaw/ComfyUI" ;;
    linux) workspace="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}/opencaw/comfyui" ;;
  esac
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to read the toolchain manifest." >&2; exit 1; }
toolchain_manifest="$opencaw_root/.styles/.gpu/toolchain.json"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then toolchain_manifest="$(wslpath -w "$toolchain_manifest")"; fi
cli_version="$("$node_bin" -e "const x=require(process.argv[1]); process.stdout.write(x.comfyCli.version)" "$toolchain_manifest")"
comfy_version="$("$node_bin" -e "const x=require(process.argv[1]); process.stdout.write(x.comfyUI.version)" "$toolchain_manifest")"

echo "OpenCaw local media toolchain"
echo "- platform: $platform"
echo "- workspace: $workspace"
echo "- comfy-cli: $cli_version"
echo "- ComfyUI: $comfy_version"
echo "- mode: $([[ $execute -eq 1 ]] && echo execute || echo dry-run)"

find_python() {
  local candidate actual
  if [[ -n "${OPENCAW_PYTHON_BIN:-}" ]]; then
    candidate="$OPENCAW_PYTHON_BIN"
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
      actual="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
      case "$actual" in 3.10|3.11|3.12|3.13) printf '%s' "$candidate"; return 0 ;; esac
    fi
  fi
  if [[ "$platform" == "windows" && "$(uname -s | tr '[:upper:]' '[:lower:]')" == linux* ]]; then
    local launcher resolved version
    launcher="$(command -v py.exe 2>/dev/null || true)"
    if [[ -n "$launcher" ]]; then
      for version in 3.13 3.12 3.11 3.10; do
        resolved="$("$launcher" -"$version" -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r' || true)"
        [[ -n "$resolved" ]] || continue
        resolved="$(wslpath -u "$resolved")"
        [[ -x "$resolved" ]] && { printf '%s' "$resolved"; return 0; }
      done
    fi
    for candidate in python3.13.exe python3.12.exe python3.11.exe python3.10.exe python.exe; do
      command -v "$candidate" >/dev/null 2>&1 || continue
      actual="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
      case "$actual" in 3.10|3.11|3.12|3.13) command -v "$candidate"; return 0 ;; esac
    done
    return 1
  fi
  for candidate in python3.13 python3.12 python3.11 python3.10 python3 python py.exe python.exe; do
    [[ -n "$candidate" ]] || continue
    command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]] || continue
    actual="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
    case "$actual" in 3.10|3.11|3.12|3.13) printf '%s' "$candidate"; return 0 ;; esac
  done
  return 1
}

run_python() {
  "$python_bin" "$@"
}

python_bin="$(find_python || true)"
if [[ -z "$python_bin" ]]; then
  echo "- supported Python: missing; planned install is Python 3.13"
  if [[ $execute -eq 1 ]]; then
    case "$platform" in
      windows)
        command -v winget >/dev/null 2>&1 || { echo "winget is required to install Python 3.13." >&2; exit 1; }
        winget install --id Python.Python.3.13 --exact --silent --accept-package-agreements --accept-source-agreements
        ;;
      macos)
        command -v brew >/dev/null 2>&1 || { echo "Homebrew is required to install Python 3.13." >&2; exit 1; }
        brew install python@3.13
        ;;
      linux)
        if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y python3.13 python3.13-venv
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y python3.13
        else echo "A supported package manager (apt-get or dnf) is required for Python 3.13." >&2; exit 1
        fi
        ;;
    esac
    python_bin="$(find_python || true)"
    [[ -n "$python_bin" ]] || { echo "Python installed but is not visible in this shell; reopen it and rerun." >&2; exit 1; }
  fi
else
  echo "- supported Python: $python_bin"
fi

force_missing_ffmpeg=0
if [[ -n "${OPENCAW_TEST_MISSING_FFMPEG:-}" ]]; then
  workspace_real="$(realpath -m "$workspace")"
  tests_real="$(realpath -m "$opencaw_root/tests")"
  if [[ "${OPENCAW_TEST_MODE:-}" != "1" || "$OPENCAW_TEST_MISSING_FFMPEG" != "1" ]]; then
    echo "OPENCAW_TEST_MISSING_FFMPEG is restricted to the OpenCaw test suite." >&2
    exit 1
  fi
  case "$workspace_real" in
    "$tests_real"/.media-runtime-*) force_missing_ffmpeg=1 ;;
    *) echo "OPENCAW_TEST_MISSING_FFMPEG requires an isolated OpenCaw test workspace." >&2; exit 1 ;;
  esac
fi

if [[ $force_missing_ffmpeg -eq 0 ]] && { command -v ffmpeg >/dev/null 2>&1 || command -v ffmpeg.exe >/dev/null 2>&1; }; then
  echo "- FFmpeg: present"
else
  echo "- FFmpeg: missing; planned operating-system package install"
  if [[ $execute -eq 1 ]]; then
    case "$platform" in
      windows)
        command -v winget >/dev/null 2>&1 || { echo "winget is required to install FFmpeg." >&2; exit 1; }
        winget install --id Gyan.FFmpeg --exact --silent --accept-package-agreements --accept-source-agreements
        ;;
      macos) command -v brew >/dev/null 2>&1 || { echo "Homebrew is required to install FFmpeg." >&2; exit 1; }; brew install ffmpeg ;;
      linux)
        if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y ffmpeg
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y ffmpeg
        else echo "A supported package manager is required for FFmpeg." >&2; exit 1
        fi
        ;;
    esac
  fi
fi

tool_env="$workspace/.opencaw"
workspace_for_comfy="$workspace"
tool_env_for_python="$tool_env"
if [[ "$python_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  workspace_for_comfy="$(wslpath -w "$(realpath -m "$workspace")")"
  tool_env_for_python="$(wslpath -w "$(realpath -m "$tool_env")")"
fi
comfy_bin="$tool_env/bin/comfy"
[[ "$platform" == "windows" ]] && comfy_bin="$tool_env/Scripts/comfy.exe"
if [[ $execute -eq 0 ]]; then
  echo "- create isolated environment: $tool_env"
  echo "- install: comfy-cli==$cli_version"
  echo "- install core only: ComfyUI $comfy_version with --skip-manager"
  echo "Dry-run complete. Rerun with --execute to apply."
  exit 0
fi

mkdir -p "$workspace"
if [[ ! -x "$comfy_bin" ]]; then
  run_python -m venv "$tool_env_for_python"
  env_python="$tool_env/bin/python"
  [[ "$platform" == "windows" ]] && env_python="$tool_env/Scripts/python.exe"
  "$env_python" -m pip install --disable-pip-version-check "comfy-cli==$cli_version"
fi

installed_cli="$($comfy_bin --version 2>/dev/null | tr -d '\r' || true)"
[[ "$installed_cli" == *"$cli_version"* ]] || { echo "Unexpected comfy-cli version: $installed_cli" >&2; exit 1; }

if [[ -f "$workspace/main.py" || -f "$workspace/ComfyUI/main.py" ]]; then
  echo "- ComfyUI workspace already exists; registering without updating it"
  "$comfy_bin" --workspace "$workspace_for_comfy" which >/dev/null 2>&1 || true
else
  "$comfy_bin" --workspace "$workspace_for_comfy" install --version "$comfy_version" --skip-manager --fast-deps
fi

echo "Installed local media toolchain in $workspace"
echo "Launch policy: 127.0.0.1 with --disable-api-nodes; no custom nodes installed."
