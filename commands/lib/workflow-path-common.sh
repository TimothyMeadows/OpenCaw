#!/usr/bin/env bash

# Durable delivery state belongs to direct children of the resolved cache.
# Callers source memory-common.sh and resolve the project before using these.
opencaw_workflow_directory() {
  local collection="$1" name="$2" current component
  [[ "$collection" == tasks || "$collection" == goals ]] || {
    opencaw_fail "Unsupported workflow collection: $collection"
    return 1
  }
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
    opencaw_fail "Workflow name must be lowercase kebab-case: $name"
    return 1
  }
  current="$OPENCAW_PROJECT_CACHE_DIR"
  for component in "$collection" "$name"; do
    current+="/$component"
    [[ ! -L "$current" ]] || {
      opencaw_fail "Workflow storage must not be a symbolic link: $current"
      return 1
    }
    [[ ! -e "$current" || -d "$current" ]] || {
      opencaw_fail "Workflow storage is not a directory: $current"
      return 1
    }
  done
  printf '%s\n' "$current"
}

opencaw_workflow_file() {
  local ref="$1" collection="$2" filename="$3" candidate name directory
  if [[ "$ref" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    candidate="$(opencaw_workflow_directory "$collection" "$ref")/$filename" || return 1
  else
    case "$ref" in
      /*) candidate="$ref" ;;
      *) candidate="$OPENCAW_PROJECT_ROOT_RESOLVED/${ref#./}" ;;
    esac
    [[ ! -d "$candidate" ]] || candidate="${candidate%/}/$filename"
  fi
  name="$(basename "$(dirname "$candidate")")"
  directory="$(opencaw_workflow_directory "$collection" "$name")" || return 1
  [[ "$candidate" == "$directory/$filename" ]] || {
    opencaw_fail "Workflow references must resolve to $OPENCAW_PROJECT_CACHE_DIR/$collection/<name>/$filename: $ref"
    return 1
  }
  [[ -f "$candidate" && ! -L "$candidate" ]] || {
    opencaw_fail "Workflow file is missing or is a symbolic link: $candidate"
    return 1
  }
  printf '%s\n' "$candidate"
}
