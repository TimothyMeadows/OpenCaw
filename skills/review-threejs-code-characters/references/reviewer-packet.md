# Independent reviewer packet

The packet includes only what a fresh reviewer needs:

- character and gate IDs;
- immutable profile, generic manifest, source, and packet hashes;
- frozen brief, identity, style, intended use, presentation distance, pixel heights, and required views;
- the gate's exact questions and relevant contextual thresholds;
- neutral view labels, deterministic captures, and semantic-part isolation evidence;
- explicit unavailable or not-applicable markers with reasons.

The packet excludes:

- builder identity beyond the separate conflict check;
- builder reasoning, strategies, correction history, confidence, or preferred verdict;
- intended answers, hidden pass/fail labels, previous subjective reviews, or comparison ordering that reveals the target;
- evidence from a different source, manifest, profile, or packet hash.

Review whole-character views first, at their declared sizes, before isolated parts or source details. Report missing packet fields as `request-input` or `stop`; do not silently infer them.
