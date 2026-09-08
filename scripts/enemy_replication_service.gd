extends Node

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const RUINOUS_FEEDBACK := preload("res://scripts/ruinous_impact_feedback.gd")

var world_generator: Node = null

var enemy_nodes_by_id: Dictionary = {}
var last_damage_peer_by_id: Dictionary = {}
var target_positions_by_id: Dictionary = {}
var target_facing_angles_by_id: Dictionary = {}
var _ruinous_feedback: RUINOUS_FEEDBACK
var _ruinous_event_serial: int = 0


func bind_world(world: Node) -> void:
	world_generator = world


func unbind_world(world: Node) -> void:
	if world_generator == world:
		world_generator = null
		clear_state()


func clear_state() -> void:
	if is_instance_valid(_ruinous_feedback):
		_ruinous_feedback.queue_free()
	_ruinous_feedback = null
	enemy_nodes_by_id.clear()
	last_damage_peer_by_id.clear()
	target_positions_by_id.clear()
	target_facing_angles_by_id.clear()


func broadcast_ruinous_launch(enemy: ENEMY_BASE_SCRIPT, impulse: Vector2, compression: bool, duration: float) -> int:
	if MultiplayerSessionManager.is_remote_replica() or not is_instance_valid(enemy) or not impulse.is_finite() or not is_finite(duration) or duration <= 0.0:
		return 0
	var feedback := _get_ruinous_feedback()
	if feedback == null:
		return 0
	_ruinous_event_serial += 1
	feedback.show_launch(_ruinous_event_serial, enemy, impulse, compression, duration)
	var enemy_id := int(enemy.get_meta("network_enemy_id", 0))
	if MultiplayerSessionManager.should_broadcast() and enemy_id > 0:
		_sync_ruinous_feedback.rpc({"kind": "launch", "serial": _ruinous_event_serial, "enemy": enemy_id, "direction": impulse.normalized(), "compression": compression, "duration": duration}, _current_room_sync_id())
	return _ruinous_event_serial


func finish_ruinous_launch(serial: int) -> void:
	if MultiplayerSessionManager.is_remote_replica() or serial <= 0:
		return
	if is_instance_valid(_ruinous_feedback):
		_ruinous_feedback.finish_launch(serial)
	if MultiplayerSessionManager.should_broadcast():
		_sync_ruinous_feedback.rpc({"kind": "finish", "serial": serial}, _current_room_sync_id())


func broadcast_ruinous_burst(position: Vector2, radius: float, direction: Vector2) -> void:
	if MultiplayerSessionManager.is_remote_replica() or not position.is_finite() or not direction.is_finite() or not is_finite(radius) or radius <= 0.0:
		return
	var payload := {"kind": "burst", "position": position, "radius": radius, "direction": direction}
	_apply_ruinous_feedback(payload)
	if MultiplayerSessionManager.should_broadcast():
		_sync_ruinous_feedback.rpc(payload, _current_room_sync_id())


@rpc("authority", "call_remote", "reliable")
func _sync_ruinous_feedback(payload: Dictionary, room_sync_id: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica() or room_sync_id != _current_room_sync_id():
		return
	_apply_ruinous_feedback(payload)


func _apply_ruinous_feedback(payload: Dictionary) -> void:
	var feedback := _get_ruinous_feedback()
	if feedback == null:
		return
	match String(payload.get("kind", "")):
		"launch":
			var enemy := enemy_nodes_by_id.get(int(payload.get("enemy", 0))) as ENEMY_BASE_SCRIPT
			feedback.show_launch(int(payload.get("serial", 0)), enemy, payload.get("direction", Vector2.ZERO), bool(payload.get("compression", false)), float(payload.get("duration", 0.0)))
		"finish":
			feedback.finish_launch(int(payload.get("serial", 0)))
		"burst":
			var sfx_volume_db := 0.0
			if is_instance_valid(world_generator):
				var player: Variant = world_generator.player
				if is_instance_valid(player) and is_instance_valid(player.player_feedback):
					sfx_volume_db = float(player.player_feedback.sfx_volume_db)
			feedback.show_burst(payload.get("position", Vector2.INF), float(payload.get("radius", 0.0)), payload.get("direction", Vector2.RIGHT), sfx_volume_db)


func _get_ruinous_feedback() -> RUINOUS_FEEDBACK:
	if is_instance_valid(_ruinous_feedback):
		return _ruinous_feedback
	var parent := world_generator if is_instance_valid(world_generator) else get_tree().current_scene
	if not is_instance_valid(parent):
		return null
	_ruinous_feedback = RUINOUS_FEEDBACK.new()
	parent.add_child(_ruinous_feedback)
	return _ruinous_feedback


func credit_damage(enemy_id: int, peer_id: int) -> void:
	if enemy_id <= 0 or peer_id <= 0:
		return
	last_damage_peer_by_id[enemy_id] = peer_id


func killer_peer_for(enemy_id: int) -> int:
	return int(last_damage_peer_by_id.get(enemy_id, 0))


func _current_room_sync_id() -> int:
	if not is_instance_valid(world_generator):
		return 0
	var sync_state: Variant = world_generator.get("_world_multiplayer_sync_state")
	return int(sync_state.current_room_sync_id) if sync_state != null else 0


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
