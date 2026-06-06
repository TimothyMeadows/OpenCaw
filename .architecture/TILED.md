# TILED.md

This repository follows a **Tiled / MapEditor level-authoring architecture** for tile maps, object layers, world files, custom properties, tilesets, collision metadata, and map export pipelines.

The architecture is optimized for:

- Tiled as the source-of-truth map and level editor
- TMX, TSX, TX, JSON, and `.world` data contracts
- 2D, isometric, staggered, hexagonal, and tile-based 2.5D worlds
- explicit map-to-runtime transformation
- stable tileset and object property schemas
- Phaser, Three.js, custom canvas/WebGL, and native game runtime integration
- reviewable map data and automated validation
- large-world workflows that reduce memory pressure and merge conflicts

The goal is to keep the system:

- clear about what designers author in Tiled and what the runtime derives
- deterministic about layers, collision, spawns, triggers, and metadata
- resilient to asset path changes, tileset updates, map version drift, and export format differences
- friendly to source control and team editing
- efficient enough for browser games and mobile devices

---

# Core Architecture Rule

**Treat Tiled as the level-authoring contract, not as the game runtime. Convert authored maps into explicit runtime systems.**

Prefer:

```text
Tiled Project -> Maps / Tilesets / Templates -> Export / Validate -> Runtime Map Model -> Engine Systems
```

Avoid:

```text
Tiled JSON loaded directly everywhere -> hidden gameplay rules, collision, spawns, and entity behavior scattered through render code
```

Tiled should own map layout, tile placement, layers, tilesets, object placement, custom properties, terrain metadata, templates, and world composition. The runtime should own loading, schema validation, entity construction, collision conversion, navigation, rendering, streaming, save-state overlays, and gameplay interpretation.

---

# Recommended Structure

```text
assets/
  maps/
    source/
      project.tiled-project
      worlds/
      maps/
      tilesets/
      templates/
      automapping/
    exported/
      maps/
      tilesets/
      worlds/
  tilesets/
  sprites/
src/
  game/
    maps/
      loadMap.ts
      validateMap.ts
      mapSchema.ts
      mapRegistry.ts
      tileProperties.ts
    levels/
    collision/
    spawning/
    navigation/
    rendering/
tools/
  tiled/
    export-maps.*
    validate-maps.*
    scripts/
```

Keep editable source files and runtime exports distinct when the runtime does not consume the authoring format directly. If the runtime consumes Tiled JSON directly, still separate authored assets, generated caches, and validation reports.

---

# File Format Contract

Choose the runtime map format intentionally.

Rules:

- prefer Tiled JSON for browser JavaScript/TypeScript runtimes unless a target engine has stronger TMX support
- use TMX/TSX when XML tooling, editor interoperability, or engine support is stronger
- keep external tilesets (`.tsx` or JSON tilesets) when maps share tile definitions
- use object templates (`.tx`) for repeated entities, triggers, NPCs, pickups, doors, and spawn definitions
- document whether maps use finite, infinite, orthogonal, isometric, staggered, or hexagonal orientation
- document tile width, tile height, object coordinate assumptions, render order, chunking, compression, and layer ordering
- avoid CSV except for simple tile layers with no object, property, template, or tileset complexity
- do not depend on file paths that only work on one designer's machine

Runtime loaders must handle:

- missing maps, tilesets, images, and templates
- duplicate asset keys or object IDs
- unsupported Tiled version or format version
- unknown layer classes or object classes
- unexpected compression or encoding
- flipped/rotated tile flags where the runtime supports them
- external file references and relative paths

---

# Map Schema and Custom Properties

Custom properties are the primary bridge from designer-authored maps to gameplay behavior.

Rules:

- define a typed property schema for maps, layers, tilesets, tiles, objects, object templates, Wang sets, and world entries when used
- prefer Tiled custom classes and enums for structured designer input
- keep property names stable, documented, and validated in CI or local tooling
- use class names for gameplay objects such as `SpawnPoint`, `Door`, `NPC`, `Enemy`, `Pickup`, `Trigger`, `Region`, `CameraZone`, and `Hazard`
- avoid free-form string conventions when an enum or custom class can prevent invalid data
- use tile property inheritance for repeated tile-object behavior, but validate per-instance overrides
- reserve properties for authored intent, not for runtime-only transient state

Required schema decisions:

- coordinate system and units
- layer naming and class conventions
- object class list
- required and optional properties per class
- property defaults and allowed values
- collision and trigger representation
- spawn and entity ID rules
- asset references and relative path policy
- localization/text handling policy

---

# Layer Architecture

Layer names and classes are part of the map API.

