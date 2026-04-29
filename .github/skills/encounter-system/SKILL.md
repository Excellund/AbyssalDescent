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
- Encounter compositions live in `BEARING_DEFINITIONS` in `scripts/encounter_profile_builder.gd`.
- Random hard mutator compatibility is decided by each mutator's `affected_archetypes` entry in `_hard_mutator_pool()`.
- Enemy mutator stat application lives in `ENEMY_MUTATOR_STAT_MAP` in `scripts/enemy_spawner.gd`.
- Debug startup controls are read from the DebugSettings child in `scenes/Main.tscn` via prefix-free fields (for example: `enabled`, `start_encounter`, `mutator_override`).

## When To Edit What
- Add or retune an encounter:
  - Update `BEARING_DEFINITIONS`.
  - Preserve the encounter's signature threat pattern across all 4 difficulty ranks (Pilgrim/Delver/Harbinger/Forsworn).
  - Keep labels aligned with glossary/debug naming.
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
  - Respect `DebugSettings.enabled` gating for startup debug behavior.
6. If an encounter name or gameplay meaning changes, update `scripts/shared/glossary_data.gd` in the same change.

## Verification
1. Run diagnostics on every changed script.
2. For each touched encounter, do a sanity check across all 4 bearings (Pilgrim, Delver, Harbinger, Forsworn).
3. If mutators changed, sanity-check at least one compatible room and one incompatible room.
4. If enemy mutator scaling changed, confirm overlay/theme application still appears on affected enemies.

## Pitfalls
- Do not reintroduce encounter-specific build/scaling helper sprawl when `BEARING_DEFINITIONS` can express the change.
- Do not add a random hard mutator without `affected_archetypes`, or invalid rooms can roll it.
- Do not duplicate per-enemy mutator logic outside `ENEMY_MUTATOR_STAT_MAP` unless the behavior is genuinely exceptional.
- Do not assume transport FX appears on custom boss draw paths: if a boss bypasses `_draw_common_body()`, its `_draw()` must explicitly gate on `is_spawn_transporting()` and render `_draw_spawn_transport_fx(...)` before returning.