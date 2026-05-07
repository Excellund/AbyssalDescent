extends Node
## Service for syncing player state across multiplayer peers.
## Handles position, health, alive status, and upgrade state replication via RPC.

## Configuration
var position_sync_interval_sec: float = 0.05  ## ~20 Hz position updates
var position_broadcast_threshold_px: float = 2.0  ## Broadcast low-latency movement updates
var rotation_broadcast_threshold_rad: float = deg_to_rad(2.0)
var position_transmit_quantum_px: float = 0.5
var rotation_transmit_quantum_rad: float = deg_to_rad(2.0)
var remote_position_snap_distance_px: float = 180.0
## Half-life in seconds for remote position/rotation interpolation (frame-rate independent).
## Lower value = snappier; higher value = smoother.
var remote_position_lerp_half_life_sec: float = 0.04
var remote_rotation_lerp_half_life_sec: float = 0.035
var feedback_sync_interval_sec: float = 0.05
var feedback_sync_payload_budget_bytes: int = 640

## References to player nodes (populated by caller)
var player_nodes: Dictionary = {}  ## peer_id -> Player node reference
var local_peer_id: int = 0
var multiplayer_session_manager

## Internal state
var _last_sync_time: float = 0.0
var _last_sync_positions: Dictionary = {}  ## peer_id -> last_synced_position
var _last_sync_rotations: Dictionary = {}  ## peer_id -> last_synced_facing_radians
var _remote_target_positions: Dictionary = {}  ## peer_id -> latest replicated position
var _remote_target_rotations: Dictionary = {}  ## peer_id -> latest replicated facing
var _feedback_sync_elapsed: float = 0.0
var _pending_feedback_events_by_peer: Dictionary = {}  ## peer_id -> Array[Dictionary]
var _last_feedback_event_count: int = 0
var _last_feedback_estimated_bytes: int = 0
var _outgoing_health_sequence_by_peer: Dictionary = {}  ## peer_id -> last emitted health sequence
var _last_applied_health_sequence_by_peer: Dictionary = {}  ## peer_id -> last applied health sequence


func _ready() -> void:
	multiplayer_session_manager = get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null:
		push_error("[PlayerReplicationService] MultiplayerSessionManager autoload is missing")
		set_process(false)
		return
	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	set_process(true)


func _process(delta: float) -> void:
	if multiplayer_session_manager == null:
		return
	if not bool(multiplayer_session_manager.is_session_connected()):
		return
	var current_local_peer_id := int(multiplayer_session_manager.local_peer_id)
	if current_local_peer_id > 0 and current_local_peer_id != local_peer_id:
		local_peer_id = current_local_peer_id
	
	_last_sync_time += delta
	if _last_sync_time >= position_sync_interval_sec:
		_last_sync_time = 0.0
		_sync_all_player_positions()
	_feedback_sync_elapsed += delta
	if _feedback_sync_elapsed >= feedback_sync_interval_sec:
		_feedback_sync_elapsed = 0.0
		_flush_pending_feedback_events()
	_interpolate_remote_players(delta)


## Register a player node for a specific peer.
func register_player(peer_id: int, player_node: Node) -> void:
	player_nodes[peer_id] = player_node
	if not _outgoing_health_sequence_by_peer.has(peer_id):
		_outgoing_health_sequence_by_peer[peer_id] = 0
	if not _last_applied_health_sequence_by_peer.has(peer_id):
		_last_applied_health_sequence_by_peer[peer_id] = 0
	var player_body := player_node as Node2D
	if player_body != null:
		_last_sync_positions[peer_id] = player_body.position
		_remote_target_positions[peer_id] = player_body.position
		var initial_rotation := _get_player_facing_angle(player_node)
		_last_sync_rotations[peer_id] = initial_rotation
		_remote_target_rotations[peer_id] = initial_rotation
	else:
		_last_sync_positions[peer_id] = Vector2.ZERO
		_last_sync_rotations[peer_id] = 0.0


## Unregister a player node.
func unregister_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_last_sync_positions.erase(peer_id)
	_last_sync_rotations.erase(peer_id)
	_remote_target_positions.erase(peer_id)
	_remote_target_rotations.erase(peer_id)
	_pending_feedback_events_by_peer.erase(peer_id)
	_outgoing_health_sequence_by_peer.erase(peer_id)
	_last_applied_health_sequence_by_peer.erase(peer_id)