Recommended layer families:

- `Ground`: base walkable or visual terrain
- `DecorationBelow`: non-colliding visuals below actors
- `Collision`: tile or object collision authoring
- `Gameplay`: triggers, regions, spawns, doors, hazards, objectives
- `Entities`: NPCs, enemies, pickups, interactables, scripted objects
- `DecorationAbove`: props or visual layers above actors
- `Occlusion`: roofs, trees, bridges, walls, foreground masks
- `Parallax`: background or foreground image layers when supported
- `Debug`: editor-only notes, boundaries, markers, and validation helpers

Rules:

- keep visual layers, collision layers, object layers, and debug layers separate
- mark editor-only/debug layers so export or runtime import can exclude them
- define draw order and depth behavior explicitly, especially for isometric and 2.5D maps
- do not infer gameplay meaning from arbitrary layer order when a class/property is more reliable
- keep layer opacity, tint, parallax, and visibility meaningful for runtime only when the engine supports them

---

# Tilesets and Terrain

Tilesets should be stable runtime contracts, not just editor palettes.

Rules:

- keep tile dimensions, margin, spacing, image paths, tile IDs, and atlas relationships stable
- use external tilesets for shared terrain, structures, props, hazards, and animated tiles
- document tile property schemas for collision, material, footstep sound, biome, terrain type, damage, ladder, water, slope, cover, and interaction
- validate that tile IDs used by maps still exist after tileset changes
- prefer named tile properties or classes over relying only on raw global tile IDs
- keep animated tile frame timing compatible with the runtime animation system
- define whether Wang sets, terrains, or automapping rules are source-only authoring aids or runtime data

For isometric projects, tilesets must align with `STYLE.md` and `ISOMETRIC_2_5D` style rules when present: projection, tile footprint, elevation step, collision readability, occlusion, and character anchor assumptions.

---

# Objects, Templates, and Entity Spawning

Object layers are the main authored bridge to runtime entities.

Rules:

- use object templates for repeated authored entities
- give every runtime-significant object a stable class and required properties
- distinguish editor labels from runtime IDs
- validate duplicate IDs, missing target references, and invalid object references
- define how rectangles, points, polygons, polylines, ellipses, text, and tile objects are interpreted
- convert Tiled objects into runtime entities through factory/registry code, not ad hoc switch statements in render code
- keep spawn position, facing, team, behavior, loot, script, patrol path, trigger radius, and linked target properties explicit

Do not encode full gameplay scripts in Tiled properties unless the project has a safe scripting architecture and validation story.

---

# Collision, Navigation, and Gameplay Data

Collision and navigation should be derived predictably from authored data.

Rules:

- define whether collision comes from tile properties, collision object layers, tileset collision shapes, object classes, or generated navigation data
- keep visual collision and runtime collision in sync through validation or debug overlays
- avoid using high-detail decorative shapes as collision geometry
- define one-way platforms, slopes, ladders, water, portals, doors, cover, hazards, and no-spawn regions explicitly
- keep navigation graphs, path nodes, patrol routes, and trigger links named and validated
- validate collision holes, unreachable spawns, overlapping blockers, duplicate exits, missing destinations, and orphaned references

When using Phaser, map Tiled layers and objects through Phaser tilemap APIs while keeping gameplay conversion in project systems. When using Three.js or custom renderers, convert Tiled coordinates and layers into renderer-specific meshes, sprites, colliders, or data chunks behind a loader boundary.

---

# Worlds, Streaming, and Large Maps

Use Tiled worlds for multi-map editing and large-world authoring.

Rules:

- use `.world` files when a game world spans multiple maps, chunks, regions, or screens
- define global map positions in pixels and keep neighboring maps aligned
- use naming patterns only when the pattern is documented and validated
- load only adjacent maps or runtime-needed chunks for large worlds when memory or render cost matters
- separate authored world placement from runtime streaming rules
- define map boundary transitions, portals, edge stitching, and cross-map object references explicitly
- keep map files small enough for review and team editing when possible

For browser games, avoid loading entire large worlds into memory unless the target devices and performance budget support it.

---

# Export and Automation

Map export should be repeatable.

Rules:

- automate exports with Tiled command-line options or scripts when generated runtime files are committed or packaged
- use JavaScript/TypeScript Tiled scripts for custom export formats, validation helpers, custom actions, or editor tools when needed
- use `@mapeditor/tiled-api` type definitions for typed Tiled scripts where practical
- keep export scripts deterministic and source-controlled
- run export validation in CI or pre-commit workflows when map data is critical
- on Linux CI, account for Tiled needing a graphical environment for command-line exports and use a headless display setup when required
- never hand-edit generated runtime exports unless the project explicitly treats them as source

