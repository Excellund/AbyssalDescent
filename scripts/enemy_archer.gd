extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
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
var _remote_projectile_target_positions: Dictionary = {}
var _projectile_sync_known_network_ids: Dictionary = {}
var _next_projectile_network_id: int = 1
var fire_time_left: float = 0.0
var arrows_fired: int = 0
var _windup_redraw_left: float = 0.0

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
	var projectile := Node2D.new()
	projectile.global_position = global_position + arrow_direction * 20.0
	get_parent().add_child(projectile)
	projectiles.append(projectile)
	var projectile_instance_id := projectile.get_instance_id()
	_projectile_network_ids[projectile_instance_id] = _next_projectile_network_id
	_next_projectile_network_id += 1
	projectile_directions[projectile.get_instance_id()] = arrow_direction
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _process_projectiles(delta: float) -> void:
	var completed_projectiles: Array[Node2D] = []
	var projectile_visual_changed := false
	
	for projectile in projectiles:
		if not is_instance_valid(projectile):
			projectile_directions.erase(projectile.get_instance_id())
			completed_projectiles.append(projectile)
			projectile_visual_changed = true
			continue

		var projectile_direction: Vector2 = projectile_directions.get(projectile.get_instance_id(), arrow_direction)
		
		# Move projectile
		var old_position := projectile.global_position
		projectile.global_position += projectile_direction * projectile_speed * delta
		if projectile.global_position.distance_squared_to(old_position) > 0.0001:
			projectile_visual_changed = true
		
		# Check for environmental collision using raycast
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(old_position, projectile.global_position)
		query.collide_with_areas = false
		var result := space_state.intersect_ray(query)
		if result:
			var collider: Object = result.get("collider", null)
			if collider is Node and (collider as Node).is_in_group("enemies"):
				continue
			# Hit something in the environment, despawn
			projectile.queue_free()
			completed_projectiles.append(projectile)
			projectile_visual_changed = true
			continue
		
		# Check hit on player
		if is_instance_valid(target):
			var dist_to_player := projectile.global_position.distance_to(target.global_position)
			if dist_to_player < 28.0:
				DAMAGEABLE.apply_damage(target, projectile_damage, {"source": "enemy_ability", "ability": "archer_projectile"})
				projectile.queue_free()
				completed_projectiles.append(projectile)
				projectile_visual_changed = true
				continue

		# Despawn when crossing room walls (arena bounds act as walls).
		var half_arena := arena_size * 0.5
		if absf(projectile.global_position.x) > half_arena.x or absf(projectile.global_position.y) > half_arena.y:
			projectile.queue_free()
			completed_projectiles.append(projectile)
			projectile_visual_changed = true
			continue
		
		# Remove if too far away
		if projectile.global_position.distance_to(global_position) > 1200.0:
			projectile.queue_free()
			projectile_directions.erase(projectile.get_instance_id())
			completed_projectiles.append(projectile)
			projectile_visual_changed = true
	
	for projectile in completed_projectiles:
		var projectile_instance_id := projectile.get_instance_id()
		projectile_directions.erase(projectile_instance_id)
		var network_id := int(_projectile_network_ids.get(projectile_instance_id, -1))
		if network_id > 0:
			_remote_projectiles_by_network_id.erase(network_id)
		_projectile_network_ids.erase(projectile_instance_id)
		projectiles.erase(projectile)
	if projectile_visual_changed:
		queue_redraw()


func _get_custom_network_runtime_state() -> Dictionary:
	return super._get_custom_network_runtime_state()


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
	var current_network_ids: Dictionary = {}
	var updates: Array = []
	for projectile in projectiles:
		if not is_instance_valid(projectile):
			continue
		var projectile_instance_id := projectile.get_instance_id()
		var network_id := int(_projectile_network_ids.get(projectile_instance_id, -1))
		if network_id <= 0:
			network_id = _next_projectile_network_id
			_next_projectile_network_id += 1
			_projectile_network_ids[projectile_instance_id] = network_id
		current_network_ids[network_id] = true
		var projectile_direction: Vector2 = projectile_directions.get(projectile_instance_id, arrow_direction)
		updates.append({
			"id": network_id,
			"position": projectile.global_position,
			"direction": projectile_direction
		})
	var despawn_ids: Array = []
	for network_id_variant in _projectile_sync_known_network_ids.keys():
		var known_network_id := int(network_id_variant)
		if current_network_ids.has(known_network_id):
			continue
		despawn_ids.append(known_network_id)
	_projectile_sync_known_network_ids = current_network_ids
	if updates.is_empty() and despawn_ids.is_empty():
		return {}
	return {
		"updates": updates,
		"despawn_ids": despawn_ids
	}


func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	if sync_state.is_empty():
		return
	var updates := sync_state.get("updates", []) as Array
	for projectile_state_variant in updates:
		if not (projectile_state_variant is Dictionary):
			continue
		var projectile_state := projectile_state_variant as Dictionary
		var network_id := int(projectile_state.get("id", -1))
		if network_id <= 0:
			continue
		var projectile := _remote_projectiles_by_network_id.get(network_id) as Node2D
		if not is_instance_valid(projectile):
			projectile = Node2D.new()
			if is_instance_valid(get_parent()):
				get_parent().add_child(projectile)
			projectiles.append(projectile)
			_remote_projectiles_by_network_id[network_id] = projectile
			_projectile_network_ids[projectile.get_instance_id()] = network_id
		var target_position := projectile_state.get("position", projectile.global_position) as Vector2
		if projectile.global_position.distance_squared_to(target_position) > 2304.0:
			projectile.global_position = target_position
		_remote_projectile_target_positions[network_id] = target_position
		projectile_directions[projectile.get_instance_id()] = projectile_state.get("direction", arrow_direction) as Vector2
	var despawn_ids := sync_state.get("despawn_ids", []) as Array
	for despawn_id_variant in despawn_ids:
		_remove_remote_projectile_by_network_id(int(despawn_id_variant))


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	super._apply_custom_network_runtime_state(custom_state)
	if network_simulation_enabled:
		return
	if not custom_state.has("archer_projectiles"):
		return
	var projectile_runtime_state := custom_state.get("archer_projectiles", []) as Array
	_apply_projectile_runtime_state(projectile_runtime_state)


