---
name: boon-design
description: "Design or rework boons (upgrade-type powers) in Godot. Use when adding, renaming, or rebalancing entries in scripts/power_registry.gd UPGRADE_BALANCE. Enforces no-healing, no-timing-manipulation rules and the upgrade id rename requirement."
argument-hint: "Boon id, intended identity, and balance goals"
---

# Boon Design

Use this skill whenever a boon (upgrade-type power) is added, reworked, renamed, or rebalanced.
Boons live in [scripts/power_registry.gd](scripts/power_registry.gd) under `UPGRADE_BALANCE` and `UPGRADE_STACK_LIMITS`.

## Hard Rules

### 1. Boons MUST NOT provide healing
- No heal-on-kill, heal-on-hit, heal-on-room-clear, lifesteal, regen, or pickup heals.
- Max-HP boons MUST NOT auto-heal the delta on pickup.
- Healing is reserved for trial powers, room rewards, and explicit recovery systems. Mixing healing into boons collapses the "stat upgrade" identity into the trial-power space.

### 2. Boons MUST NOT manipulate timings
Forbidden levers:
- Cooldown reductions of any kind (dash cooldown, attack cooldown, ability cooldowns).
- Attack speed, animation lock, recovery time, windup time.
- Any modifier whose payoff is "press the same button more times per second."

Why: timing boons reward mashing, not decision-making. They flatten the moment-to-moment combat rhythm and make encounters feel like DPS races instead of readable threat patterns. The fixed combat cadence is a design contract — players should learn one rhythm and master it, not have it shifted by random rewards.

Acceptable adjacent space: bonuses that trigger on conditions the player chooses (target HP threshold, slowed/marked enemies, first hit on a target), or stat increases that change capability without changing tempo (damage, range, arc, armor, max HP, dash distance).

### 3. Renaming a boon REQUIRES renaming its id
If a boon's identity, fantasy, or mechanic changes meaningfully, rename the id (the dictionary key in `UPGRADE_BALANCE`) — not just the display name. Stale ids confuse telemetry, mislead future readers, and break the link between save data and intended behavior.

Rename checklist (find/replace the old id across ALL of these):
- [scripts/power_registry.gd](scripts/power_registry.gd): `UPGRADE_BALANCE` key, `UPGRADE_STACK_LIMITS` key, `get_upgrade_pool()` entries (description var, dynamic call, `Power.new()`), `get_objective_upgrade_pool()` favored set, `_get_upgrade_fallback_description()` match arm.
- [scripts/upgrade_system.gd](scripts/upgrade_system.gd): `UPGRADE_IDS` key, `apply_upgrade()` match arm, `get_upgrade_card_description()` match arm.
- [scripts/player.gd](scripts/player.gd): `boon_ids` set in the apply-by-id helper, `RUN_SNAPSHOT_PROPERTIES` (if the backing field name changed too), the backing field declaration, any apply-helper functions named after the boon.

If the backing property on the player also changes (e.g. `swift_strike_dash_cooldown_refund_on_hit` → `vanguard_bonus_damage`), rename that field everywhere it appears. Do not leave dead fields behind.

## Procedure

1. **State the identity in one sentence.** Example: "Vanguard rewards swapping to fresh targets by adding burst damage to enemies above a HP threshold."
2. **Verify identity is not healing or timing.** If it touches HP regeneration or any cooldown/speed/lock duration, redesign.
3. **Pick a backing property.** Either an existing player stat (`max_health`, `attack_damage`, `attack_range`, `attack_arc_degrees`, `max_speed`, `dash_speed`, `iron_skin_armor`, `battle_trance_move_speed_bonus`) or a new bespoke field (e.g. `vanguard_bonus_damage`).
4. **Write `UPGRADE_BALANCE` entry** with `kind` (`add_int`, `add_float`, `add_clamp`, `mul_min`), `property`, and per-stack values. Keep stack scaling linear unless there is a documented reason.
5. **Set `UPGRADE_STACK_LIMITS`.** Default to 3 for additive stat boosts, 2 for high-impact stats (max HP, multiplicative dash), 1 for unique mechanics.
6. **Add display + description.**
   - Add display name in `get_upgrade_pool()` `Power.new(...)`.
   - Add fallback description in `_get_upgrade_fallback_description()`.
   - Add rich card description in `upgrade_system.get_upgrade_card_description()` showing `current -> next` values.
7. **Wire the apply path.** If using a generic stat property, the default `apply_upgrade()` arm is sufficient. If the boon needs side effects (e.g. syncing `health_state`), add a dedicated match arm in `upgrade_system.apply_upgrade()`.
8. **Wire the runtime effect** if the property is bespoke (e.g. add `_get_vanguard_bonus_damage(enemy_node)` and add it into `_perform_melee_attack` and `_apply_razor_wind` damage assembly).
9. **Add the field to `RUN_SNAPSHOT_PROPERTIES`** in `player.gd` so saves persist it.
10. **Add the id to the `boon_ids` set** in `player.gd`'s id-routing helper so debug/console application works.
11. **Run script diagnostics on every changed file.**

## Anti-Patterns to Reject

- "+10% attack speed" — timing.
- "Dash refunds 50ms on hit" — timing.
- "Heal 5 HP every room cleared" — healing.
- "Lifesteal 10% of damage dealt" — healing.
- "Cooldowns 5% faster while above 80% HP" — timing.
- A new boon that duplicates an existing trial power's payoff (boons should remain stat-shaped, not turn into mini-trials).

## Quality Bar

- Every boon should describe itself in one card line and one mental model.
- Players should be able to plan around boons before they trigger; boons should not pop up surprise effects.
- A boon at max stacks should feel meaningful but never trivialize the encounter identity.
