extends Node
## Service for syncing player state across multiplayer peers.
## Handles position, health, alive status, and upgrade state replication via RPC.

## Configuration
var position_sync_interval_sec: float = 0.05  ## ~20 Hz position updates
var position_broadcast_threshold_px: float = 2.0  ## Broadcast low-latency movement updates
var rotation_broadcast_threshold_rad: float = deg_to_rad(2.0)
var position_transmit_quantum_px: float = 0.5
var rotation_transmit_quantum_rad: float = deg_to_rad(2.0)
var remote_position_lerp_speed: float = 18.0
var remote_rotation_lerp_speed: float = 20.0
var remote_position_snap_distance_px: float = 180.0

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
	_interpolate_remote_players(delta)


## Register a player node for a specific peer.
func register_player(peer_id: int, player_node: Node) -> void:
	player_nodes[peer_id] = player_node
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


func _remove_invalid_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_last_sync_positions.erase(peer_id)
	_last_sync_rotations.erase(peer_id)
	_remote_target_positions.erase(peer_id)
	_remote_target_rotations.erase(peer_id)


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
	
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
		return
	var player_body := player_node as Node2D
	if player_body != null:
		var distance_to_target := player_body.position.distance_to(position)
		if distance_to_target >= remote_position_snap_distance_px:
			player_body.position = position
		_remote_target_positions[peer_id] = position
	_remote_target_rotations[peer_id] = facing_radians


func _interpolate_remote_players(delta: float) -> void:
	var position_weight := clampf(delta * remote_position_lerp_speed, 0.0, 1.0)
	var rotation_weight := clampf(delta * remote_rotation_lerp_speed, 0.0, 1.0)
	for peer_id in player_nodes.keys():
		if peer_id == local_peer_id:
			continue
		var player_node_variant: Variant = player_nodes.get(peer_id)
		if not is_instance_valid(player_node_variant):
			_remove_invalid_player(peer_id)
			continue
		var player_node := player_node_variant as Node
		if player_node == null:
			_remove_invalid_player(peer_id)
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
func _sync_player_health(peer_id: int, health: float) -> void:
	if peer_id not in player_nodes:
		return
	
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
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
	
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
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
	
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
		return
	if player_node.has_method("revive_with_health"):
		player_node.revive_with_health(revived_health)
	if player_node.has_method("set_combat_removed"):
		player_node.set_combat_removed(false)


## Called by player's health_state when health changes.
## Should be called from player.gd's health signal handler.
func broadcast_health_change(peer_id: int, health: float) -> void:
	if (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) or peer_id == local_peer_id:
		_sync_player_health.rpc(peer_id, health)


## Called by player when they die.
## Should be called from player.gd's death signal handler.
func broadcast_player_died(peer_id: int) -> void:
	if (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) or peer_id == local_peer_id:
		_sync_player_alive_status.rpc(peer_id, false)


## Called when a revived player regains control.
## Should be called after encounter clear or revival trigger.
func broadcast_player_revived(peer_id: int, health: float = 1.0) -> void:
	if (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) or peer_id == local_peer_id:
		_sync_player_revived.rpc(peer_id, health)


func broadcast_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12) -> void:
	if peer_id <= 0:
		return
	if (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) or peer_id == local_peer_id:
		_sync_attack_indicator.rpc(peer_id, attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration)


@rpc("unreliable", "any_peer", "call_local")
func _sync_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
		return
	if player_node.has_method("play_network_attack_indicator"):
		player_node.play_network_attack_indicator(attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration)


func broadcast_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id <= 0:
		return
	if snapshot.is_empty():
		return
	if (multiplayer_session_manager != null and bool(multiplayer_session_manager.is_host())) or peer_id == local_peer_id:
		_sync_player_build_snapshot.rpc(peer_id, snapshot)


@rpc("reliable", "any_peer", "call_local")
func _sync_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	if snapshot.is_empty():
		return
	var player_node_variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(player_node_variant):
		_remove_invalid_player(peer_id)
		return
	var player_node := player_node_variant as Node
	if player_node == null:
		_remove_invalid_player(peer_id)
		return
	if player_node.has_method("apply_network_build_snapshot"):
		player_node.apply_network_build_snapshot(snapshot)
