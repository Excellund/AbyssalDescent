---
name: vfx-transport-fx
description: "Design or tune spawn transport VFX and enemy transport animations in Godot. Use when adding a new transport effect, retuning durations, or improving visual quality of the beam/pillar/flash sequence in scripts/enemy_base.gd. Enforces crisp-glow principles: sharp core + soft halo, directed motion, restraint."
argument-hint: "What needs improving: timing feel, visual quality, a specific phase, or a new enemy color identity"
---

# VFX: Spawn Transport Effect

Use this skill when working on the spawn transport animation — the effect that plays when enemies are transported into the arena.

## System Overview

All transport VFX live in `_draw_spawn_transport_fx()` in [scripts/enemy_base.gd](../../../scripts/enemy_base.gd).

The animation is driven by two instance variables:
```gdscript
var spawn_transport_time_left: float = 0.0
var spawn_transport_duration: float = 0.0
```

`t` runs 0 → 1 over the duration (0 = just spawned, 1 = fully arrived):
```gdscript
var t := 1.0 - clampf(spawn_transport_time_left / duration, 0.0, 1.0)
```

Behavior is gated during transport — `_physics_process()` zeroes velocity and skips `_process_behavior()` until `is_spawn_transporting()` returns false.

### Durations (as of last tuning)

| Enemy type | Duration | Set in |
|---|---|---|
| Normal enemies | 0.36 s | `enemy_spawner.gd` → `spawn_transport_duration` |
| Boss 1 (Warden) | 0.40 s | `world_generator.gd` → `_begin_boss_room()` |
| Boss 2 (Sovereign) | 0.40 s | `world_generator.gd` → `_begin_second_boss_room()` |
| Survey pulse | 0.24 s | `world_generator.gd` → `_start_encounter_intro_grace()` |

### Survey-phase guard
`_start_encounter_intro_grace()` fires a 0.24 s transport pulse on all enemies. It must **not** overwrite an in-progress boss transport. The guard:
```gdscript
if enemy.has_method("begin_spawn_transport") and not enemy.get("spawn_transport_time_left") > 0.36:
```
If boss durations are increased, raise this threshold above the new boss duration.

### Per-enemy tint color
Each enemy can override `_get_transport_color()` in `enemy_base.gd`. Current identities:
- Base / normal enemies: cyan `Color(0.56, 0.94, 1.0)`
- Boss 1 Warden: amber/gold `Color(1.0, 0.68, 0.18)` — in `enemy_boss.gd`
- Boss 2 Sovereign: cool blue-violet `Color(0.46, 0.62, 1.0)` — in `enemy_boss_2.gd`

### Boss draw integration (critical)
`enemy_base.gd` only auto-renders transport FX for enemies that pass through `_draw_common_body()`.

Bosses with custom `_draw()` implementations must add an early transport gate, or spawn FX will never show:
```gdscript
if is_spawn_transporting():
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	_draw_spawn_transport_fx(BOSS_BODY_RADIUS, facing)
	return
```

Use the boss's canonical radius (`34.0` Warden, `36.0` Sovereign) to keep scaling consistent with its silhouette.

## Crisp Glow Principles

These rules produced the best-feeling result and must guide all future iterations:

### 1. Core + Glow separation — never treat them as the same layer
- **Core**: white or near-white, tight (2–5 px line width), high contrast, clearly readable shape.
- **Glow**: tinted from `_get_transport_color()`, wide (10–56 px), low alpha (0.18–0.32). Atmospheric, not structural.
- If only the glow layer exists, it reads as blur. If only core exists, it reads as harsh. Both together feel premium.

### 2. Directed motion — not random orbiting
- Radial streaks shooting outward from the body are readable and intentional.
- Orbiting particles are noisy and hard to distinguish from each other.
- Each streak: wide tinted glow pass + sharp 2 px white line + bright dot at the tip.

### 3. Restraint — maximum 3–4 visible layers at any moment
Old approach: 10 particles + 2 rings + hull + shockwave all firing simultaneously → muddy.
Target: at any given `t`, no more than 3 things are drawing at once.

### 4. Phase windows with clean edges
Each phase has an explicit `t` range. Overlap slightly (≈0.1 t) for smooth transitions, but not so much that everything fires at once.

Current phase structure:
```
t 0.00 → 1.00  Soft outer glow (tinted halo, bell-curve alpha)
t 0.00 → 0.50  Pillar descending (wide tinted fog + white 4px spine)
t 0.26 → 0.88  Body ring (wide tinted halo + white 2px arc)
t 0.30 → 0.80  4 radial streaks (directed outward, not orbiting)
t 0.72 → 1.00  Materialize bridge (pre-body silhouette fade for handoff)
t 0.86 → 1.00  Arrival flash (white core + warm ring, linear decay)
```

### Handoff smoothing at spawn end
If the moment after flash feels like a visual dip before normal body render, add or tune a short materialize bridge phase near the end (`t ≈ 0.72→1.0`):
- very low-alpha outer shell
- body-sized tinted fill
- faint white inner core

This bridges transport FX into normal enemy rendering without adding duration.

### 5. Fast arrival flash — pop and get out
The flash at `t > 0.86` should be short (0.12–0.16 t units), linear decay (not bell curve), and gone completely before the enemy starts moving. A lingering flash competes visually with the enemy's own draw.

### 6. Timing: fast snap with short decay
Typical beat: pop in 0.05–0.10 s, decay 0.25–0.40 s total. Boss transports can be slightly longer for drama, but never so long the player is waiting. If it feels slow, cut duration before cutting layers.

## Procedure

### Tuning duration only
Edit the float passed to `begin_spawn_transport()` at the call site. No FX changes needed.

### Improving visual quality
1. Read `_draw_spawn_transport_fx()` in full.
2. Identify which phase looks wrong: pillar, ring, streaks, or flash.
3. Apply crisp-glow rules to that phase only. Do not rewrite other phases.
4. Run `get_errors` on `enemy_base.gd` after editing.

### Adding a new enemy color identity
1. Override `_get_transport_color()` in the enemy's script.
2. Return a saturated `Color(r, g, b, 1.0)` — full alpha, the FX function controls per-layer alpha itself.
3. Test at all phase windows to confirm the tint reads well against the ambient scene.

### Adding a new enemy type that should transport
`begin_spawn_transport(duration)` is inherited from `enemy_base.gd`. No per-enemy changes are required unless a custom color is needed.

## Anti-Patterns

- **Don't add more orbiting particles.** They add noise without adding readability.
- **Don't use a pulsing `sin(ms * …)` for core shapes.** The pulse was removed because it made the core shimmer instead of snap. Reserve pulse for glow layers only if at all.
- **Don't widen the pillar shaft line** past ~8 px — it stops reading as a spine and starts reading as a filled rectangle.
- **Don't let the soft glow alpha exceed ~0.35.** Above that it starts to occlude the scene around the spawn point and looks fogged-in rather than atmospheric.
- **Don't forget the survey-phase guard.** Raising boss duration without raising the guard threshold means the survey pulse will overwrite the boss transport.
- **Don't assume custom boss draw paths get transport for free.** If `_draw_common_body()` is bypassed, add the explicit `is_spawn_transporting()` gate in that boss script.