func _build_projectile_runtime_state() -> Array:
	var payload: Array = []
	for projectile in projectiles:
		if not is_instance_valid(projectile):
			continue
		var projectile_instance_id := projectile.get_instance_id()
		var network_id := int(_projectile_network_ids.get(projectile_instance_id, -1))
		if network_id <= 0:
			network_id = _next_projectile_network_id
			_next_projectile_network_id += 1
			_projectile_network_ids[projectile_instance_id] = network_id
		var projectile_direction: Vector2 = projectile_directions.get(projectile_instance_id, arrow_direction)
		payload.append({
			"id": network_id,
			"position": projectile.global_position,
			"direction": projectile_direction
		})
	return payload


func _apply_projectile_runtime_state(projectile_runtime_state: Array) -> void:
	var seen_network_ids: Dictionary = {}
	for projectile_state_variant in projectile_runtime_state:
		if not (projectile_state_variant is Dictionary):
			continue
		var projectile_state := projectile_state_variant as Dictionary
		var network_id := int(projectile_state.get("id", -1))
		if network_id <= 0:
			continue
		seen_network_ids[network_id] = true
		var projectile := _remote_projectiles_by_network_id.get(network_id) as Node2D
		if not is_instance_valid(projectile):
			projectile = Node2D.new()
			if is_instance_valid(get_parent()):
				get_parent().add_child(projectile)
			projectiles.append(projectile)
			_remote_projectiles_by_network_id[network_id] = projectile
			_projectile_network_ids[projectile.get_instance_id()] = network_id
		var target_position := projectile_state.get("position", projectile.global_position) as Vector2
		if not is_instance_valid(projectile):
			continue
		if projectile.global_position.distance_squared_to(target_position) > 2304.0:
			projectile.global_position = target_position
		_remote_projectile_target_positions[network_id] = target_position
		projectile_directions[projectile.get_instance_id()] = projectile_state.get("direction", arrow_direction) as Vector2

	var stale_network_ids: Array = []
	for network_id_variant in _remote_projectiles_by_network_id.keys():
		var existing_network_id := int(network_id_variant)
		if seen_network_ids.has(existing_network_id):
			continue
		stale_network_ids.append(existing_network_id)
	for stale_network_id_variant in stale_network_ids:
		var stale_network_id := int(stale_network_id_variant)
		var stale_projectile := _remote_projectiles_by_network_id.get(stale_network_id) as Node2D
		if is_instance_valid(stale_projectile):
			projectile_directions.erase(stale_projectile.get_instance_id())
			_projectile_network_ids.erase(stale_projectile.get_instance_id())
			projectiles.erase(stale_projectile)
			stale_projectile.queue_free()
		_remote_projectile_target_positions.erase(stale_network_id)
		_remote_projectiles_by_network_id.erase(stale_network_id)


func _process_network_visuals(delta: float) -> void:
	if _remote_projectiles_by_network_id.is_empty():
		return
	var projectile_visual_changed := false
	for network_id_variant in _remote_projectiles_by_network_id.keys():
		var network_id := int(network_id_variant)
		var projectile := _remote_projectiles_by_network_id.get(network_id) as Node2D
		if not is_instance_valid(projectile):
			continue
		var projectile_direction := projectile_directions.get(projectile.get_instance_id(), arrow_direction) as Vector2
		var prev_position := projectile.global_position
		var target_position := _remote_projectile_target_positions.get(network_id, projectile.global_position) as Vector2
		var step_distance := projectile_speed * delta
		if projectile.global_position.distance_squared_to(target_position) > step_distance * step_distance * 9.0:
			projectile.global_position = target_position
		elif projectile_direction.length_squared() > 0.000001:
			projectile.global_position += projectile_direction.normalized() * step_distance
		else:
			projectile.global_position = target_position
		if projectile.global_position.distance_squared_to(prev_position) > 0.04:
			projectile_visual_changed = true
	if projectile_visual_changed:
		queue_redraw()


func _remove_remote_projectile_by_network_id(network_id: int) -> void:
	if network_id <= 0:
		return
	var projectile := _remote_projectiles_by_network_id.get(network_id) as Node2D
	if is_instance_valid(projectile):
		projectile_directions.erase(projectile.get_instance_id())
		_projectile_network_ids.erase(projectile.get_instance_id())
		projectiles.erase(projectile)
		projectile.queue_free()
	_remote_projectile_target_positions.erase(network_id)
	_remote_projectiles_by_network_id.erase(network_id)


func _clear_all_projectiles() -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	projectile_directions.clear()
	_projectile_network_ids.clear()
	_remote_projectile_target_positions.clear()
	_remote_projectiles_by_network_id.clear()
	_projectile_sync_known_network_ids.clear()

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
