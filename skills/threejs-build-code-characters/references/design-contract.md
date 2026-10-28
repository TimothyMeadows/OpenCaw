# Character design contract

Freeze these decisions before detailed authoring:

- Identity: character or creature kind, concise brief, intended use, temperament, distinguishing idea, and signature semantic parts.
- Presentation: primary and required views, close/mid/far context, exact representative pixel heights, actor count, negative-space intent, and asymmetry policy.
- Structure: coordinate system, origin and grounding, semantic part hierarchy, joints, symmetry groups, attachments, sockets, colliders, and tolerance rationale.
- Motion: `static`, `articulated`, or `skinned`; skeleton identity when applicable; influence limit; required animation roles; clips; contacts; looping; root-motion ownership; and representative poses.
- Budgets: bones, clips, shader variants, texture bytes, representative actors, and contextual CPU/GPU thresholds when measurable.
- Review: canonical builder identities, independent-review requirement, per-gate attempt limit, and repeated-failure limit.

Use stable lowercase kebab-case identifiers. Make every signature part a declared semantic part. Keep part and joint parent graphs acyclic. Static actors declare no skeleton, influences, or clips; skinned actors declare a skeleton and positive influence limit.

Do not encode presentation-only fixes as structural truth. When a design choice is unknown and changes the acceptance target, use `request-input` instead of inventing it.
