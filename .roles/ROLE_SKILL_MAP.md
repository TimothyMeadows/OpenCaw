# Role Capability Map

This file is generated from `.roles/ROLE_SKILL_MAP.json`. Edit the canonical JSON and regenerate this file.

Role mappings use domain-qualified identifiers. Shared capabilities apply after each role-specific mapping.

## Shared Capabilities

### Skills

- `create-task-file`
- `manage-task-issues`
- `maintain-memory`
- `maintain-repository-map`
- `clean-context`
- `pr-readiness-gate`
- `link-pr-to-task-issue`
- `post-pr-qa`
- `record-correction-pattern`
- `record-debug-resolution`
- `verify-and-explain`

### Commands

- `commands/create-task-file.sh`
- `commands/create-task-issue.sh`
- `commands/import-task-from-issue.sh`
- `commands/sync-task-issues.sh`
- `commands/resolve-opencaw-paths.sh`
- `commands/install-windows-bash.ps1`
- `commands/query-project-context.sh`
- `commands/append-project-memory.sh`
- `commands/append-system-memory.sh`
- `commands/repo-map-status.sh`
- `commands/validate-memory.sh`
- `commands/pr-readiness-check.sh`
- `commands/link-pr-to-task-issue.sh`
- `commands/comment-pr-qa-results.sh`
- `commands/update-todo-checklist.sh`

## Role Mappings

### arts/art-director

Skills:

- `select-art-pipeline`
- `use-external-asset-library`
- `maintain-art-style-contract`
- `develop-original-brand-directions`
- `design-ui-from-constraints`
- `source-licensed-visual-assets`
- `audit-reference-originality`
- `plan-generative-media-pipeline`
- `use-comfyui-local-generation`
- `validate-generated-media`
- `prepare-rigged-runtime-actors`
- `prepare-game-art-handoff`
- `direct-blender-production`
- `author-blender-materials-and-lookdev`
- `light-and-frame-blender-scenes`
- `render-and-composite-blender-output`
- `review-blender-deliverables`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/validate-style-contract.sh`
- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`
- `commands/validate-rigged-actor-manifest.sh`
- `commands/print-blender-production-brief.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/build-originality-evidence.sh`
- `commands/print-web-experience-brief.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/blender-production-artist

Skills:

- `select-art-pipeline`
- `use-external-asset-library`
- `direct-blender-production`
- `model-blender-assets`
- `prepare-blender-uvs-and-textures`
- `author-blender-materials-and-lookdev`
- `build-procedural-blender-scenes`
- `rig-and-animate-blender-actors`
- `simulate-blender-effects`
- `light-and-frame-blender-scenes`
- `render-and-composite-blender-output`
- `optimize-and-export-blender-assets`
- `review-blender-deliverables`
- `maintain-art-style-contract`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `prepare-rigged-runtime-actors`
- `create-game-vfx`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/print-blender-production-brief.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/validate-blender-python.sh`
- `commands/validate-style-contract.sh`
- `commands/validate-rigged-actor-manifest.sh`
- `commands/print-game-art-handoff-template.sh`

### arts/board-ui-artist

Skills:

- `tcg-art-direction`
- `design-ui-from-constraints`
- `source-licensed-visual-assets`
- `enforce-art-language-safety`

Commands:

- `commands/print-tcg-art-style-template.sh`
- `commands/validate-svg-assets.sh`
- `commands/build-originality-evidence.sh`

### arts/card-illustrator

Skills:

- `tcg-art-direction`
- `develop-original-brand-directions`
- `source-licensed-visual-assets`
- `audit-reference-originality`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/print-tcg-art-style-template.sh`
- `commands/build-originality-evidence.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/css-vector-artist

Skills:

- `select-art-pipeline`
- `maintain-art-style-contract`
- `design-ui-from-constraints`
- `prepare-game-art-handoff`
- `enforce-art-language-safety`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/validate-style-contract.sh`
- `commands/print-css-art-token-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/validate-svg-assets.sh`

### arts/cutout-rig-animator

Skills:

- `maintain-art-style-contract`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/flat-minimalist-game-artist

Skills:

- `maintain-art-style-contract`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/game-vfx-artist

Skills:

- `create-game-vfx`
- `simulate-blender-effects`
- `render-and-composite-blender-output`
- `review-blender-deliverables`
- `plan-hybrid-game-assets`
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/print-gameplay-system-brief.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/generative-art-designer

Skills:

- `select-art-pipeline`
- `develop-original-brand-directions`
- `source-licensed-visual-assets`
- `audit-reference-originality`
- `maintain-art-style-contract`
- `plan-generative-media-pipeline`
- `use-comfyui-local-generation`
- `validate-generated-media`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/build-originality-evidence.sh`
- `commands/validate-style-contract.sh`
- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/illustrative-2d-artist

