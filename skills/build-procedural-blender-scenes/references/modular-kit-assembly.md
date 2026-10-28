# Modular kit assembly

## Establish the kit system

Record the intended camera, game scale, traversal clearances, target format and chosen engine importer before deriving module sizes. Define a base length, allowed multiples, floor heights, wall thickness, orientation, pivot convention and tolerances. Choose these from the project; neither a particular metre grid nor a universal asset pivot is required.

Give each piece a stable identity, dimensions, intended neighbours and attachment faces. Treat the visible surface, connection envelope and collision shape as separate responsibilities. Doors, stairs, railings and ceilings must fit the declared player or vehicle envelope rather than only the render composition.

## Build a complete small assembly

Start with an untextured working-copy kit containing the pieces needed to close a useful space: straight runs, inside and outside corners, floor/ceiling joins, openings, end caps and the junctions actually used by the layout. Add slopes, transitions and height changes when the design requires them. A folder of attractive wall segments does not establish a usable kit.

Assemble a representative room and connecting passage using only declared transforms and pieces. Include a loop that returns to its starting grid coordinate so accumulated dimensional errors become visible. Test mirrored or rotated uses only where their normals, UV direction and attachment rules permit them. Record any intentional overlap used to hide joins; do not conceal arbitrary gaps with added trim.

Compare numeric positions and dimensions against the kit contract. Viewport increment snapping can depend on view settings and starting positions, so the appearance of snapping is not measurement evidence. Preserve source transforms needed by downstream consumers; apply transforms only through the delivery contract.

## Surface and iteration ownership

Assign trim-sheet or atlas regions and texture direction before filling the kit with detail. Review joins under neutral light, oblique light and the intended camera, including repeat patterns, shading seams and texture discontinuities. Keep damage variants and dressing separate from the structural connection envelope.

If nodes or a placement tool assemble the kit, bind selections to stable piece identities and declared orientation rules. A regenerated assembly must preserve intentional overrides or report exactly which overrides it replaces. Never depend on alphabetical or collection order as an undocumented variant selector.

## Acceptance and handoff

Deliver the authored kit, piece/connection inventory, complete sample assembly and source-bound measured results. Check clearance, closed corners, junction coverage, collision continuity, visible repetition and actual material/draw costs. Independently inspect the staged export in the selected target; Blender assembly success does not prove engine navigation, collision or instancing support. Missing required connectors or an untested target scale remain open defects.

[Blender 4.5 snapping manual](https://docs.blender.org/manual/en/4.5/scene_layout/object/editing/snap.html) describes placement tools; the kit's dimensions and acceptance tolerances remain project decisions.
