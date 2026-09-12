extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const VISUAL_MATH := preload("res://scripts/shared/visual_math.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")

@export var move_speed: float = 90.0
@export var acceleration: float = 760.0
@export var deceleration: float = 1100.0
@export var stop_distance: float = 120.0
@export var wave_interval: float = 2.8
@export var ring_node_count: int = 12
@export var ring_speed: float = 176.0
@export var ring_radius_max: float = 360.0
@export var ring_damage: int = 12
@export var node_hit_radius: float = 20.0

var wave_timer: float = 0.0
# World-space origins stay fixed even while the Drifter moves away from a wave.
# Host-only damaged maps each player's instance ID to its hit-node flags.
# At most one pellet damage request reaches each player per wave.
# Each ring: { "id": int, "world_pos": Vector2, "radius": float, "gap_index": int, "damaged": Dictionary }
var rings: Array[Dictionary] = []
var _next_ring_network_id: int = 1
var _ring_sync_sequence: int = 0
var _ring_sync_was_active: bool = false
var _last_remote_ring_sequence: int = -1
var _highest_remote_ring_id: int = 0
var _remote_wave_id: int = -1


func _get_custom_network_runtime_state() -> Dictionary:
	# Ring arrays use the separate projectile channel, outside the runtime-size cap.
	return {"wave_timer": wave_timer, "wave_interval": wave_interval, "wave_id": _next_ring_network_id - 1}


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	_apply_remote_wave_phase(
		int(custom_state.get("wave_id", 0)),
		float(custom_state.get("wave_timer", wave_timer)),
		float(custom_state.get("wave_interval", wave_interval))
	)


func _apply_remote_wave_phase(wave_id: int, time_left: float, interval: float) -> void:
	if network_simulation_enabled or wave_id < _remote_wave_id:
		return
	wave_interval = maxf(0.001, interval)
	# Same-wave samples cannot rewind the locally animated charge halo.
	wave_timer = maxf(0.0, time_left) if wave_id != _remote_wave_id else minf(wave_timer, maxf(0.0, time_left))
	_remote_wave_id = wave_id


func set_ring_start_offset(offset_seconds: float) -> void:
	wave_timer += maxf(0.0, offset_seconds)


func _ready() -> void:
	# Base _ready creates both current health and its bar from this value.
	# Assigning it afterward left the Drifter at the inherited 40 current HP.
	max_health = 88
	super()
	crowd_separation_radius = 52.0
	crowd_separation_strength = 80.0
	wave_timer = wave_interval * 0.6


func _process_behavior(delta: float) -> void:
	wave_timer = maxf(0.0, wave_timer - delta)
	_process_rings(delta)
	var desired := Vector2.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length() > stop_distance:
			desired = to_target.normalized() * move_speed * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	if wave_timer <= 0.0:
		_emit_ring()
		wave_timer = wave_interval


func _emit_ring() -> void:
	if not network_simulation_enabled:
		return
	var gap_index := randi() % ring_node_count
	rings.append({"id": _next_ring_network_id, "world_pos": global_position, "radius": 0.0, "gap_index": gap_index, "damaged": {}})
	_next_ring_network_id += 1


func _process_rings(delta: float) -> void:
	var hit_targets: Array[Node2D] = []
	if network_simulation_enabled:
		hit_targets = _get_ring_damageable_targets()
	var i := rings.size() - 1
	while i >= 0:
		var ring := rings[i] as Dictionary
		ring["radius"] = float(ring["radius"]) + ring_speed * delta
		var ring_radius := float(ring["radius"])
		if ring_radius >= ring_radius_max:
			rings.remove_at(i)
			i -= 1
			queue_redraw()
			continue
		if network_simulation_enabled:
			var gap_index := int(ring["gap_index"])
			var damaged := ring["damaged"] as Dictionary
			for hit_target in hit_targets:
				if not _is_ring_target_valid(hit_target):
					continue
				var player_id := hit_target.get_instance_id()
				if not damaged.has(player_id):
					var hit_nodes: Array[bool] = []
					hit_nodes.resize(ring_node_count)
					hit_nodes.fill(false)
					damaged[player_id] = hit_nodes
				var player_hit_nodes := damaged[player_id] as Array
				if player_hit_nodes.has(true):
					continue
				for node_i in range(ring_node_count):
					if node_i == gap_index or bool(player_hit_nodes[node_i]):
						continue
					if not _is_ring_target_valid(hit_target):
						break
					var node_world_pos := _get_ring_node_world_position(ring, node_i)
					if node_world_pos.distance_to(hit_target.global_position) <= node_hit_radius:
						if DAMAGEABLE.apply_damage(hit_target, ring_damage, {"source": "enemy_ability", "ability": "drifter_ring"}):
							player_hit_nodes[node_i] = true
							break
		i -= 1
	queue_redraw()


