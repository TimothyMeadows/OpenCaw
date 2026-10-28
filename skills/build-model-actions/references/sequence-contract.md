# Sequence and ancestry contract

Read the actual native command help and workflow schemas before writing recipe data. Bind the human-reviewed source motion package, model hash, rig identity and every used clip's sampled motion hash. A staged source review is distinct from runtime acceptance; the CLI records cooperative assertions and does not authenticate a person.

The source-motion review includes `rights: {"authorized": true, "license": "applicable model and clip terms"}`. Record actual rights to use/modify the model and selected motions. A file copy, tool license or workflow selection does not establish asset rights or accept legal terms for someone else.

Each source step has a stable ID and explicit source trim, rate, repetition count and incoming blend. Expanded occurrences retain source clip ID/hash and exact source/action times. Bake timing must fit the chosen FPS. Keep overlap within adjacent steps without triple overlap. Empty spans, missing source channels and silently repeated source loops fail.

Cue addresses identify a step occurrence and either an action-clock offset after that occurrence starts or an actual unique source marker. Marker mapping accounts for the trim and rate. Reject absent, duplicated or clipped markers. Fixed target bindings name a world-point input and a distance limit. They do not describe a gameplay target entity or grant targeting authority.

Keep source and composite motion hashes distinct. Changing source, recipe, trim, rate, blend, cue, target policy, script, tool or engine invalidates dependent evidence. Retain complete previous attempts. Initial shared composition uses in-place clips; a rigid vehicle needs no fake skeleton or combat clip set.

Export must contain real composite clips with the declared IDs and actual duration/channels. Preserve an editable source and independently re-import the GLB. Sequence graphs and effects remain separate engine data; an animation file cannot instantiate a portable particle or ability system.