Skills:

- `maintain-art-style-contract`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `source-licensed-visual-assets`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/isometric-2-5d-art-director

Skills:

- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/isometric-2-5d-environment-artist

Skills:

- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/papercraft-art-director

Skills:

- `maintain-art-style-contract`
- `plan-generative-media-pipeline`
- `use-comfyui-local-generation`
- `validate-generated-media`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/parallax-background-artist

Skills:

- `maintain-art-style-contract`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/pixel-artist

Skills:

- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/pre-rendered-2-5d-artist

Skills:

- `maintain-art-style-contract`
- `light-and-frame-blender-scenes`
- `render-and-composite-blender-output`
- `review-blender-deliverables`
- `review-isometric-production`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/sound-designer

Skills:

- `plan-generative-media-pipeline`
- `produce-generative-audio`
- `validate-generated-media`
- `plan-hybrid-game-assets`

Commands:

- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`

### arts/technical-3d-artist

Skills:

- `select-art-pipeline`
- `use-external-asset-library`
- `build-threejs-code-models`
- `build-threejs-code-characters`
- `review-threejs-code-characters`
- `prepare-rigged-runtime-actors`
- `model-blender-assets`
- `rig-and-animate-blender-actors`
- `optimize-and-export-blender-assets`
- `review-blender-deliverables`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `build-gameplay-runtime`
- `maintain-art-style-contract`
- `iterate-art-to-sanity`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/create-code-model-manifest.sh`
- `commands/validate-code-model-manifest.sh`
- `commands/next-code-model-pass.sh`
- `commands/record-code-model-review.sh`
- `commands/create-code-character-profile.sh`
- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- `commands/validate-rigged-actor-manifest.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/validate-style-contract.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/tile-set-artist

Skills:

- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `plan-hybrid-game-assets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`

### arts/token-vfx-artist

Skills:

- `tcg-art-direction`
- `create-game-vfx`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:

- `commands/print-tcg-art-style-template.sh`
- `commands/print-gameplay-system-brief.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/web-experience-designer

Skills:

- `select-art-pipeline`
- `use-external-asset-library`
- `build-threejs-code-models`
- `design-web-experiences`
- `design-conversion-pages`
- `design-ui-from-constraints`
- `develop-original-brand-directions`
- `build-scroll-authored-web-experiences`
- `build-accessible-motion-systems`
- `build-interactive-web-effects`
- `build-webgl-experiences`
- `optimize-web-motion`
- `capture-ui-reference-pack`
- `extract-interaction-patterns`
- `prototype-from-reference-pack`
- `source-licensed-visual-assets`
- `audit-reference-originality`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/create-code-model-manifest.sh`
- `commands/validate-code-model-manifest.sh`
- `commands/next-code-model-pass.sh`
- `commands/record-code-model-review.sh`
- `commands/print-web-experience-brief.sh`
- `commands/validate-style-contract.sh`
- `commands/playwright-capture-page.sh`
- `commands/render-browser-demo.sh`
- `commands/web-performance-report.sh`
- `commands/build-originality-evidence.sh`

### computer-science/ai-data-remediation-engineer

Skills:

- `audit-untrusted-agent-source`
- `adapt-external-agent-skills`
- `verify-and-explain`
- `repo-map-dotnet`

Commands:

- `commands/audit-agent-source.sh`
- `commands/validate-skill-safety.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

### computer-science/ai-engineer

Skills:

- `audit-untrusted-agent-source`
- `adapt-external-agent-skills`
- `verify-and-explain`
- `plan-generative-media-pipeline`
- `use-comfyui-local-generation`
- `produce-generative-audio`
- `validate-generated-media`
- `dependency-audit-dotnet`

Commands:

