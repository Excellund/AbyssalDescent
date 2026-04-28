# Project Guidelines

## Encounter Workflow
- Preserve encounter identity first when balancing. Keep each encounter's signature threat pattern intact and tune pressure around that identity.
- If an encounter is added, renamed, or its gameplay meaning changes, update glossary content in scripts/shared/glossary_data.gd in the same change.
- When route policy changes, verify scripts/encounter_profile_builder.gd, scripts/world_generator.gd, and scripts/world_renderer.gd still agree on labels and icon usage.

## Terminology
- **Encounter**: a room composition type — Skirmish, Crossfire, Blitz, Onslaught, Fortress, Suppression, Vanguard, Ambush, Gauntlet.
- **Bearing**: a difficulty tier — Pilgrim, Delver, Harbinger, Forsworn.
- The code names `BEARING_DEFINITIONS`, `bearing_key`, and aggregate fields like `deaths_by_bearing` refer to encounter type data. This is a code naming artifact; conceptually these are encounter-level fields.

## Validation
- Run script diagnostics for all changed files before finishing.
- For encounter work, include a quick per-encounter sanity check across all 4 bearings (Pilgrim, Delver, Harbinger, Forsworn) in the final summary.
