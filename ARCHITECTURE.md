# ARCHITECTURE.md

This file is the canonical architecture contract for this repository.

Generated from OpenCaw architecture templates:
- MARKDOWN
- DOTNET

---

This document intentionally stays concise by referencing selected templates.

## Read Template Instructions

Read `./.architecture/MARKDOWN.md` instructions
Read `./.architecture/DOTNET.md` instructions

Add repository-specific architecture instructions below these read directives.


## Native asset orchestration

The runtime under `commands/lib/proof-to-model/` targets .NET 10. Keep domain rules independent of application orchestration, infrastructure adapters, and CLI transport. Dependencies point inward; the CLI composes application services and infrastructure. Native subprocess execution is bounded, cancellable, logged, and repository-confined, but is not an OS sandbox. No web/API framework, Docker daemon, Bubo checkout, AssetForge, AssetFurnace, or sibling project is a runtime requirement. Source-derived code retains attribution and import receipts.
