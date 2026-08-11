#!/usr/bin/env bash

external_asset_library_fail() {
  echo "$*" >&2
  return 1
}

external_asset_library_validate_id() {
  local value="$1"
  [[ "$value" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || {
    external_asset_library_fail "External asset library id must use 1-63 lowercase letters, digits, or hyphens: $value"
    return 1
  }
}

external_asset_library_validate_path() {
  local value="$1"
  local normalized

  [[ -n "$value" ]] || { external_asset_library_fail 'External asset library path must not be empty.'; return 1; }
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *'`'* ]] || {
    external_asset_library_fail 'External asset library path contains a prohibited control character or backtick.'
    return 1
  }
  [[ "$value" == "${value# }" && "$value" == "${value% }" ]] || {
    external_asset_library_fail 'External asset library path must not start or end with whitespace.'
    return 1
  }
  [[ "$value" != *'://'* ]] || { external_asset_library_fail 'External asset libraries must be filesystem paths, not URLs.'; return 1; }

  if [[ "$value" == /* ]]; then
    [[ "$value" != '/' ]] || { external_asset_library_fail 'A filesystem root cannot be an external asset library.'; return 1; }
  elif [[ "$value" =~ ^[A-Za-z]:[\\/].+ ]]; then
    :
  elif [[ "$value" =~ ^\\\\[^\\/]+[\\/][^\\/]+[\\/].+ ]]; then
    :
  else
    external_asset_library_fail "External asset library path must be an absolute POSIX, Windows drive, or UNC path: $value"
    return 1
  fi

  normalized="${value//\\//}"
  [[ "/$normalized/" != *'/../'* ]] || {
    external_asset_library_fail 'External asset library path must not contain parent traversal.'
    return 1
  }
  [[ "/$normalized/" != *'/./'* ]] || {
    external_asset_library_fail 'External asset library path must not contain current-directory segments.'
    return 1
  }
}

external_asset_library_parse_spec() {
  local raw="$1"
  [[ "$raw" == *=* ]] || { external_asset_library_fail 'Use --asset-library ID=ABSOLUTE_PATH.'; return 1; }
  EXTERNAL_ASSET_LIBRARY_ID="${raw%%=*}"
  EXTERNAL_ASSET_LIBRARY_PATH="${raw#*=}"
  external_asset_library_validate_id "$EXTERNAL_ASSET_LIBRARY_ID"
  external_asset_library_validate_path "$EXTERNAL_ASSET_LIBRARY_PATH"
}

external_asset_library_entries() {
  local style_file="$1"
  local line section=0

  [[ -f "$style_file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == '## External Asset Libraries' ]]; then
      section=1
      continue
    fi
    if [[ $section -eq 1 && "$line" == \#* ]]; then
      break
    fi
    [[ $section -eq 1 && "$line" == '- '* ]] || continue
    if [[ "$line" =~ ^-\ ([a-z0-9][a-z0-9-]{0,62}):\ \`([^\`]*)\`$ ]]; then
      printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
      external_asset_library_fail "Malformed external asset library entry in $style_file: $line"
      return 1
    fi
  done < "$style_file"
}

external_asset_library_get_path() {
  local style_file="$1" expected_id="$2"
  local id path
  while IFS=$'\t' read -r id path; do
    [[ "$id" == "$expected_id" ]] || continue
    printf '%s\n' "$path"
    return 0
  done < <(external_asset_library_entries "$style_file")
  external_asset_library_fail "External asset library is not configured in STYLE.md: $expected_id"
  return 1
}

external_asset_library_path_for_node() {
  local value="$1" node_bin="$2"
  if [[ "$node_bin" == *.exe ]]; then
    if [[ "$value" =~ ^[A-Za-z]:[\\/] || "$value" =~ ^\\\\ ]]; then
      printf '%s\n' "$value"
    elif command -v wslpath >/dev/null 2>&1; then
      wslpath -w "$value"
    elif command -v cygpath >/dev/null 2>&1; then
      cygpath -w "$value"
    else
      external_asset_library_fail "Cannot translate POSIX path for Windows Node.js: $value"
      return 1
    fi
  else
    if [[ "$value" =~ ^[A-Za-z]:[\\/] || "$value" =~ ^\\\\ ]]; then
      if command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$value"
      else
        external_asset_library_fail "Configured Windows library path is unavailable to native Node.js: $value"
        return 1
      fi
    else
      printf '%s\n' "$value"
    fi
  fi
}

external_asset_library_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  fi
}
