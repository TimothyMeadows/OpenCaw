# Style Templates

Available OpenCaw art style templates:

- ABYSSAL_MONSTER_GROTESQUE
- ARCANE_ARENA_CLARITY
- ASHEN_GOTHIC_FANTASY
- CATHEDRAL_SHADOW_HORROR
- CEL_SHADED_COMIC
- CURSED_RELIC_BAROQUE
- CUTOUT_RIGGED
- DOODLE_SKETCH
- FLAT_MINIMALIST
- GAME_VFX
- GEOMETRIC_SHAPE
- HAND_DRAWN_ILLUSTRATIVE
- HD_2D
- HEROIC_FACTION_FANTASY
- ISOMETRIC_2_5D
- LAYERED_PAPERCRAFT
- LOW_POLY_2_5D
- MONOCHROME_LIMITED_PALETTE
- MYTHIC_GODFORGE
- PAINTERLY_2D
- PAPER_DIORAMA
- PARALLAX_BACKGROUND
- PIXEL_ART
- POPUP_STORYBOOK
- PRE_RENDERED_2_5D
- RUINED_MEDIEVAL_REALISM
- SCIENCE_FANTASY
- TACTICAL_UI_HUD
- TILESET_ENVIRONMENT
- VECTOR_UI
- WARM_TAVERN_FANTASY
- WEB_ATMOSPHERIC
- WEB_DARK_GLASS
- WEB_EDITORIAL
- WEB_LIGHT_PAPER
- WEB_SKEUOMORPHIC
- WEB_TECHNICAL_GRID

Use one or more of these when generating `../STYLE.md` for a host repository.

## Local GPU Generation Support

Local GPU generation assets are stored under `.styles/.gpu/` but are not selectable art-style templates:

- `.styles/.gpu/COMFYUI_LOCAL.md` defines the loopback-only ComfyUI backend.
- `.styles/.gpu/toolchain.json` pins the supported local toolchain.
- `.styles/.gpu/model-packs.json` defines reviewed model and workflow packs.

## Recommended Starting Points

- Isometric tactics, town builders, ARPGs, and 2.5D exploration: `ISOMETRIC_2_5D`
- Pixel games: `PIXEL_ART` plus `TILESET_ENVIRONMENT`
- Hand-painted games: `HAND_DRAWN_ILLUSTRATIVE` or `PAINTERLY_2D`
- Dark fantasy, gothic ruins, cursed medieval worlds, and boss-heavy horror: start with one of `ASHEN_GOTHIC_FANTASY`, `RUINED_MEDIEVAL_REALISM`, `CATHEDRAL_SHADOW_HORROR`, `CURSED_RELIC_BAROQUE`, or `ABYSSAL_MONSTER_GROTESQUE`, then add `PAINTERLY_2D`, `PRE_RENDERED_2_5D`, `GAME_VFX`, or `TACTICAL_UI_HUD` as needed
- UI-heavy games: `TACTICAL_UI_HUD` plus `VECTOR_UI`
- TCG, CCG, deck-builder, and card-battler games: start with one of `WARM_TAVERN_FANTASY`, `ARCANE_ARENA_CLARITY`, `MYTHIC_GODFORGE`, `HEROIC_FACTION_FANTASY`, or `SCIENCE_FANTASY`, then add `TACTICAL_UI_HUD`, `VECTOR_UI`, `PAINTERLY_2D`, or `GAME_VFX` as needed
- Animation-heavy characters: `CUTOUT_RIGGED`
- Tactile cut-paper assets and interfaces: `LAYERED_PAPERCRAFT`
- Layered shadow-box scenes: `PAPER_DIORAMA` plus `LAYERED_PAPERCRAFT`
- Responsive bound-page experiences: `POPUP_STORYBOOK` plus `LAYERED_PAPERCRAFT`
- Sprite-rendered 3D pipelines: `PRE_RENDERED_2_5D` or `HD_2D`
- Effects-heavy combat or magic: `GAME_VFX`
- Content-led web products and documentation: `WEB_LIGHT_PAPER` or `WEB_EDITORIAL`
- Dense technical products and operational interfaces: `WEB_TECHNICAL_GRID`
- Layered dark interfaces: `WEB_DARK_GLASS`
- Immersive campaign or showcase pages: `WEB_ATMOSPHERIC`
- Interfaces that benefit from restrained physical affordances: `WEB_SKEUOMORPHIC`

## Research Basis

- Unity 2D art style reference: https://docs.unity.cn/6000.0/Documentation/Manual/2d-game-art-syle-reference.html
- Unity isometric tilemap guidance: https://docs.unity.cn/Manual/Tilemap-Isometric.html
- Unity Sprite Atlas guidance: https://learn.unity.com/tutorial/introduction-to-the-sprite-atlas-2019-3
- Godot parallax guidance: https://docs.godotengine.org/en/4.5/tutorials/2d/2d_parallax.html
- Godot 2D lights and shadows: https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html
- Godot cutout and skeletal animation: https://docs.godotengine.org/en/stable/tutorials/animation/cutout_animation.html and https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html
- Godot 2D particle systems: https://docs.godotengine.org/en/latest/tutorials/2d/particle_systems_2d.html
- Microsoft Xbox Accessibility Guideline 102: https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102
- Game Accessibility Guidelines contrast guidance: https://gameaccessibilityguidelines.com/provide-high-contrast-between-text-ui-and-background/
- GameMaker 2D game art style guide: https://gamemaker.io/en/blog/2d-game-art-styles
- Pixune 2D art style overview: https://pixune.com/blog/2d-art-styles/
