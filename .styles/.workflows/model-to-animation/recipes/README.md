# Motion recipe examples

The example files are editable declarations, not universal fitted rigs or automatic semantic classifiers. Match their named nodes to the real source model, fit the skeleton/pivots to actual geometry, select appropriate actions and budgets, and review the generated rig and full motion before acceptance.

- `humanoid.example.json` declares a metric humanoid skeleton and native heat skinning. Bone positions require per-model fitting. The supplied actions illustrate loop, jump, swimming and death authoring; they do not certify anatomical motion or animation-ready topology.
- `articulated-car.example.json` requires actual independent chassis/wheel nodes and calibrated radius/steering ownership. A fused body/wheel mesh must be repaired first.
- `rigid-ship.example.json` uses actual hull/thruster nodes, anchors, continuous speed parameters and cruise/boost/warp phases without an artificial skin rig.

These recipes invoke no external provider and include no purchased clips or model weights. Optional owned/licensed motion imports require separate provenance and an explicit retarget map. Adobe products and provider integrations are unsupported.