## Returns true when this peer is authoritative for the given peer_id:
## always true for the host, or for a client broadcasting their own peer.
func _is_authority_for_peer(peer_id: int) -> bool:
	return (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) \
		or peer_id == local_peer_id


## Looks up the player node for peer_id. Returns null and cleans up if invalid.
func _get_player_node(peer_id: int) -> Node:
	var variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(variant):
		_remove_invalid_player(peer_id)
		return null
	var node := variant as Node
	if node == null:
		_remove_invalid_player(peer_id)
		return null
	return node


func _remove_invalid_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_last_sync_positions.erase(peer_id)
	_last_sync_rotations.erase(peer_id)
	_remote_target_positions.erase(peer_id)
	_remote_target_rotations.erase(peer_id)
	_pending_feedback_events_by_peer.erase(peer_id)
	_outgoing_health_sequence_by_peer.erase(peer_id)
	_last_applied_health_sequence_by_peer.erase(peer_id)


func _estimate_feedback_event_bytes(event_name: String, payload: Dictionary) -> int:
	return event_name.length() + var_to_str(payload).length() + 16


func get_last_feedback_sync_metrics() -> Dictionary:
	return {
		"event_count": _last_feedback_event_count,
		"estimated_bytes": _last_feedback_estimated_bytes
	}


func broadcast_feedback_event(peer_id: int, event_name: String, payload: Dictionary, reliable: bool = false) -> void:
	if peer_id <= 0:
		return
	if event_name.is_empty() or payload.is_empty():
		return
	if not _is_authority_for_peer(peer_id):
		return
	var pending_variant: Variant = _pending_feedback_events_by_peer.get(peer_id, [])
	var pending_events: Array[Dictionary] = []
	if pending_variant is Array:
		for entry in pending_variant:
			if entry is Dictionary:
				pending_events.append((entry as Dictionary).duplicate(true))
	var event_payload := payload.duplicate(true)
	var estimated_bytes := _estimate_feedback_event_bytes(event_name, event_payload)
	if estimated_bytes > feedback_sync_payload_budget_bytes:
		return
	var pending_bytes := 0
	for existing_event in pending_events:
		pending_bytes += int(existing_event.get("estimated_bytes", 0))
	if pending_bytes + estimated_bytes > feedback_sync_payload_budget_bytes and not pending_events.is_empty():
		_flush_feedback_events_for_peer(peer_id, pending_events)
		pending_events.clear()
	pending_events.append({
		"event": event_name,
		"payload": event_payload,
		"reliable": reliable,
		"estimated_bytes": estimated_bytes
	})
	_pending_feedback_events_by_peer[peer_id] = pending_events


func _flush_pending_feedback_events() -> void:
	_last_feedback_event_count = 0
	_last_feedback_estimated_bytes = 0
	if _pending_feedback_events_by_peer.is_empty():
		return
	for peer_key in _pending_feedback_events_by_peer.keys():
		var peer_id := int(peer_key)
		var pending_variant: Variant = _pending_feedback_events_by_peer.get(peer_id, [])
		if not (pending_variant is Array):
			continue
		var pending_events: Array[Dictionary] = []
		for entry in pending_variant:
			if entry is Dictionary:
				pending_events.append((entry as Dictionary).duplicate(true))
		_flush_feedback_events_for_peer(peer_id, pending_events)
	_pending_feedback_events_by_peer.clear()


func _flush_feedback_events_for_peer(peer_id: int, pending_events: Array[Dictionary]) -> void:
	if pending_events.is_empty():
		return
	var unreliable_events: Array[Dictionary] = []
	var reliable_events: Array[Dictionary] = []
	for event_entry in pending_events:
		var event_name := String(event_entry.get("event", ""))
		var payload := event_entry.get("payload", {}) as Dictionary
		if event_name.is_empty() or payload.is_empty():
			continue
		var packet := {
			"event": event_name,
			"payload": payload
		}
		if bool(event_entry.get("reliable", false)):
			reliable_events.append(packet)
		else:
			unreliable_events.append(packet)
		_last_feedback_event_count += 1
		_last_feedback_estimated_bytes += int(event_entry.get("estimated_bytes", 0))
	if not unreliable_events.is_empty():
		_sync_player_feedback_events_unreliable.rpc(peer_id, unreliable_events)
	if not reliable_events.is_empty():
		_sync_player_feedback_events_reliable.rpc(peer_id, reliable_events)


