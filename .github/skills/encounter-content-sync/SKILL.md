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
  - scripts/world_generator.gd debug encounter enum/export options

## Procedure
1. Update encounter source-of-truth builders/scalers.
2. Update route selection or door metadata if encounter can appear through doors.
3. Add or update glossary entry with accurate player-facing description.
4. Update debug hooks when practical so encounter can be tested directly.
5. Run diagnostics for all touched scripts.
6. Report a sync checklist in the final summary.

## Done Criteria
- Encounter exists where intended in generation flow.
- Glossary reflects current meaning.
- Door prompt naming/icon behavior is coherent.
- No script errors in changed files.
