#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/playwright-capture-page.sh --url URL --output PATH [--full-page] [--viewport WxH] [--reduced-motion reduce|no-preference]

Captures a page to PNG using an already installed Playwright package and browser.
The output must remain inside the current repository. No dependency is installed.
EOF
}

url=""
output=""
full_page="false"
viewport="1440x900"
reduced_motion="reduce"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) [[ $# -ge 2 ]] || { echo "--url requires a value" >&2; exit 1; }; url="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 1; }; output="$2"; shift 2 ;;
    --full-page) full_page="true"; shift ;;
    --viewport) [[ $# -ge 2 ]] || { echo "--viewport requires WxH" >&2; exit 1; }; viewport="$2"; shift 2 ;;
    --reduced-motion) [[ $# -ge 2 ]] || { echo "--reduced-motion requires a value" >&2; exit 1; }; reduced_motion="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$url" && -n "$output" ]] || { usage >&2; exit 1; }
[[ "$viewport" =~ ^([1-9][0-9]{0,4})x([1-9][0-9]{0,4})$ ]] || { echo "Invalid viewport '$viewport'; expected WxH." >&2; exit 1; }
width="${BASH_REMATCH[1]}"
height="${BASH_REMATCH[2]}"
(( width <= 10000 && height <= 10000 )) || { echo "Viewport dimensions must not exceed 10000." >&2; exit 1; }
[[ "$reduced_motion" == "reduce" || "$reduced_motion" == "no-preference" ]] || { echo "Invalid reduced-motion value: $reduced_motion" >&2; exit 1; }
[[ "$url" =~ ^https?:// ]] || { echo "Only http:// and https:// URLs are supported." >&2; exit 1; }
[[ "${output,,}" == *.png ]] || { echo "Output must use a .png extension." >&2; exit 1; }
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for page capture." >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
playwright_root="${OPENCAW_PLAYWRIGHT_ROOT:-$repo_root}"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  repo_root="$(wslpath -w "$repo_root")"
  output="$(wslpath -w "$output")"
  case "$playwright_root" in
    [A-Za-z]:\\*|\\\\*) ;;
    *) playwright_root="$(wslpath -w "$playwright_root")" ;;
  esac
fi
"$node_bin" - "$repo_root" "$url" "$output" "$full_page" "$width" "$height" "$reduced_motion" "$playwright_root" <<'NODE'
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const [repoArg, url, outputArg, fullPageArg, widthArg, heightArg, reducedMotion, playwrightRootArg] = process.argv.slice(2);
const repoRoot = fs.realpathSync(repoArg);
const output = path.resolve(outputArg);
const relative = path.relative(repoRoot, output);
if (relative.startsWith('..') || path.isAbsolute(relative)) {
  console.error(`Output must remain inside repository root: ${repoRoot}`);
  process.exit(1);
}
if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) {
  console.error(`Output file must not be a symbolic link: ${output}`);
  process.exit(1);
}
let existingAncestor = path.dirname(output);
while (!fs.existsSync(existingAncestor)) {
  const parent = path.dirname(existingAncestor);
  if (parent === existingAncestor) break;
  existingAncestor = parent;
}
const realAncestor = fs.realpathSync(existingAncestor);
const ancestorRelative = path.relative(repoRoot, realAncestor);
if (ancestorRelative.startsWith('..') || path.isAbsolute(ancestorRelative)) {
  console.error(`Output parent resolves outside repository root: ${realAncestor}`);
  process.exit(1);
}
fs.mkdirSync(path.dirname(output), { recursive: true });
const realParent = fs.realpathSync(path.dirname(output));
const parentRelative = path.relative(repoRoot, realParent);
if (parentRelative.startsWith('..') || path.isAbsolute(parentRelative)) {
  console.error(`Output parent resolves outside repository root: ${realParent}`);
  process.exit(1);
}

let playwright;
try {
  const dependencyRoot = fs.realpathSync(playwrightRootArg);
  const requireFromRepo = createRequire(path.join(dependencyRoot, '__opencaw_loader__.js'));
  playwright = requireFromRepo('playwright');
} catch {
  console.error('Playwright is not installed for this repository. Install it through the host architecture before capture.');
  process.exit(1);
}

(async () => {
  let browser;
  try {
    browser = await playwright.chromium.launch({ headless: true });
    const context = await browser.newContext({
      viewport: { width: Number(widthArg), height: Number(heightArg) },
      reducedMotion,
      serviceWorkers: 'block'
    });
    const page = await context.newPage();
    const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    if (!response) throw new Error('Navigation produced no HTTP response.');
    if (response.status() >= 400) throw new Error(`Navigation failed with HTTP ${response.status()}.`);
    await page.screenshot({ path: output, fullPage: fullPageArg === 'true', animations: 'disabled' });
    await context.close();
    console.log(`Captured ${url} to ${output}`);
  } catch (error) {
    console.error(`Page capture failed: ${error.message}`);
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close();
  }
})();
NODE
