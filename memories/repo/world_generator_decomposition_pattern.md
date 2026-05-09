# WorldGenerator decomposition pattern

When extracting a cohesive responsibility out of `scripts/world_generator.gd`:

- New helper is a `RefCounted` script under `scripts/core/`.
- Constructor takes the WG node and stores it as `var _world: Node2D` (type the field — untyped `_world` returns Variant on `.foo()` and breaks `:=` inference at every call site).
- Move both the state (per-id dictionaries, tuning vars, last-tick metrics) and the cohesive methods. WG keeps a single `var <helper_name>` handle.
- `@rpc` methods MUST stay on WG (they're bound to the WG node's authority). The helper invokes them via `_world._sync_xxx.rpc(...)`.
- Per-tick entry call from WG becomes a single delegation (`<helper>.tick(delta)`).
- Receive-side handlers (joiner-applies-state) stay on WG next to their `@rpc` methods.
- External callers that previously hit private WG methods (`world._foo`) must be updated to call the helper (`world.<helper>.foo`). Search the whole `scripts/` tree for stragglers — `objective_runtime.gd` is a frequent caller.
- Existing examples: `RunSummaryRecorder` (telemetry/summary), `EnemyStateSyncBroadcaster` (host-side enemy state replication).
