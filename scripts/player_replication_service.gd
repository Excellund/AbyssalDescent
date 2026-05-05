extends Node
## Service for syncing player state across multiplayer peers.
## Handles position, health, alive status, and upgrade state replication via RPC.

## Configuration
var position_sync_interval_sec: float = 0.1  ## ~10 Hz position updates
var position_broadcast_threshold_px: float = 10.0  ## Only broadcast if moved >threshold

## References to player nodes (populated by caller)
var player_nodes: Dictionary = {}  ## peer_id -> Player node reference
var local_peer_id: int = 0
var multiplayer_session_manager

## Internal state
var _last_sync_time: float = 0.0
var _last_sync_positions: Dictionary = {}  ## peer_id -> last_synced_position


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
	
	_last_sync_time += delta
	if _last_sync_time >= position_sync_interval_sec:
		_last_sync_time = 0.0
		_sync_all_player_positions()


## Register a player node for a specific peer.
func register_player(peer_id: int, player_node: Node) -> void:
	player_nodes[peer_id] = player_node
	_last_sync_positions[peer_id] = Vector2.ZERO


## Unregister a player node.
func unregister_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_last_sync_positions.erase(peer_id)


func _remove_invalid_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_last_sync_positions.erase(peer_id)


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
			if player_node.has_property("position"):
				var current_pos: Vector2 = player_node.position
				var last_pos: Vector2 = _last_sync_positions.get(peer_id, Vector2.ZERO)
				var distance := current_pos.distance_to(last_pos)
				
				if distance >= position_broadcast_threshold_px:
					_last_sync_positions[peer_id] = current_pos
					_sync_player_position.rpc(peer_id, current_pos)


## RPC: Broadcast a player's position to all peers.
@rpc("reliable")
func _sync_player_position(peer_id: int, position: Vector2) -> void:
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
	if player_node.has_property("position"):
		player_node.position = position


## RPC: Sync a player's health.
@rpc("reliable")
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
@rpc("reliable")
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


## RPC: Sync a player's revived status.
@rpc("reliable")
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
