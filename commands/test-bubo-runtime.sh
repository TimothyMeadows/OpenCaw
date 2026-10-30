#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  host) project='Bubo.Host.Tests/Bubo.Host.Tests' ;;
  proof-to-model) project='runtime/proof-to-model/Tests/RuntimeTests' ;;
  model-to-animation) project='runtime/model-to-animation/Tests/RuntimeTests' ;;
  model-to-action) project='runtime/model-to-action/Tests/RuntimeTests' ;;
  media) project='media/Tests/Media.Tests' ;;
  *) echo 'Use test-bubo-runtime.sh host|proof-to-model|model-to-animation|model-to-action|media [Release|Debug]. Explicitly build Bubo first.' >&2; exit 1 ;;
esac
configuration="${2:-Release}"
[[ "$configuration" == Release || "$configuration" == Debug ]] || { echo 'Invalid build configuration.' >&2; exit 1; }
node "$command_dir/lib/bubo-runtime.cjs" verify >/dev/null
dependency="$(node -e 'process.stdout.write(require(process.argv[1]).dependency().root.replace(/\\/g,"/"))' "$command_dir/lib/bubo-runtime.cjs")"
project_directory="${project%/*}"; assembly="${project##*/}"
test_dll="$dependency/src/$project_directory/bin/$configuration/net10.0/$assembly.dll"
[[ -f "$test_dll" ]] || { echo 'Bubo executable tests are not built. Run build-bubo-runtime.sh explicitly.' >&2; exit 1; }
test_app="${test_dll%.dll}"
if [[ "${OS:-}" == Windows_NT ]]; then test_app+='.exe'; fi
[[ -f "$test_app" ]] || { echo 'The built Bubo test apphost is unavailable. Rebuild explicitly; tests relaunch their own apphost.' >&2; exit 1; }
cd "$dependency"
mkdir -p .bubo/test-temp
export TEMP="$dependency/.bubo/test-temp" TMP="$dependency/.bubo/test-temp" TMPDIR="$dependency/.bubo/test-temp"
exec "$test_app"
