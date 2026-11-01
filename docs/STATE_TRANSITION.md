# Hephaera local-state transition

New installations use only `<project>/.hephaera/`; fresh installs without legacy state work normally. Legacy `.opencaw/.cache/` remains a read-only historical source during the rename. It is not a fallback cache and is never imported automatically.

```bash
bash .hephaera/commands/state-transition.sh inspect
bash .hephaera/commands/state-transition.sh prepare
```

`inspect` reads only bounded bootstrap and filesystem metadata. `prepare` explicitly creates `.hephaera/.cache/STATE_TRANSITION.json` when legacy state is detected; it does not move, copy or alter legacy state. Repeated preparation never overwrites an existing marker. A marker remains a fence even if the legacy directory disappears or its marker contents are malformed. There is no force, clear or automatic-adoption option.

Read-only discovery remains available. Before creating a second canonical cache beside legacy state, explicitly run `prepare`; local tasks created with `--no-issue` and memory maintenance then remain available without granting production authority. Legacy state or a persistent fence blocks native production, explicit provisioning/model loading and media promotion. New task issue writes are blocked by an unresolved marker, an old managed root bootstrap, or that task's legacy directory. Old operation hashes and published markers are not regenerated under the new brand.

Before scaffolding an installed host, an existing legacy managed root `AGENTS.md` bootstrap must be explicitly reviewed and migrated. The scaffold refuses it before writes rather than append a second managed directive. Merely having historical cache data does not make new memory files execution authority.

Preserve original task/Gauntlet checkpoints, journals, generation manifests, claims, consent and installation receipts byte-for-byte. A cache move changes paths; changed contracts and implementation hashes invalidate affected execution/review evidence. Renaming a path or refreshing a hash is not approval. Original candidate/revision consumption must remain bound to its actual approval and shared ledger. Never remove the old ignore protection before the historical data is safely ignored at its destination.

Any later migration needs a separately reviewed exact source/destination plan, quiescent workers and locks, no links/collisions, preservation checks and explicit handling of original shared approval roots. Relocated virtual environments and absolute-path installation receipts are not declared ready by these tools. New registration, execution scope and affected human reviews must be verified without rewriting old grants or resetting budgets.

These filesystem checks are cooperative safeguards, not an operating-system sandbox. They do not authorize installation, generation, external publication, disclosure or asset promotion.
