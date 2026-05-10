---
name: multiplayer-enemy-custom-state
description: Design custom per-tick network state for elites/bosses (Apex variants, multi-phase enemies) so joiners see every projectile, telegraph, and phase transition smoothly. Use when adding/refactoring an enemy that has projectile arrays, animated telegraph axes, multi-stage timers, or any custom payload sampled by `_get_custom_network_runtime_state`.
---

# Multiplayer Enemy Custom State

**When to use**: Building an Apex/elite/boss whose `_get_custom_network_runtime_state()` carries arrays (projectiles, beams, hazards) or animated derived values (rotating axes, sliding seams). Joiners must see exactly what the host sees — no missing projectiles, no shaking telegraphs, no phantom hits.

---

## The Five Rules

### 1. Joiner runs `_process_network_visuals(delta)`, NOT `_process_behavior(delta)`

`_process_behavior` is host-only when `network_simulation_enabled = false`. Any joiner-side ticking — state timers, projectile motion, axis rotation, hit-flash decay — MUST be in `_process_network_visuals`, otherwise it never runs on the joiner.

Pair every implementation of `_process_network_visuals` with `should_process_remote_visuals_every_frame()` returning true while there's anything animated to show. Default throttling will look chunky.

Reference: `scripts/enemy_mirrorline.gd`, `scripts/enemy_boss_2.gd` (Sovereign).

### 2. Custom payload has a hard size cap (~900 bytes)

`scripts/core/enemy_state_sync_broadcaster.gd::_fit_state_to_size_limit` silently erases the entire `runtime_state_delta.custom` dict when the per-enemy synced state exceeds the adaptive cap (900B for <40 active enemies, dropping to 480B at 60+).

When `custom` is erased, joiners receive position + facing + health but **none** of your gameplay state. Symptom: "first 1-2 projectiles work, the rest never appear" — small payloads ship, then the array grows past threshold and the whole field disappears.

Mitigations (apply in this order):

1. **Short wire keys.** Long names like `"axis_target_normal"` cost ~22B; `"tn"` costs ~6B. Re-expand to readable names in `_apply_*` and any merge helpers so the rest of the script stays readable.
2. **Elide derivable fields.** Per-projectile `time_total` when it equals a constant `echo_lifetime`; `hit:bool` flags when the host removes hit entries from the array immediately (so the wire never carries `hit:true`).
3. **Elide derivable scalars.** `state_time_left` can be reset on state transition via a local `_local_duration_for_state(state)` function — the joiner ticks it down between syncs without ever needing the value on the wire.

Reference: `/memories/repo/custom_runtime_state_size_budget.md`, `scripts/enemy_mirrorline.gd::_get_custom_network_runtime_state`.

### 3. Atomic delta on top-level keys

`_compute_runtime_state_delta` only checks `current_val != previous_val` per top-level key. Any sub-field change inside `custom` re-sends the WHOLE `custom` dict. So:

- A scalar that changes every frame (e.g. `state_time_left`, an animation phase) makes the entire `custom` payload re-send every host tick. This both costs bandwidth and exposes you to the size-cap erasure.
- Don't put every-frame-changing values in `custom` unless they're gameplay-critical to sync.

### 4. Animated derived state: sync inputs, derive locally

If something animates smoothly (a rotating telegraph axis, a sliding hazard), DO NOT put the animated value on the wire and overwrite the local visible state from incoming snapshots. The host samples at 30ms during attack windows, the joiner ticks every frame — the gap shows up as visible shaking.

Pattern: sync the inputs (`prev_normal`, `target_normal`, `telegraph_total`) and recompute the visible value (`axis_normal`) locally each frame from the local `state_time_left`. Reference: `_advance_axis_rotation` in `enemy_mirrorline.gd`.

### 5. Projectile arrays: stable IDs + append-only merge

When `custom.echoes` (or any projectile array) arrives on the joiner, do NOT replace the local array with the incoming snapshot. That rubber-bands every projectile to ~30Hz host samples.

Pattern:
- Allocate a stable monotonic `id` per projectile on host spawn.
- Joiner keeps locally-simulated projectiles intact; only ADDS host-spawned ids it hasn't seen and lets locally-expired projectiles despawn naturally.
- Implicit hit signal: host removes hit projectiles from its array, so any id missing from incoming = hit-or-expired. Don't put a `hit:bool` on the wire (rule #2).

Reference: `_merge_remote_echoes` in `enemy_mirrorline.gd`.

---

## Anti-Patterns to Avoid

- **Anchoring vs. drifting host body.** Joiner positions lerp toward sampled host position at a fixed rate (e.g. 14 px/s in `EnemyReplicationService`). If the host body wanders during a telegraph/reflect window, the joiner's seam visuals (anchored to the body) wobble against the lerp. Anchor host velocity to zero with `_anchor_in_place(delta)` during attack windows so the seam stays still.
- **Spawn-and-die-in-one-frame projectiles.** A projectile that spawns at point-blank range (e.g. mirror-reflected origin coincident with player) can hit + despawn within one host frame, never sampled by the broadcaster. Joiner never sees it. Fix: small post-spawn grace window (~0.12s, ≥ 4 priority sync cycles at 30ms) before damage collision is allowed.
- **Syncing every-frame ticking scalars.** `attack_anim_time_left`, `state_time_left`, `_contact_attack_cooldown_left` all change every frame and re-send the whole `custom` dict. Either omit (rule #2) or accept they cost bandwidth — be explicit about the choice.

---

## Diagnostic Checklist (when "joiner sees X but not Y")

1. Is the relevant ticker in `_process_network_visuals` (not `_process_behavior`)?
2. Does `should_process_remote_visuals_every_frame()` return true while X is happening?
3. Is `should_force_network_runtime_state_sampling()` true and `get_priority_network_sync_interval_sec()` returning ~0.03 during the attack window?
4. Estimate the custom payload size (sum of dict keys + Vector2 = 16B + float = 8B + int = 8B + bool = 2B + dict overhead ~8B). If ≥ ~700B, you're at risk; cut keys per rule #2.
5. For a missing projectile/effect specifically: is there a possible spawn-and-instantly-collide path (zero range)? Add the post-spawn grace window.

---

## Reference Implementations

- `scripts/enemy_mirrorline.gd` — full pattern: short wire keys, derived axis, append-only echoes, anchored body, post-spawn grace.
- `scripts/enemy_boss_2.gd` (Sovereign) — `should_process_remote_visuals_every_frame`, `get_priority_network_sync_interval_sec`, `_get_damageable_targets`, hit-flash + cached health bar tinting pattern.
- `scripts/core/enemy_state_sync_broadcaster.gd` — broadcaster delta, size-fit, far-enemy throttling logic.
- `scripts/enemy_replication_service.gd` — joiner position lerp at fixed px/s.

## Related Memory

- `/memories/repo/custom_runtime_state_size_budget.md`
- `/memories/repo/joiner_remote_visuals_path.md`
- `/memories/repo/multiplayer_remote_position_extrapolation.md`
- `/memories/repo/enemy_runtime_delta_semantics.md`

## Related Skills

- `multiplayer-content-integration` — registry/preload-driven content auto-sync (separate concern from per-tick state).
- `multiplayer-player-rpc-routing` — host-driven effects on specific player peers.