func _get_ring_damageable_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate_variant in target_candidates:
		if not is_instance_valid(candidate_variant) or not (candidate_variant is Node2D):
			continue
		var candidate := candidate_variant as Node2D
		if _is_ring_target_valid(candidate) and not result.has(candidate):
			result.append(candidate)
	if result.is_empty() and _is_ring_target_valid(target):
		result.append(target)
	return result


func _is_ring_target_valid(candidate: Node2D) -> bool:
	if not _is_target_valid(candidate):
		return false
	var player := candidate as PLAYER_SCRIPT
	return player == null or not player._combat_removed


func _get_ring_node_world_position(ring: Dictionary, node_index: int) -> Vector2:
	# Alternate half a spoke between waves so a stationary incidental gap is
	# not safe forever. Stable wave IDs give replicas exactly the same geometry.
	var half_step := 0.5 if posmod(int(ring.get("id", 1)) - 1, 2) == 1 else 0.0
	var angle := (float(node_index) + half_step) * TAU / float(ring_node_count)
	return (ring["world_pos"] as Vector2) + Vector2(cos(angle), sin(angle)) * float(ring["radius"])


func _is_in_priority_attack_state() -> bool:
	return not rings.is_empty() or wave_timer <= minf(0.6, wave_interval)


func should_process_remote_visuals_every_frame() -> bool:
	# The charge halo also animates between attacks, outside the priority window.
	return not network_simulation_enabled and (wave_timer > 0.0 or not rings.is_empty())


func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active := not rings.is_empty()
	if not active and not _ring_sync_was_active:
		return {}
	var payload: Array = []
	for ring in rings:
		# Stable id, world origin, sampled radius, safe gap. Damage flags stay host-only.
		payload.append([int(ring["id"]), ring["world_pos"], float(ring["radius"]), int(ring["gap_index"])])
	_ring_sync_sequence += 1
	_ring_sync_was_active = active
	return {
		"q": _ring_sync_sequence, "r": payload,
		"c": [ring_node_count, ring_speed, ring_radius_max, node_hit_radius],
		"w": _next_ring_network_id - 1, "t": wave_timer, "v": wave_interval
	}


func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled or sync_state.is_empty():
		return
	var sequence := int(sync_state.get("q", -1))
	# This channel is unreliable; old packets must not resurrect expired waves.
	if sequence <= _last_remote_ring_sequence:
		return
	_last_remote_ring_sequence = sequence
	var config := sync_state.get("c", []) as Array
	if config.size() == 4:
		ring_node_count = maxi(2, int(config[0]))
		ring_speed = maxf(0.0, float(config[1]))
		ring_radius_max = maxf(1.0, float(config[2]))
		node_hit_radius = maxf(0.0, float(config[3]))
	_apply_remote_wave_phase(int(sync_state.get("w", 0)), float(sync_state.get("t", wave_timer)), float(sync_state.get("v", wave_interval)))
	var incoming := sync_state.get("r", []) as Array
	var incoming_ids: Dictionary = {}
	var local_ids: Dictionary = {}
	for ring in rings:
		local_ids[int(ring["id"])] = true
	var newest_id := _highest_remote_ring_id
	for ring_variant in incoming:
		if not (ring_variant is Array):
			continue
		var ring_state := ring_variant as Array
		if ring_state.size() != 4 or not (ring_state[1] is Vector2):
			continue
		var ring_id := int(ring_state[0])
		if ring_id <= 0:
			continue
		incoming_ids[ring_id] = true
		newest_id = maxi(newest_id, ring_id)
		if local_ids.has(ring_id) or ring_id <= _highest_remote_ring_id:
			continue
		var radius := maxf(0.0, float(ring_state[2]))
		if radius >= ring_radius_max:
			continue
		rings.append({"id": ring_id, "world_pos": ring_state[1], "radius": radius, "gap_index": posmod(int(ring_state[3]), ring_node_count)})
		local_ids[ring_id] = true
	_highest_remote_ring_id = newest_id
	# Known rings keep their locally advanced radius, avoiding sample-rate shaking.
	for i in range(rings.size() - 1, -1, -1):
		if not incoming_ids.has(int(rings[i]["id"])):
			rings.remove_at(i)
	queue_redraw()


