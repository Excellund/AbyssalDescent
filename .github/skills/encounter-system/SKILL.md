---
name: encounter-system
description: "Refactor or extend Godot encounter generation after the data-driven cleanup. Use when changing encounter compositions, hard mutator selection, or enemy mutator stat application in scripts/encounter_profile_builder.gd or scripts/enemy_spawner.gd."
argument-hint: "Encounter name, mutator, or enemy-type change"
---

# Encounter System

Use this skill when working on the refactored encounter-generation surfaces.

## Terminology

- **Encounter**: a room composition type — Skirmish, Crossfire, Blitz, Onslaught, Fortress, Suppression, Vanguard, Ambush, Gauntlet.
- **Bearing**: a difficulty tier — Pilgrim, Delver, Harbinger, Forsworn.
- Note: the code uses `BEARING_DEFINITIONS` and `bearing_key`/`bearing_label` fields to store encounter type data. This is a code-level naming artifact; conceptually these are encounter definitions.

## Source Of Truth

- Canonical encounter compositions live in `scripts/shared/encounter_definition_data.gd`.
- `scripts/encounter_profile_builder.gd` must consume those definitions directly and must not duplicate composition tables.
- Random hard mutator compatibility is decided by each mutator's `affected_archetypes` entry in `_hard_mutator_pool()`.
- Enemy mutator stat application lives in `ENEMY_MUTATOR_STAT_MAP` in `scripts/enemy_spawner.gd`.
- Canonical debug encounter keys live in `DEBUG_ENCOUNTER_MAP` in `scripts/shared/encounter_contracts.gd`.
- Canonical objective kind strings are written by `profile_set_survival_objective`, `profile_set_priority_target_objective`, and `profile_set_control_objective` in `scripts/shared/encounter_contracts.gd`.
- Temporary transferable mutators (objective rewards and similar) are contract-driven and can target player/enemy/both.
- Keep hard mutators (room-level) and temporary mutators (cross-encounter) distinct in naming and tuning intent.
- Debug startup controls are read from the DebugSettings child in `scenes/Main.tscn` via prefix-free fields (for example: `enabled`, `start_encounter`, `mutator_override`).

## When To Edit What

- Add or retune an encounter:
  - Update canonical definitions in `scripts/shared/encounter_definition_data.gd`.
  - Preserve the encounter's signature threat pattern across all 4 difficulty ranks (Pilgrim/Delver/Harbinger/Forsworn).
  - Keep labels aligned with glossary/debug naming.
  - If canonical debug encounter keys or objective kind strings are renamed, update all contract consumers in the same change (builder dispatch, world runtime checks, objective runtime, HUD, telemetry bearing keys).
  - If debug launch paths are affected, keep `DebugSettings.start_encounter` behavior coherent in `scripts/world_generator.gd` and `scripts/menu_controller.gd`.
- Add or retune a random hard mutator:
  - Update `_hard_mutator_pool()`.
  - Set `affected_archetypes` so incompatible rooms cannot roll it.
  - Keep debug mutator support coherent through `build_debug_mutator`.
- Add a new enemy type to mutator scaling:
  - Add an entry to `ENEMY_MUTATOR_STAT_MAP`.
  - Reuse existing stat families intentionally when the enemy shares an archetype.
  - Only add new mutator stat keys in `encounter_contracts.gd` when an existing family no longer fits.
- Tune spawn intro pacing for encounters/boss rooms:
  - Add or retune a temporary transferable mutator:
    - Keep identity first (name/icon/fantasy) and define explicit target scope.
    - Use contract fields for effects, stack policy, stack limit, and falloff.
    - Ensure reward UI, HUD, and glossary all reflect the same mutator identity.
    - Ensure enemy-target temporary effects are applied through the enemy spawner pipeline, not ad hoc per enemy script.
  - Edit `begin_spawn_transport()` call-site durations in `scripts/enemy_spawner.gd` (normal) and `scripts/world_generator.gd` (bosses).
  - Keep `_start_encounter_intro_grace()` pulse from overwriting in-progress boss transport.

## Archetype Rules

- `melee`: chasers and lurkers
- `charger`: chargers and rams
- `archer`: archers and lancers
- `shielder`: shielders

Mutators match a profile if any declared archetype is present. If a filtered pool would be empty, encounter generation falls back to the full hard mutator pool.

## Procedure

1. Start in `scripts/encounter_profile_builder.gd` if the change affects room identity, encounter selection, or mutator compatibility.
2. Start in `scripts/enemy_spawner.gd` if the change affects how a mutator modifies spawned enemies.
3. Prefer data edits over new branching logic.
4. Preserve encounter identity first: do not flatten distinct encounters into similar mixes.
5. Keep debug encounter and mutator entry points working.
6. Respect `DebugSettings.enabled` gating for startup debug behavior.
7. Keep `scripts/world_generator.gd` as an orchestrator only for objectives:

- Route enemy-kill objective mutations through a dedicated coordinator/runtime surface (for example `scripts/core/objective_progress_coordinator.gd`) instead of writing objective-manager internals inline.
- Route per-frame objective tick and control-overlay redraw decisions through a coordinator surface (for example `scripts/core/objective_frame_coordinator.gd`) instead of inline world loop checks.
- Build HUD objective fields from `objective_manager.get_hud_state()` instead of duplicating direct field reads in world orchestration code.
- Keep objective kind and control-overlay predicates on `objective_manager` helpers (for example `has_active_objective`, `should_draw_control_overlay`) rather than hardcoded world-side string checks.

8. If an encounter name or gameplay meaning changes, update `scripts/shared/glossary_data.gd` in the same change.

## Verification

1. Run diagnostics on every changed script.
2. For each touched encounter, do a sanity check across all 4 bearings (Pilgrim, Delver, Harbinger, Forsworn).
3. If mutators changed, sanity-check at least one compatible room and one incompatible room.
4. If enemy mutator scaling changed, confirm overlay/theme application still appears on affected enemies.

## Pitfalls

- Do not reintroduce encounter-specific build/scaling helper sprawl when canonical encounter definition data can express the change.
- When building a profile shell that will immediately have all counts filled by `_apply_profile_counts`, do not pass placeholder count values. Use default parameters so the shell call is honest about what it owns (label and room size only).
- Do not add a random hard mutator without `affected_archetypes`, or invalid rooms can roll it.
- Do not duplicate per-enemy mutator logic outside `ENEMY_MUTATOR_STAT_MAP` unless the behavior is genuinely exceptional.
- Do not route internal world/objective calls through method-name string dispatch helpers (for example `_call(method: String, ...)` + `callv`); prefer explicit typed calls.
- Do not infer objective debug encounters via string prefixes (for example `begins_with("objective_")`) when keys are canonical data. Use contract metadata (for example `debug_encounter_is_objective`) so renames do not silently break reward routing.
- Do not assume transport FX appears on custom boss draw paths: if a boss bypasses `_draw_common_body()`, its `_draw()` must explicitly gate on `is_spawn_transporting()` and render `_draw_spawn_transport_fx(...)` before returning.
- Do not add new integer constant ladders for finite categorical state (debug modes, AI states, camera modes, tier IDs). Define enums in shared `scripts/shared/*_enums.gd` files and reference enum members directly in consumers.
- Do not mirror shared enum members with local alias constants in usage scripts unless a compatibility boundary explicitly requires legacy symbols.
