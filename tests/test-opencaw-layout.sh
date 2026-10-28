#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$(mktemp -d "$repo_root/tests/.layout-runtime-XXXXXX")"
cleanup() {
  case "$runtime_dir" in "$repo_root"/tests/.layout-runtime-*) rm -rf -- "$runtime_dir" ;; esac
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local output="$1"; shift
  if "$@" >"$output" 2>&1; then fail "accepted invalid install/cache operation: $*"; fi
}
copy_runtime() {
  local destination="$1"
  mkdir -p "$destination/commands/lib"
  cp "$repo_root/commands/lib/memory-common.sh" "$destination/commands/lib/"
  cp "$repo_root/commands/lib/platform-common.sh" "$destination/commands/lib/"
  cp "$repo_root/commands/resolve-opencaw-paths.sh" "$destination/commands/"
  cp "$repo_root/commands/create-host-ai-scaffold.sh" "$destination/commands/"
  cp "$repo_root/.gitignore" "$destination/"
  printf '# Controlled baseline instructions\n' > "$destination/AGENTS.md"
}
project="$runtime_dir/project"
mkdir -p "$project"
git -C "$project" init -q
copy_runtime "$project/.opencaw"
printf '# Host instructions\nKeep this project-specific content.\n' > "$project/AGENTS.md"

echo '[1/6] fixed installed root, independent of working directory'
selection="$(env -u OPENCAW_PROJECT_ROOT bash "$project/.opencaw/commands/resolve-opencaw-paths.sh")"
grep -Fq "OPENCAW_PROJECT_ROOT=$project" <<< "$selection" || fail 'wrong host parent'
grep -Fq "OPENCAW_INSTALL_DIR=$project/.opencaw" <<< "$selection" || fail 'wrong install folder'
grep -Fq "OPENCAW_PROJECT_CACHE_DIR=$project/.opencaw/.cache" <<< "$selection" || fail 'wrong cache'
if grep -q 'OPENCAW_PROJECT_AI_DIR=' <<< "$selection"; then fail 'retired public path alias exposed'; fi
expect_failure "$runtime_dir/root-conflict.log" env OPENCAW_PROJECT_ROOT="$runtime_dir" bash "$project/.opencaw/commands/resolve-opencaw-paths.sh"
grep -Fq 'direct parent' "$runtime_dir/root-conflict.log" || fail 'root mismatch lacks guidance'

echo '[2/6] idempotent fresh scaffold and one bootstrap source'
env -u OPENCAW_PROJECT_ROOT bash "$project/.opencaw/commands/create-host-ai-scaffold.sh" > "$runtime_dir/scaffold.log"
cache="$project/.opencaw/.cache"
for file in SYSTEM_MEMORY MEMORY REPO_MAP RULES DEBUG; do [[ -f "$cache/$file.md" ]] || fail "missing cache $file"; done
for folder in tasks goals gauntlets archive reports; do [[ -d "$cache/$folder" ]] || fail "missing $folder"; done
grep -Fq 'Keep this project-specific content.' "$project/AGENTS.md" || fail 'host content overwritten'
grep -Fq './.opencaw/AGENTS.md' "$project/AGENTS.md" || fail 'bootstrap missing canonical source'
if grep -Eq '\.codex|\.claude|\.cursor|Fallback|Preferred baseline locations' "$project/AGENTS.md"; then fail 'bootstrap advertises alternate source'; fi
before="$(sha256sum "$project/AGENTS.md" "$cache/SYSTEM_MEMORY.md" "$cache/MEMORY.md")"
env -u OPENCAW_PROJECT_ROOT bash "$project/.opencaw/commands/create-host-ai-scaffold.sh" >/dev/null
[[ "$before" == "$(sha256sum "$project/AGENTS.md" "$cache/SYSTEM_MEMORY.md" "$cache/MEMORY.md")" ]] || fail 'scaffold is not idempotent'
[[ "$(grep -c 'OPENCAW_BOOTSTRAP_START' "$project/AGENTS.md")" -eq 1 ]] || fail 'duplicated bootstrap'
[[ ! -e "$project/.ai" && ! -e "$runtime_dir/.opencaw/.cache" ]] || fail 'state escaped canonical cache'

echo '[3/6] retired and arbitrary nested installation folders rejected'
for name in .codex .claude .cursor OpenCaw baseline-copy; do
  bad_project="$runtime_dir/rejected-${name//./}"
  mkdir -p "$bad_project"
  git -C "$bad_project" init -q
  copy_runtime "$bad_project/$name"
  # Even a nested independent checkout cannot turn a wrong mount into a source checkout.
  git -C "$bad_project/$name" init -q
  expect_failure "$runtime_dir/rejected.log" env -u OPENCAW_PROJECT_ROOT bash "$bad_project/$name/commands/create-host-ai-scaffold.sh"
  grep -Fq '.opencaw' "$runtime_dir/rejected.log" || fail 'invalid install lacks canonical guidance'
  [[ ! -e "$bad_project/AGENTS.md" && ! -e "$bad_project/.opencaw/.cache" ]] || fail 'invalid install wrote host state'