- `commands/audit-agent-source.sh`
- `commands/validate-skill-safety.sh`
- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/install-comfyui-local.sh`
- `commands/install-comfyui-models.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`
- `commands/dependency-check.sh`

### computer-science/autonomous-optimization-architect

Skills:

- `generate-architecture`
- `verify-and-explain`
- `profile-application-performance`
- `optimize-web-games`

Commands:

- `commands/generate-architecture.sh`
- `commands/web-performance-report.sh`
- `commands/validate-opencaw.sh`

### computer-science/backend-architect

Skills:

- `generate-architecture`
- `apim-change-review`
- `verify-and-explain`
- `solution-build`
- `test-dotnet`

Commands:

- `commands/generate-architecture.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

### computer-science/code-migrator

Skills:

- `dependency-audit-dotnet`
- `upgrade-dotnet-runtime`
- `test-dotnet`
- `format-dotnet`
- `clean-rebuild-dotnet`
- `verify-and-explain`

Commands:

- `commands/dotnet-list-outdated-packages.sh`
- `commands/dotnet-upgrade-assistant.sh`
- `commands/dotnet-restore.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`
- `commands/dotnet-format.sh`
- `commands/dotnet-clean-rebuild.sh`

### computer-science/code-reviewer

Skills:

- `verify-and-explain`
- `audit-untrusted-agent-source`
- `audit-reference-originality`
- `dependency-audit-dotnet`

Commands:

- `commands/audit-agent-source.sh`
- `commands/build-originality-evidence.sh`
- `commands/dependency-check.sh`
- `commands/validate-opencaw.sh`

### computer-science/data-engineer

Skills:

- `install-database-cli-tools`
- `database-cli-query`
- `generate-architecture`
- `verify-and-explain`

Commands:

- `commands/install-database-cli-tools.sh`
- `commands/database-cli-query.sh`
- `commands/generate-architecture.sh`

### computer-science/database-optimizer

Skills:

- `install-database-cli-tools`
- `database-cli-query`
- `verify-and-explain`
- `profile-application-performance`

Commands:

- `commands/install-database-cli-tools.sh`
- `commands/database-cli-query.sh`
- `commands/web-performance-report.sh`

### computer-science/devops-automator

Skills:

- `generate-architecture`
- `create-host-ai-scaffold`
- `audit-untrusted-agent-source`
- `verify-and-explain`

Commands:

- `commands/generate-architecture.sh`
- `commands/create-host-ai-scaffold.sh`
- `commands/audit-agent-source.sh`
- `commands/validate-opencaw.sh`

### computer-science/embedded-firmware-engineer

Skills:

- `generate-architecture`
- `verify-and-explain`

Commands:

- `commands/generate-architecture.sh`
- `commands/validate-opencaw.sh`

### computer-science/frontend-developer

Skills:

- `select-art-pipeline`
- `use-external-asset-library`
- `build-threejs-code-models`
- `build-threejs-code-characters`
- `design-web-experiences`
- `design-ui-from-constraints`
- `build-scroll-authored-web-experiences`
- `build-accessible-motion-systems`
- `build-interactive-web-effects`
- `build-webgl-experiences`
- `optimize-web-motion`
- `capture-full-page-evidence`
- `produce-browser-demo`
- `profile-application-performance`
- `maintain-art-style-contract`
- `prepare-game-art-handoff`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/create-code-model-manifest.sh`
- `commands/validate-code-model-manifest.sh`
- `commands/next-code-model-pass.sh`
- `commands/record-code-model-review.sh`
- `commands/create-code-character-profile.sh`
- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- `commands/print-web-experience-brief.sh`
- `commands/playwright-capture-page.sh`
- `commands/render-browser-demo.sh`
- `commands/web-performance-report.sh`
- `commands/validate-style-contract.sh`
- `commands/validate-svg-assets.sh`

### computer-science/fullstack-engineer

Skills:

- `generate-architecture`
- `design-web-experiences`
- `capture-full-page-evidence`
- `profile-application-performance`
- `solution-build`
- `test-dotnet`
- `verify-and-explain`

Commands:

- `commands/generate-architecture.sh`
- `commands/playwright-capture-page.sh`
- `commands/web-performance-report.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

### computer-science/game-designer

Skills:

- `author-game-worlds`
- `design-action-gameplay`
- `test-playable-games`
- `review-threejs-code-characters`
- `maintain-art-style-contract`
- `review-isometric-production`

Commands:

