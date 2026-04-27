---
name: encounter-system
description: "Refactor or extend Godot encounter generation after the data-driven cleanup. Use when changing bearing compositions, hard mutator selection, or enemy mutator stat application in scripts/encounter_profile_builder.gd or scripts/enemy_spawner.gd."
argument-hint: "Encounter bearing, mutator, or enemy-type change"
---

# Encounter System

Use this skill when working on the refactored encounter-generation surfaces.

## Source Of Truth
- Bearing compositions live in `BEARING_DEFINITIONS` in `scripts/encounter_profile_builder.gd`.
- Random hard mutator compatibility is decided by each mutator's `affected_archetypes` entry in `_hard_mutator_pool()`.
- Enemy mutator stat application lives in `ENEMY_MUTATOR_STAT_MAP` in `scripts/enemy_spawner.gd`.

## When To Edit What
- Add or retune a bearing:
  - Update `BEARING_DEFINITIONS`.
  - Preserve the bearing's signature threat pattern across all 4 difficulty ranks.
  - Keep labels aligned with glossary/debug naming.
- Add or retune a random hard mutator:
  - Update `_hard_mutator_pool()`.
  - Set `affected_archetypes` so incompatible rooms cannot roll it.
  - Keep debug mutator support coherent through `build_debug_mutator`.
- Add a new enemy type to mutator scaling:
  - Add an entry to `ENEMY_MUTATOR_STAT_MAP`.
  - Reuse existing stat families intentionally when the enemy shares an archetype.
  - Only add new mutator stat keys in `encounter_contracts.gd` when an existing family no longer fits.

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
4. Preserve encounter identity first: do not flatten distinct bearings into similar mixes.
5. Keep debug encounter and mutator entry points working.
6. If an encounter name or gameplay meaning changes, update `scripts/shared/glossary_data.gd` in the same change.

## Verification
1. Run diagnostics on every changed script.
2. Do a per-bearing sanity check for touched bearings across Pilgrim, Delver, Harbinger, and Forsworn.
3. If mutators changed, sanity-check at least one compatible room and one incompatible room.
4. If enemy mutator scaling changed, confirm overlay/theme application still appears on affected enemies.

## Pitfalls
- Do not reintroduce bearing-specific build/scaling helper sprawl when `BEARING_DEFINITIONS` can express the change.
- Do not add a random hard mutator without `affected_archetypes`, or invalid rooms can roll it.
- Do not duplicate per-enemy mutator logic outside `ENEMY_MUTATOR_STAT_MAP` unless the behavior is genuinely exceptional.