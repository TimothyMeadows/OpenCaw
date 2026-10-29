#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/render-browser-demo.sh --manifest FILE --output FILE

Renders local image frames described by JSON into a GIF, MP4, or WebM file.
Requires existing ffmpeg and ffprobe executables; installs nothing and performs no capture.
EOF
}

manifest=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) [[ $# -ge 2 ]] || { echo "--manifest requires a file" >&2; exit 1; }; manifest="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || { echo "--output requires a file" >&2; exit 1; }; output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$manifest" && -n "$output" ]] || { usage >&2; exit 1; }
[[ -f "$manifest" ]] || { echo "Manifest does not exist: $manifest" >&2; exit 1; }
case "${output,,}" in *.gif|*.mp4|*.webm) ;; *) echo "Output must be .gif, .mp4, or .webm." >&2; exit 1 ;; esac
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
ffmpeg_bin="$(command -v ffmpeg 2>/dev/null || command -v ffmpeg.exe 2>/dev/null || true)"
ffprobe_bin="$(command -v ffprobe 2>/dev/null || command -v ffprobe.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for manifest validation." >&2; exit 1; }
[[ -n "$ffmpeg_bin" ]] || { echo "ffmpeg is required but was not found; install it through the host architecture." >&2; exit 1; }
[[ -n "$ffprobe_bin" ]] || { echo "ffprobe is required but was not found; install it through the host architecture." >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
settings_file="$temp_dir/settings.txt"
concat_file="$temp_dir/frames.ffconcat"

if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  repo_root="$(wslpath -w "$repo_root")"
  manifest="$(wslpath -w "$manifest")"
  output="$(wslpath -w "$output")"
  settings_file="$(wslpath -w "$settings_file")"
  concat_file="$(wslpath -w "$concat_file")"
fi

"$node_bin" - "$repo_root" "$manifest" "$output" "$settings_file" "$concat_file" <<'NODE'
const fs = require('fs');
const path = require('path');

const [repoArg, manifestArg, outputArg, settingsFile, concatFile] = process.argv.slice(2);
const repoRoot = fs.realpathSync(repoArg);
const manifestPath = fs.realpathSync(manifestArg);
const manifestRoot = path.dirname(manifestPath);
const output = path.resolve(outputArg);
function inside(root, value) { const rel = path.relative(root, value); return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel)); }
if (!inside(repoRoot, output)) { console.error(`Output must remain inside repository root: ${repoRoot}`); process.exit(1); }
if (/[\r\n]/.test(output)) { console.error('Output path must not contain line breaks.'); process.exit(1); }
if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) { console.error(`Output file must not be a symbolic link: ${output}`); process.exit(1); }
let existingAncestor = path.dirname(output);
while (!fs.existsSync(existingAncestor)) {
  const parent = path.dirname(existingAncestor);
  if (parent === existingAncestor) break;
  existingAncestor = parent;
}
if (!inside(repoRoot, fs.realpathSync(existingAncestor))) { console.error('Output parent resolves outside the repository root.'); process.exit(1); }
fs.mkdirSync(path.dirname(output), { recursive: true });
if (!inside(repoRoot, fs.realpathSync(path.dirname(output)))) { console.error('Output parent resolves outside the repository root.'); process.exit(1); }

let data;
try { data = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
catch (error) { console.error(`Malformed manifest JSON: ${error.message}`); process.exit(1); }
if (!Number.isInteger(data.width) || data.width < 1 || data.width > 8192) { console.error('Manifest width must be an integer from 1 to 8192.'); process.exit(1); }
if (!Number.isInteger(data.height) || data.height < 1 || data.height > 8192) { console.error('Manifest height must be an integer from 1 to 8192.'); process.exit(1); }
if (!Number.isFinite(data.fps) || data.fps < 1 || data.fps > 120) { console.error('Manifest fps must be from 1 to 120.'); process.exit(1); }
if (!Array.isArray(data.frames) || data.frames.length < 1 || data.frames.length > 10000) { console.error('Manifest frames must contain 1 to 10000 entries.'); process.exit(1); }

const concat = ['ffconcat version 1.0'];
let totalDuration = 0;
let lastPath = '';
for (const [index, frame] of data.frames.entries()) {
  if (!frame || typeof frame.path !== 'string' || !Number.isFinite(frame.duration) || frame.duration <= 0 || frame.duration > 60) {
    console.error(`Frame ${index} requires a local path and duration from 0 to 60 seconds.`);
    process.exit(1);
  }
  const candidate = path.resolve(manifestRoot, frame.path);
  if (/[\r\n]/.test(frame.path)) { console.error(`Frame ${index} path contains a line break.`); process.exit(1); }
  if (!inside(manifestRoot, candidate) || !fs.existsSync(candidate) || !fs.statSync(candidate).isFile()) {
    console.error(`Frame ${index} is missing or escapes the manifest directory: ${frame.path}`);
    process.exit(1);
  }
  const real = fs.realpathSync(candidate);
  if (!inside(manifestRoot, real)) { console.error(`Frame ${index} resolves outside the manifest directory.`); process.exit(1); }
  const portable = real.replace(/\\/g, '/').replace(/'/g, "'\\''");
  concat.push(`file '${portable}'`, `duration ${frame.duration}`);
  totalDuration += frame.duration;
  lastPath = portable;
}
concat.push(`file '${lastPath}'`);
fs.writeFileSync(concatFile, `${concat.join('\n')}\n`, 'utf8');
fs.writeFileSync(settingsFile, `${[`WIDTH=${data.width}`, `HEIGHT=${data.height}`, `FPS=${data.fps}`, `DURATION=${totalDuration}`, `OUTPUT=${output}`].join('\n')}\n`, 'utf8');
NODE

while IFS='=' read -r key value; do
  case "$key" in
    WIDTH) width="$value" ;;
    HEIGHT) height="$value" ;;
    FPS) fps="$value" ;;
    DURATION) duration="$value" ;;
    OUTPUT) resolved_output="$value" ;;
  esac
done < <(if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then cat "$(wslpath -u "$settings_file")"; else cat "$settings_file"; fi)

video_filter="fps=${fps},scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:color=black"
"$ffmpeg_bin" -hide_banner -loglevel error -y -f concat -safe 0 -i "$concat_file" -t "$duration" -vf "$video_filter" "$resolved_output"
"$ffprobe_bin" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$resolved_output" >/dev/null
printf 'Rendered %s seconds at %sx%s and %s fps to %s\n' "$duration" "$width" "$height" "$fps" "$resolved_output"
