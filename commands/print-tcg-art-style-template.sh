#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
# TCG Art Style Brief

## Target Style
- Primary style: warm-tavern-fantasy
- Secondary style traits:
- Audience:
- Gameplay fantasy:
- Reference cues:
  - Use named games only for broad genre cues.
  - Do not copy proprietary frames, boards, logos, characters, icons, or exact layouts.

## Card Frame Direction
- Card type(s):
- Frame materials:
- Art window:
- Cost/resource treatment:
- Rarity treatment:
- Title/rules readability:
- Card back:
- Hand-size thumbnail rules:
- Playable/disabled/selected states:

## Board Zones
- Player hand:
- Opponent hand:
- Battlefield/token zone:
- Deck/library:
- Discard/graveyard:
- Exile/banish/void:
- Secrets/traps/attachments:
- Player and opponent state:
- Turn/phase/action prompt:

## Hand, Deck, Graveyard Rules
- Cards in hand remain fanned, countable, and hover/readable.
- Deck/library and discard/graveyard piles use distinct silhouettes, tilt, color, and count badges.
- Graveyard/discard state must support inspection without blocking board state.
- Hidden opponent cards use a clear card-back treatment without revealing art or text.

## Token / Minion Visual Rules
- Token silhouette:
- Ownership marker:
- Base shape:
- Attack/health/counter treatment:
- Status markers:
- Summoned/ready/exhausted/damaged/dead states:
- Small-size readability rule:

## VFX And Readability Checks
- Summon:
- Attack/block:
- Damage/heal:
- Death/discard/graveyard:
- Reveal/secret trigger:
- Targeting:
- VFX must not hide card counts, targeting states, prompts, or token stats.
- Do not rely on color alone for ownership or status.

## IP-Safety Constraints
- Original frame geometry, board composition, symbols, tokens, and card backs.
- No copied commercial card frames, boards, logos, characters, factions, icons, or exact UI layouts.
- No in-image protected game names or marks.
- Named games may guide only mood, materials, readability, and broad interaction patterns.
EOF

echo
echo "Printed reusable TCG art style brief template."
