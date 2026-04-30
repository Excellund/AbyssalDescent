---
name: encounter-identity-balance
description: "Balance or retune encounters in Godot while preserving encounter identity first. Use for per-bearing difficulty tuning, pressure changes, and encounter composition adjustments."
argument-hint: "Encounter names, target bearings, and balance goals"
---

# Encounter Identity Balance

Use this skill when encounter balance is changing and identity must remain the primary constraint.

## Terminology
- **Encounter**: a room composition type — Skirmish, Crossfire, Blitz, Onslaught, Fortress, Suppression, Vanguard, Ambush, Gauntlet.
- **Bearing**: a difficulty tier — Pilgrim, Delver, Harbinger, Forsworn. "Per-bearing tuning" means adjusting how an encounter plays at each difficulty tier.
- **Bearing shorthand**: `P`, `D`, `H`, `F` map to Pilgrim, Delver, Harbinger, Forsworn.
- **Depth shorthand**: `1` through `16` map to run depth.
- **Combined shorthand**: tokens like `H3`, `P1`, `F12` mean bearing + depth. Example: `H3` = Harbinger depth 3.

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
   - Prefer table-driven tuning helpers (rank/depth maps + resolver functions) over inline one-off conditionals, so future changes stay coherent and auditable.
3. Apply per-bearing (per-difficulty-tier) tuning.
   - Tune Pilgrim, Delver, Harbinger, Forsworn rank_counts intentionally.
   - Keep progression monotonic unless a deliberate exception is documented.
   - For control-objective runtime multipliers, keep monotonic tier guarantees:
     - contested_decay_mult is not higher on easier tiers.
     - out_of_zone_decay_mult is not higher on easier tiers.
     - progress_gain_mult is not lower on easier tiers.
4. Apply depth-band tuning systematically when needed.
   - Use centralized depth-window tables with explicit start/end depths and additive biases.
   - Avoid inline one-off depth conditionals that are hard to audit.
5. Validate route and runtime consistency.
   - Ensure route output still matches expected encounter intent.
   - Confirm runtime systems consume profile fields consistently.
6. Perform quick sanity checks.
   - Early-depth and late-depth spot checks.
   - Objective and trial parity checks when affected.
7. Summarize clearly.
   - State which encounter's identity was preserved.
   - State which bearing (difficulty tier) the pressure lever changed and why.

## Key Files
- scripts/encounter_profile_builder.gd
- scripts/world_generator.gd
- scripts/difficulty_config.gd
