---
description: "Use when adding encounters, balancing encounters, changing route generation, or editing glossary encounter definitions in Godot gameplay scripts."
name: "Encounter Workflow"
applyTo:
  - scripts/encounter_profile_builder.gd
  - scripts/world_generator.gd
  - scripts/shared/glossary_data.gd
  - scripts/world_renderer.gd
---

# Encounter Workflow

## Preserve Identity First
- Keep each encounter's signature enemy mix and combat fantasy stable.
- Increase or decrease pressure by counts, pacing, and sequencing without collapsing identity into generic compositions.
- Prefer explicit per-encounter scaling helpers when generic scaling erodes identity.

## Content Sync Checklist
- Encounter labels in scripts/encounter_profile_builder.gd match glossary names in scripts/shared/glossary_data.gd.
- New or renamed encounters are represented in debug entry points where applicable:
  - scripts/encounter_profile_builder.gd build_debug_encounter_profile
  - scripts/world_generator.gd debug encounter enum and export list
- Door-facing text/icons remain coherent with route output in scripts/world_renderer.gd.

## Before Finish
- Run diagnostics on touched files.
- Summarize identity preservation decisions and glossary/debug sync in the final response.