done

echo '[4/6] existing .ai is ignored, never imported or modified'
legacy="$runtime_dir/retired-state"
mkdir -p "$legacy/.ai"
copy_runtime "$legacy/.opencaw"
printf 'Old location must not be loaded.\n' > "$legacy/.ai/MEMORY.md"
old_hash="$(sha256sum "$legacy/.ai/MEMORY.md")"
env -u OPENCAW_PROJECT_ROOT bash "$legacy/.opencaw/commands/create-host-ai-scaffold.sh" >/dev/null
[[ "$old_hash" == "$(sha256sum "$legacy/.ai/MEMORY.md")" ]] || fail 'old state was modified'
if grep -Fq 'Old location' "$legacy/.opencaw/.cache/MEMORY.md"; then fail 'old state was imported'; fi

echo '[5/6] ignored cache and real-directory boundaries'
git -C "$project/.opencaw" init -q
git -C "$project/.opencaw" check-ignore -q .cache/MEMORY.md || fail 'cache would pollute baseline Git'
git -C "$repo_root" check-ignore -q .opencaw/.cache/MEMORY.md || fail 'maintainer cache is not ignored'
collision="$runtime_dir/collision"
mkdir -p "$collision"
copy_runtime "$collision/.opencaw"
printf 'collision\n' > "$collision/.opencaw/.cache"
expect_failure "$runtime_dir/collision.log" env -u OPENCAW_PROJECT_ROOT bash "$collision/.opencaw/commands/create-host-ai-scaffold.sh"
[[ ! -e "$collision/AGENTS.md" ]] || fail 'collision wrote bootstrap before validation'
linked="$runtime_dir/linked-cache"
mkdir -p "$linked" "$runtime_dir/outside-cache"
copy_runtime "$linked/.opencaw"
if ln -s "$runtime_dir/outside-cache" "$linked/.opencaw/.cache" 2>/dev/null; then
  expect_failure "$runtime_dir/link.log" env -u OPENCAW_PROJECT_ROOT bash "$linked/.opencaw/commands/create-host-ai-scaffold.sh"
  [[ ! -e "$runtime_dir/outside-cache/SYSTEM_MEMORY.md" && ! -e "$linked/AGENTS.md" ]] || fail 'symlink escaped cache guard'
else
  echo 'SKIP: symlink creation unavailable; run under a capable host for link confinement evidence.'
fi
printf 'Outside sentinel must remain unchanged.\n' > "$runtime_dir/outside-file.md"
sentinel_hash="$(sha256sum "$runtime_dir/outside-file.md")"
for linked_target in tasks tasks/example-task SYSTEM_MEMORY.md host-AGENTS; do
  unsafe="$runtime_dir/unsafe-${linked_target//\//-}"
  mkdir -p "$unsafe"
  copy_runtime "$unsafe/.opencaw"
  mkdir -p "$unsafe/.opencaw/.cache"
  case "$linked_target" in
    tasks) target="$unsafe/.opencaw/.cache/tasks"; source="$runtime_dir/outside-cache" ;;
    tasks/example-task) mkdir -p "$unsafe/.opencaw/.cache/tasks"; target="$unsafe/.opencaw/.cache/tasks/example-task"; source="$runtime_dir/outside-cache" ;;
    SYSTEM_MEMORY.md) target="$unsafe/.opencaw/.cache/SYSTEM_MEMORY.md"; source="$runtime_dir/outside-file.md" ;;
    host-AGENTS) target="$unsafe/AGENTS.md"; source="$runtime_dir/outside-file.md" ;;
  esac
  if ln -s "$source" "$target" 2>/dev/null; then
    expect_failure "$runtime_dir/descendant-link.log" env -u OPENCAW_PROJECT_ROOT bash "$unsafe/.opencaw/commands/create-host-ai-scaffold.sh"
    [[ "$sentinel_hash" == "$(sha256sum "$runtime_dir/outside-file.md")" ]] || fail 'linked file was changed'
    [[ ! -e "$runtime_dir/outside-cache/TODO.md" && ! -e "$runtime_dir/outside-cache/TASK.md" ]] || fail 'linked task directory was written'
    [[ ! -e "$unsafe/.opencaw/.cache/MEMORY.md" ]] || fail 'scaffold wrote state before descendant preflight'
    if [[ "$linked_target" != host-AGENTS ]]; then [[ ! -e "$unsafe/AGENTS.md" ]] || fail 'host bootstrap preceded descendant validation'; fi
  else
    echo "SKIP: descendant link fixture unavailable for $linked_target"
  fi
done

echo '[6/6] installed commands run from inside the baseline without nesting caches'
(cd "$project/.opencaw" && env -u OPENCAW_PROJECT_ROOT bash commands/create-host-ai-scaffold.sh >/dev/null)
[[ ! -d "$project/.opencaw/.opencaw" ]] || fail 'nested installation/cache created'
echo 'Fixed OpenCaw install/cache layout tests passed.'