- `commands/print-gameplay-system-brief.sh`
- `commands/validate-gameplay-review.sh`
- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`

### computer-science/gameplay-engineer

Skills:

- `use-external-asset-library`
- `build-threejs-code-characters`
- `build-gameplay-runtime`
- `build-game-production-tools`
- `design-action-gameplay`
- `prepare-rigged-runtime-actors`
- `plan-hybrid-game-assets`
- `create-game-vfx`
- `optimize-web-games`
- `test-playable-games`
- `ship-web-games`
- `verify-and-explain`

Commands:

- `commands/list-external-asset-libraries.sh`
- `commands/inspect-external-asset-library.sh`
- `commands/copy-external-asset.sh`
- `commands/create-code-character-profile.sh`
- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- `commands/print-gameplay-system-brief.sh`
- `commands/validate-gameplay-review.sh`
- `commands/validate-rigged-actor-manifest.sh`
- `commands/playwright-capture-page.sh`
- `commands/render-browser-demo.sh`
- `commands/web-performance-report.sh`

### computer-science/generative-media-pipeline-engineer

Skills:

- `select-art-pipeline`
- `plan-generative-media-pipeline`
- `use-comfyui-local-generation`
- `produce-generative-audio`
- `validate-generated-media`
- `audit-untrusted-agent-source`
- `verify-and-explain`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/generate-media-contract.sh`
- `commands/validate-media-contract.sh`
- `commands/install-comfyui-local.sh`
- `commands/install-comfyui-models.sh`
- `commands/inspect-local-media-host.sh`
- `commands/run-comfyui-workflow.sh`
- `commands/validate-media-generation-manifest.sh`
- `commands/validate-media-templates.sh`

### computer-science/git-workflow-master

Skills:

- `branch-name-suggester`
- `git-commit-dotnet`
- `link-pr-to-task-issue`
- `pr-readiness-gate`
- `verify-and-explain`

Commands:

- `commands/git-commit.sh`
- `commands/link-pr-to-task-issue.sh`
- `commands/pr-readiness-check.sh`

### computer-science/incident-response-commander

Skills:

- `record-debug-resolution`
- `verify-and-explain`
- `audit-untrusted-agent-source`
- `manage-task-issues`

Commands:

- `commands/audit-agent-source.sh`
- `commands/security-scan.sh`
- `commands/create-task-issue.sh`
- `commands/append-debug.sh`

### computer-science/mobile-app-builder

Skills:

- `generate-architecture`
- `design-ui-from-constraints`
- `build-accessible-motion-systems`
- `profile-application-performance`
- `verify-and-explain`

Commands:

- `commands/generate-architecture.sh`
- `commands/print-web-experience-brief.sh`
- `commands/web-performance-report.sh`

### computer-science/project-manager

Skills:

- `brainstorm-flow`
- `create-task-file`
- `gauntlet-flow`
- `goal-flow`
- `manage-task-issues`
- `orchestrate-subagents`
- `pr-readiness-gate`
- `post-pr-qa`
- `clean-context`
- `verify-and-explain`

Commands:

- `commands/brainstorm-mode.sh`
- `commands/validate-brainstorm.sh`
- `commands/show-brainstorm.sh`
- `commands/create-gauntlet-file.sh`
- `commands/validate-gauntlet.sh`
- `commands/record-gauntlet-round.sh`
- `commands/record-gauntlet-pr-event.sh`
- `commands/record-gauntlet-promotion-qa.sh`
- `commands/create-gauntlet-completion-report.sh`
- `commands/create-goal-file.sh`
- `commands/create-goal-completion-report.sh`
- `commands/create-task-file.sh`
- `commands/create-task-issue.sh`
- `commands/create-subagent-plan.sh`
- `commands/validate-subagent-plan.sh`
- `commands/record-subagent-result.sh`
- `commands/import-task-from-issue.sh`
- `commands/sync-task-issues.sh`
- `commands/update-todo-checklist.sh`
- `commands/pr-readiness-check.sh`
- `commands/comment-pr-qa-results.sh`

### computer-science/qa-engineer

Skills:

- `verify-and-explain`
- `review-threejs-code-characters`
- `review-blender-deliverables`
- `capture-full-page-evidence`
- `produce-browser-demo`
- `profile-application-performance`
- `test-playable-games`
- `optimize-web-games`
- `playwright-e2e-tests`
- `playwright-browser-discovery`
- `playwright-test-refinement`
- `playwright-reporting`
- `post-pr-qa`
- `comment-issue-test-results`
- `test-dotnet`

