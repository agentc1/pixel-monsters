# Complex Unity Package Readiness Roadmap

This document tracks the work needed before attempting a substantially more complex Unity package than **Pixel Art Top Down - Basic**.

The goal is not to make a universal Unity importer. The goal is to make the current importer resilient enough that a new package can be scanned, triaged, imported incrementally, and tested without guessing which assumptions broke.

## Current Baseline

The Basic importer currently supports:

- direct `.unitypackage` and extracted Unity metadata inputs
- semantic prefab reconstruction for the Basic pack
- imported Basic demo scenes, preview wrappers, and a playable runtime wrapper
- grid-based runtime movement through a generated navigation map
- live navigation overlays, designer overrides, and override baking
- synthetic regression tests, developer-local real-pack acceptance tests, manual QA scripts, and MCP-driven runtime probes

The next package should not be attempted as a blind import until the readiness gates below are met.

## Readiness Gates

Before choosing the next package, we should be able to answer these questions from generated reports and tests:

- What Unity classes and asset types does the package use?
- Which features are imported, approximated, deferred, or unsupported?
- Which generated scenes load without missing resources?
- Which cells are navigable, why are they navigable, and what gameplay effects are attached?
- Which designer corrections survive save, reload, bake, and reimport workflows?
- Which failures are package-specific content gaps rather than importer regressions?

## Milestone 1: Navigation Semantics

Status: Next

Purpose: make the navigation map explain gameplay meaning, not just boolean movement.

Deliverables:

- Add per-cell semantic data to `CainosGridNavigationMap`.
- Add `query_cell(layer, cell)` returning walkable state, blocked state, reason tags, terrain tags, source, and effect tags.
- Add `query_move(actor_profile, from_layer, from_cell, direction)` returning allowed, reason, target layer/cell, movement kind, move cost, effects, and transition details.
- Keep `is_cell_navigable()` and `can_step()` compatible for existing tests and runtime code.
- Display selected-cell reason/tag data in the navigation overlay HUD.
- Record designer edits with explicit reasons such as `designer_walkable` and `designer_blocked`.

Acceptance criteria:

- Existing Basic runtime navigation tests still pass.
- Overlay edit mode shows the active cell's semantic reason.
- A blocked move can distinguish at least `unsupported`, `blocked_cell`, `blocked_edge`, `from_blocked`, and `wrong_transition` style failures.
- A stair move reports a transition movement kind instead of looking like a normal step.

## Milestone 2: Reimport-Safe Designer Data

Status: Planned

Purpose: protect human-authored navigation and metadata corrections when generated output is refreshed.

Deliverables:

- Define which generated resources are safe to overwrite and which resources are designer-owned.
- Move or mirror baked navigation corrections into a stable designer-owned location, or implement a merge step during reimport.
- Add manifest entries describing preserved designer data.
- Add a reimport test proving corrections survive a clean import over existing output.

Acceptance criteria:

- A designer can mark a cell blocked, save it, bake it, re-run import, and keep the correction.
- The importer does not silently discard baked navigation work.
- The report clearly states whether designer navigation data was created, preserved, merged, or skipped.

## Milestone 3: Package Audit Report

Status: Planned

Purpose: make unknown Unity content measurable before implementing support.

Deliverables:

- Add scan-only reporting for Unity document class IDs and class names.
- Count unsupported Unity features by package, scene, prefab, and asset path.
- Report MonoBehaviour script GUIDs, known behavior kinds, unknown behavior kinds, and missing script references.
- Report materials, shaders, animation clips/controllers, particle systems, audio assets, cameras, lights, tilemap extras, prefab variants, and nested prefab depth.
- Add a concise Markdown summary plus a machine-readable JSON report.

Acceptance criteria:

- Running scan on a new package produces a prioritized feature inventory.
- Unsupported content appears with asset paths and next-step guidance.
- The report is useful before any import code changes are made for that package.

## Milestone 4: Tile And Gameplay Metadata Model

Status: Planned

Purpose: define how Godot TileSet custom data, navigation-map cell data, prefab metadata, and runtime gameplay rules fit together.

Deliverables:

- Define canonical keys for terrain, movement, visibility, projectile blocking, hazards, interaction, and move cost.
- Use TileSet custom data for reusable tile-archetype defaults where appropriate.
- Use the navigation map for placed-cell and layer-specific truth.
- Use typed runtime scripts/resources for gameplay behavior rather than relying on generic metadata.
- Document the ownership boundary between imported defaults and designer-authored overrides.

Acceptance criteria:

- A tile can carry default terrain/effect tags.
- A placed cell can override those defaults without changing every instance of the same tile.
- Runtime movement queries consume the merged result.

## Milestone 5: Importer Capability Expansion

Status: Planned

Purpose: address the most likely feature gaps found by the package audit without losing the current Basic stability.

Candidate areas:

- deeper nested prefab and prefab-variant override support
- disabled object/component handling
- more Unity component class coverage
- animation clip and animator-controller reporting or partial conversion
- material/shader fallback mapping
- trigger/collision layer semantics
- composite or more complex 2D collider handling
- package-specific behavior hint normalization

Acceptance criteria:

- Each new capability has a synthetic fixture case.
- Each new capability has at least one real-pack acceptance anchor when licensed content is available.
- Unsupported cases remain explicit in reports instead of silently degrading.

## Milestone 6: Complex Package Pilot

Status: Planned

Purpose: run a controlled first import of a more sophisticated Unity package.

Process:

1. Run package audit only.
2. Decide the minimum useful import target for the package.
3. Add synthetic fixtures for the new feature classes.
4. Implement only the required importer/runtime support.
5. Generate preview scenes and package-specific reports.
6. Use MCP/runtime probes where gameplay or navigation behavior matters.
7. Document known differences before treating the package as supported.

Acceptance criteria:

- The package has a report-backed support boundary.
- At least one generated scene can be opened and visually inspected.
- Any playable scene has a navigation debug overlay and runtime probe path.
- Known gaps are explicit and actionable.

## Ongoing Quality Bar

Every milestone should preserve:

- code-only repository boundaries; no licensed package content committed
- deterministic generated paths and reports
- headless regression coverage for synthetic fixtures
- developer-local real-pack acceptance coverage where licensed content is required
- manual QA instructions for visual/editor workflows
- clear separation between generated assets and designer-owned edits

## Current Next Step

Start with **Milestone 1: Navigation Semantics**. It strengthens the current Basic runtime scene and creates the movement/effects foundation needed before a more complex package introduces terrain, hazards, doors, bridges, water, or package-specific traversal rules.
