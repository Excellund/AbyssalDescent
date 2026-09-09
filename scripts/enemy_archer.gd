extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const PROJECTILE_HIT_RADIUS := 28.0
const PROJECTILE_SOURCE_RANGE := 1200.0
const PROJECTILE_VISUAL_LEASE := 0.35
const ENEMY_STATE_ENUMS := preload("res://scripts/shared/enemy_state_enums.gd")

@export var seek_speed: float = 78.0
@export var acceleration: float = 800.0
@export var deceleration: float = 1200.0
@export var preferred_range: float = 220.0
@export var range_tolerance: float = 40.0
@export var trigger_range: float = 300.0
@export var windup_time: float = 0.6
@export var projectile_speed: float = 280.0
@export var projectile_damage: int = 14
@export var attack_cooldown: float = 2.2
@export var fire_interval: float = 0.22
@export var arena_size: Vector2 = Vector2(940.0, 700.0)
@export var remote_projectile_lerp_speed: float = 20.0
@export var windup_redraw_interval_sec: float = 0.05

var attack_cooldown_left: float = 0.0
var archer_state: int = ENEMY_STATE_ENUMS.ArcherState.SEEK
var archer_state_time_left: float = 0.0
var arrow_direction: Vector2 = Vector2.LEFT
var projectiles: Array[Node2D] = []
var projectile_directions: Dictionary = {}
var _projectile_network_ids: Dictionary = {}
var _remote_projectiles_by_network_id: Dictionary = {}
var _projectile_states: Dictionary = {}
var _projectile_wire_sequence := 0
var _projectile_received_sequence := -1
var _projectile_visual_lease := 0.0
var _projectile_sync_was_active := false
var _projectile_generation := 0
var _projectile_history_interrupted := false
var _next_projectile_network_id: int = 1
var fire_time_left: float = 0.0
var arrows_fired: int = 0
var _windup_redraw_left: float = 0.0

func _physics_process(delta: float) -> void:
	if network_simulation_enabled and not _projectile_states.is_empty() and _launch_freezes_projectiles():
		# Inherited launch movement skips arrow processing, including its final
		# step. Reseed only when processing resumes at the actors' new positions.
		_projectile_history_interrupted = true
	super._physics_process(delta)

func _launch_freezes_projectiles() -> bool:
	return _launch_state != null and _launch_state.active and not _launch_state.compression
func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	_process_projectiles(delta)
	_process_state_machine(delta)


