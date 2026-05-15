# MARKDOWN.md

This repository follows a **GitHub-flavored Markdown architecture** optimized for clear documentation, predictable rendering on GitHub, and maintainable plain-text collaboration.

The architecture is optimized for:

- GitHub Markdown rendering
- reviewable documentation changes
- durable repository knowledge
- readable diffs
- accessible tables, lists, and headings
- docs that work in issues, pull requests, wikis, and repository files

The goal is to keep documentation:

- easy to scan
- easy to review
- stable across GitHub surfaces
- friendly to automation
- useful as source-controlled project knowledge

---

# Core Architecture Rule

**Prefer simple GitHub-flavored Markdown that renders predictably in repository files, issues, pull requests, and comments.**

Prefer:

```text
plain Markdown -> predictable GitHub rendering -> reviewable knowledge
```

Avoid:

```text
HTML-heavy documents -> fragile rendering -> hard-to-review knowledge
```

---

# Document Structure

Markdown documents should use:

- one top-level heading that names the document
- short sections with descriptive headings
- concise paragraphs before dense lists
- tables only when comparison is clearer than prose
- fenced code blocks with language identifiers when practical
- relative links for repository-local files

Suggested layout for durable documentation:

```text
# Document Title

## Purpose

## Scope

## Decisions

## Usage

## Verification

## References
```

---

# GitHub Rendering Rules

Use GitHub-flavored Markdown features intentionally:

- fenced code blocks for commands, config, logs, and examples
- task lists for actionable checklists
- tables for compact matrices and compatibility notes
- blockquotes only for quoted or callout-style context
- relative links for repository files and folders
- autolinks for GitHub issues, pull requests, commits, and users when helpful

Rules:

- include a language identifier on fenced code blocks when known
- keep table cells short enough to review in diffs
- keep checklist items actionable and independently verifiable
- prefer Markdown links over raw URLs when link text improves clarity
- keep headings stable when other documents link to them

---

# Formatting Rules

Markdown should be:

- line-oriented for readable diffs
- concise without losing required context
- explicit about assumptions, commands, and paths
- consistent with nearby repository documentation

Rules:

- use ATX headings with `#`
- use `-` for unordered lists
- use `1.` style for ordered lists
- wrap paths, commands, flags, environment variables, and literal values in backticks
- use fenced code blocks instead of indented code blocks
- separate major sections with headings rather than visual decoration

---

# Accessibility and Review Rules

Documentation should support readers using GitHub previews, plain-text editors, and assistive technology.

Rules:

- write descriptive link text
- avoid empty headings and heading-level jumps
- avoid relying on color, emoji, or visual alignment to carry meaning
- provide text alternatives or captions for images when images carry information
- keep tables simple enough to read on narrow screens
- prefer plain text summaries before long logs or generated output

---

# Repository Knowledge Rules

Use Markdown as source-controlled knowledge, not as a dumping ground.

Durable Markdown should make clear:

- what decision or workflow it captures
- who or what audience it serves
- what commands or files are authoritative
- how the content should be verified or updated

Rules:

- keep generated output clearly labeled
- avoid copying long logs when a short summary and artifact reference is enough
- keep temporary notes in task files rather than permanent docs
- promote only durable, reusable facts into shared memory or architecture files

---

# Anti-Patterns

Never introduce:

- large HTML blocks for ordinary document structure
- heading hierarchies chosen only for visual size
- screenshots as the only source of required procedural information
- tables used for page layout
- hidden assumptions in prose without commands, paths, or references
- massive pasted logs without summary or reason
- link-only sections with no local explanation

---

# Code Generation Rules for Agents

When generating or editing GitHub Markdown:

1. Match the style of nearby documentation.
2. Use GitHub-flavored Markdown features only when they improve clarity.
3. Keep diffs small, line-oriented, and easy to review.
4. Prefer relative repository links for local files.
5. Put commands, paths, environment variables, and literal values in backticks.
6. Use fenced code blocks with language identifiers for examples.
7. Keep durable docs focused on reusable knowledge and move task chatter to task files.

When in doubt:

**Prefer plain, predictable Markdown that renders well on GitHub and remains readable as source text.**
