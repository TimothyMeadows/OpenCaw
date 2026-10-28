# Geometry Nodes authoring and regeneration

## Make the interface inspectable

Record the Blender 4.5 node-group identity and its input/output socket names, types, meanings, coordinate spaces and units. Distinguish scalar parameters from fields and geometry inputs. Expose only the controls a consumer needs; keep implementation nodes owned by the group. Bind referenced objects, collections, materials and nested groups to declared repository-local dependencies.

Define valid values and behaviour for empty input, missing dependencies, invalid dimensions and excessive output. Interface minimum/maximum values guide UI editing; they are not sufficient enforcement for values supplied through links or animation. Clamp where clamping has a documented meaning; otherwise reject the operation through the approved authoring/validation workflow and report the invalid input.

## Author explicit operations

Trace one representative element from input through selection, placement, variation and output. For placement, supply actual points, the intended source geometry, rotation/scale and explicit variant selection to Instance on Points. Record the mapping from semantic variant identity to instance choice; changing source-list order must not silently change asset identities.

For edits, name the affected geometry component, attribute domain and selection. Set Position moves existing points; it does not create an opening. If the design needs holes, thickness or closed walls, author the necessary geometry operations and verify the resulting boundaries and topology. A list of intended nodes is a specification until a real group has been authored and evaluated.

Check fields in the geometry context where they are consumed. Capture or store required values before operations that change topology or domains, and inspect their resulting values with the Spreadsheet Editor. Declare custom attribute names, types and domains; avoid collisions with UVs, vertex groups or other owners. Do not assume every named attribute becomes a usable exported runtime channel.

## Identity, bounds and realization

Derive variation from recorded seeds and stable element identities. If an ID is absent, topology changes or an input collection is replaced, inspect whether generated assignments remain stable; do not describe a fixed seed as immunity to every input edit. Preserve an explicit correspondence table when consumers depend on durable part identity.

Bound point counts, nested instances, source complexity, realized geometry, memory and evaluation time. Test empty, minimum, representative and maximum inputs, including a dense worst case. Culling the viewport does not bound evaluation or export. Record measured counts before accepting the candidate.

Keep instances until the declared downstream operation requires geometry. For realization, specify selected instances and nesting depth, then recheck UVs, materials, IDs, attribute type/domain propagation and parent ownership. Realization can greatly increase memory and combines instance/base attributes; it is a derived stage rather than an automatic export fix.

## Deliver reproducible evidence

Save the actual node group and working scene, resolved dependency identities, parameters, seeds and output measurements. Reopen and evaluate in a clean session, compare repeated runs, and test regeneration after a controlled source change. Keep manual edits in separately owned layers or freeze their result with ancestry; regeneration must not silently discard them.

These procedures supply guidance, not a bundled generator or node-group library. Missing native evaluation is blocked/not-run, never a passing procedural result. Existing exact-script validation and connected-authoring rules still govern any implementation.

Primary references: [group interfaces](https://docs.blender.org/manual/en/4.5/interface/controls/nodes/groups.html), [attribute domains](https://docs.blender.org/manual/en/4.5/modeling/geometry_nodes/attributes_reference.html), and [Realize Instances](https://docs.blender.org/manual/en/4.5/modeling/geometry_nodes/instances/realize_instances.html). Inspect the selected Blender 4.5 installation before relying on a node or socket.
