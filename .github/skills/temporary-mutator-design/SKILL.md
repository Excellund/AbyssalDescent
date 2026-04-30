---
name: temporary-mutator-design
description: "Design or rework temporary mutators that can target player, enemies, or both while preserving encounter identity and reward excitement."
argument-hint: "Mutator fantasy, source objective/encounter, target scope, and stacking goals"
---

# Temporary Mutator Design

Use this skill when creating or redesigning temporary mutators that persist across encounters.

## Design Targets
- Give each mutator a clear fantasy and recognizable identity (name, icon, color, banner).
- Keep mutator power tied to player action patterns, not passive waiting.
- Preserve encounter/objective identity instead of flattening all pressure into raw stat buffs.
- Keep behavior predictable through explicit scope and stacking rules.

## Required Contract Fields
- `id`
- `name`
- `icon_shape_id`
- `theme_color`
- `target_scope` (`player`, `enemy`, `both`)
- `effects` (typed effect list)
- `stack_policy` (`refresh`, `replace`, `stack`)
- `stack_limit`
- `stack_falloff`
- `duration_encounters`

## Runtime Surfaces
- Contract and helper APIs: scripts/shared/encounter_contracts.gd
- Reward/source wiring: scripts/encounter_profile_builder.gd, scripts/world_generator.gd, scripts/reward_selection_ui.gd
- Player effects and lifecycle: scripts/player.gd
- Enemy effects: scripts/enemy_spawner.gd
- HUD and identity display: scripts/world_hud.gd
- Glossary sync: scripts/shared/glossary_data.gd

## Procedure
1. Define mutator identity first.
2. Define scope and effect entries in contract format.
3. Define stack behavior and duration.
4. Wire source encounter/objective reward path.
5. Validate player-only, enemy-only, and both scopes.
6. Sync icon/name/desc in reward UI, HUD, and glossary.
7. Run diagnostics on all changed scripts.

## Guardrails
- Do not leave mutator identity partial (for example, name without icon mapping).
- Do not hide stack behavior implicitly in code branches.
- Do not apply enemy-target temporary effects directly inside individual enemy scripts.
- Do not let temporary mutators bypass objective pressure readability.

## Validation Checklist
- Identity: banner, icon, color, and glossary text agree.
- Scope: effects apply only to intended targets.
- Stacking: refresh/replace/stack behavior matches contract.
- Duration: decrement and expiry happen exactly once per encounter.
- Bearings: Pilgrim, Delver, Harbinger, Forsworn still feel monotonic.