## Sync all registered player positions if they've moved significantly.
func _sync_all_player_positions() -> void:
	for peer_id in player_nodes.keys():
		var player_node_variant: Variant = player_nodes.get(peer_id)
		if not is_instance_valid(player_node_variant):
			_remove_invalid_player(peer_id)
			continue
		var player_node := player_node_variant as Node
		if player_node == null:
			_remove_invalid_player(peer_id)
			continue
		
		if peer_id == local_peer_id:
			## Local player: broadcast own position to peers
			var player_body := player_node as Node2D
			if player_body != null:
				var current_pos: Vector2 = player_body.position
				var position_quantum := maxf(0.0001, position_transmit_quantum_px)
				var quantized_pos := Vector2(
					snappedf(current_pos.x, position_quantum),
					snappedf(current_pos.y, position_quantum)
				)
				var last_pos: Vector2 = _last_sync_positions.get(peer_id, Vector2.ZERO)
				var distance := quantized_pos.distance_to(last_pos)
				var current_rotation := _get_player_facing_angle(player_node)
				var rotation_quantum := maxf(0.0001, rotation_transmit_quantum_rad)
				var quantized_rotation := snappedf(current_rotation, rotation_quantum)
				var last_rotation := float(_last_sync_rotations.get(peer_id, quantized_rotation))
				var rotation_delta := absf(wrapf(quantized_rotation - last_rotation, -PI, PI))
				
				if distance >= position_broadcast_threshold_px or rotation_delta >= rotation_broadcast_threshold_rad:
					_last_sync_positions[peer_id] = quantized_pos
					_last_sync_rotations[peer_id] = quantized_rotation
					_sync_player_transform.rpc(peer_id, quantized_pos, quantized_rotation)


## RPC: Broadcast a player's transform to all peers.
@rpc("unreliable", "any_peer", "call_local")
func _sync_player_transform(peer_id: int, position: Vector2, facing_radians: float) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	var player_body := player_node as Node2D
	if player_body != null:
		var distance_to_target := player_body.position.distance_to(position)
		if distance_to_target >= remote_position_snap_distance_px:
			player_body.position = position
		_remote_target_positions[peer_id] = position
	_remote_target_rotations[peer_id] = facing_radians


func _interpolate_remote_players(delta: float) -> void:
	var position_weight := 1.0 - pow(0.5, delta / maxf(0.0001, remote_position_lerp_half_life_sec))
	var rotation_weight := 1.0 - pow(0.5, delta / maxf(0.0001, remote_rotation_lerp_half_life_sec))
	for peer_id in player_nodes.keys():
		if peer_id == local_peer_id:
			continue
		var player_node := _get_player_node(peer_id)
		if player_node == null:
			continue
		var player_body := player_node as Node2D
		if player_body == null:
			continue
		var target_pos: Vector2 = _remote_target_positions.get(peer_id, player_body.position)
		player_body.position = player_body.position.lerp(target_pos, position_weight)
		var current_rotation := _get_player_facing_angle(player_node)
		var target_rotation := float(_remote_target_rotations.get(peer_id, current_rotation))
		var smoothed_rotation := lerp_angle(current_rotation, target_rotation, rotation_weight)
		_set_player_facing_angle(player_node, smoothed_rotation)


func _get_player_facing_angle(player_node: Node) -> float:
	if player_node.has_method("get_network_facing_angle"):
		return float(player_node.get_network_facing_angle())
	if player_node is Node2D:
		return (player_node as Node2D).rotation
	return 0.0


func _set_player_facing_angle(player_node: Node, facing_radians: float) -> void:
	if player_node.has_method("set_network_facing_angle"):
		player_node.set_network_facing_angle(facing_radians)
		return
	if player_node is Node2D:
		(player_node as Node2D).rotation = facing_radians


