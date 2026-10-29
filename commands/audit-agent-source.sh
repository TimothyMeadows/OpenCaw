#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/audit-agent-source.sh <source-dir> [--output FILE] [--fail-on LEVEL]

Statically audits an untrusted agent source tree without executing its contents.
LEVEL is one of: critical, high, medium, low, none. The default is none.
EOF
}

source_dir="${1:-}"
if [[ -z "$source_dir" || "$source_dir" == "-h" || "$source_dir" == "--help" ]]; then
  usage
  [[ -z "$source_dir" ]] && exit 1 || exit 0
fi
shift

output_file=""
fail_on="none"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a file" >&2; exit 1; }
      output_file="$2"
      shift 2
      ;;
    --fail-on)
      [[ $# -ge 2 ]] || { echo "--fail-on requires a level" >&2; exit 1; }
      fail_on="$2"
      shift 2
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

case "$fail_on" in
  critical|high|medium|low|none) ;;
  *) echo "Invalid --fail-on level: $fail_on" >&2; exit 1 ;;
esac

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for static auditing." >&2; exit 1; }
to_node_path() {
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"; else printf '%s\n' "$1"; fi
}
node_source_dir="$(to_node_path "$source_dir")"
node_output_file=""
if [[ -n "$output_file" ]]; then node_output_file="$(to_node_path "$output_file")"; fi

"$node_bin" - "$node_source_dir" "$node_output_file" "$fail_on" <<'NODE'
const fs = require('fs');
const path = require('path');

const sourceArg = process.argv[2];
const outputArg = process.argv[3];
const failOn = process.argv[4];

if (!fs.existsSync(sourceArg) || !fs.lstatSync(sourceArg).isDirectory()) {
  console.error(`Source directory does not exist: ${sourceArg}`);
  process.exit(1);
}

const sourceRoot = fs.realpathSync(sourceArg);
let outputPath = '';
if (outputArg) {
  outputPath = path.resolve(outputArg);
  const parent = path.dirname(outputPath);
  if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) {
    console.error(`Output parent does not exist: ${parent}`);
    process.exit(1);
  }
  if (fs.existsSync(outputPath) && fs.lstatSync(outputPath).isSymbolicLink()) {
    console.error(`Output file must not be a symbolic link: ${outputPath}`);
    process.exit(1);
  }
}

const findings = [];
let fileCount = 0;
let directoryCount = 0;
let skippedBinaryCount = 0;

function add(severity, code, file, line, evidence, risk) {
  const redacted = String(evidence || '')
    .replace(/(?:gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|(?:api[_-]?key|token|secret|password)\s*[:=]\s*[^\s]+)/gi, '[REDACTED]')
    .slice(0, 220);
  findings.push({ severity, code, file, line, evidence: redacted, risk });
}

