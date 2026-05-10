---
name: arcana-design
description: "Design or rework arcana (trial powers) in Godot. Use when adding, renaming, or rebalancing entries in scripts/power_registry.gd TRIAL_POWER_BALANCE / TRIAL_POWER_STACK_LIMITS so that stacking past L1 feels meaningful."
argument-hint: "Arcana id, intended identity, and stacking goal"
---

# Arcana Design

Use this skill whenever an arcana (trial power) is added, reworked, renamed, or rebalanced.
Arcana live in [scripts/power_registry.gd](scripts/power_registry.gd) under `TRIAL_POWER_BALANCE` and `TRIAL_POWER_STACK_LIMITS`. Mapping to player runtime fields is in [scripts/power_parameter_mapper.gd](scripts/power_parameter_mapper.gd). Descriptions and current/next previews are in [scripts/upgrade_system.gd](scripts/upgrade_system.gd).

## Hard Rule: Stacking Must Feel Cool

A second or third pick of the same arcana MUST feel meaningfully different from picking a new arcana. If a stack is "the same effect, slightly bigger numbers", players will always diversify and the stack cap is wasted.

The required shape for any arcana with stack limit ≥ 2:

- **L1 (baseline)**: a clearly weaker version that establishes identity. Trim the L1 numbers ~10–20% below where you'd want a "satisfying single pick" to land. This makes room for L2 to feel like a real upgrade rather than a tiny bump.
- **L2 (headline)**: the version players quote when they say "this arcana is great". Two numeric knobs grow per stack, AND one structural change happens (extra charge, extra mark slot, wider arc, added side-effect, etc.).
- **L3 (mastery)**: the ceiling. Numbers continue to grow on the same two knobs, AND a second structural unlock fires (extra hit per mark, chain detonation, shockwave, full refresh, etc.).

> **Two-knob-per-stack with one structural change per stack** is the rule. If you can't name the structural change, the stack design isn't done.

## Hard Rule: Stack Limits Are Mandatory

Every arcana entry in `TRIAL_POWER_BALANCE` MUST have a matching entry in `TRIAL_POWER_STACK_LIMITS`. Without a limit, the arcana can be stacked unbounded and balance breaks. Default: 3. Use 4 only for arcana whose L4 is a small numeric polish, never a new mechanic.

## Hard Rule: No Boss/Apex Stuns

Arcana MUST NOT stun bosses or apex enemies. Stuns trivialize telegraphs and break the readable threat pattern. Acceptable substitutes:
- Brief slow (e.g. `apply_slow(0.6, 0.6)` — 60% speed for 0.6s) — mirrors `hunters_snare`.
- Damage pulse / shockwave — see `_apply_riftpunch_shockwave` for the radial-chip pattern.
- Vulnerability / fragility windows that boost the player's outgoing damage rather than disable the enemy.

## Procedure

### 1. Decide the identity
One sentence the player would say. "Hits build resonance on one target." "Dash marks enemies for splash." If you can't say it without using the word "and" twice, the identity is muddled.

### 2. Pick two numeric knobs that scale per stack
These are the levers in `TRIAL_POWER_BALANCE`. Examples:
- `damage_ratio_base` + `damage_ratio_per_stack`
- `radius_base` + `radius_per_stack`
- `bonus_damage_base` + `bonus_damage_per_stack`

Trim the base, bump the per-stack growth. The stacked version should feel ~1.5–2× the L1 version on these knobs by L3.

### 3. Pick the structural change(s)
Each stack past L1 needs a yes/no behavioral unlock. Patterns that work:

| Pattern | Example arcana | Implementation hook |
|---|---|---|
| Wider conditional band | `bloodvow` (low-HP threshold widens per stack) | `threshold_base/_per_stack/_cap` in balance, mapper emits `low_hp_threshold` |
| Extra hits per mark | `eclipse_mark`, `wraithstep` | `hits_left` on the per-enemy dict entry; only erase at 0 |
| Wider attack shape | `razor_wind` (matches player arc at L2) | `arc_match_player_at_stack` in balance, mapper reads `attack_arc_degrees` |
| Faster threshold | `voidfire` (`danger_zone_threshold_base/_per_stack/_min`) | Scaling threshold via mapper |
| Extra fault lines / projectiles | `fracture_field` (3/4/5 beams) | `min(cap, base + stack)` in spawner |
| Bigger max stack pool | `dread_resonance` (`max_stacks_base/_per_stack/_cap`) | Mapper emits `max_stacks` per stack |
| Side-effect on hit | `riftpunch` L2 slow, L3 shockwave | Conditional branch in consumer based on `<power>_stacks` |
| Cross-cutting global multiplier | `hunters_snare` L3 (2× duration on every player-applied slow) | Single helper (e.g. `_global_slow_duration_mult()`) consumed by all slow sites; multiplier also goes into the `enemy_apply_slow` cue payload so multiplayer mirrors it |
| Stored consumable trigger | `reaper_step` L2 (kill within window stores 1 extra dash credit) | Window timer field + stored-count field; dash-start gate consumes credit instead of failing on cooldown; reset both on death and run reset |
| Cooldown halving | `voidfire` L3 (overheat lockout × 0.5) | Multiply lockout at the assignment site; remember to also propagate to `apply_polar_shift_dash_lockout` if applicable |
| Recursive AoE chain | `rupture_wave` L3 (one re-trigger from farthest hit) | Pass `chain_depth: int = 0` and a hit-id set; gate recursion on `chain_depth == 0` to cap at one chain |

### 4. Wire the data
- Add or update fields in `TRIAL_POWER_BALANCE`. Use the `_base` / `_per_stack` / `_cap` / `_min` / `_max` suffix convention so the mapper can derive scaled values.
- Update `TRIAL_POWER_STACK_LIMITS`.
- Update `TRIAL_POWER_PARAM_MAP` in `power_parameter_mapper.gd` to declare the parameters this arcana exposes.
- Update `build_trial_values` match arm to derive the per-stack values from base/per_stack data.

### 5. Wire the runtime
- Counter / per-enemy state lives on the player. Reset on death and on run start.
- Side-effect branches (`L2+`, `L3+`) are gated by `player.<power>_stacks >= N`.
- For multi-hit marks, store `hits_left` on the dict entry. Decrement on consume; only erase at 0.
- For multiplayer-affecting effects (slow, knockback, status), use the existing cue broadcast path. See `multiplayer-player-rpc-routing` skill.
- New player fields that influence runtime values MUST be added to `RUN_SNAPSHOT_PROPERTIES`.

### 6. Wire the descriptions
Sentence templates in `_power_sentence_template`. Both `get_power_current_description` (build detail) and `get_trial_power_card_description` (reward card) MUST emit the structural unlocks visibly so players see what L2/L3 actually grants. Helpers go at the end of `upgrade_system.gd`:

```gdscript
func _eclipse_hits_for_stack(stack_count: int) -> int:
    return maxi(1, stack_count)
```

Helper logic in `upgrade_system.gd` MUST match the corresponding runtime helper in `player.gd` exactly. If the player picks differently from the card, the system is lying.

Description cap: 109 visible chars enforced by `description_cap_guard.assert_visible_cap`. If you bust the cap, drop the least-informative knob from the template (grace duration, internal cooldown, etc.) — not the structural unlock.

### 7. Renaming requires renaming the id
If identity, fantasy, or mechanic changes meaningfully, rename the dictionary key — not just the flavor text. Touch every site:
- `TRIAL_POWER_BALANCE`, `TRIAL_POWER_STACK_LIMITS`, the trial-power pool
- `TRIAL_POWER_PARAM_MAP` and `build_trial_values` match arms in `power_parameter_mapper.gd`
- Match arms in `get_power_current_description`, `get_trial_power_card_description`, `_power_sentence_template`, `get_power_flavor_text` in `upgrade_system.gd`
- Backing player fields and `RUN_SNAPSHOT_PROPERTIES` entries
- Glossary entries in `scripts/shared/glossary_data.gd`

## Validation

- Run script diagnostics on `power_registry.gd`, `power_parameter_mapper.gd`, `upgrade_system.gd`, and `player.gd`.
- Verify the reward card text shows the structural unlock at L2 and L3 (not just numbers).
- Per-bearing sanity check: arcana balance is bearing-agnostic, but Forsworn (highest trial frequency mult) reaches L3 fastest — confirm the L3 ceiling is intentional, not accidentally infinite.
- If multiplayer-relevant (slow / status / damage burst), confirm the cue is broadcast and applied per-peer correctly.
