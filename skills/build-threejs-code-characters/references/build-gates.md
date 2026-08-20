# Ordered character gates

Apply exactly one required character gate to each generic CODE pass:

| CODE pass | Character gate | Owner | Required claim |
|---|---|---|---|
| `blockout` | `blockout-readability` | independent reviewer | Whole-character identity and silhouette read at intended scale. |
| `structure` | `structure-integrity` | calibrated machine evidence | Grounding, hierarchy, symmetry, and attachments satisfy declared tolerances. |
| `form` | `form-readability` | independent reviewer | Required and signature parts read as coherent attached forms. |
| `materials` | `materials-style` | independent reviewer | Values and materials preserve style, hierarchy, and identity. |
| `interaction` | `interaction-runtime` | calibrated machine evidence | Applicable motion, contacts, sockets, colliders, and teardown behave correctly. |
| `optimization` | `optimization-budget` | calibrated machine evidence | Construction is deterministic and contextual budgets and repeated lifecycle limits hold. |

For reviewer gates, supply the reviewer packet as both a hashed packet field and `reviewer-packet` evidence. For machine gates, require at least one independently authored passing fixture and one focused failing fixture tied to the same measurement semantics.

A character gate passes before its paired generic CODE pass. Record the generic pass with `--character-profile`; the parent command then rejects missing, incomplete, or stale character evidence.
