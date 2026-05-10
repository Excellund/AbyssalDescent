# Player.gd decomposition audit (May 2026)

`scripts/player.gd` is the largest gameplay script. Apply the same discipline as
`world_generator_decomposition_pattern.md`: only extract genuine cohesive
islands, not trampolines.

## Established pattern

- Helper lives in `scripts/core/` as a `RefCounted` `class_name`.
- For pure-geometry / pure-function blocks, prefer **stateless `static`
  methods** and pass `self` (the `CanvasItem`) as the first arg. Selection
  logic stays on `Player` so the source-of-truth flags don't leak.
- Existing extraction: `PlayerIdentitySilhouette` (5 per-character draw
  variants + default fallback).

## Audited and rejected (would be trampolines)

These look like islands but every method writes/reads `Player` state, calls
`_broadcast_cue_event`, or fires queue_redraw on the player. Extracting them
forces a `_player` back-reference and round-tripping for every line of logic —
no clarity gain.

- **Cue event handlers** (`apply_network_cue_event` + ~25 `_on_cue_*`
  methods): each handler mutates `Player` dictionaries
  (`wraithstep_remote_mark_expiry_by_network_enemy_id`, combo counters,
  execution_edge timers) or calls `player_feedback.*`. The handlers are
  already one-liners around field assignment; moving them moves the dict
  ownership too, which spreads sync state across two files.

- **Cue dispatch table / registry rewrite** (the "data-driven cue
  dispatcher" idea): also rejected. Of 28 cases, 6 are stateful
  (`static_wake_dot`, `execution_edge_state`, `wraithstep_mark_add/remove/
  clear`, `enemy_apply_slow`) and cannot fit a uniform table — they
  mutate Player dicts or resolve nodes. Of the remaining 22, at least 2
  (`voidfire_ui_state`, `oath_ui_state`) use runtime-computed defaults
  (`maxf(1.0, void_heat_cap)`, `_get_indomitable_fill_requirement()`),
  so entries need per-row closures, not literals. Net result: equal LOC,
  worse navigability (Find-Refs on `play_world_ring` no longer lands on
  the handler), parallel match block still required for the stateful 6.
  Today's match in `apply_network_cue_event` IS the registry, with
  maximally local data flow. Do not revisit unless cue churn becomes a
  measurable maintenance burden (e.g. >2 cues added per week or repeated
  copy-paste bugs in the unpacking).
- **Static wake trail block** (`_update_static_wake_trails`,
  `_emit_static_wake_trails_along_dash_segment`,
  `_append_static_wake_trail`, `_clamp_static_wake_position_to_arena`):
  reads/writes the trail array on `Player` and broadcasts
  `static_wake_dot` cues. State + replication are entangled.
- **Wraithstep marks** (`_update_wraithstep_marks`,
  `_apply_wraithstep_marks_during_dash`, `_consume_wraithstep_mark`,
  `_apply_wraithstep_chain`, `_apply_wraithstep_splash`): mutates per-enemy
  mark dictionaries on `Player` and resolves attack hits via
  `_resolve_attack_hit`. Inseparable from combat resolution.
- **Eclipse / Apex / Voidfire / Iron Retort updates**: each owns a small
  state machine on `Player` driven by per-frame deltas. Moving any one of
  them would still require `_player.field = value` writes for every step.
- **Damage breakdown / cone hit detection** (`_get_damageable_enemies_in_cone`,
  `_resolve_attack_hit`, `_build_damage_breakdown`): the central combat
  pipeline. Many call sites depend on its current locality next to the
  attack handlers.

## Reject any future "extract another helper from player.gd" request

unless it identifies a NEW cohesive island that:
1. Reads only its arguments (or a small, named subset of `Player` fields).
2. Does not call back into `Player` mutators or broadcast RPCs.
3. Has one (or a few) entry points already grouped together.

If the candidate fails any of these, leave it on `Player`.
