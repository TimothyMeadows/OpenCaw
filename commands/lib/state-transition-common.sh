#!/usr/bin/env bash

# Explicit legacy-state boundary, intentionally independent of Node/Python.
hephaera_transition_check_paths() {
  local transition_root="$1" transition_path
  [[ -d "$transition_root" && ! -L "$transition_root" ]] || { echo 'State transition root must be a real directory.' >&2; return 1; }
  for transition_path in "$transition_root/.opencaw" "$transition_root/.opencaw/.cache" "$transition_root/.hephaera" "$transition_root/.hephaera/.cache"; do
    [[ ! -L "$transition_path" ]] || { echo 'State transition paths must not traverse symbolic links.' >&2; return 1; }
    [[ ! -e "$transition_path" || -d "$transition_path" ]] || { echo 'State transition directory collides with another file type.' >&2; return 1; }
  done
  for transition_path in "$transition_root/AGENTS.md" "$transition_root/.hephaera/.cache/STATE_TRANSITION.json"; do
    [[ ! -L "$transition_path" ]] || { echo 'State transition metadata must not be a symbolic link.' >&2; return 1; }
    [[ ! -e "$transition_path" || -f "$transition_path" ]] || { echo 'State transition metadata must be a regular file.' >&2; return 1; }
  done
}

hephaera_transition_has_legacy_bootstrap() {
  local transition_root="$1"
  [[ -f "$transition_root/AGENTS.md" ]] && grep -Eq '<!--[[:space:]]*OPENCAW_BOOTSTRAP_(START|END)[[:space:]]*-->' "$transition_root/AGENTS.md"
}

hephaera_transition_assert_bootstrap_allowed() {
  local transition_root="$1"
  hephaera_transition_check_paths "$transition_root" || return 1
  if hephaera_transition_has_legacy_bootstrap "$transition_root"; then
    echo 'Legacy managed AGENTS bootstrap must be migrated explicitly before Hephaera scaffolding; no second bootstrap was appended.' >&2
    return 1
  fi
  hephaera_transition_assert_local_state_prepared "$transition_root"
}

hephaera_transition_assert_local_state_prepared() {
  local transition_root="$1"
  hephaera_transition_check_paths "$transition_root" || return 1
  if [[ ! -e "$transition_root/.hephaera/.cache/STATE_TRANSITION.json" ]]; then
    if [[ -d "$transition_root/.opencaw/.cache" ]] || hephaera_transition_has_legacy_bootstrap "$transition_root"; then
      echo 'Prepare the state transition explicitly before creating canonical local state: state-transition.sh prepare.' >&2
      return 1
    fi
  fi
}

hephaera_transition_assert_production_allowed() {
  local transition_root="$1" transition_operation="${2:-production}"
  hephaera_transition_check_paths "$transition_root" || return 1
  if [[ -d "$transition_root/.opencaw/.cache" || -e "$transition_root/.hephaera/.cache/STATE_TRANSITION.json" ]] || hephaera_transition_has_legacy_bootstrap "$transition_root"; then
    echo "State transition blocks $transition_operation; inspect and review preserved legacy state. No old approval, ledger or receipt was rebound." >&2
    return 1
  fi
}
