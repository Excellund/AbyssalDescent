---
name: encounter-content-sync
description: "Add or update encounter content in Godot and keep all required surfaces in sync, including glossary, debug entry points, and route-facing labels/icons."
argument-hint: "Encounter name and what changed"
---

# Encounter Content Sync

Use this skill whenever an encounter is added, renamed, removed, or meaningfully redefined.

## Required Sync Surfaces

- Encounter construction and selection:
  - scripts/encounter_profile_builder.gd
- Route and door integration:
  - scripts/world_generator.gd
  - scripts/world_renderer.gd
- Glossary entry text and grouping:
  - scripts/shared/glossary_data.gd
- Debug discoverability (when applicable):
  - scripts/encounter_profile_builder.gd build_debug_encounter_profile
  - scripts/world_generator.gd debug encounter handling
  - scenes/Main.tscn DebugSettings node values

## Debug Settings Contract

- Debug runtime settings are isolated under scenes/Main.tscn in the DebugSettings child node.
- DebugSettings properties are prefix-free (for example: enabled, start_encounter, start_depth, mutator_override).
- Keep debug startup behavior gated by DebugSettings.enabled.
- If encounter debug entry points change, keep menu autostart checks aligned with DebugSettings.enabled + DebugSettings.start_encounter.
- Treat `scripts/shared/encounter_contracts.gd` DEBUG_ENCOUNTER_MAP keys as canonical debug encounter names.
- Do not maintain alias maps for debug encounter keys unless explicitly requested.
- When objective debug keys are renamed, update objective reward detection to use contract metadata (for example `debug_encounter_is_objective`) instead of key-prefix checks.

## Procedure

1. Update encounter source-of-truth builders/scalers.
2. Update route selection or door metadata if encounter can appear through doors.
3. Prefer shared door presentation helpers in `scripts/shared/encounter_contracts.gd` for route-facing labels, colors, icons, and boss/rest identity instead of mutating door dictionaries downstream in `world_generator.gd` or re-deriving display text in `world_renderer.gd`.
4. Add or update glossary entry with accurate player-facing description.
5. Update debug hooks/settings when practical so encounter can be tested directly.
6. If canonical debug key names or objective kind names change, sync all key consumers in the same change:

- `scripts/shared/encounter_contracts.gd` (`DEBUG_ENCOUNTER_MAP`, objective kind setters)
- `scripts/encounter_profile_builder.gd` (`build_debug_encounter_profile`, objective kind dispatch)
- `scripts/world_generator.gd` (debug routing, boss key checks, objective reward mode checks, telemetry bearing keys)
- `scripts/objective_runtime.gd` and `scripts/world_hud.gd` objective kind comparisons

7. Run diagnostics for all touched scripts.
8. Report a sync checklist in the final summary.

## Done Criteria

- Encounter exists where intended in generation flow.
- Glossary reflects current meaning.
- Door prompt naming/icon behavior is coherent.
- No script errors in changed files.
