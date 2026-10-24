---
name: phaserjs-build-tilemaps
description: Integrate Phaser tilemaps, tilesets, layers and authored object data with validated coordinates, collisions and level identity.
engines: [PHASERJS]
---

# Build Phaser Tilemaps

## When to use

Load or author tile-based levels, convert editor objects to gameplay entities, or diagnose tile collision and alignment.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh phaserjs-build-tilemaps`; require compatibility and honor task override scope. Inspect the locked Phaser major, exporter/schema version, map orientation, selected physics plugin and world contract. Tiled or other editors are optional selected tools; no editor/plugin installation or map download is implied.

## Workflow

1. Validate map schema, dimensions, tile size, tileset image dependencies, margin/spacing and layer names before runtime construction. Reject unsupported external tilesets, chunking, orientation or export features explicitly rather than dropping content silently.
2. Use the installed version's loader (`tilemapTiledJSON` where applicable), `this.make.tilemap`, `addTilesetImage` and `createLayer`. Match the authored tileset name to the runtime texture key; validate failed returns instead of continuing with blank layers.
3. Specify layer origin, scale, camera/parallax behavior and world/tile coordinate conversion. Preserve flip/rotation flags and tileset GID ranges. Object layers require explicit shape, anchor and rotation conversion; image origins do not automatically match authored object positions.
4. For Arcade, select collision indices/properties and validate body contacts with layer collision faces. For Matter, use the supported tile conversion path and authored shapes; never assume Arcade layer colliders operate in a Matter world.
5. Convert spawn, trigger and navigation markers into validated content records with stable IDs. Keep mutable level state and save migrations separate from tile graphics. Dynamic tile edits must refresh relevant collision/navigation data and preserve no-loss persistence rules.
6. Bound layer/chunk creation, visible work and memory. Phaser 3 custom pipelines and Phaser 4 render-node/GPU-layer behavior need version-specific review. Teardown owned objects/listeners without removing shared tileset textures still used by another scene.

## Output and verification

Deliver import validation, layer/tileset mapping and coordinate/collision evidence. Test map edges, flipped tiles, scaled maps, object rotations, missing tilesets, triggers, save/reload and supported chunk boundaries. Inspect rendered alignment and physical contacts in the runtime. Read the [Tilemap API](https://docs.phaser.io/api-documentation/3.88.2/class/tilemaps-tilemap) as a versioned reference and select the host's matching version before implementation.
