# Scene report contract

`opencaw-blender-scene/v1` binds a report to one repository-relative `.blend` path and lowercase SHA-256, one production profile, and Blender 4.5.x. It records scene units and render settings; consistent totals; uniquely named objects, meshes, materials, images, armatures, actions, node groups, modifiers, simulations, and dependencies; finite transforms; cross-references; and severity-ranked findings.

Profiles add minimum evidence:

- `static-asset`: at least one mesh.
- `rigged-actor`: mesh, armature, action, and referenced skeleton identity.
- `procedural-scene`: a node group and explicit realization policy.
- `render-scene`: a camera matching the active-camera reference.
- `simulation`: a simulation with a required cache and resolved bake state.

`--require-clean` permits warnings but rejects errors, invalid topology, absent or external dependencies, unresolved required caches, and profile omissions. The full machine-checked contract is owned by `validate-blender-scene-report.sh`; human review remains required after validation.
