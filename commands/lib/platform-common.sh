#!/usr/bin/env bash

# Shared host-platform helpers. Commands sourcing this file must enable strict mode.

opencaw_is_windows_host() {
  local kernel="${1:-}"
  local version_text="${2:-}"

  [[ -n "$kernel" ]] || kernel="$(uname -s 2>/dev/null || true)"
  if [[ -z "$version_text" && -r /proc/version ]]; then
    version_text="$(< /proc/version)"
  fi

  case "$kernel" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac

  [[ -n "${WSL_INTEROP:-}" || "$version_text" =~ [Mm]icrosoft ]]
}
