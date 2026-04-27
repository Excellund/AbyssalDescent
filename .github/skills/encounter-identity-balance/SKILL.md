---
name: encounter-identity-balance
description: "Balance or retune encounters in Godot while preserving encounter identity first. Use for per-bearing tuning, pressure changes, and encounter composition adjustments."
argument-hint: "Encounter names, target bearings, and balance goals"
---

# Encounter Identity Balance

Use this skill when encounter balance is changing and identity must remain the primary constraint.

## Goals
- Preserve the encounter fantasy and signature threat pattern.
- Adjust difficulty through pressure, cadence, and bounded composition changes.
- Avoid flattening distinct encounters into similar enemy mixes.

## Procedure
1. Identify encounter identity contracts.
   - Read builders/scalers in scripts/encounter_profile_builder.gd.
   - Write down required signature units and forbidden collapses.
2. Choose scaling strategy.
   - Prefer encounter-specific scaling helpers when identity-sensitive.
   - Use shared scaling only where identity remains intact.
3. Apply per-bearing tuning.
   - Tune Pilgrim, Delver, Harbinger, Forsworn intentionally.
   - Keep progression monotonic unless a deliberate exception is documented.
4. Validate route and runtime consistency.
   - Ensure route output still matches expected encounter intent.
   - Confirm runtime systems consume profile fields consistently.
5. Perform quick sanity checks.
   - Early-depth and late-depth spot checks.
   - Objective and trial parity checks when affected.
6. Summarize clearly.
   - State what identity was preserved.
   - State what pressure lever changed and why.

## Key Files
- scripts/encounter_profile_builder.gd
- scripts/world_generator.gd
- scripts/difficulty_config.gd
