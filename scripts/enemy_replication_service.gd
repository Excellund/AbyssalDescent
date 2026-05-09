extends Node

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


func interpolate_remote_enemies(delta: float, position_lerp_speed: float, rotation_lerp_speed: float) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var position_weight := clampf(delta * position_lerp_speed, 0.0, 1.0)
	var rotation_weight := clampf(delta * rotation_lerp_speed, 0.0, 1.0)
	var facing_update_threshold := 0.01
	for enemy_id_variant in enemy_nodes_by_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy := enemy_nodes_by_id.get(enemy_id) as Node2D
		if not is_instance_valid(enemy):
			continue
		var target_position := target_positions_by_id.get(enemy_id, enemy.global_position) as Vector2
		var current_facing_angle := enemy.global_rotation
		if enemy.has_method("get_network_facing_angle"):
			current_facing_angle = float(enemy.call("get_network_facing_angle"))
		var target_facing_angle := float(target_facing_angles_by_id.get(enemy_id, current_facing_angle))
		enemy.global_position = enemy.global_position.lerp(target_position, position_weight)
		var facing_delta := absf(wrapf(target_facing_angle - current_facing_angle, -PI, PI))
		if facing_delta > facing_update_threshold:
			if enemy.has_method("set_network_facing_angle"):
				enemy.call("set_network_facing_angle", target_facing_angle)
			else:
				var smoothed_facing_angle := lerp_angle(current_facing_angle, target_facing_angle, rotation_weight)
				enemy.global_rotation = smoothed_facing_angle