func _exit_tree() -> void:
	_clear_all_projectiles()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _process_state_machine(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	if archer_state == ENEMY_STATE_ENUMS.ArcherState.SEEK:
		_process_seek_state(delta)
		return

	if archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP:
		_process_windup_state(delta)
		return

	if archer_state == ENEMY_STATE_ENUMS.ArcherState.FIRE:
		_process_fire_state(delta)
		return

	_process_recover_state(delta)

func _process_seek_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var dist_to_target := to_target.length()
	
	# Maintain preferred range
	var desired_direction := to_target.normalized()
	var speed_multiplier := 1.0
	if dist_to_target < preferred_range - range_tolerance:
		desired_direction = -desired_direction  # Back away
		speed_multiplier = 0.6
	elif dist_to_target > preferred_range + range_tolerance:
		speed_multiplier = 1.0
	else:
		speed_multiplier = 0.0  # At ideal range, hold position
	
	var desired_velocity := desired_direction * seek_speed * speed_multiplier * slow_speed_mult
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	
	if attack_cooldown_left <= 0.0 and dist_to_target <= trigger_range:
		_enter_windup_state()

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	_windup_redraw_left = maxf(0.0, _windup_redraw_left - delta)
	if _windup_redraw_left <= 0.0:
		_windup_redraw_left = maxf(0.016, windup_redraw_interval_sec)
		queue_redraw()
	
	if archer_state_time_left <= 0.0:
		_enter_fire_state()

func _process_fire_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	
	fire_time_left = maxf(0.0, fire_time_left - delta)
	if fire_time_left <= 0.0 and arrows_fired < 3:
		_fire_arrow()
		fire_time_left = fire_interval
		arrows_fired += 1
	
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	if archer_state_time_left <= 0.0:
		_enter_recover_state()

func _process_recover_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	if archer_state_time_left <= 0.0:
		archer_state = ENEMY_STATE_ENUMS.ArcherState.SEEK
		attack_cooldown_left = attack_cooldown

func _enter_windup_state() -> void:
	archer_state = ENEMY_STATE_ENUMS.ArcherState.WINDUP
	archer_state_time_left = windup_time
	_windup_redraw_left = 0.0
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		arrow_direction = to_target.normalized()
	visual_facing_direction = arrow_direction
	queue_redraw()

func _enter_fire_state() -> void:
	archer_state = ENEMY_STATE_ENUMS.ArcherState.FIRE
	archer_state_time_left = fire_interval * 3.5
	fire_time_left = 0.0
	arrows_fired = 0
	_windup_redraw_left = 0.0

func _enter_recover_state() -> void:
	archer_state = ENEMY_STATE_ENUMS.ArcherState.RECOVER
	archer_state_time_left = 0.4
	_windup_redraw_left = 0.0

func _fire_arrow() -> void:
	if not network_simulation_enabled:
		return
	var projectile := Node2D.new()
	get_parent().add_child(projectile)
	projectile.global_position = global_position + arrow_direction * 20.0
	var network_id := _next_projectile_network_id
	_next_projectile_network_id += 1
	_register_projectile(projectile, network_id, arrow_direction)
	var state := _projectile_states[network_id] as Dictionary
	_seed_target_history(state)
	state["source_position"] = global_position
	state["room"] = EnemyReplicationService._current_room_sync_id()
	state["bounds"] = _projectile_room_bounds()
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _register_projectile(projectile: Node2D, network_id: int, direction: Vector2) -> void:
	projectiles.append(projectile)
	var instance_id := projectile.get_instance_id()
	_projectile_network_ids[instance_id] = network_id
	projectile_directions[instance_id] = direction
	_projectile_states[network_id] = {"node": projectile, "instance_id": instance_id}

func _valid_projectile_target(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not (candidate is Node2D) or candidate.is_queued_for_deletion():
		return false
	if not _is_target_valid(candidate):
		return false
	return candidate.global_position.is_finite() and (not (candidate is PLAYER_SCRIPT) or not candidate._combat_removed)

func _seed_target_history(state: Dictionary) -> void:
	state["target_id"] = target.get_instance_id() if _valid_projectile_target(target) else 0
	state["target_position"] = target.global_position if _valid_projectile_target(target) else Vector2.ZERO
	state["target_reset"] = int(target.get_meta("combat_position_reset_generation", 0)) if _valid_projectile_target(target) else 0

func _projectile_room_bounds() -> Rect2:
	var bounds := EnemyReplicationService.get_current_room_bounds()
	return bounds if bounds.has_area() else Rect2(-arena_size * 0.5, arena_size)

func _process_projectiles(delta: float) -> void:
	if not network_simulation_enabled or _projectile_states.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	var reseed_history := _projectile_history_interrupted
	_projectile_history_interrupted = false
	var generation := _projectile_generation
	var bounds := _projectile_room_bounds()
	var room_id := EnemyReplicationService._current_room_sync_id()
	# Enemy bodies do not stop arrows. Exclude them in the same query so a
	# nearer enemy cannot hide real cover further along a long frame's segment.
	var ignored: Array[RID] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy is CollisionObject2D:
			ignored.append(enemy.get_rid())
	var hit_target: Node2D = target if _valid_projectile_target(target) else null
	if hit_target is CollisionObject2D:
		ignored.append(hit_target.get_rid())
	for network_id in _projectile_states.keys():
		if generation != _projectile_generation or is_queued_for_deletion():
			return
		var state := _projectile_states[network_id] as Dictionary
		var projectile: Variant = state.get("node")
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion() or int(state.get("room", room_id)) != room_id:
			_remove_projectile(network_id)
			continue
		var start: Vector2 = projectile.global_position
		var direction: Vector2 = projectile_directions.get(int(state.instance_id), arrow_direction)
		var step := direction * projectile_speed * delta
		if not start.is_finite() or not step.is_finite():
			_remove_projectile(network_id)
			continue
		var source_start: Vector2 = state.get("source_position", global_position)
		var bounds_changed: bool = state.get("bounds", bounds) != bounds
		if bounds_changed or reseed_history:
			# World corrections and movement while arrows were frozen must not
			# become a continuous target or source segment on the next step.
			_seed_target_history(state)
			source_start = global_position
		var boundary := ARENA_BOUNDARY.sweep(start, step, bounds)
		if bool(boundary.get("outside", false)) or start.distance_to(source_start) > PROJECTILE_SOURCE_RANGE:
			_remove_projectile(network_id)
			continue
		var stop_fraction := minf(float(boundary.get("fraction", INF)), _range_exit_fraction(start - source_start, step - (global_position - source_start)))
		var end := start + step * minf(1.0, stop_fraction)
		var query := PhysicsRayQueryParameters2D.create(start, end)
		query.exclude = ignored
		query.collide_with_areas = false
		query.hit_from_inside = true
		var terrain := get_world_2d().direct_space_state.intersect_ray(query)
		if not terrain.is_empty():
			var distance_fraction := start.distance_to(terrain.position) / maxf(step.length(), 0.000001)
			stop_fraction = minf(stop_fraction, distance_fraction)
		var hit_fraction := INF
		if _valid_projectile_target(hit_target):
			var target_end := hit_target.global_position
			var target_start := target_end
			if int(state.get("target_id", 0)) == hit_target.get_instance_id() and int(state.get("target_reset", -1)) == int(hit_target.get_meta("combat_position_reset_generation", 0)):
				target_start = state.get("target_position", target_end)
			hit_fraction = _target_contact_fraction(start - target_start, step - (target_end - target_start))
		# Cover wins ties. Consume before damage, whose callbacks may destroy
		# this enemy or clear the whole room and every remaining projectile.
		if hit_fraction <= 1.0 and hit_fraction < stop_fraction:
			projectile.global_position = start + step * hit_fraction
			_remove_projectile(network_id)
			DAMAGEABLE.apply_damage(hit_target, projectile_damage, {"source": "enemy_ability", "ability": "archer_projectile"})
		elif stop_fraction <= 1.0:
			projectile.global_position = start + step * stop_fraction
			_remove_projectile(network_id)
		else:
			projectile.global_position = start + step
			_seed_target_history(state)
			state["source_position"] = global_position
			state["bounds"] = bounds
	queue_redraw()

func _target_contact_fraction(relative_start: Vector2, relative_step: Vector2) -> float:
	var c := relative_start.length_squared() - PROJECTILE_HIT_RADIUS * PROJECTILE_HIT_RADIUS
	if c < 0.0:
		return 0.0
	var a := relative_step.length_squared()
	if a <= 0.00000001:
		return INF
	var b := relative_start.dot(relative_step)
	var discriminant := b * b - a * c
	if discriminant <= 0.0:
		return INF # Exact tangency remains outside the original strict radius.
	var fraction := (-b - sqrt(discriminant)) / a
	return fraction if fraction >= 0.0 and fraction < 1.0 else INF

func _range_exit_fraction(relative_start: Vector2, relative_step: Vector2) -> float:
	if (relative_start + relative_step).length_squared() <= PROJECTILE_SOURCE_RANGE * PROJECTILE_SOURCE_RANGE:
		return INF
	var a := relative_step.length_squared()
	if a <= 0.00000001:
		return 0.0
	var b := relative_start.dot(relative_step)
	var c := relative_start.length_squared() - PROJECTILE_SOURCE_RANGE * PROJECTILE_SOURCE_RANGE
	return clampf((-b + sqrt(maxf(0.0, b * b - a * c))) / a, 0.0, 1.0)

func _get_custom_network_runtime_state() -> Dictionary:
	return {
		"attack_cooldown_left": attack_cooldown_left,
		"archer_state": archer_state,
		"archer_state_time_left": archer_state_time_left,
		"arrow_direction": arrow_direction,
		"fire_time_left": fire_time_left
	}


func should_force_network_runtime_state_sampling() -> bool:
	return archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP or archer_state == ENEMY_STATE_ENUMS.ArcherState.FIRE


func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and not _remote_projectiles_by_network_id.is_empty()


func get_priority_network_sync_interval_sec() -> float:
	if archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP or archer_state == ENEMY_STATE_ENUMS.ArcherState.FIRE:
		return 0.03
	return 0.0


func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var states: Array = []
	for network_id in _projectile_states:
		var state := _projectile_states[network_id] as Dictionary
		var projectile: Variant = state.get("node")
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			continue
		var direction: Vector2 = projectile_directions.get(int(state.instance_id), arrow_direction)
		var visual_velocity := Vector2.ZERO if _launch_freezes_projectiles() or _projectile_history_interrupted else direction * projectile_speed
		states.append([int(network_id), PackedVector2Array([projectile.global_position, visual_velocity])])
	var active := not states.is_empty()
	if not active and not _projectile_sync_was_active:
		return {}
	_projectile_sync_was_active = active
	_projectile_wire_sequence += 1
	return {"q": _projectile_wire_sequence, "r": EnemyReplicationService._current_room_sync_id(), "p": states}

func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	var sequence: Variant = sync_state.get("q")
	var room_id: Variant = sync_state.get("r")
	var entries: Variant = sync_state.get("p")
	if not (sequence is int) or not (room_id is int) or not (entries is Array):
		return
	if sequence <= _projectile_received_sequence or room_id != EnemyReplicationService._current_room_sync_id():
		return
	var seen := {}
	for entry in entries:
		if not (entry is Array) or entry.size() != 2 or not (entry[0] is int) or entry[0] <= 0 or seen.has(entry[0]):
			return
		if not (entry[1] is PackedVector2Array) or entry[1].size() != 2 or not entry[1][0].is_finite() or not entry[1][1].is_finite():
			return
		seen[entry[0]] = true
	# Reject malformed packets before advancing sequence or touching live shots.
	_projectile_received_sequence = sequence
	for network_id in _projectile_states.keys():
		if not seen.has(network_id):
			_remove_projectile(network_id)
	for entry in entries:
		var network_id: int = entry[0]
		var vectors: PackedVector2Array = entry[1]
		var state := _projectile_states.get(network_id, {}) as Dictionary
		var projectile: Variant = state.get("node")
		if not is_instance_valid(projectile):
			_remove_projectile(network_id)
			projectile = Node2D.new()
			get_parent().add_child(projectile)
			_register_projectile(projectile, network_id, vectors[1].normalized())
			_remote_projectiles_by_network_id[network_id] = projectile
			state = _projectile_states[network_id]
		projectile.global_position = vectors[0]
		projectile_directions[int(state.instance_id)] = vectors[1].normalized()
		state["velocity"] = vectors[1]
		state["room"] = room_id
	_projectile_visual_lease = PROJECTILE_VISUAL_LEASE if not entries.is_empty() else 0.0
	queue_redraw()

func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	attack_cooldown_left = float(custom_state.get("attack_cooldown_left", attack_cooldown_left))
	archer_state = int(custom_state.get("archer_state", archer_state))
	archer_state_time_left = float(custom_state.get("archer_state_time_left", archer_state_time_left))
	arrow_direction = custom_state.get("arrow_direction", arrow_direction) as Vector2
	fire_time_left = float(custom_state.get("fire_time_left", fire_time_left))
	if network_simulation_enabled:
		return


func _process_network_visuals(delta: float) -> void:
	if network_simulation_enabled or _projectile_states.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_projectile_visual_lease = maxf(0.0, _projectile_visual_lease - delta)
	if _projectile_visual_lease <= 0.0:
		_clear_all_projectiles()
		return
	var bounds := _projectile_room_bounds()
	for network_id in _projectile_states.keys():
		var state := _projectile_states[network_id] as Dictionary
		var projectile: Variant = state.get("node")
		if not is_instance_valid(projectile) or int(state.get("room", -1)) != EnemyReplicationService._current_room_sync_id():
			_remove_projectile(network_id)
			continue
		var start: Vector2 = projectile.global_position
		var step: Vector2 = state.get("velocity", Vector2.ZERO) * delta
		if not ARENA_BOUNDARY.sweep(start, step, bounds).is_empty():
			_remove_projectile(network_id)
		else:
			projectile.global_position = start + step
	queue_redraw()

func _remove_projectile(network_id: int) -> void:
	var state := _projectile_states.get(network_id, {}) as Dictionary
	var projectile: Variant = state.get("node")
	var instance_id := int(state.get("instance_id", 0))
	for index in range(projectiles.size() - 1, -1, -1):
		if not is_instance_valid(projectiles[index]) or projectiles[index] == projectile:
			projectiles.remove_at(index)
	if is_instance_valid(projectile):
		projectile.queue_free()
	projectile_directions.erase(instance_id)
	_projectile_network_ids.erase(instance_id)
	_remote_projectiles_by_network_id.erase(network_id)
	_projectile_states.erase(network_id)

func _remove_remote_projectile_by_network_id(network_id: int) -> void:
	_remove_projectile(network_id)

func _clear_all_projectiles() -> void:
	_projectile_generation += 1
	_projectile_history_interrupted = false
	for network_id in _projectile_states.keys():
		_remove_projectile(network_id)
	projectiles.clear()
	projectile_directions.clear()
	_projectile_network_ids.clear()
	_remote_projectiles_by_network_id.clear()
	_projectile_visual_lease = 0.0
	queue_redraw()

func set_network_simulation_enabled(enabled: bool) -> void:
	if enabled != network_simulation_enabled:
		_clear_all_projectiles()
	super.set_network_simulation_enabled(enabled)
func _draw() -> void:
	var body_radius := 12.8
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var body_color := COLOR_ARCHER_BODY
	var core_color := COLOR_ARCHER_CORE
	if archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP:
		body_color = Color(0.34, 0.8, 1.0, 0.96)
		core_color = Color(0.7, 0.96, 1.0, 0.88)
	elif archer_state == ENEMY_STATE_ENUMS.ArcherState.FIRE:
		core_color = Color(1.0, 0.9, 0.5, 0.92)
	elif archer_state == ENEMY_STATE_ENUMS.ArcherState.RECOVER:
		body_color = Color(0.22, 0.66, 0.86, 0.84)
	_draw_common_body(body_radius, body_color, core_color, facing)

	# Bow-arm fins communicate ranged role from a distance.
	var fin_base := facing * (body_radius + 1.8)
	var upper_fin := PackedVector2Array([
		fin_base + side * 7.6,
		fin_base + side * 3.1 + facing * 8.0,
		fin_base + side * 2.6 - facing * 5.8
	])
	var lower_fin := PackedVector2Array([
		fin_base - side * 7.6,
		fin_base - side * 3.1 + facing * 8.0,
		fin_base - side * 2.6 - facing * 5.8
	])
	var fin_color := Color(0.84, 0.97, 1.0, 0.44)
	if archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP:
		fin_color = Color(1.0, 0.88, 0.5, 0.62)
	draw_colored_polygon(upper_fin, fin_color)
	draw_colored_polygon(lower_fin, fin_color)
	
	# Draw telegraph during windup
	if archer_state == ENEMY_STATE_ENUMS.ArcherState.WINDUP:
		var low_detail_telegraph := _is_high_load_visual_lod_active()
		var windup_phase := 1.0 - (archer_state_time_left / windup_time) if windup_time > 0.0 else 1.0
		var line_length := 400.0
		var line_end := arrow_direction * line_length
		var bracket_size := 20.0
		var aim_side := Vector2(-arrow_direction.y, arrow_direction.x)  
		var aim_pos := arrow_direction * 100.0
		var bracket_pulse := 0.6 + 0.4 * sin(windup_phase * PI * 2.0)
		var bracket_alpha := COLOR_ARCHER_AIM_BRACKET.a * bracket_pulse
		draw_line(Vector2.ZERO, line_end, COLOR_ARCHER_AIM, 2.0)
		draw_line(aim_pos - aim_side * bracket_size, aim_pos + aim_side * bracket_size, Color(COLOR_ARCHER_AIM_BRACKET.r, COLOR_ARCHER_AIM_BRACKET.g, COLOR_ARCHER_AIM_BRACKET.b, bracket_alpha), 1.8)
		if not low_detail_telegraph:
			# Background aim guide (subtle inner line)
			draw_line(Vector2.ZERO, line_end * 0.8, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.3), 1.0)
			# Corner accent marks for target box
			var corner_len := 8.0
			draw_line(aim_pos + aim_side * bracket_size - arrow_direction * corner_len, aim_pos + aim_side * bracket_size, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.7), 1.4)
			draw_line(aim_pos - aim_side * bracket_size - arrow_direction * corner_len, aim_pos - aim_side * bracket_size, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.7), 1.4)
	
	# Draw projectiles
	var viewport := get_viewport()
	var screen_rect := viewport.get_visible_rect() if viewport != null else Rect2()
	var canvas_transform := viewport.get_canvas_transform() if viewport != null else Transform2D.IDENTITY
	var offscreen_margin := 16.0
	for projectile in projectiles:
		if is_instance_valid(projectile):
			if viewport != null:
				var projectile_screen_pos := canvas_transform * projectile.global_position
				if projectile_screen_pos.x < -offscreen_margin or projectile_screen_pos.x > screen_rect.size.x + offscreen_margin or projectile_screen_pos.y < -offscreen_margin or projectile_screen_pos.y > screen_rect.size.y + offscreen_margin:
					continue
			var offset := projectile.global_position - global_position
			draw_circle(offset, 4.0, COLOR_ARCHER_PROJECTILE)
			draw_circle(offset, 2.2, Color(1.0, 0.92, 0.6, 0.9))
	_draw_slow_indicator(12.8)
