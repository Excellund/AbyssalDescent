---
name: encounter-identity-balance
description: "Balance or retune encounters in Godot while preserving encounter identity first. Use for per-bearing difficulty tuning, pressure changes, and encounter composition adjustments."
argument-hint: "Encounter names, target bearings, and balance goals"
---

# Encounter Identity Balance

Use this skill when encounter balance is changing and identity must remain the primary constraint.

## Terminology
- **Encounter**: a room composition type — Skirmish, Crossfire, Blitz, Onslaught, Fortress, Suppression, Vanguard, Ambush, Convergence, Gauntlet, Undertow.
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
   - Undertow is a standard Act 2–3 encounter, with an obstacle-free center, light melee pursuit and staggered Drifter rings. Keep at most two living Drifters after biome/count modifiers, co-op and spawn-time additions; cap the planned profile before counting remaining enemies so blocked spawns cannot prevent room completion.
   - Gate act-specific encounters by the active act/biome, not raw depth (Bearing room counts differ). Keep new debug enum entries appended so existing saved Inspector selections retain their meaning.
   - New cover templates must leave a safe center, multiple passable gaps, and room-edge clearance for every character; movement Arcana may exploit the formations, but ordinary movement must remain viable. Existing saved layouts remain valid.
   - Preserve chosen layouts and canonical encounter identity through Endless normalization. Display suffixes such as `Tier 3` must not disable encounter-specific spawn limits; include legacy profiles that have only the suffixed label.
   - Before promoting a specialist to an encounter's signature threat, verify its host-owned hazard state and attack cues replicate to joiners and that visual-only client simulation never deals damage.
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
