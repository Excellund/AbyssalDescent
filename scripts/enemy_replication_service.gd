extends Node

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")

var world_generator: Node = null

var enemy_nodes_by_id: Dictionary = {}
var last_damage_peer_by_id: Dictionary = {}
var target_positions_by_id: Dictionary = {}
var target_facing_angles_by_id: Dictionary = {}


func bind_world(world: Node) -> void:
	world_generator = world


func unbind_world(world: Node) -> void:
	if world_generator == world:
		world_generator = null
		clear_state()


func clear_state() -> void:
	enemy_nodes_by_id.clear()
	last_damage_peer_by_id.clear()
	target_positions_by_id.clear()
	target_facing_angles_by_id.clear()


func credit_damage(enemy_id: int, peer_id: int) -> void:
	if enemy_id <= 0 or peer_id <= 0:
		return
	last_damage_peer_by_id[enemy_id] = peer_id


func killer_peer_for(enemy_id: int) -> int:
	return int(last_damage_peer_by_id.get(enemy_id, 0))


## Enemy impacts belong to the host even when a joiner owns their reward.
func broadcast_world_ring(position: Vector2, radius: float, color: Color, duration: float) -> void:
	if MultiplayerSessionManager.is_remote_replica() or not position.is_finite() or not is_finite(radius) or not is_finite(duration):
		return
	var payload := {"position": position, "radius": clampf(radius, 1.0, 500.0), "color": color, "duration": clampf(duration, 0.01, 2.0)}
	_apply_world_ring(payload)
	if MultiplayerSessionManager.should_broadcast():
		_sync_world_ring.rpc(payload, _current_room_sync_id())


@rpc("authority", "call_remote", "unreliable")
func _sync_world_ring(payload: Dictionary, room_sync_id: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica() or room_sync_id != _current_room_sync_id():
		return
	_apply_world_ring(payload)


func _current_room_sync_id() -> int:
	if not is_instance_valid(world_generator):
		return 0
	var sync_state: Variant = world_generator.get("_world_multiplayer_sync_state")
	return int(sync_state.current_room_sync_id) if sync_state != null else 0


func _apply_world_ring(payload: Dictionary) -> void:
	var position: Vector2 = payload.get("position", Vector2.INF)
	var radius := float(payload.get("radius", 0.0))
	var duration := float(payload.get("duration", 0.0))
	if not position.is_finite() or not is_finite(radius) or not is_finite(duration) or radius <= 0.0 or duration <= 0.0:
		return
	var candidates := get_tree().get_nodes_in_group("combat_players")
	if is_instance_valid(world_generator):
		var local_player: Variant = world_generator.get("player")
		if is_instance_valid(local_player) and not candidates.has(local_player):
			candidates.append(local_player)
	for candidate in candidates:
		var feedback := candidate.get("player_feedback") as Node
		if feedback != null and feedback.has_method("play_world_ring"):
			feedback.play_world_ring(position, clampf(radius, 1.0, 500.0), payload.get("color", Color.ORANGE), clampf(duration, 0.01, 2.0))
			return


func interpolate_remote_enemies(delta: float, position_lerp_speed: float) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var position_weight := clampf(delta * position_lerp_speed, 0.0, 1.0)
	var facing_update_threshold := 0.01
	for enemy_id_variant in enemy_nodes_by_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy := enemy_nodes_by_id.get(enemy_id) as ENEMY_BASE_SCRIPT
		if not is_instance_valid(enemy):
			continue
		var target_position := target_positions_by_id.get(enemy_id, enemy.global_position) as Vector2
		var current_facing_angle := enemy.get_network_facing_angle()
		var target_facing_angle := float(target_facing_angles_by_id.get(enemy_id, current_facing_angle))
		enemy.global_position = enemy.global_position.lerp(target_position, position_weight)
		var facing_delta := absf(wrapf(target_facing_angle - current_facing_angle, -PI, PI))
		if facing_delta > facing_update_threshold:
			enemy.set_network_facing_angle(target_facing_angle)