Recommended pipeline:

```text
edit map -> save source -> export/generate runtime data -> validate schema/assets -> run map smoke tests
```

---

# Runtime Integration

Keep runtime integration behind a map-loading boundary.

Rules:

- centralize map parsing, version checks, tileset resolution, property normalization, and entity spawning
- expose runtime-specific map models instead of leaking raw Tiled JSON/TMX everywhere
- keep renderer setup separate from gameplay object creation
- validate layer names, object classes, required properties, tileset references, and asset existence before starting a level
- generate actionable errors for designers: map file, layer, object ID/name, class, and missing property
- keep save-game state as overlays on top of authored maps, not edits to source map files

Integration notes:

- Phaser can consume Tiled JSON through tilemap APIs, but project systems should still own gameplay conversion and entity spawning.
- Three.js generally needs a custom conversion layer from Tiled maps into meshes, sprites, planes, instanced geometry, or 2.5D scene objects.
- Custom canvas/WebGL runtimes should parse Tiled once into engine-friendly chunks, draw batches, collision structures, and entity spawn lists.

---

# Source Control and Review

Map data is code-adjacent production data.

Rules:

- prefer stable formatting and deterministic exports for reviewable diffs
- keep large binary source assets separate from map metadata where possible
- avoid embedding tilesets when external tilesets reduce duplicated diffs
- keep map files small enough to avoid frequent merge conflicts, or use world/chunk splitting
- document which generated files are committed and which are build artifacts
- include designer-facing validation errors in PR/CI output when map changes fail checks

---

# Testing and Verification

Map changes need more than visual inspection in Tiled.

Test categories:

- schema validation for required layers, classes, and properties
- asset validation for missing tilesets, images, templates, maps, and audio references
- tile ID validation after tileset edits
- collision and navigation validation
- spawn/exit/portal/reference validation
- export smoke tests for every committed map
- runtime load tests for representative maps
- browser tests for map render, collision debug overlays, object spawning, camera bounds, and scene transitions
- screenshot or canvas checks for key levels when rendering risk is high

Acceptance checks should include at least one real runtime load path, not only a successful Tiled save.

---

# Security and Safety

- Do not load untrusted remote maps, scripts, or asset packs without validation and sandboxing.
- Treat custom Tiled scripts as code; review them like build tooling.
- Keep asset paths, export paths, and runtime URLs configuration-driven when environments differ.
- Validate user-generated maps before loading them into a live game runtime.
- Preserve licensing and attribution for tilesets, map packs, fonts, audio, and third-party templates.

---

# Anti-Patterns

Never introduce:

- gameplay-critical conventions that exist only in a designer's memory
- raw Tiled JSON parsing scattered across game systems
- layer names that change without migration or validation updates
- stringly typed custom properties where classes/enums would prevent mistakes
- maps that only work because assets exist at absolute local paths
- generated exports committed without a reproducible export command
- collision hidden in visual decoration with no debug or validation path
- giant monolithic maps that cause memory, performance, or merge-conflict pain
- runtime save-state changes written back into source map files
- claiming map support without testing a map in the actual runtime

---

# Reference Sources

- Tiled GitHub repository: https://github.com/mapeditor/tiled
- Tiled documentation: https://doc.mapeditor.org/
- Tiled custom properties: https://doc.mapeditor.org/en/stable/manual/custom-properties/
- Tiled export formats: https://doc.mapeditor.org/en/stable/manual/export/
- Tiled JSON map format: https://doc.mapeditor.org/en/stable/reference/json-map-format/
- Tiled TMX map format: https://doc.mapeditor.org/en/stable/reference/tmx-map-format/
- Tiled worlds: https://doc.mapeditor.org/en/stable/manual/worlds/
- Tiled scripting API: https://www.mapeditor.org/docs/scripting/
- Phaser Tilemap API: https://docs.phaser.io/api-documentation/class/tilemaps-tilemap

---

# Code Generation Rules for Agents

When generating Tiled integration code:

1. Start by identifying the selected source/export format and map schema.
2. Define required layers, object classes, custom properties, tileset contracts, and asset paths before writing runtime loaders.
3. Keep raw Tiled parsing behind a map-loading boundary.
4. Convert maps into runtime models for rendering, collision, spawns, triggers, navigation, and camera bounds.
5. Add validation with designer-friendly errors.
6. Test at least one representative map in the actual runtime.
7. Keep source maps, exported runtime files, and generated artifacts clearly separated.

When in doubt:

**Let Tiled author the world; let the runtime interpret it through validated contracts.**
