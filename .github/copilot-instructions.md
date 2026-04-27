# Project Guidelines

## Encounter Workflow
- Preserve encounter identity first when balancing. Keep each encounter's signature threat pattern intact and tune pressure around that identity.
- If an encounter is added, renamed, or its gameplay meaning changes, update glossary content in scripts/shared/glossary_data.gd in the same change.
- When route policy changes, verify scripts/encounter_profile_builder.gd, scripts/world_generator.gd, and scripts/world_renderer.gd still agree on labels and icon usage.

## Validation
- Run script diagnostics for all changed files before finishing.
- For encounter work, include a quick per-bearing sanity check note in the final summary.
