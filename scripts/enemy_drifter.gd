extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const VISUAL_MATH := preload("res://scripts/shared/visual_math.gd")

@export var move_speed: float = 72.0
@export var acceleration: float = 760.0
@export var deceleration: float = 1100.0
@export var stop_distance: float = 120.0
@export var wave_interval: float = 3.4
@export var ring_node_count: int = 8
@export var ring_speed: float = 148.0
@export var ring_radius_max: float = 280.0
@export var ring_damage: int = 12
@export var node_hit_radius: float = 17.0

var wave_timer: float = 0.0
# Each ring: { "world_pos": Vector2, "radius": float, "gap_index": int, "damaged": Array }
var rings: Array[Dictionary] = []


func _get_custom_network_runtime_state() -> Dictionary:
	return {"wave_timer": wave_timer}


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	wave_timer = float(custom_state.get("wave_timer", wave_timer))


func _ready() -> void:
	super()
	max_health = 68
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
	var gap_index := randi() % ring_node_count
	var damaged: Array[bool] = []
	damaged.resize(ring_node_count)
	damaged.fill(false)
	rings.append({"world_pos": global_position, "radius": 0.0, "gap_index": gap_index, "damaged": damaged})


func _process_rings(delta: float) -> void:
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
		if network_simulation_enabled and is_instance_valid(target):
			var ring_world_pos := ring["world_pos"] as Vector2
			var gap_index := int(ring["gap_index"])
			var damaged := ring["damaged"] as Array
			for node_i in range(ring_node_count):
				if node_i == gap_index:
					continue
				if bool(damaged[node_i]):
					continue
				var angle := float(node_i) * TAU / float(ring_node_count)
				var node_world_pos := ring_world_pos + Vector2(cos(angle), sin(angle)) * ring_radius
				if node_world_pos.distance_to(target.global_position) <= node_hit_radius:
					if DAMAGEABLE.apply_damage(target, ring_damage, {"source": "enemy_ability", "ability": "drifter_ring"}):
						damaged[node_i] = true
		i -= 1
	queue_redraw()


func _is_in_priority_attack_state() -> bool:
	return false


func get_projectile_network_sync_state() -> Dictionary:
	return {}


func apply_projectile_network_sync_state(_sync_state: Dictionary) -> void:
	pass


func _process_network_visuals(_delta: float) -> void:
	if not rings.is_empty():
		queue_redraw()


func _draw() -> void:
	var body_radius := 13.5
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	# Idle ripple halos — concentric arcs hint at ring-wave identity, drawn behind body
	for i in range(3):
		var ripple_r := body_radius + 10.0 + float(i) * 9.5
		var ripple_a := maxf(0.0, 0.10 - float(i) * 0.028)
		draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 32,
			Color(COLOR_DRIFTER_CORE.r, COLOR_DRIFTER_CORE.g, COLOR_DRIFTER_CORE.b, ripple_a), 1.2)
	_draw_common_body(body_radius, COLOR_DRIFTER_BODY, COLOR_DRIFTER_CORE, facing)
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
		var ring_world_pos := ring["world_pos"] as Vector2
		var gap_index := int(ring["gap_index"])
		var ratio := clampf(ring_radius / maxf(1.0, ring_radius_max), 0.0, 1.0)
		var fade := VISUAL_MATH.late_fade(ratio, 0.90, 3.0)
		var ring_local_center := to_local(ring_world_pos)
		for node_i in range(ring_node_count):
			if node_i == gap_index:
				continue
			var angle := float(node_i) * TAU / float(ring_node_count)
			var node_pos := ring_local_center + Vector2(cos(angle), sin(angle)) * ring_radius
			draw_circle(node_pos, node_hit_radius * 0.95,
				Color(COLOR_DRIFTER_RING.r, COLOR_DRIFTER_RING.g, COLOR_DRIFTER_RING.b, 0.18 * fade))
			draw_circle(node_pos, node_hit_radius * 0.52,
				Color(COLOR_DRIFTER_RING.r, COLOR_DRIFTER_RING.g, COLOR_DRIFTER_RING.b, 0.65 * fade))
