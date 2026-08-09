#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local output_file="$1"
  shift
  set +e
  "$@" >"$output_file" 2>&1
  local result=$?
  set -e
  [[ $result -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}

new_project() {
  local name="$1"
  local project="$temp_root/$name"
  mkdir -p "$project"
  git -C "$project" init -q
  printf 'fixture\n' > "$project/app.txt"
  git -C "$project" add app.txt
  printf '%s\n' "$project"
}

run_for() {
  local project="$1"
  shift
  OPENCAW_PROJECT_ROOT="$project" "$@"
}

copy_resolver_runtime() {
  local target="$1"
  mkdir -p "$target/commands/lib"
  cp commands/resolve-opencaw-paths.sh "$target/commands/resolve-opencaw-paths.sh"
  cp commands/lib/memory-common.sh "$target/commands/lib/memory-common.sh"
  chmod +x "$target/commands/resolve-opencaw-paths.sh"
}

echo '[1/9] resolving safe project boundaries'
explicit_project="$(new_project explicit-project)"
explicit_output="$(OPENCAW_PROJECT_ROOT="$explicit_project" OPENCAW_HOME="$temp_root/ignored-home" bash commands/resolve-opencaw-paths.sh)"
grep -Fq "OPENCAW_PROJECT_ROOT=$explicit_project" <<< "$explicit_output" || fail 'explicit project root was not used'
grep -Fq "SYSTEM_MEMORY_FILE=$explicit_project/.ai/SYSTEM_MEMORY.md" <<< "$explicit_output" || fail 'system memory did not resolve under the project .ai directory'
! grep -q '^OPENCAW_HOME=' <<< "$explicit_output" || fail 'deprecated global memory home was exposed'

mounted_project="$temp_root/mounted-project"
mkdir -p "$mounted_project"
copy_resolver_runtime "$mounted_project/.codex"
mounted_output="$(bash "$mounted_project/.codex/commands/resolve-opencaw-paths.sh")"
grep -Fq "OPENCAW_PROJECT_ROOT=$mounted_project" <<< "$mounted_output" || fail 'recognized mount parent was not resolved'

standalone_parent="$temp_root/standalone-parent"
standalone_root="$standalone_parent/OpenCaw"
mkdir -p "$standalone_root" "$standalone_parent/sibling"
copy_resolver_runtime "$standalone_root"
git -C "$standalone_root" init -q
git -C "$standalone_parent/sibling" init -q
standalone_output="$(bash "$standalone_root/commands/resolve-opencaw-paths.sh")"
grep -Fq "OPENCAW_PROJECT_ROOT=$standalone_root" <<< "$standalone_output" || fail 'standalone checkout escaped to sibling workspace'

ambiguous_root="$temp_root/ambiguous/tools"
copy_resolver_runtime "$ambiguous_root"
expect_failure "$temp_root/ambiguous.log" env -u OPENCAW_PROJECT_ROOT bash "$ambiguous_root/commands/resolve-opencaw-paths.sh"
grep -q 'Unable to resolve a safe project root' "$temp_root/ambiguous.log" || fail 'ambiguous root did not fail closed'

echo '[2/9] creating an idempotent Memory v2 scaffold'
project="$(new_project primary-project)"
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
run_for "$project" bash commands/create-task-file.sh boundary-task 'Boundary task' --no-issue >/dev/null
[[ -f "$project/.ai/SYSTEM_MEMORY.md" ]] || fail 'repository-local system memory was not created'
[[ -f "$project/.ai/MEMORY.md" && -f "$project/.ai/REPO_MAP.md" ]] || fail 'project memory files were not created'
[[ -f "$project/.ai/tasks/boundary-task/TASK.md" ]] || fail 'task command did not honor the resolved project root'
[[ ! -e "$temp_root/.ai/tasks/boundary-task/TASK.md" ]] || fail 'task command escaped into the workspace parent'
[[ ! -d "$project/.ai/FRAGMENTS" && ! -d "$project/.ai/LEARNINGS" ]] || fail 'legacy fragment stores were created'
[[ "$(grep -c 'Never store passwords' "$project/.ai/SYSTEM_MEMORY.md")" -eq 1 ]] || fail 'protected defaults were duplicated'
[[ ! -e "$temp_root/ignored-home/SYSTEM_MEMORY.md" ]] || fail 'OPENCAW_HOME redirected system memory outside the repository'

echo '[3/9] validating safe tagged writes and replacement'
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:workflow,area:auth,tech:dotnet' --entry 'Run focused authentication tests before the full suite.' >/dev/null
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:workflow,area:auth,tech:dotnet' --entry 'Run focused authentication tests before the full suite.' >/dev/null
[[ "$(grep -c 'Run focused authentication tests' "$project/.ai/MEMORY.md")" -eq 1 ]] || fail 'duplicate project memory was appended'
expect_failure "$temp_root/untagged.log" run_for "$project" bash commands/append-project-memory.sh --entry 'untagged'
expect_failure "$temp_root/invalid-tag.log" run_for "$project" bash commands/append-project-memory.sh --tags 'kind:workflow,Auth' --entry 'invalid tags'
expect_failure "$temp_root/secret.log" run_for "$project" bash commands/append-system-memory.sh --entry 'api_key=do-not-store-this-value'
expect_failure "$temp_root/project-secret.log" run_for "$project" bash commands/append-project-memory.sh --tags 'kind:environment,topic:security' --entry 'access_token=do-not-store-this-value'
expect_failure "$temp_root/personal-path.log" run_for "$project" bash commands/append-system-memory.sh --entry 'Use C:\Users\someone\private\tool.exe.'
run_for "$project" bash commands/append-system-memory.sh --entry 'Bash and Git are available to OpenCaw commands.' >/dev/null
awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$project/.ai/MEMORY.md" > "$project/.ai/MEMORY.md.tmp"
mv "$project/.ai/MEMORY.md.tmp" "$project/.ai/MEMORY.md"
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:workflow,area:auth,tech:dotnet' --entry 'Run the authentication smoke tests first.' --replace 'Run focused authentication tests before the full suite.' >/dev/null
run_for "$project" bash commands/append-rules.sh 'Fixture preventive rule.' >/dev/null
run_for "$project" bash commands/append-debug.sh 'Fixture debug resolution.' >/dev/null
! grep -q 'Run focused authentication tests' "$project/.ai/MEMORY.md" || fail 'replaced fact remained active'
grep -q 'Run the authentication smoke tests first' "$project/.ai/MEMORY.md" || fail 'replacement fact was not stored'
grep -q 'Fixture preventive rule' "$project/.ai/RULES.md" || fail 'rule append failed for a leading-hyphen format'
grep -q 'Fixture debug resolution' "$project/.ai/DEBUG.md" || fail 'debug append failed for a leading-hyphen format'
find "$project/.ai/archive/memory" -name 'MEMORY-replace-*.md' | grep -q . || fail 'replacement was not archived'

echo '[4/9] retrieving ranked relevant context'
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:gotcha,area:billing,tech:dotnet' --entry 'Billing fixture fact.' >/dev/null
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:convention,scope:core' --entry 'Core fixture fact.' >/dev/null
printf '%s\n' '- [kind:component] [area:auth] `src/Auth` owns authentication.' >> "$project/.ai/REPO_MAP.md"
query_output="$(run_for "$project" bash commands/query-project-context.sh --tags 'area:auth,tech:dotnet' --limit 1)"
grep -q 'Core fixture fact' <<< "$query_output" || fail 'core context was not always loaded'
grep -q 'authentication smoke tests' <<< "$query_output" || fail 'highest-ranked relevant memory was not returned'
! grep -q 'Billing fixture fact' <<< "$query_output" || fail 'unrelated memory polluted context'
tags_output="$(run_for "$project" bash commands/query-project-context.sh --list-tags)"
grep -q '^area:auth ' <<< "$tags_output" || fail 'tag catalog omitted project tags'
expect_failure "$temp_root/invalid-query-tag.log" run_for "$project" bash commands/query-project-context.sh --tags 'Auth'

echo '[5/9] purging exact categories with archives'
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:gotcha,area:legacy' --entry 'Legacy category fact.' >/dev/null
run_for "$project" bash commands/append-project-memory.sh --tags 'kind:gotcha,area:legacy-extra' --entry 'Similar category fact.' >/dev/null
run_for "$project" bash commands/purge-project-memory.sh --tag 'area:legacy' --dry-run >/dev/null 2>&1
grep -q 'Legacy category fact' "$project/.ai/MEMORY.md" || fail 'dry-run changed memory'
run_for "$project" bash commands/purge-project-memory.sh --tag 'area:legacy' >/dev/null 2>&1
! grep -q 'Legacy category fact' "$project/.ai/MEMORY.md" || fail 'exact-tag purge did not remove target'
grep -q 'Similar category fact' "$project/.ai/MEMORY.md" || fail 'exact-tag purge removed a similar tag'
find "$project/.ai/archive/memory" -name 'MEMORY-purge-area-legacy-*.md' | grep -q . || fail 'purge archive was not created'

echo '[6/9] detecting semantic repository-map staleness'
run_for "$project" bash commands/repo-map-status.sh --stamp >/dev/null
grep -q 'REPO_MAP_STATUS=CURRENT' < <(run_for "$project" bash commands/repo-map-status.sh) || fail 'stamped map was not current'
awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$project/.ai/REPO_MAP.md" > "$project/.ai/REPO_MAP.md.tmp"
mv "$project/.ai/REPO_MAP.md.tmp" "$project/.ai/REPO_MAP.md"
grep -q 'REPO_MAP_STATUS=CURRENT' < <(run_for "$project" bash commands/repo-map-status.sh) || fail 'CRLF repository-map marker was not recognized'
printf 'content-only change\n' >> "$project/app.txt"
grep -q 'REPO_MAP_STATUS=CURRENT' < <(run_for "$project" bash commands/repo-map-status.sh) || fail 'content-only edit made map stale'
printf 'new tracked path\n' > "$project/new-component.txt"
git -C "$project" add new-component.txt
grep -q 'REPO_MAP_STATUS=STALE' < <(run_for "$project" bash commands/repo-map-status.sh) || fail 'tracked path addition did not make map stale'
run_for "$project" bash commands/repo-map-status.sh --stamp >/dev/null
grep -q 'REPO_MAP_STATUS=CURRENT' < <(run_for "$project" bash commands/repo-map-status.sh) || fail 'CRLF repository map could not be restamped'

echo '[7/9] applying complete AI-classified migration'
migration_project="$(new_project migration-project)"
mkdir -p "$migration_project/.ai/FRAGMENTS" "$migration_project/.ai/LEARNINGS"
printf '# Project Memory\n\n- Bash is available on this machine.\n- The dependency audit is required before installation.\n- api_key=legacy-value-that-must-not-be-copied\n' > "$migration_project/.ai/MEMORY.md"
printf '# Conventions\n\n- Commands use strict Bash mode.\n' > "$migration_project/.ai/FRAGMENTS/conventions.md"
printf '# Repository Map\n\n- `commands/` contains deterministic execution scripts.\n' > "$migration_project/.ai/FRAGMENTS/repo-map.md"
printf '# Bugs\n\n- Path translation can fail across WSL and Windows executables.\n' > "$migration_project/.ai/LEARNINGS/bugs.md"
prepare_output="$(run_for "$migration_project" bash commands/migrate-memory-v2.sh --prepare)"
grep -q 'MIGRATION_CANDIDATES=6' <<< "$prepare_output" || fail 'migration did not inventory every legacy entry'
! grep -q 'legacy-value-that-must-not-be-copied' "$migration_project/.ai/migrations/memory-v2-candidates.tsv" || fail 'migration manifest copied a legacy secret value'
classification="$temp_root/classification.tsv"
printf '0001\tsystem\t-\n0002\tmemory\tkind:dependency,topic:dependency-audit\n0003\tarchive\tcredential-shaped legacy value\n0004\tmemory\tkind:convention,tech:bash\n0005\trepo-map\tkind:component,area:commands\n0006\tmemory\tkind:bug,env:wsl,env:windows\n' > "$classification"
incomplete="$temp_root/incomplete.tsv"
head -n 5 "$classification" > "$incomplete"
expect_failure "$temp_root/incomplete.log" run_for "$migration_project" bash commands/migrate-memory-v2.sh --apply "$incomplete"
run_for "$migration_project" bash commands/migrate-memory-v2.sh --apply "$classification" >/dev/null
grep -q 'Bash is available on this machine' "$migration_project/.ai/SYSTEM_MEMORY.md" || fail 'repository-local system migration route failed'
grep -q '\[kind:dependency\].*dependency audit' "$migration_project/.ai/MEMORY.md" || fail 'project migration route failed'
grep -q '\[kind:component\].*commands/' "$migration_project/.ai/REPO_MAP.md" || fail 'repository-map migration route failed'
[[ ! -d "$migration_project/.ai/FRAGMENTS" && ! -d "$migration_project/.ai/LEARNINGS" ]] || fail 'legacy stores were not retired'
find "$migration_project/.ai/archive/memory-v1" -type f | grep -q . || fail 'legacy sources were not archived'
find "$migration_project/.ai/archive/memory-v1" -name 'classification-*.tsv' | grep -q . || fail 'applied migration classification was not archived'

echo '[8/9] validating and summarizing without arbitrary memory excerpts'
run_for "$project" bash commands/repo-map-status.sh --stamp >/dev/null
run_for "$project" bash commands/validate-memory.sh >/dev/null
run_for "$migration_project" bash commands/validate-memory.sh >/dev/null
run_for "$project" bash commands/summarize-memory.sh >/dev/null
grep -q '## Tag Catalog' "$project/.ai/CONTEXT_SUMMARY.md" || fail 'summary omitted tag inventory'
! grep -q 'Billing fixture fact' "$project/.ai/CONTEXT_SUMMARY.md" || fail 'summary copied arbitrary memory content'
printf '\n1. [x] Boundary task (`.ai/tasks/boundary-task/TASK.md`)\n' >> "$project/.ai/tasks/TODO.md"
printf '# Boundary task\r\n\r\n## Status\r\nArchived on 20260725T000000Z.\r\n' > "$project/.ai/tasks/boundary-task/TASK.md"
cleanup_preview="$(run_for "$project" bash commands/clean-context.sh --dry-run)"
grep -q '^TASK_FILES_COMPACTED=0$' <<< "$cleanup_preview" || fail 'clean-context did not recognize an archived CRLF task'

echo '[9/9] checking command syntax and repository validation hooks'
fake_gh_dir="$temp_root/fake-gh"
fake_gh_log="$temp_root/fake-gh.log"
fake_path_conversion_log="$temp_root/fake-path-conversion.log"
fake_qa_summary="$temp_root/fake-qa-summary.md"
host_cygpath="$(command -v cygpath 2>/dev/null || true)"
mkdir -p "$fake_gh_dir"
cat > "$fake_gh_dir/gh.exe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == 'pr view' ]]; then
  echo 'https://github.com/example/project/pull/73'
  exit 0
fi
if [[ "${1:-} ${2:-}" == 'pr comment' ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == '--body-file' ]]; then
      printf '%s\n' "${2:-}" > "$OPENCAW_TEST_GH_LOG"
      echo 'https://github.com/example/project/pull/73#issuecomment-7301'
      exit 0
    fi
    shift
  done
fi
exit 1
EOF
chmod +x "$fake_gh_dir/gh.exe"
if [[ -n "$host_cygpath" ]]; then
  cat > "$fake_gh_dir/cygpath" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$OPENCAW_TEST_PATH_CONVERSION_LOG"
exec "$OPENCAW_TEST_REAL_CYGPATH" "$@"
EOF
  chmod +x "$fake_gh_dir/cygpath"
fi
printf '# QA\n\nPASS\n' > "$fake_qa_summary"
PATH="$fake_gh_dir:$PATH" run_for "$project" bash commands/comment-pr-qa-results.sh --help >/dev/null
qa_comment_output="$(PATH="$fake_gh_dir:$PATH" OPENCAW_TEST_GH_LOG="$fake_gh_log" OPENCAW_TEST_PATH_CONVERSION_LOG="$fake_path_conversion_log" OPENCAW_TEST_REAL_CYGPATH="$host_cygpath" run_for "$project" bash commands/comment-pr-qa-results.sh 73 "$fake_qa_summary")"
if [[ -n "$host_cygpath" ]]; then
  grep -Eq '^-w /' "$fake_path_conversion_log" || fail 'Git Bash gh.exe body path did not pass through cygpath'
  grep -Eq '^(/|[A-Za-z]:\\|\\\\)' "$fake_gh_log" || fail 'Git Bash gh.exe did not receive an absolute body-file path'
else
  grep -Eq '^([A-Za-z]:\\|\\\\)' "$fake_gh_log" || fail 'Windows gh.exe did not receive a translated body-file path'
fi
grep -Fq 'COMMENT_URL=https://github.com/example/project/pull/73#issuecomment-7301' <<< "$qa_comment_output" || fail 'PR QA helper did not return the durable GitHub comment URL'
bash -n commands/lib/memory-common.sh commands/*memory*.sh commands/query-project-context.sh commands/repo-map-status.sh commands/resolve-opencaw-paths.sh
bash commands/validate-commands.sh >/dev/null
bash commands/validate-skills.sh >/dev/null

echo 'Memory v2 tests passed.'
