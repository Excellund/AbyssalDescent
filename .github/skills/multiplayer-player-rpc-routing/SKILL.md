---
name: multiplayer-player-rpc-routing
description: Route gameplay effects (knockback, status, lockouts) from host enemies to a specific player peer in Godot co-op. Use when an effect works for the host but silently does nothing for the joiner — including velocity impulses, dash lockouts, debuffs, or any host-driven mutation of player state.
---

# Multiplayer Player RPC Routing

**When to use**: Host-authoritative gameplay code (boss attacks, world hazards, objective effects) needs to apply an effect to a specific player and the joiner is unaffected even though the host is. Symptoms: velocity changes don't apply, status effects don't activate, lockout timers don't start on the remote player.

---

## Why direct RPC on player nodes fails

The player system in this project does **not** use Godot's `MultiplayerAPI` authority system. Players are instantiated locally on every peer by `world_generator.gd`, and a custom autoload (`PlayerReplicationService` at `/root/PlayerReplicationService`) handles all replication.

Two consequences make naive RPC routing fail silently:

1. **`get_multiplayer_authority()` returns `1` (host) for every player node** — `set_multiplayer_authority()` is never called on player instances. Using this to pick a peer always sends to the host.
2. **Player node paths differ between peers.** Host has `player` and `second_player`; joiner has them in a different scene-tree position relative to its local view. Calling `remote_player_node.rpc_id(peer_id, ...)` cannot match the path on the receiving peer, so the RPC is dropped silently.

The `player_id` field on the player node is the source of truth for which peer owns that instance, not `get_multiplayer_authority()`.

---

## Required pattern

Always route player-targeted gameplay effects through `PlayerReplicationService` (the autoload path is identical on every peer, so RPCs resolve correctly).

### Step 1: Add a host-entrypoint method on the service

```gdscript
## In scripts/player_replication_service.gd

## Host-authoritative: dispatch <effect> to the player owned by target_peer_id.
func send_<effect_name>(target_peer_id: int, ...args) -> void:
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_session_connected()):
		_apply_<effect_name>_local(target_peer_id, ...args)
		return
	if not bool(multiplayer_session_manager.should_broadcast()):
		return
	if target_peer_id == local_peer_id:
		_apply_<effect_name>_local(target_peer_id, ...args)
		return
	_rpc_apply_<effect_name>.rpc_id(target_peer_id, target_peer_id, ...args)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_<effect_name>(target_peer_id: int, ...args) -> void:
	_apply_<effect_name>_local(target_peer_id, ...args)


func _apply_<effect_name>_local(target_peer_id: int, ...args) -> void:
	var player_node := _get_player_node(target_peer_id)
	if player_node == null:
		return
	if player_node.has_method("<player_method>"):
		player_node.<player_method>(...args)
```

Use `"authority"` mode + `"call_remote"` because the host calls local apply directly when the target is itself; the RPC only fires for remote peers. Use `"reliable"` for one-shot gameplay effects that must not be dropped.

### Authority predicates (use these, never inline `is_host()` cocktails)

`MultiplayerSessionManager` exposes four predicates that encode every common authority check. Use them in place of ad-hoc `is_multiplayer and/or is_host()` boolean combinations — those are the largest source of host/joiner divergence bugs.

| Predicate | Meaning | Replaces |
|---|---|---|
| `is_authoritative()` | This peer owns the simulation (singleplayer or host) | `not is_multiplayer or MultiplayerSessionManager.is_host()` |
| `is_remote_replica()` | A multiplayer session is active and this peer is **not** the host | `is_multiplayer and not MultiplayerSessionManager.is_host()` |
| `should_broadcast()` | Active multiplayer host — guard `.rpc()` send sites with this | `is_multiplayer and MultiplayerSessionManager.is_host()` |
| `is_authoritative_for_peer(peer_id)` | Host (always) or any peer for its own `peer_id` | per-peer authority checks |

Rules of thumb:
- Guarding a `.rpc()` send: `if not MultiplayerSessionManager.should_broadcast(): return`.
- Guarding an authority-only RPC handler / state mutation: `if MultiplayerSessionManager.is_remote_replica(): return`.
- Singleplayer-or-host code path: `if MultiplayerSessionManager.is_authoritative():`.
- Never write `is_multiplayer and is_host()` style cocktails in new code; the polarity is easy to invert and the duplication drifts.

### Step 2: Mark the player methods as plain methods (no @rpc)

The player's effect methods (`apply_polar_shift_impulse`, `apply_polar_shift_dash_lockout`, etc.) do **not** need `@rpc` annotations. They are called locally on each peer by the replication service.

### Step 3: Boss/source code calls the service, not the player directly

```gdscript
## In the boss/hazard script

if hit_target is CharacterBody2D:
	var target_body := hit_target as CharacterBody2D
	var target_peer_id := 0
	if "player_id" in target_body:
		target_peer_id = int(target_body.player_id)
	var replication_service := get_node_or_null("/root/PlayerReplicationService")
	if target_peer_id > 0 and replication_service != null and replication_service.has_method("send_<effect_name>"):
		replication_service.send_<effect_name>(target_peer_id, ...args)
	else:
		# Single-player / fallback: apply directly
		if target_body.has_method("<player_method>"):
			target_body.<player_method>(...args)
```

Always use `target_body.player_id`, never `target_body.get_multiplayer_authority()`.

---

## Anti-patterns to avoid

- **`target_body.rpc_id(target_body.get_multiplayer_authority(), "method", ...)`** — authority is always `1`, so this only ever hits the host.
- **`target_body.rpc("method", ...)`** on a remote player node — the receiving peer cannot resolve the node path; the RPC is silently dropped.
- **`@rpc("any_peer", "call_local") func apply_effect(...)` on the player** — works only when the call site can resolve the path on the receiver. It cannot, when called from a host enemy node, because remote player paths don't match.
- **Setting `target_body.velocity = ...` directly on a remote player** — overwritten next frame by the replication system.

---

## What does NOT need this routing

Damage application via `DAMAGEABLE.apply_damage()` already routes correctly because the helper checks the host authority itself. Cue events (VFX/audio) go through `broadcast_cue_event` which uses the same service pattern. This skill only applies when a host enemy needs to mutate persistent player state (velocity, lockouts, status timers) on the remote player.

---

## Validation checklist

Before finishing a host→player effect change:

- [ ] Effect method on the player has no `@rpc` annotation (plain method).
- [ ] `PlayerReplicationService` exposes a `send_<effect_name>` host-entrypoint and an `_rpc_apply_<effect_name>` RPC.
- [ ] Boss/hazard reads `player_id` (not `get_multiplayer_authority()`) to pick the peer.
- [ ] Single-player / fallback path applies the method directly when `target_peer_id <= 0`.
- [ ] Tested in `launch_local_mp_pair.bat` with both host and joiner standing in the effect area: both react identically.
