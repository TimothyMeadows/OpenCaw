#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
/* CSS art token template (vector/interface focused) */
:root {
  /* Color and stroke */
  --art-color-primary: #1b3a4b;
  --art-color-secondary: #3a86a8;
  --art-color-accent: #f6b73c;
  --art-stroke-thin: 1px;
  --art-stroke-base: 1.5px;
  --art-stroke-strong: 2px;

  /* Size tiers */
  --art-size-16: 16px;
  --art-size-20: 20px;
  --art-size-24: 24px;
  --art-size-32: 32px;
  --art-size-48: 48px;
  --art-size-64: 64px;
  --art-size-128: 128px;

  /* Logo and mark rules */
  --logo-min-size: var(--art-size-24);
  --logo-clear-space: 0.25em;

  /* Depth/elevation */
  --art-depth-base: none;
  --art-depth-raised: 0 1px 2px rgb(0 0 0 / 0.12);
  --art-depth-floating: 0 4px 10px rgb(0 0 0 / 0.16);
  --art-depth-overlay: 0 8px 24px rgb(0 0 0 / 0.2);
}
EOF

echo "Printed CSS art token template."
echo "Use consistent token naming to keep vector art portable across components."