## RPC: Sync a player's health.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_health(peer_id: int, health: float, health_sequence: int = 0) -> void:
	if peer_id not in player_nodes:
		return
	if health_sequence > 0:
		var last_applied_sequence := int(_last_applied_health_sequence_by_peer.get(peer_id, 0))
		if health_sequence <= last_applied_sequence:
			return
		_last_applied_health_sequence_by_peer[peer_id] = health_sequence
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if health > 0.0 and player_node.has_method("is_dead") and bool(player_node.call("is_dead")):
		# Dead players must only transition back through explicit revive sync.
		return
	if player_node.has_method("set_health"):
		player_node.set_health(health)
	elif player_node.has_node("HealthState"):
		var health_state = player_node.get_node("HealthState")
		if health_state.has_method("set_current_health"):
			health_state.set_current_health(health)


## RPC: Sync a player's alive/dead status.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_alive_status(peer_id: int, is_alive: bool) -> void:
	if peer_id not in player_nodes:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if player_node.has_method("set_alive"):
		player_node.set_alive(is_alive)
	if player_node.has_method("set_combat_removed"):
		player_node.set_combat_removed(not is_alive)


## RPC: Sync a player's revived status.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_revived(peer_id: int, revived_health: float = 1.0) -> void:
	if peer_id not in player_nodes:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if player_node.has_method("revive_with_health"):
		player_node.revive_with_health(revived_health)
	if player_node.has_method("set_combat_removed"):
		player_node.set_combat_removed(false)


## Called by player's health_state when health changes.
## Should be called from player.gd's health signal handler.
func broadcast_health_change(peer_id: int, health: float) -> void:
	if _is_authority_for_peer(peer_id):
		var next_sequence := int(_outgoing_health_sequence_by_peer.get(peer_id, 0)) + 1
		_outgoing_health_sequence_by_peer[peer_id] = next_sequence
		_sync_player_health.rpc(peer_id, health, next_sequence)


## Called by player when they die.
## Should be called from player.gd's death signal handler.
func broadcast_player_died(peer_id: int) -> void:
	if _is_authority_for_peer(peer_id):
		_sync_player_alive_status.rpc(peer_id, false)


## Called when a revived player regains control.
## Should be called after encounter clear or revival trigger.
func broadcast_player_revived(peer_id: int, health: float = 1.0) -> void:
	if _is_authority_for_peer(peer_id):
		_sync_player_revived.rpc(peer_id, health)


func broadcast_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12) -> void:
	if peer_id <= 0:
		return
	if _is_authority_for_peer(peer_id):
		_sync_attack_indicator.rpc(peer_id, attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration)


@rpc("unreliable", "any_peer", "call_local")
func _sync_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if player_node.has_method("play_network_attack_indicator"):
		player_node.play_network_attack_indicator(attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration)


func broadcast_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id <= 0:
		return
	if snapshot.is_empty():
		return
	if _is_authority_for_peer(peer_id):
		_sync_player_build_snapshot.rpc(peer_id, snapshot)


@rpc("reliable", "any_peer", "call_local")
func _sync_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	if snapshot.is_empty():
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if player_node.has_method("apply_network_build_snapshot"):
		player_node.apply_network_build_snapshot(snapshot)


@rpc("unreliable", "any_peer", "call_local")
func _sync_player_feedback_events_unreliable(peer_id: int, events: Array[Dictionary]) -> void:
	_apply_network_feedback_events(peer_id, events)


@rpc("reliable", "any_peer", "call_local")
func _sync_player_feedback_events_reliable(peer_id: int, events: Array[Dictionary]) -> void:
	_apply_network_feedback_events(peer_id, events)


func _apply_network_feedback_events(peer_id: int, events: Array[Dictionary]) -> void:
	if peer_id not in player_nodes:
		return
	if events.is_empty():
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if peer_id == local_peer_id:
		if not player_node.has_method("apply_owner_feedback_event"):
			return
		for event_entry in events:
			var local_event_name := String(event_entry.get("event", ""))
			var local_payload := event_entry.get("payload", {}) as Dictionary
			if local_event_name.is_empty() or local_payload.is_empty():
				continue
			player_node.apply_owner_feedback_event(local_event_name, local_payload)
		return
	if not player_node.has_method("apply_network_feedback_event"):
		return
	for event_entry in events:
		var event_name := String(event_entry.get("event", ""))
		var payload := event_entry.get("payload", {}) as Dictionary
		if event_name.is_empty() or payload.is_empty():
			continue
		player_node.apply_network_feedback_event(event_name, payload)
