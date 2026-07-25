#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-skill-safety.sh [skill-dir]

Validates one skill directory, or every skill under ./skills when omitted.
EOF
}

skill_input="${1:-./skills}"
if [[ "$skill_input" == "-h" || "$skill_input" == "--help" ]]; then
  usage
  exit 0
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for skill safety validation." >&2; exit 1; }
node_skill_input="$skill_input"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_skill_input="$(wslpath -w "$skill_input")"; fi

"$node_bin" - "$node_skill_input" <<'NODE'
const fs = require('fs');
const path = require('path');

const input = path.resolve(process.argv[2]);
if (!fs.existsSync(input) || !fs.statSync(input).isDirectory()) {
  console.error(`Skill directory does not exist: ${process.argv[2]}`);
  process.exit(1);
}

const directSkill = fs.existsSync(path.join(input, 'SKILL.md'));
const skillDirs = directSkill
  ? [input]
  : fs.readdirSync(input, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && fs.existsSync(path.join(input, entry.name, 'SKILL.md')))
      .map(entry => path.join(input, entry.name))
      .sort();

const errors = [];
function error(skill, message) { errors.push(`${path.basename(skill)}: ${message}`); }
function inside(root, candidate) { const rel = path.relative(root, candidate); return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel)); }

for (const skillDir of skillDirs) {
  const expectedName = path.basename(skillDir);
  const skillFile = path.join(skillDir, 'SKILL.md');
  const skillText = fs.readFileSync(skillFile, 'utf8');
  const frontmatter = skillText.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n/);
  if (!frontmatter) {
    error(skillDir, 'SKILL.md has no YAML frontmatter');
    continue;
  }
  const nameMatch = frontmatter[1].match(/^name:\s*['"]?([^'"\r\n]+)['"]?\s*$/m);
  const declaredName = nameMatch ? nameMatch[1].trim() : '';
  if (declaredName !== expectedName) error(skillDir, `frontmatter name '${declaredName}' does not match folder '${expectedName}'`);

  const agentsFile = path.join(skillDir, 'agents', 'openai.yaml');
  if (!fs.existsSync(agentsFile)) {
    error(skillDir, 'missing required agents/openai.yaml interface metadata');
  } else {
    const metadata = fs.readFileSync(agentsFile, 'utf8');
    const promptMatch = metadata.match(/^\s*default_prompt:\s*["']([^"']*)["']\s*$/m);
    const displayMatch = metadata.match(/^\s*display_name:\s*["']([^"']+)["']\s*$/m);
    const shortMatch = metadata.match(/^\s*short_description:\s*["']([^"']+)["']\s*$/m);
    if (!displayMatch || !shortMatch || !promptMatch) error(skillDir, 'agents/openai.yaml is missing required interface metadata');
    else {
      if (!promptMatch[1].includes(`$${expectedName}`)) error(skillDir, `default_prompt must reference $${expectedName}`);
      if (displayMatch[1].trim().length === 0 || displayMatch[1].length > 64) error(skillDir, 'display_name must be between 1 and 64 characters');
      const normalizedDisplay = displayMatch[1].toLowerCase().replace(/[^a-z0-9]/g, '');
      const normalizedSkill = expectedName.toLowerCase().replace(/[^a-z0-9]/g, '');
      if (normalizedDisplay !== normalizedSkill) error(skillDir, `display_name '${displayMatch[1]}' does not match skill '${expectedName}'`);
      if (shortMatch[1].trim().length < 10 || shortMatch[1].length > 80) error(skillDir, 'short_description must be between 10 and 80 characters');
    }
  }

  const entries = [];
  function walk(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      const relative = path.relative(skillDir, absolute).split(path.sep).join('/');
      if (entry.isSymbolicLink()) {
        error(skillDir, `symbolic links are not allowed: ${relative}`);
        continue;
      }
      let stat;
      try { stat = fs.lstatSync(absolute); }
      catch (readError) {
        if (readError && readError.code === 'EISDIR') error(skillDir, `symbolic or cross-runtime links are not allowed: ${relative}`);
        else error(skillDir, `unreadable entry is not allowed: ${relative}`);
        continue;
      }
      if (stat.isSymbolicLink()) {
        error(skillDir, `symbolic links are not allowed: ${relative}`);
      } else if (stat.isDirectory()) {
        walk(absolute);
      } else if (stat.isFile()) {
        entries.push({ absolute, relative, stat });
      }
    }
  }
  walk(skillDir);

  for (const { absolute, relative, stat } of entries) {
    if ((stat.mode & 0o111) !== 0 || /\.(?:sh|bash|zsh|fish|ps1|bat|cmd|exe|com|msi|dll|so|dylib|jar)$/i.test(relative)) {
      error(skillDir, `executable helpers are not allowed: ${relative}`);
    }
    if (stat.size > 2 * 1024 * 1024) continue;
    const buffer = fs.readFileSync(absolute);
    if (buffer.includes(0)) continue;
    const text = buffer.toString('utf8');
    const lines = text.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (/(?:\b[A-Za-z]:[\\/]Users[\\/][^\\/\s]+|\/(?:Users|home)\/[^/\s]+)/i.test(line)) error(skillDir, `${relative}:${index + 1} contains an absolute personal path`);
      if (/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b/i.test(line) || /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i.test(line)) error(skillDir, `${relative}:${index + 1} contains a credential-like value`);
      if (/\b(?:automatically|silently|without (?:asking|confirmation|approval))[^\n]{0,80}\b(?:publish|deploy|release|send (?:an )?email|post to social)\b/i.test(line)) error(skillDir, `${relative}:${index + 1} contains an automatic external publishing instruction`);
      const excludedOperation = /\b(?:send (?:an )?email|issue (?:a )?refund|cancel (?:a |the )?(?:subscription|service)|invite (?:a )?(?:user|member)|(?:create|delete|modify|update) (?:a )?(?:customer )?account|billing mutation|social (?:media )?(?:post|impersonation)|account-bound voice generation)\b/i;
      if (excludedOperation.test(line) && !/\b(?:do not|never|must not|excluded|prohibited)\b/i.test(line)) error(skillDir, `${relative}:${index + 1} contains an excluded account operation`);
      if (/^\s*(?:required[- ]vendor|vendor[- ]requirement)\s*:\s*(?!none\b|host-selected\b|architecture-selected\b).+/i.test(line)) error(skillDir, `${relative}:${index + 1} contains an unapproved vendor requirement`);
    });
  }

  const markdownLink = /\]\(([^)]+)\)/g;
  let link;
  while ((link = markdownLink.exec(skillText)) !== null) {
    let target = link[1].trim().replace(/^<|>$/g, '').split('#')[0];
    if (!target || /^(?:https?:|mailto:|#)/i.test(target)) continue;
    try { target = decodeURIComponent(target); } catch {}
    const resolved = path.resolve(skillDir, target.replace(/\\/g, path.sep));
    if (!inside(skillDir, resolved)) error(skillDir, `resource link escapes the skill folder: ${link[1]}`);
    else if (!fs.existsSync(resolved)) error(skillDir, `resource link does not exist: ${link[1]}`);
  }
}

if (skillDirs.length === 0) errors.push(`No SKILL.md files found below ${process.argv[2]}`);
if (errors.length) {
  errors.sort().forEach(message => console.error(message));
  process.exit(1);
}
console.log(`Skill safety validation passed for ${skillDirs.length} skill(s).`);
NODE
