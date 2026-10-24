---
name: babylonjs-integrate-physics
description: Integrate an explicitly selected Babylon.js physics plugin with bodies, queries, collision events and controlled stepping.
engines: [BABYLONJS]
---

# Integrate Babylon.js Physics

## When to use

Add dynamics, character collision, constraints or physics queries to a Babylon scene.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh babylonjs-integrate-physics`; require compatibility and honor task override scope. Require a named plugin and compatible Babylon/plugin versions, deployment files, license decision, units and timing requirements. Havok/WASM or another compatible plugin must be explicitly selected; do not download, install or substitute it automatically. Internal camera/mesh collision is a separate facility.

## Workflow

1. Verify plugin initialization and required local WASM/module loading before `scene.enablePhysics`. Missing binaries or unsupported platforms block physics rather than quietly producing visual-only movement.
2. Distinguish the selected plugin API generation. For v2, use supported `PhysicsBody`, `PhysicsShape`, constraints and `PhysicsAggregate` helpers; do not mix legacy `PhysicsImpostor` recipes with v2 contracts. Declare mass, motion type, material, collision masks and sensor behavior.
3. Select a single stepping owner, timestep, substep budget and resume policy. Keep render interpolation separate. Dynamic bodies own physical transforms; kinematic movement and teleports use the plugin's supported update path, not competing per-frame mesh writes.
4. Translate collision/query results to stable entity IDs. Queue gameplay consequences into the simulation boundary; guard duplicate contacts and destroyed entities. Document unsupported shapes and query limitations rather than pretending a render mesh is always a suitable collider.
5. Navigation/AI produces desired movement; the movement adapter performs queries and applies allowed results. Save validated gameplay pose/velocity or checkpoint state, not raw plugin handles. Deterministic replay requires measured support, not an assumption about a fixed step.
6. Dispose owned bodies, constraints, shapes and subscriptions in dependency order. Respect shared shape/plugin ownership and preserve scene teardown safety after partial initialization.

## Output and verification

Deliver the dependency/stepping contract and a controlled runtime fixture. Exercise grounding, triggers, collision filtering, fast movement, teleports, restart, low frame rates and plugin-load failure. Record actual solver behavior and costs; mocked contacts cannot certify dynamics. Check the [official physics integration guide](https://doc.babylonjs.com/features/featuresDeepDive/physics/usingPhysicsEngine/) against the installed API generation.
