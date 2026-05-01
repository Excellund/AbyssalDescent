---
name: player-feedback-vfx
description: "Design or retune player-centric feedback VFX in Godot for readability-first top-down play, including heal/rest cues in scripts/player_feedback.gd and trigger wiring from player/world flow."
argument-hint: "What feels unclear: readability, motion direction, density, pulse timing, or trigger timing"
---

# Player Feedback VFX (Top-Down Readability)

Use this skill when adding or tuning player feedback effects that must read instantly in top-down gameplay.

## Scope

Primary runtime surface:
- [scripts/player_feedback.gd](../../../scripts/player_feedback.gd)

Common trigger surfaces:
- [scripts/player.gd](../../../scripts/player.gd)
- [scripts/world_generator.gd](../../../scripts/world_generator.gd)

## Core Rules

### 1) Anchor effects to the player footprint
In top-down, strong northward drift can read as effects falling off the character.

Prefer:
- Radial bloom around player center.
- Small tangential drift for life.
- Minimal vertical lift as accent only.

Avoid:
- Dominant upward travel as the primary motion language.

### 2) Keep symbol density low for clarity
For short heal bursts, start with 4 to 6 symbols.

Why:
- Too many symbols blur into noise during movement/combat overlap.
- Fewer symbols preserve the silhouette and improve legibility.

### 3) Separate ground pulse from symbols
Use a short ring/pulse stack to establish location, then symbols to communicate effect type.

Pattern:
- 1 fast inner pulse
- 1 mid ring
- Optional faint outer ring for falloff

This keeps the effect readable even when symbols overlap enemies or props.

### 4) Keep timing short and decisive
Target windows:
- Pulse: ~0.11 to 0.24 s
- Symbol life: ~0.34 to 0.44 s

Long tails make feedback feel sluggish and reduce event-to-feedback trust.

### 5) Reuse established color language
Use existing health color constants instead of introducing new greens.

Current source:
- `ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL`

This avoids palette drift and keeps HUD/world feedback coherent.

## Integration Pattern

1. Implement effect internals in [scripts/player_feedback.gd](../../../scripts/player_feedback.gd).
2. Expose a thin player wrapper method in [scripts/player.gd](../../../scripts/player.gd) (no VFX logic in world flow).
3. Trigger from encounter/system flow (for rest-site heal, [scripts/world_generator.gd](../../../scripts/world_generator.gd)) right after state change is applied.

Order matters:
- Apply gameplay state (heal) first.
- Trigger VFX immediately after.

## Tuning Checklist

- Top-down read: does motion look centered on player rather than drifting away?
- Density: can you parse each symbol at gameplay speed?
- Layer safety: ring/cross z-order does not hide core combat reads.
- Timing: pulse onset aligns with heal event.
- Color consistency: matches existing health language.

## Anti-Patterns

- Increasing readability by shrinking symbols too much.
- Solving clutter by extending duration.
- Adding multiple unrelated motif layers at once.
- Hardcoding new green tones when shared health greens exist.
- Wiring VFX directly in world flow without a player-level method.

## Validation

After edits:
- Run diagnostics on changed scripts.
- Verify in-game at least once at normal combat zoom and while nearby enemies/props are visible.
