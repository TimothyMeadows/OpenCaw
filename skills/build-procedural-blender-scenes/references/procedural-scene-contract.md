# Procedural scene contract

## Deterministic inputs

List each input, unit, range, default, stable seed, referenced collection, and output responsibility. Randomness derives only from declared seeds and stable identifiers. Evaluation must not depend on selection, collection order, wall-clock time, user preferences, or undeclared external files.

## Instances and realization

Prefer instances for repeated geometry. For each output declare `keep-instances`, `realize-for-edit`, `realize-for-simulation`, `realize-for-render`, or `realize-for-export`. Record which attributes survive realization and which downstream stage owns it.

## Bounds

Set limits for source pieces, generated instances, realized vertices and triangles, evaluation time, memory, texture dependencies, and nested node-group depth. Test minimum, representative, maximum, and adversarial parameter fixtures.

## Delivery

Choose one of: regenerate from nodes, ship a frozen realized result, or ship both with identity linkage. Record manual overrides and whether regeneration preserves or replaces them.
