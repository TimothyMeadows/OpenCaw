#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/build-originality-evidence.sh --subject PATH --reference PATH --output FILE

Builds local similarity evidence from file hashes and normalized text tokens.
The report is evidence for human review, not a legal conclusion.
EOF
}

subject=""
reference=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subject) [[ $# -ge 2 ]] || { echo "--subject requires a path" >&2; exit 1; }; subject="$2"; shift 2 ;;
    --reference) [[ $# -ge 2 ]] || { echo "--reference requires a path" >&2; exit 1; }; reference="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || { echo "--output requires a file" >&2; exit 1; }; output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$subject" && -n "$reference" && -n "$output" ]] || { usage >&2; exit 1; }
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to build originality evidence." >&2; exit 1; }
to_node_path() {
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"; else printf '%s\n' "$1"; fi
}
node_subject="$(to_node_path "$subject")"
node_reference="$(to_node_path "$reference")"
node_output="$(to_node_path "$output")"

"$node_bin" - "$node_subject" "$node_reference" "$node_output" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const [subjectArg, referenceArg, outputArg] = process.argv.slice(2);
for (const [label, value] of [['subject', subjectArg], ['reference', referenceArg]]) {
  if (!fs.existsSync(value)) { console.error(`${label} path does not exist: ${value}`); process.exit(1); }
}
const output = path.resolve(outputArg);
if (!fs.existsSync(path.dirname(output))) { console.error(`Output parent does not exist: ${path.dirname(output)}`); process.exit(1); }
if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) { console.error(`Output file must not be a symbolic link: ${output}`); process.exit(1); }

function inventory(input) {
  const root = fs.realpathSync(input);
  const rootStat = fs.statSync(root);
  const files = [];
  function add(file, relative) {
    if (path.resolve(file) === output) return;
    const stat = fs.statSync(file);
    const buffer = fs.readFileSync(file);
    const binary = buffer.includes(0);
    const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
    let tokens = [];
    if (!binary && stat.size <= 2 * 1024 * 1024) {
      tokens = [...new Set(buffer.toString('utf8').toLowerCase().normalize('NFKC').match(/[\p{L}\p{N}_-]{3,}/gu) || [])].sort();
    }
    files.push({ path: relative.split(path.sep).join('/'), bytes: stat.size, sha256, binary, tokens });
  }
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const absolute = path.join(dir, entry.name);
      const stat = fs.lstatSync(absolute);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) walk(absolute);
      else if (stat.isFile()) add(absolute, path.relative(root, absolute));
    }
  }
  if (rootStat.isDirectory()) walk(root); else add(root, path.basename(root));
  return { root, files };
}

function similarity(left, right) {
  if (!left.tokens.length || !right.tokens.length) return null;
  const a = new Set(left.tokens);
  const b = new Set(right.tokens);
  let intersection = 0;
  for (const token of a) if (b.has(token)) intersection += 1;
  return intersection / (a.size + b.size - intersection);
}

const subject = inventory(subjectArg);
const reference = inventory(referenceArg);
const pairs = [];
for (const left of subject.files) {
  for (const right of reference.files) {
    const score = similarity(left, right);
    const exactHash = left.sha256 === right.sha256;
    if (exactHash || (score !== null && score >= 0.15)) pairs.push({ subject: left.path, reference: right.path, exactHash, tokenJaccard: score === null ? null : Number(score.toFixed(4)) });
  }
}
pairs.sort((a, b) => Number(b.exactHash) - Number(a.exactHash) || (b.tokenJaccard || 0) - (a.tokenJaccard || 0) || a.subject.localeCompare(b.subject) || a.reference.localeCompare(b.reference));

const lines = [
  '# Originality Evidence', '',
  '> This report records mechanical similarity evidence for human review. It does not determine authorship, ownership, infringement, or legal status.', '',
  '## Scope', '',
  `- Subject: \`${subject.root.replace(/`/g, '')}\``,
  `- Reference: \`${reference.root.replace(/`/g, '')}\``,
  `- Subject files: ${subject.files.length}`,
  `- Reference files: ${reference.files.length}`, '',
  '## Method', '',
  '- Exact evidence uses SHA-256 equality.',
  '- Text similarity uses Jaccard overlap across unique normalized tokens of three or more characters.',
  '- Symbolic links, binary text extraction, and files over two mebibytes are excluded from token comparison.', '',
  '## Similarity Evidence', ''
];
if (!pairs.length) lines.push('No exact hashes or token-overlap pairs at or above 0.15 were found.');
else {
  lines.push('| Subject | Reference | Exact hash | Token Jaccard |', '| --- | --- | ---: | ---: |');
  for (const pair of pairs) lines.push(`| \`${pair.subject.replace(/`/g, '')}\` | \`${pair.reference.replace(/`/g, '')}\` | ${pair.exactHash ? 'yes' : 'no'} | ${pair.tokenJaccard === null ? 'n/a' : pair.tokenJaccard.toFixed(4)} |`);
}
lines.push('', '## Review Limits', '', '- Common terminology and short technical phrases can raise token overlap without indicating copied expression.', '- Low token overlap does not prove independent creation.', '- Review distinctive structure, examples, assets, and provenance separately.', '');
fs.writeFileSync(output, `${lines.join('\n')}\n`, 'utf8');
NODE
