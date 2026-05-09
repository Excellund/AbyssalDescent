# WorldGenerator decomposition pattern

When extracting a cohesive responsibility out of `scripts/world_generator.gd`:

- New helper is a `RefCounted` script under `scripts/core/`.
- Constructor takes the WG node and stores it as `var _world: Node2D` (type the field — untyped `_world` returns Variant on `.foo()` and breaks `:=` inference at every call site).
- Move both the state (per-id dictionaries, tuning vars, last-tick metrics) and the cohesive methods. WG keeps a single `var <helper_name>` handle.
- `@rpc` methods MUST stay on WG (they're bound to the WG node's authority). The helper invokes them via `_world._sync_xxx.rpc(...)`.
- Per-tick entry call from WG becomes a single delegation (`<helper>.tick(delta)`).
- Receive-side handlers (joiner-applies-state) stay on WG next to their `@rpc` methods.
- External callers that previously hit private WG methods (`world._foo`) must be updated to call the helper (`world.<helper>.foo`). Search the whole `scripts/` tree for stragglers — `objective_runtime.gd` is a frequent caller.
- Existing examples: `RunSummaryRecorder` (telemetry/summary), `EnemyStateSyncBroadcaster` (host-side enemy state replication), `EnemyStateSyncReceiver` (joiner-side replication: door/spawn/objective spawn/boss spawn payloads + enemy state/death apply), `DifficultyScalingProvider` (config provider lookup + party-size + co-op health scaling + co-op durability mutator), `RoomDepthBookkeeper` (boss-target depth math + boss-unlock predicates + throttled depth-sanity clamp).
- Symmetric pattern: for any host→joiner replication concern, the broadcaster owns the host-side bookkeeping/RPC fan-out and the receiver owns the joiner-side gating/payload application. RPC methods stay on WG and one-line delegate to receiver methods.

## Saturation point (May 2026)

After 7 helpers extracted, WG is at ~3,555 lines (down from ~4,900). Further mechanical extraction is now anti-productive. Audited and rejected:

- **Room/encounter lifecycle block** (`_advance_to_next_room`, `_enter_*_boss_room`, `_finish_*_boss_clear`, `_choose_door`, `_spawn_door_options`, `_advance_room_progress`): writes 20+ WG fields read by 30+ other methods. Helper would be `_world.X = Y` trampoline.
- **EndlessModeController**: surface is already minimal — single bool + 4-line `_is_endless_mode()` wrapper + 1-call `ENDLESS_PROFILE_SCALER` delegation. `room_clear_outcome_coordinator` already consumes endless state through its dict contract.
- **RewardSelectionGate**: `reward_selection_ui` is a Node child in scene tree, used by HUD input dispatch + 2 signals + `player_flow_coordinator`. Sprawling, not an island.
- **Debug encounter starters** (`_start_debug_*`, ~200 lines): every method writes 8–14 WG fields directly. Trampoline.
- **Snapshot wrappers** (`_build_active_run_snapshot`, `_apply_active_run_snapshot`): already 1-call delegations to `RUN_SNAPSHOT_SERVICE`. Inlining makes call sites longer, not shorter.
- **Progress sync codec** (`_build_progress_sync_state` + `_sanitize_progress_sync_state` + `_apply_progress_sync_state`): split-protocol risk — apply writes 12 WG fields. Moving build+sanitize without apply means contributors must update two files when adding a sync field.

Remaining ~3,555 lines are genuine orchestration: scene-tree owner, all `@rpc` handlers (must stay on WG for authority binding), signal wiring, full game-state surface read by many systems. Reject "extract another helper" requests unless they identify a NEW cohesive island this list missed.