const rules = [
  ['critical', 'embedded-private-key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i, 'A private key marker is embedded in source.'],
  ['high', 'credential-like-value', /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b/i, 'A credential-shaped value may be exposed.'],
  ['high', 'destructive-command', /\b(?:rm\s+-rf|Remove-Item\s+[^\n]*-Recurse|format\s+[A-Za-z]:|drop\s+(?:database|table))\b/i, 'The content includes a destructive operation.'],
  ['high', 'remote-execution-pipeline', /(?:curl|wget|Invoke-WebRequest)[^\n|;]*(?:\||;)[^\n]*(?:sh|bash|pwsh|powershell)\b/i, 'Remote content appears to be piped into an interpreter.'],
  ['high', 'automatic-external-mutation', /\b(?:automatically|silently|without (?:asking|confirmation|approval))[^\n]{0,80}\b(?:publish|post|deploy|send|invite|refund|cancel)\b/i, 'The instruction may perform an external mutation without a human gate.'],
  ['medium', 'prompt-control-language', /\b(?:ignore|override|disregard)\b[^\n]{0,60}\b(?:previous|prior|system|developer|safety)\b[^\n]{0,40}\b(?:instruction|message|rule|prompt)s?\b/i, 'Prompt-control language may attempt to redirect an agent.'],
  ['medium', 'absolute-personal-path', /(?:\b[A-Za-z]:[\\/]Users[\\/][^\\/\s]+|\/(?:Users|home)\/[^/\s]+)/i, 'A personal absolute path reduces portability and may reveal identity.'],
  ['medium', 'account-operation', /\b(?:send (?:an )?email|issue (?:a )?refund|cancel (?:the )?subscription|invite (?:a )?(?:user|member)|social (?:media )?post|account-bound voice)\b/i, 'The instruction performs an excluded account-bound operation.'],
  ['low', 'remote-resource', /https?:\/\/[^\s)>'"]+/i, 'A remote resource requires provenance and trust review.']
];

function inspectFile(absolutePath, relativePath, stat) {
  fileCount += 1;
  if ((stat.mode & 0o111) !== 0 || /\.(?:sh|bash|zsh|fish|ps1|bat|cmd|exe|dll|so|dylib|jar|com|msi)$/i.test(relativePath)) {
    add('high', 'executable-content', relativePath, null, 'executable file or extension', 'Executable content must not be trusted or run during review.');
  }
  if (stat.size > 2 * 1024 * 1024) {
    add('low', 'large-file-not-inspected', relativePath, null, `${stat.size} bytes`, 'Large content was inventoried but not scanned as text.');
    return;
  }
  const buffer = fs.readFileSync(absolutePath);
  if (buffer.includes(0)) {
    skippedBinaryCount += 1;
    add('low', 'binary-content', relativePath, null, `${stat.size} bytes`, 'Binary content requires separate provenance and malware review.');
    return;
  }
  const lines = buffer.toString('utf8').split(/\r?\n/);
  lines.forEach((line, index) => {
    for (const [severity, code, expression, risk] of rules) {
      if (expression.test(line)) add(severity, code, relativePath, index + 1, line.trim(), risk);
    }
  });
}

function walk(directory) {
  directoryCount += 1;
  const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    if (entry.name === '.git') continue;
    const absolutePath = path.join(directory, entry.name);
    const relativePath = path.relative(sourceRoot, absolutePath).split(path.sep).join('/');
    if (entry.isSymbolicLink()) {
      let destination = '[unreadable]';
      try { destination = fs.readlinkSync(absolutePath); } catch {}
      add('high', 'symbolic-link', relativePath, null, destination, 'Symbolic links can escape the reviewed source boundary.');
      continue;
    }
    let stat;
    try { stat = fs.lstatSync(absolutePath); }
    catch (error) {
      if (error && error.code === 'EISDIR') {
        add('high', 'symbolic-link', relativePath, null, '[cross-runtime link]', 'A link-like entry could not be resolved safely across the runtime boundary.');
        continue;
      }
      add('medium', 'unreadable-entry', relativePath, null, error.code || 'read error', 'An unreadable entry could not be included in the static inspection.');
      continue;
    }
    if (stat.isSymbolicLink()) {
      let destination = '[unreadable]';
      try { destination = fs.readlinkSync(absolutePath); } catch {}
      add('high', 'symbolic-link', relativePath, null, destination, 'Symbolic links can escape the reviewed source boundary.');
      continue;
    }
    if (stat.isDirectory()) walk(absolutePath);
    else if (stat.isFile()) inspectFile(absolutePath, relativePath, stat);
    else add('medium', 'special-file', relativePath, null, entry.name, 'Special files are outside the static text-audit model.');
  }
}

walk(sourceRoot);
const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
findings.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity] || a.file.localeCompare(b.file) || (a.line || 0) - (b.line || 0) || a.code.localeCompare(b.code));
const counts = { critical: 0, high: 0, medium: 0, low: 0 };
for (const finding of findings) counts[finding.severity] += 1;
const report = {
  schema: 'opencaw-agent-source-audit/v1',
  source: sourceRoot,
  inspection: 'static-only',
  summary: { directories: directoryCount, files: fileCount, skippedBinaryFiles: skippedBinaryCount, findings: findings.length, bySeverity: counts },
  limitations: [
    'Static inspection does not establish author intent or runtime safety.',
    'Binary files and files larger than two mebibytes are inventoried but not content-scanned.',
    'Detected credential-like values are redacted from evidence.'
  ],
  findings
};
const serialized = `${JSON.stringify(report, null, 2)}\n`;
if (outputPath) fs.writeFileSync(outputPath, serialized, { encoding: 'utf8', flag: 'w' });
else process.stdout.write(serialized);

if (failOn !== 'none') {
  const threshold = severityOrder[failOn];
  if (findings.some(finding => severityOrder[finding.severity] <= threshold)) process.exitCode = 2;
}
NODE