func _process_network_visuals(delta: float) -> void:
	if network_simulation_enabled:
		return
	wave_timer = maxf(0.0, wave_timer - delta)
	_process_rings(delta)


func _draw() -> void:
	var body_radius := 13.5
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	# Idle ripple halos — concentric arcs hint at ring-wave identity, drawn behind body
	for i in range(3):
		var ripple_r := body_radius + 10.0 + float(i) * 9.5
		var ripple_a := maxf(0.0, 0.10 - float(i) * 0.028)
		draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 32,
			Color(COLOR_DRIFTER_CORE.r, COLOR_DRIFTER_CORE.g, COLOR_DRIFTER_CORE.b, ripple_a), 1.2)
	_draw_common_body(body_radius, COLOR_DRIFTER_BODY, COLOR_DRIFTER_CORE, facing, &"drifter")
	# 3 orbiting satellite dots — rotate continuously around the body
	var t := _draw_time_sec
	for i in range(3):
		var sat_angle := t * 1.35 + float(i) * TAU / 3.0
		var sat_pos := Vector2(cos(sat_angle), sin(sat_angle)) * (body_radius + 9.5)
		draw_circle(sat_pos, 5.5,
			Color(COLOR_DRIFTER_CORE.r, COLOR_DRIFTER_CORE.g, COLOR_DRIFTER_CORE.b, 0.15))
		draw_circle(sat_pos, 2.8,
			Color(COLOR_DRIFTER_CORE.r, COLOR_DRIFTER_CORE.g, COLOR_DRIFTER_CORE.b, 0.82))
	var charge_t := 1.0 - clampf(wave_timer / maxf(0.001, wave_interval), 0.0, 1.0)
	if charge_t > 0.05:
		draw_arc(Vector2.ZERO, body_radius + 3.5 + charge_t * 5.5, 0.0, TAU, 24,
			Color(COLOR_DRIFTER_CORE.r, COLOR_DRIFTER_CORE.g, COLOR_DRIFTER_CORE.b, 0.28 * charge_t), 2.0)
	for ring_variant in rings:
		var ring := ring_variant as Dictionary
		var ring_radius := float(ring["radius"])
		var gap_index := int(ring["gap_index"])
		var ratio := clampf(ring_radius / maxf(1.0, ring_radius_max), 0.0, 1.0)
		var fade := VISUAL_MATH.late_fade(ratio, 0.90, 3.0)
		for node_i in range(ring_node_count):
			if node_i == gap_index:
				continue
			var node_pos := to_local(_get_ring_node_world_position(ring, node_i))
			draw_circle(node_pos, node_hit_radius,
				Color(COLOR_DRIFTER_RING.r, COLOR_DRIFTER_RING.g, COLOR_DRIFTER_RING.b, 0.22 * fade))
			draw_arc(node_pos, node_hit_radius, 0.0, TAU, 20,
				Color(COLOR_DRIFTER_RING.r, COLOR_DRIFTER_RING.g, COLOR_DRIFTER_RING.b, 0.5 * fade), 1.2)
			draw_circle(node_pos, node_hit_radius * 0.52,
				Color(COLOR_DRIFTER_RING.r, COLOR_DRIFTER_RING.g, COLOR_DRIFTER_RING.b, 0.65 * fade))
