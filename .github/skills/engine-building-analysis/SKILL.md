---
name: engine-building-analysis
description: "Analyze and design power synergies before expanding any pool (arcana, boons, boss rewards, mutators). Ensures new content creates compounding interactions, not isolated stat bumps. Use when planning 3+ new powers or rebalancing a stagnant pool."
argument-hint: "Power pool name, intended synergy patterns, and 2-3 reference powers that should be amplified"
---

# Engine Building Analysis

**Core Principle**: An engine is a system that gets better at producing results by using its own results.
- Transformations → change rules, not just values
- Synergies → components amplify each other  
- Feedback loops → outputs feed back into inputs
- Compounding → each step is stronger than the last

## When to Use This Skill

- **Before adding 3+ powers** to arcana, boons, boss rewards, or mutator pools
- **When a pool feels stagnant** (upgrades feel good in isolation but don't interact)
- **When rebalancing** to improve cohesion across difficulty tiers (Pilgrim → Forsworn)
- **When designing character-specific power sets** to ensure thematic synergies

## Engine Anatomy

### 1. Transformations (Rule Changes)
Not just "+5 damage"—powers that shift how combat works.

**Examples**:
- `first_strike`: Adds a decision point (engage above 80% HP vs. below) → changes positioning logic
- `battle_trance`: Converts movement into survivability → changes dash usage from pure repositioning to defense
- `severing_edge`: Transforms low-HP enemies from threats into damage sources → changes focus priority

**Red Flag**: If a power only scales an existing stat (damage +7, speed +17), it's a linear booster, not a transformation. Fine for filler, but engine-building powers must change what decisions matter.

### 2. Feedback Loops (Input → Output → Improves Input)
Where do power effects feed back to strengthen future actions?

**Example Loop 1: Damage Scaling Runaway**
```
heavy_blow (+7 dmg) → higher hit damage
                   ↓
trial powers scale off hit damage (razor_wind: 60% hit damage)
                   ↓
harder hits trigger more trial damage
                   ↓
player clears faster, gains more upgrades
                   ↓
loop tightens (exponential)
```

**Example Loop 2: Survivability → Aggression**
```
iron_skin (+4 armor per stack) → survive longer in danger zones
                              ↓
battle_trance (+0.22 move speed while moving) → movement = survival
                              ↓
player repositions aggressively with more confidence
                              ↓
loop: survives because armored + speed means evasion works
```

**Example Loop 3: Precision Damage on Weakness**
```
severing_edge (+14 dmg on enemies <55% HP) → focus low-HP targets
                                          ↓
execution_edge (+220% dmg every 4 hits) → hits low-HP first
                                          ↓
reach overkill threshold faster on already-wounded
                                          ↓
loop: synergy rewards planned kill order
```

### 3. Synergy Matrix
For every new power, map what it amplifies and what amplifies it.

**Template**:
```
New Power: [power_name]

Amplifies:
  ✓ [existing_power_1]: because [mechanic interaction]
  ✓ [existing_power_2]: because [mechanic interaction]
  ✓ [existing_power_3]: because [mechanic interaction]

Amplified By:
  ✓ [existing_power_A]: because [mechanic interaction]
  ✓ [existing_power_B]: because [mechanic interaction]
  ✓ [existing_power_C]: because [mechanic interaction]

Synergy Density: X/9 (at least 2 amplifies + 2 amplified-by = minimum viable engine)
```

**Real Example**: `apex_predator` (+22 dmg on enemies <50% HP, boss reward)

Amplifies:
- ✓ `execution_edge`: easier to trigger overkill on weakened targets
- ✓ `severing_edge`: 44 dmg total at stack 2 against <50% hp = rounds faster
- ✓ `battle_trance`: more damage finish = shorter danger window = trance stacks safely

Amplified By:
- ✓ `heavy_blow`: base damage up → threshold hits harder
- ✓ `first_strike`: gap openers hit harder → better setup for apex burst
- ✓ `rupture_wave`: radial damage weakens group → apex predator cleans individual

Synergy Density: 6/9 (strong engine participation)

### 4. Scaling Tiers
How does stacking change the game state? Geometric or arithmetic?

**Linear Scaling** (Additive): Each stack adds same value
```
Stack 1: +7 dmg
Stack 2: +7 dmg (total +14)
Stack 3: +7 dmg (total +21)
→ Damage output grows linearly, not exponentially
→ Safe default for stat boosters
```

**Exponential Scaling** (Multiplicative or stacking multipliers):
```
Stack 1: 60% hit damage (execution_edge base)
Stack 2: 60% + 12% = 72% hit damage
Stack 3: 72% + 12% = 84% hit damage
...with damage_mult_base: 2.2 per proc
→ Damage output is 2.2x at each trigger, scales multiplicatively
→ Exponential on each trigger, arithmetic per stack
→ Dangerous without stack limits (runaway in high-clears)
```

**Compounding Through Interaction**:
```
severting_edge stack 1: +14 dmg
+ apex_predator stack 1: +22 dmg on <50% HP
= +36 dmg on weakness zone
→ Stack 2 of both: +28 + 44 = +72 (2x)
→ Compounds because both affect same threshold
```

**Stack Limit Purpose**: Prevent soft-locks where stacked powers create unbeatable runaway (e.g., 5 stacks of +0.22 move speed = 110% move speed bonus = game balance collapses).

Typical limits:
- Stat additive (+dmg, +HP, +armor): stack limit 3
- Multiplicative/threshold-based: stack limit 2
- Unique mechanics: stack limit 1

## Analysis Checklist (Before Adding New Power)

- [ ] **Identity Clear**: One sentence that describes what rule it changes (not just value added)
- [ ] **Transformation**: Does it shift how combat decisions work, or just boost an existing stat?
- [ ] **Amplifies Existing**: Which 2-3 existing powers does it make stronger? (synergy map)
- [ ] **Amplified By**: Which 2-3 existing powers does it benefit from? (feedback loop)
- [ ] **Synergy Density**: At least 4 directional connections (2 out, 2 in)? If not, reconsider.
- [ ] **Stack Scaling**: Linear or exponential? Does stack limit prevent runaway?
- [ ] **Loop Participation**: Does it feed back into inputs (player action patterns)?
- [ ] **Bearing Monotonic**: Does adding this power maintain Pilgrim < Delver < Harbinger < Forsworn? (test mentally across all 4)
- [ ] **Not Island**: Power doesn't live orthogonal to existing loops (e.g., heal isn't in damage loops → OK if healing has its own loop; random crit chance isn't in any loop → NOT OK)

## Red Flags (Anti-Patterns)

🚩 **Isolated Stat Bump**
- Power feels good in isolation, never mentioned with other powers
- Solution: Redesign to interact with at least 3 existing powers

🚩 **Linear When Should Compound**
- Stack scaling is arithmetic for a power that should exponentially reward stacking
- Solution: Change formula to multiplicative (damage_mult_per_stack vs. damage_add_per_stack)

🚩 **Stack Limit Blocks Strategy**
- Stack limit of 1 prevents interesting multi-stacking combos
- Example: "I want first_strike + severing_edge in every build" but stacking limit 1 means can only pick one
- Solution: Increase limit to 2-3, or redesign to make 1 stack sufficient

🚩 **Transforms Wrong Variable**
- Power affects a stat that's already heavily reinforced by other synergies
- Example: Adding another +damage upgrade when heavy_blow + trial power scaling already covers damage
- Solution: Transform a different decision point (mobility, survivability, positioning)

🚩 **No Feedback Loop**
- Power affects outputs but outputs don't feed back into player input patterns
- Example: Random proc on hit (player can't control it) vs. conditional bonus on specific action (player can strategize)
- Solution: Tie bonus to player-controlled condition

## Procedure: Expanding a Power Pool

### Phase 1: Current Engine Audit (30 min)
1. List all powers in target pool
2. For each power, identify: transformation it makes, feedback loop it participates in, 2-3 existing powers it interacts with
3. Map synergy matrix (create grid of which powers interact)
4. Identify gaps: Which decision-making areas are underserved? Which feedback loops are weak?

**Questions to ask**:
- What playstyles does this pool reward? (glass cannon, tank, mobility, precision, etc.)
- What decision points matter most? (targeting, positioning, pacing, resource management)
- Which synergies are strong? Which are weak?

### Phase 2: New Power Ideation (1 hour)
1. Identify 1-2 decision points the pool doesn't yet transform
2. For each gap, propose 2-3 new powers that would strengthen feedback loops in that direction
3. For each candidate, map synergy: which 3+ existing powers does it interact with?
4. Rank by synergy density: pick powers with 4+ directional connections

**Example**: Arcana pool is heavy on damage scaling, light on survivability decision-making
- Candidate: `temporal_shield` (brief invulnerability after dash) → transforms dashing from pure movement to defensive choice
- Synergies: amplifies `blink_dash` (more dash use), amplified by `surge_step` (speed makes shield timing harder but rewarding), feeds back to `battle_trance` loop (survive longer → move more → trance stacks)
- Density: 5/9 connections ✓

### Phase 3: Balance and Stacking (30 min)
1. Set values (stat boosts, cooldown multipliers, etc.)
2. Decide stack limit: will stacking this power create exponential power growth? If yes, limit to 2. If linear, limit to 3.
3. Test mentally across all 4 bearings: does adding this power maintain Pilgrim < Delver < Harbinger < Forsworn?
4. Check for stack limit conflicts: if adding this with max stacks of amplified power, does game become unbalanced? Adjust values or limits.

### Phase 4: Telemetry Plan (15 min)
1. Plan what metrics to track: pickup rate by bearing, win rate delta by bearing, average stack count per run
2. Set success criteria: e.g., "pickup rate should be 15-25% in Delver to match pool median"
3. Plan rebalance triggers: e.g., "if >30% of runs in Harbinger + 5 stacks, reduce power by 10%"

### Phase 5: Implementation and Sync
1. Add power definitions to registry (power_registry.gd)
2. Wire power into selection pool (get_upgrade_pool, etc.)
3. Sync descriptions (fallback + card description)
4. Update glossary if pool is player-facing
5. Run diagnostics on all changed scripts

## Integration with Related Skills

**Use alongside**:
- [boon-design](../boon-design/SKILL.md): Add new boon with engine-building first
- [objective-design](../objective-design/SKILL.md): Objective rewards should strengthen existing loops or open new ones
- [temporary-mutator-design](../temporary-mutator-design/SKILL.md): Mutator effects participate in loops (not isolated to objective)
- [encounter-identity-balance](../encounter-identity-balance/SKILL.md): Balance changes should maintain synergies across bearings

## Examples from Live Codebase

### Example 1: Damage Scaling Engine
```
heavy_blow (boon): +7 damage
  ↓ amplifies
trial_power scaling: razor_wind 60% hit damage
  ↓ creates feedback
more damage per trial trigger
  ↓ amplifies
execution_edge: 4-hit multiplier on higher base damage = faster overkill
  ↓ compounds
harder fights clear faster → more runs → more upgrades
```

### Example 2: Survivability Loop
```
iron_skin (boon): +4 armor per stack
  ↓ amplifies
battle_trance (boon): movement-based speed bonus
  ↓ creates feedback
player can position aggressively in danger zones
  ↓ amplifies
surge_step (boon): +85 dash speed
  ↓ compounds
fast evasion + armor = survive longer in pressure zones
  ↓ enables
picking glass-cannon damage powers without instant death
```

### Example 3: Boss Reward Synergy
```
apex_predator (boss reward): +22 dmg on enemies <50% HP
  ↓ amplifies existing
severing_edge (boon): +14 dmg on enemies <55% HP
  ↓ synergize on same threshold
combined +36 dmg on weakness zone (non-additive, stacks interact)
  ↓ enables
focusing low-HP targets becomes overwhelming advantage
  ↓ creates feedback
bosses die faster → reward screen sooner → next run has apex_predator available
```

## Success Criteria

A well-designed engine pool satisfies:
1. **Synergy Density**: Every new power amplifies ≥2 existing + amplified by ≥2 existing
2. **Feedback Loops**: At least 3 distinct loops active across the pool
3. **Decision Transformation**: Pool offers 3+ distinct playstyle directions (damage, defense, mobility, precision, etc.)
4. **Bearing Monotonic**: Pilgrim < Delver < Harbinger < Forsworn across average run metrics
5. **Telemetry Support**: Pickup rates, win rates, and stack counts tell a coherent story of player engagement

---

**Further Reading**: See [power-description-sync](../power-description-sync/SKILL.md) for keeping display text synchronized after engine changes.
