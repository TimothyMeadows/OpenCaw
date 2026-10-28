# Choose and prepare a motion profile

Skinned subjects need a real rest/bind pose, fitted skeleton, normalized weights, stable root and deformation-ready geometry. Inspect shoulders/hips/joints and equipment at extremes. A generated display mesh with fused limbs, clothing or missing hidden surfaces may need modeling repair or an approved neutral-pose production version before motion authoring. Declared landmarks are artist inputs; a template name is not proof of a correctly fitted rig.

Articulated mechanical assets need independent moving parts and real hierarchy/pivots. Establish wheels, steering, suspension, propellers, doors and control surfaces only when present and requested. Separate clip-driven and continuous-parameter transform ownership. Missing independent geometry blocks the affected articulation; metadata cannot create a movable wheel inside a fused hull.

Rigid assets need stable root/coordinates/anchors and any local response curves, without artificial skeletons. Ship travel is controller-owned; speed/acceleration can drive banking, thruster response and presentation. Mounted characters and composite vehicles have explicit component ownership rather than an assumed universal humanoid rig.

Define the game's actual motion set. A humanoid may need idle/run, starts/stops/turns, jump takeoff/airborne/fall/landing, swimming entry/idle/movement/exit and death entry/settle. No universal attack or combat-collider requirement applies to every profile. Custom anatomy and creatures need explicit recipes and review.

Preserve model and per-clip rights independently. Retarget only declared compatible source motion with explicit source/target mapping, rest-axis correction, root translation policy and target rig identity. Do not infer commercial clearance from a tool's source-code license. The native baseline uses local authored and cleared motion inputs, with no external provider default or vendor skeleton preset.
