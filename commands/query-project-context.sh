#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./commands/query-project-context.sh --list-tags
  ./commands/query-project-context.sh --tags "area:<area>,tech:<tech>" [--match ranked|any|all] [--limit 25]
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

tags=''
match='ranked'
limit=25
list_tags='false'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags)
      tags="${2:-}"
      shift 2
      ;;
    --match)
      match="${2:-}"
      shift 2
      ;;
    --limit)
      limit="${2:-}"
      shift 2
      ;;
    --list-tags)
      list_tags='true'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ "$match" =~ ^(ranked|any|all)$ ]] || { echo "Invalid match mode: $match" >&2; exit 1; }
[[ "$limit" =~ ^[1-9][0-9]*$ ]] || { echo 'Limit must be a positive integer.' >&2; exit 1; }

opencaw_resolve_paths

files=()
labels=()
if [[ -f "$OPENCAW_PROJECT_MEMORY_FILE" ]]; then
  files+=("$OPENCAW_PROJECT_MEMORY_FILE")
  labels+=('memory')
fi
if [[ -f "$OPENCAW_REPO_MAP_FILE" ]]; then
  files+=("$OPENCAW_REPO_MAP_FILE")
  labels+=('repo-map')
fi

if [[ "$list_tags" == 'true' ]]; then
  if [[ ${#files[@]} -eq 0 ]]; then
    exit 0
  fi
  awk '
    /^-[[:space:]]+\[/ {
      line = $0
      sub(/^-[[:space:]]+/, "", line)
      while (match(line, /^\[[^]]+\][[:space:]]*/)) {
        tag = substr(line, 2, index(line, "]") - 2)
        count[tag]++
        line = substr(line, RLENGTH + 1)
      }
    }
    END { for (tag in count) print tag, count[tag] }
  ' "${files[@]}" | LC_ALL=C sort
  exit 0
fi

[[ -n "$tags" ]] || { usage >&2; exit 1; }

IFS=',' read -r -a requested_tags <<< "$tags"
for requested_tag in "${requested_tags[@]}"; do
  requested_tag="${requested_tag#"${requested_tag%%[![:space:]]*}"}"
  requested_tag="${requested_tag%"${requested_tag##*[![:space:]]}"}"
  [[ "$requested_tag" =~ ^(kind|area|tech|env|topic|scope):[a-z0-9]+(-[a-z0-9]+)*$ ]] \
    || { echo "Invalid query tag: $requested_tag" >&2; exit 1; }
done

temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
records="$temp_dir/records.tsv"

for index in "${!files[@]}"; do
  awk -v wanted_csv="$tags" -v mode="$match" -v source="${labels[$index]}" '
    BEGIN {
      wanted_count = split(wanted_csv, wanted_values, ",")
      for (i = 1; i <= wanted_count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", wanted_values[i])
        wanted[wanted_values[i]] = 1
      }
    }
    /^-[[:space:]]+\[/ {
      original = $0
      line = $0
      sub(/^-[[:space:]]+/, "", line)
      score = 0
      core = 0
      delete present

      while (match(line, /^\[[^]]+\][[:space:]]*/)) {
        tag = substr(line, 2, index(line, "]") - 2)
        present[tag] = 1
        if (tag == "scope:core") core = 1
        if (tag in wanted) score++
        line = substr(line, RLENGTH + 1)
      }

      matches_all = 1
      for (tag in wanted) if (!(tag in present)) matches_all = 0
      include = core || (mode == "all" ? matches_all : score > 0)
      if (include) printf "%d\t%d\t%s\t%s\n", core, score, source, original
    }
  ' "${files[$index]}" >> "$records"
done

echo '# Relevant Project Context'
echo
if [[ -s "$records" ]]; then
  awk -F '\t' '$1 == 1 { print "[" $3 "] " $4 }' "$records"

  if [[ "$match" == 'ranked' ]]; then
    awk -F '\t' '$1 == 0 { print $2 "\t" NR "\t[" $3 "] " $4 }' "$records" \
      | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2n \
      | head -n "$limit" \
      | cut -f3-
  else
    awk -F '\t' '$1 == 0 { print "[" $3 "] " $4 }' "$records" | head -n "$limit"
  fi
else
  echo '- none'
fi