Commands:

- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- `commands/inspect-blender-scene.sh`
- `commands/validate-blender-scene-report.sh`
- `commands/playwright-capture-page.sh`
- `commands/render-browser-demo.sh`
- `commands/web-performance-report.sh`
- `commands/validate-gameplay-review.sh`
- `commands/playwright-test.sh`
- `commands/playwright-report-summary.sh`
- `commands/playwright-artifact-index.sh`
- `commands/playwright-discovery-report.sh`
- `commands/playwright-evidence-report.sh`
- `commands/dotnet-test.sh`
- `commands/comment-pr-qa-results.sh`
- `commands/comment-issue-test-results.sh`

### computer-science/rapid-prototyper

Skills:

- `prototype-from-reference-pack`
- `design-ui-from-constraints`
- `design-web-experiences`
- `build-scroll-authored-web-experiences`
- `build-gameplay-runtime`
- `verify-and-explain`

Commands:

- `commands/print-web-experience-brief.sh`
- `commands/print-gameplay-system-brief.sh`
- `commands/playwright-capture-page.sh`

### computer-science/researcher

Skills:

- `brainstorm-flow`
- `verify-and-explain`

Commands:

- `commands/validate-brainstorm.sh`
- `commands/show-brainstorm.sh`

### computer-science/security-engineer

Skills:

- `audit-untrusted-agent-source`
- `adapt-external-agent-skills`
- `audit-reference-originality`
- `verify-and-explain`
- `apim-change-review`

Commands:

- `commands/audit-agent-source.sh`
- `commands/validate-skill-safety.sh`
- `commands/build-originality-evidence.sh`
- `commands/veracode-scan.sh`
- `commands/snyk-scan.sh`
- `commands/stackhawk-scan.sh`
- `commands/security-scan.sh`
- `commands/dependency-check.sh`

### computer-science/senior-developer

Skills:

- `select-art-pipeline`
- `build-threejs-code-models`
- `solution-restore`
- `solution-build`
- `test-dotnet`
- `format-dotnet`
- `verify-and-explain`
- `audit-untrusted-agent-source`

Commands:

- `commands/resolve-art-pipeline.sh`
- `commands/create-code-model-manifest.sh`
- `commands/validate-code-model-manifest.sh`
- `commands/next-code-model-pass.sh`
- `commands/record-code-model-review.sh`
- `commands/dotnet-restore.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`
- `commands/dotnet-format.sh`
- `commands/audit-agent-source.sh`

### computer-science/software-architect

Skills:

- `generate-architecture`
- `verify-and-explain`
- `audit-untrusted-agent-source`
- `profile-application-performance`

Commands:

- `commands/generate-architecture.sh`
- `commands/audit-agent-source.sh`
- `commands/web-performance-report.sh`
- `commands/validate-opencaw.sh`

### computer-science/solidity-smart-contract-engineer

Skills:

- `audit-untrusted-agent-source`
- `verify-and-explain`
- `dependency-audit-dotnet`

Commands:

- `commands/audit-agent-source.sh`
- `commands/security-scan.sh`
- `commands/dependency-check.sh`

### computer-science/sre

Skills:

- `verify-and-explain`
- `profile-application-performance`
- `record-debug-resolution`
- `audit-untrusted-agent-source`

Commands:

- `commands/web-performance-report.sh`
- `commands/security-scan.sh`
- `commands/audit-agent-source.sh`
- `commands/append-debug.sh`

### computer-science/technical-writer

Skills:

- `verify-and-explain`
- `derive-visual-spec-from-video`
- `extract-interaction-patterns`
- `capture-ui-reference-pack`
- `audit-reference-originality`

Commands:

- `commands/print-web-experience-brief.sh`
- `commands/print-gameplay-system-brief.sh`
- `commands/build-originality-evidence.sh`

### computer-science/threat-detection-engineer

Skills:

- `audit-untrusted-agent-source`
- `verify-and-explain`
- `apim-change-review`

Commands:

- `commands/audit-agent-source.sh`
- `commands/veracode-scan.sh`
- `commands/snyk-scan.sh`
- `commands/stackhawk-scan.sh`
- `commands/security-scan.sh`
