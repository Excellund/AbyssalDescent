extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ENEMY_STATE_ENUMS := preload("res://scripts/shared/enemy_state_enums.gd")
const SEAMLOCK_SYNC_GROUP := "seamlock_sync_group"

# --- Scale & Health ---
@export var max_health_apex: int = 380
@export var body_draw_radius: float = 26.0

# --- Movement ---
@export var move_speed: float = 68.0
@export var acceleration: float = 680.0
@export var deceleration: float = 920.0
@export var band_inner_min: float = 120.0
@export var band_outer_max: float = 250.0

# --- Contact ---
@export var contact_damage: int = 22
@export var contact_attack_range: float = 56.0
@export var contact_attack_interval: float = 1.2

# --- Stalk / Teleport ---
@export var stalk_duration_min: float = 1.8
@export var stalk_duration_max: float = 3.2
@export var teleport_windup_time: float = 0.55
@export var arena_size: Vector2 = Vector2(1160.0, 860.0)
@export var arena_center_world: Vector2 = Vector2.ZERO

# --- Illusion ---
@export var illusion_phase_duration: float = 4.5

# --- Band Attack ---
@export var band_attack_windup: float = 1.2
@export var band_attack_duration: float = 2.8
@export var band_inner_danger_radius: float = 78.0
@export var band_safe_1_outer_radius: float = 168.0
@export var band_mid_danger_outer_radius: float = 328.0
@export var band_safe_2_outer_radius: float = 418.0
@export var band_tick_damage: int = 12
@export var band_tick_interval: float = 0.55

# --- Spiral ---
@export var spiral_windup: float = 0.8
@export var spiral_arm_count: int = 4
@export var spiral_projectile_speed: float = 140.0
@export var spiral_spin_rate: float = 2.1
@export var spiral_max_radius: float = 380.0
@export var spiral_hit_radius: float = 10.0
@export var spiral_damage: int = 16

# --- Arena Penalty ---
@export var arena_shrink_per_step: float = 72.0
@export var arena_shrink_lerp_speed: float = 3.2
@export var illusion_wrong_hit_tolerance: float = 24.0

# --- Health Bar ---
@export var health_bar_size_apex: Vector2 = Vector2(84.0, 11.0)
@export var health_bar_offset_apex: Vector2 = Vector2(-42.0, -52.0)

# === State ===
var seamlock_state: int = ENEMY_STATE_ENUMS.SeamlockState.STALK
var state_time_left: float = 0.0
var contact_attack_cooldown_left: float = 0.0

# Teleport
var _teleport_flash_left: float = 0.0

# Illusion
var _illusion_positions: Array[Vector2] = []
var _illusion_shatter_times: Array[float] = []
var _illusion_phase_left: float = 0.0
var _last_target_attack_anim_time: float = 0.0

# Band attack
var _band_windup_left: float = 0.0
var _band_duration_left: float = 0.0
var _band_tick_left: float = 0.0
var _band_is_active: bool = false

# Spiral arms: Array of {angle: float, radius: float}
var _spiral_arms: Array[Dictionary] = []
var _spiral_hit_cooldowns: Array[float] = []
var _spiral_windup_left: float = 0.0
var _spiral_active: bool = false

# Arena penalty
var arena_penalty_steps: int = 0
var _arena_penalty_applied_steps: float = 0.0
var _arena_center_anchor_world: Vector2 = Vector2.ZERO

var _attack_sync_was_active: bool = false

func _get_custom_network_runtime_state() -> Dictionary:
	var illusion_positions: Array = []
	for pos in _illusion_positions:
		illusion_positions.append(pos)
	var illusion_shatter_times: Array = []
	for t in _illusion_shatter_times:
		illusion_shatter_times.append(float(t))
	var spiral_arms: Array = []
	for arm_variant in _spiral_arms:
		if arm_variant is Dictionary:
			spiral_arms.append((arm_variant as Dictionary).duplicate(true))
	var spiral_hit_cooldowns: Array = []
	for cooldown in _spiral_hit_cooldowns:
		spiral_hit_cooldowns.append(float(cooldown))
	return {
		"seamlock_state": seamlock_state,
		"state_time_left": state_time_left,
		"contact_attack_cooldown_left": contact_attack_cooldown_left,
		"teleport_flash_left": _teleport_flash_left,
		"illusion_positions": illusion_positions,
		"illusion_shatter_times": illusion_shatter_times,
		"illusion_phase_left": _illusion_phase_left,
		"band_windup_left": _band_windup_left,
		"band_duration_left": _band_duration_left,
		"band_tick_left": _band_tick_left,
		"band_is_active": _band_is_active,
		"spiral_arms": spiral_arms,
		"spiral_hit_cooldowns": spiral_hit_cooldowns,
		"spiral_windup_left": _spiral_windup_left,
		"spiral_active": _spiral_active,
		"arena_penalty_steps": arena_penalty_steps,
		"arena_center_anchor_world": _arena_center_anchor_world
	}


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	seamlock_state = int(custom_state.get("seamlock_state", seamlock_state))
	state_time_left = float(custom_state.get("state_time_left", state_time_left))
	contact_attack_cooldown_left = float(custom_state.get("contact_attack_cooldown_left", contact_attack_cooldown_left))
	_teleport_flash_left = float(custom_state.get("teleport_flash_left", _teleport_flash_left))
	_illusion_positions.clear()
	var illusion_positions := custom_state.get("illusion_positions", []) as Array
	for pos_variant in illusion_positions:
		if pos_variant is Vector2:
			_illusion_positions.append(pos_variant as Vector2)
	_illusion_shatter_times.clear()
	var illusion_shatter_times := custom_state.get("illusion_shatter_times", []) as Array
	for time_variant in illusion_shatter_times:
		_illusion_shatter_times.append(float(time_variant))
	_illusion_phase_left = float(custom_state.get("illusion_phase_left", _illusion_phase_left))
	_band_windup_left = float(custom_state.get("band_windup_left", _band_windup_left))
	_band_duration_left = float(custom_state.get("band_duration_left", _band_duration_left))
	_band_tick_left = float(custom_state.get("band_tick_left", _band_tick_left))
	_band_is_active = bool(custom_state.get("band_is_active", _band_is_active))
	_spiral_arms.clear()
	var spiral_arms := custom_state.get("spiral_arms", []) as Array
	for arm_variant in spiral_arms:
		if arm_variant is Dictionary:
			_spiral_arms.append((arm_variant as Dictionary).duplicate(true))
	_spiral_hit_cooldowns.clear()
	var spiral_hit_cooldowns := custom_state.get("spiral_hit_cooldowns", []) as Array
	for cooldown_variant in spiral_hit_cooldowns:
		_spiral_hit_cooldowns.append(float(cooldown_variant))
	_spiral_windup_left = float(custom_state.get("spiral_windup_left", _spiral_windup_left))
	_spiral_active = bool(custom_state.get("spiral_active", _spiral_active))
	arena_penalty_steps = int(custom_state.get("arena_penalty_steps", arena_penalty_steps))
	_arena_center_anchor_world = custom_state.get("arena_center_anchor_world", _arena_center_anchor_world) as Vector2

func _ready() -> void:
	max_health = max_health_apex
	super._ready()
	add_to_group(SEAMLOCK_SYNC_GROUP)
	_arena_center_anchor_world = _resolve_stationary_arena_center()
	crowd_separation_radius = 110.0
	crowd_separation_strength = 140.0
	configure_health_bar_visuals(health_bar_offset_apex, health_bar_size_apex)
	health_changed.connect(_on_health_changed)
	state_time_left = randf_range(stalk_duration_min, stalk_duration_max)
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 24.0
			break
	_arena_penalty_applied_steps = float(arena_penalty_steps)
	_sync_health_bar_visibility()

func _resolve_stationary_arena_center() -> Vector2:
	if arena_center_world != Vector2.ZERO:
		return arena_center_world
	for node in get_tree().get_nodes_in_group(SEAMLOCK_SYNC_GROUP):
		if node == self:
			continue
		if not is_instance_valid(node):
			continue
		var shared_center: Variant = node.get("_arena_center_anchor_world")
		if shared_center is Vector2 and (shared_center as Vector2) != Vector2.ZERO:
			arena_center_world = shared_center
			return shared_center as Vector2
	arena_center_world = global_position
	return arena_center_world

func _exit_tree() -> void:
	remove_from_group(SEAMLOCK_SYNC_GROUP)

# When the Seamlock takes damage during ILLUSION_PHASE, determine if the player
# was closest to the real body or to a decoy. Wrong guess = arena shrinks.
func _on_health_changed(_current: int, _max_hp: int) -> void:
	if seamlock_state != ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE:
		return
	# Real body took damage during illusion phase: this is a confirmed correct hit.
	_illusion_positions.clear()
	_illusion_shatter_times.clear()
	_illusion_phase_left = 0.0
	_enter_band_attack()

func _apply_arena_penalty() -> void:
	var next_steps := mini(arena_penalty_steps + 1, 3)
	for node in get_tree().get_nodes_in_group(SEAMLOCK_SYNC_GROUP):
		if node is Node and is_instance_valid(node) and node.has_method("_set_shared_arena_penalty_steps"):
			node.call("_set_shared_arena_penalty_steps", next_steps)

func _set_shared_arena_penalty_steps(steps: int) -> void:
	var clamped := clampi(steps, 0, 3)
	if clamped == arena_penalty_steps:
		return
	arena_penalty_steps = clamped
	queue_redraw()

func _get_effective_arena_half() -> Vector2:
	var shrink := _arena_penalty_applied_steps * arena_shrink_per_step
	return Vector2(
		maxf(160.0, arena_size.x * 0.5 - shrink),
		maxf(120.0, arena_size.y * 0.5 - shrink)
	)

func _clamp_to_active_room_bounds(world_pos: Vector2) -> Vector2:
	var parent_node := get_parent()
	if parent_node != null:
		var effective_size_variant: Variant = parent_node.get("current_effective_room_size")
		if effective_size_variant is Vector2 and (effective_size_variant as Vector2) != Vector2.ZERO:
			var half := (effective_size_variant as Vector2) * 0.5
			return Vector2(
				clampf(world_pos.x, -half.x, half.x),
				clampf(world_pos.y, -half.y, half.y)
			)
	var fallback_half := _get_effective_arena_half()
	return Vector2(
		clampf(world_pos.x, _arena_center_anchor_world.x - fallback_half.x, _arena_center_anchor_world.x + fallback_half.x),
		clampf(world_pos.y, _arena_center_anchor_world.y - fallback_half.y, _arena_center_anchor_world.y + fallback_half.y)
	)

func _get_active_room_bounds() -> Rect2:
	var parent_node := get_parent()
	if parent_node != null:
		var effective_size_variant: Variant = parent_node.get("current_effective_room_size")
		if effective_size_variant is Vector2 and (effective_size_variant as Vector2) != Vector2.ZERO:
			var effective_size := effective_size_variant as Vector2
			return Rect2(-effective_size * 0.5, effective_size)
	var fallback_half := _get_effective_arena_half()
	var fallback_size := fallback_half * 2.0
	return Rect2(_arena_center_anchor_world - fallback_half, fallback_size)

func _update_arena_penalty_lerp(delta: float) -> void:
	var target_steps := float(arena_penalty_steps)
	var prev_steps := _arena_penalty_applied_steps
	_arena_penalty_applied_steps = move_toward(_arena_penalty_applied_steps, target_steps, arena_shrink_lerp_speed * delta)
	if absf(prev_steps - _arena_penalty_applied_steps) > 0.0001:
		queue_redraw()

func _process_behavior(delta: float) -> void:
	if contact_attack_cooldown_left > 0.0:
		contact_attack_cooldown_left = maxf(0.0, contact_attack_cooldown_left - delta)
	_try_contact_attack()
	_sync_health_bar_visibility()
	_update_arena_penalty_lerp(delta)
	_process_spiral_projectiles_independent(delta)
	if _teleport_flash_left > 0.0:
		_teleport_flash_left = maxf(0.0, _teleport_flash_left - delta)
		queue_redraw()
	match seamlock_state:
		ENEMY_STATE_ENUMS.SeamlockState.STALK:
			_process_stalk(delta)
		ENEMY_STATE_ENUMS.SeamlockState.TELEPORT:
			_process_teleport(delta)
		ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE:
			_process_illusion_phase(delta)
		ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK:
			_process_band_attack(delta)
		ENEMY_STATE_ENUMS.SeamlockState.SPIRAL:
			_process_spiral(delta)
		ENEMY_STATE_ENUMS.SeamlockState.RECOVER:
			_process_recover(delta)

func _process_spiral_projectiles_independent(delta: float) -> void:
	if _spiral_arms.is_empty():
		if _spiral_active:
			_spiral_active = false
			if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL:
				_enter_recover()
		return
	_update_spiral_arms(delta)
	queue_redraw()
	if _spiral_arms.is_empty() and _spiral_active:
		_spiral_active = false
		if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL:
			_enter_recover()

func _process_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var desired := Vector2.ZERO
	if dist > band_outer_max:
		desired = to_target.normalized() * move_speed * slow_speed_mult
	elif dist < band_inner_min:
		desired = -to_target.normalized() * move_speed * 0.7 * slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		_enter_teleport()

func _enter_teleport() -> void:
	seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.TELEPORT
	state_time_left = teleport_windup_time
	velocity = Vector2.ZERO
	queue_redraw()

func _process_teleport(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_execute_teleport()

func _execute_teleport() -> void:
	var effective_half := _get_effective_arena_half()
	var margin := 80.0
	var new_pos := global_position
	for _attempt in range(10):
		var cx := randf_range(-effective_half.x + margin, effective_half.x - margin)
		var cy := randf_range(-effective_half.y + margin, effective_half.y - margin)
		var candidate := _arena_center_anchor_world + Vector2(cx, cy)
		if not is_instance_valid(target) or candidate.distance_to(target.global_position) > band_inner_min + 40.0:
			new_pos = _clamp_to_active_room_bounds(candidate)
			break
	global_position = _clamp_to_active_room_bounds(new_pos)
	_teleport_flash_left = 0.40
	_enter_illusion_phase(true)

func _enter_illusion_phase(allow_group_sync: bool) -> void:
	_spawn_illusions()
	seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE
	_illusion_phase_left = illusion_phase_duration
	velocity = Vector2.ZERO
	queue_redraw()
	if allow_group_sync and _has_multiple_seamlocks_active():
		for node in get_tree().get_nodes_in_group(SEAMLOCK_SYNC_GROUP):
			if node == self:
				continue
			if node is Node and is_instance_valid(node) and node.has_method("_force_synced_illusion_phase"):
				node.call("_force_synced_illusion_phase")

func _force_synced_illusion_phase() -> void:
	# Keep other behavior unsynced: only align illusion windows when multiple Seamlocks are present.
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE:
		_illusion_phase_left = maxf(_illusion_phase_left, illusion_phase_duration)
		return
	_teleport_flash_left = maxf(_teleport_flash_left, 0.30)
	_enter_illusion_phase(false)

func _has_multiple_seamlocks_active() -> bool:
	var active_count := 0
	for node in get_tree().get_nodes_in_group(SEAMLOCK_SYNC_GROUP):
		if not is_instance_valid(node):
			continue
		if node is Node2D and not node.is_queued_for_deletion():
			active_count += 1
			if active_count > 1:
				return true
	return false

func _spawn_illusions() -> void:
	_illusion_positions.clear()
	_illusion_shatter_times.clear()
	var active_bounds := _get_active_room_bounds()
	var margin := 80.0
	var min_x := active_bounds.position.x + margin
	var max_x := active_bounds.position.x + active_bounds.size.x - margin
	var min_y := active_bounds.position.y + margin
	var max_y := active_bounds.position.y + active_bounds.size.y - margin
	if max_x <= min_x:
		min_x = active_bounds.position.x
		max_x = active_bounds.position.x + active_bounds.size.x
	if max_y <= min_y:
		min_y = active_bounds.position.y
		max_y = active_bounds.position.y + active_bounds.size.y
	var attempts := 0
	while _illusion_positions.size() < 3 and attempts < 24:
		attempts += 1
		var candidate := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if candidate.distance_to(global_position) < 120.0:
			continue
		var too_close := false
		for existing in _illusion_positions:
			if candidate.distance_to(existing) < 100.0:
				too_close = true
				break
		if not too_close:
			_illusion_positions.append(candidate)
			_illusion_shatter_times.append(0.0)

func _process_illusion_phase(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_try_resolve_illusion_guess_from_player_attack()
	_illusion_phase_left = maxf(0.0, _illusion_phase_left - delta)
	for i in _illusion_shatter_times.size():
		_illusion_shatter_times[i] = maxf(0.0, float(_illusion_shatter_times[i]) - delta)
	queue_redraw()
	if _illusion_phase_left <= 0.0:
		_illusion_positions.clear()
		_illusion_shatter_times.clear()
		_enter_band_attack()

func _is_point_inside_attack_indicator(origin: Vector2, direction: Vector2, point: Vector2, indicator_range: float, indicator_arc_degrees: float, radius_padding: float) -> bool:
	var to_point := point - origin
	var dist := to_point.length()
	if dist > indicator_range + radius_padding:
		return false
	if dist <= 0.0001:
		return true
	var dir := direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var half_arc_radians := deg_to_rad(maxf(0.0, indicator_arc_degrees * 0.5))
	var point_dir := to_point / dist
	var dot_value := clampf(dir.dot(point_dir), -1.0, 1.0)
	var angle_to_point := acos(dot_value)
	return angle_to_point <= half_arc_radians

func _try_resolve_illusion_guess_from_player_attack() -> void:
	if seamlock_state != ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE:
		_last_target_attack_anim_time = 0.0
		return
	if not is_instance_valid(target) or _illusion_positions.is_empty():
		_last_target_attack_anim_time = 0.0
		return
	var attack_anim_time := float(target.get("attack_anim_time_left")) if target.get("attack_anim_time_left") != null else 0.0
	var attack_started := attack_anim_time > 0.0 and _last_target_attack_anim_time <= 0.0
	_last_target_attack_anim_time = attack_anim_time
	if not attack_started:
		return
	var attack_origin := target.global_position
	var attack_direction := target.get("visual_facing_direction") as Vector2
	if attack_direction.length_squared() <= 0.000001:
		attack_direction = (global_position - attack_origin).normalized()
	if attack_direction.length_squared() <= 0.000001:
		attack_direction = Vector2.RIGHT
	var indicator_range := float(target.get("attack_range")) if target.get("attack_range") != null else 78.0
	var indicator_arc := float(target.get("attack_arc_degrees")) if target.get("attack_arc_degrees") != null else 130.0
	var target_padding := body_draw_radius + 8.0
	var real_hit := _is_point_inside_attack_indicator(attack_origin, attack_direction, global_position, indicator_range, indicator_arc, target_padding)
	var nearest_illusion_dist := INF
	var nearest_illusion_idx := -1
	for i in _illusion_positions.size():
		var illusion_pos := _illusion_positions[i]
		if not _is_point_inside_attack_indicator(attack_origin, attack_direction, illusion_pos, indicator_range, indicator_arc, target_padding):
			continue
		var dist := attack_origin.distance_to(illusion_pos)
		if dist < nearest_illusion_dist:
			nearest_illusion_dist = dist
			nearest_illusion_idx = i
	if nearest_illusion_idx < 0:
		# Swing did not intersect any illusion; only real damage callback should resolve success.
		return
	if not real_hit or nearest_illusion_dist <= attack_origin.distance_to(global_position) + illusion_wrong_hit_tolerance:
		_apply_arena_penalty()
		if nearest_illusion_idx < _illusion_shatter_times.size():
			_illusion_shatter_times[nearest_illusion_idx] = 0.44

func _enter_band_attack() -> void:
	seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK
	_band_windup_left = band_attack_windup
	_band_duration_left = band_attack_duration
	_band_tick_left = 0.0
	_band_is_active = false
	velocity = Vector2.ZERO
	queue_redraw()

func _process_band_attack(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if _band_windup_left > 0.0:
		_band_windup_left = maxf(0.0, _band_windup_left - delta)
		queue_redraw()
		if _band_windup_left <= 0.0:
			_band_is_active = true
			_band_tick_left = 0.0
		return
	_band_duration_left = maxf(0.0, _band_duration_left - delta)
	_band_tick_left = maxf(0.0, _band_tick_left - delta)
	if _band_tick_left <= 0.0:
		_try_band_damage()
		_band_tick_left = band_tick_interval
	queue_redraw()
	if _band_duration_left <= 0.0:
		_band_is_active = false
		_enter_spiral()

func _try_band_damage() -> void:
	if not is_instance_valid(target) or not DAMAGEABLE.can_take_damage(target):
		return
	var dist := global_position.distance_to(target.global_position)
	if _is_in_band_danger(dist):
		if DAMAGEABLE.apply_damage(target, band_tick_damage, {"source": "enemy_contact", "ability": "seamlock_band"}):
			attack_anim_time_left = attack_anim_duration
			queue_redraw()

func _get_band_outer_limit_radius() -> float:
	return band_safe_2_outer_radius

func _is_in_band_danger(dist: float) -> bool:
	if dist < band_inner_danger_radius:
		return true
	if dist > band_safe_1_outer_radius and dist < band_mid_danger_outer_radius:
		return true
	return false

func _enter_spiral() -> void:
	seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.SPIRAL
	_spiral_windup_left = spiral_windup
	_spiral_active = false
	_spiral_arms.clear()
	_spiral_hit_cooldowns.clear()
	queue_redraw()

func _process_spiral(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if _spiral_windup_left > 0.0:
		_spiral_windup_left = maxf(0.0, _spiral_windup_left - delta)
		queue_redraw()
		if _spiral_windup_left <= 0.0:
			_launch_spiral_arms()
		return

func _launch_spiral_arms() -> void:
	_spiral_active = true
	_spiral_arms.clear()
	_spiral_hit_cooldowns.clear()
	var base_angle := randf() * TAU
	for i in spiral_arm_count:
		var arm_angle := base_angle + (TAU / float(spiral_arm_count)) * float(i)
		_spiral_arms.append({"angle": arm_angle, "radius": body_draw_radius + 4.0})
		_spiral_hit_cooldowns.append(0.0)

func _update_spiral_arms(delta: float) -> void:
	for i in _spiral_hit_cooldowns.size():
		_spiral_hit_cooldowns[i] = maxf(0.0, float(_spiral_hit_cooldowns[i]) - delta)
	var to_remove: Array[int] = []
	for i in _spiral_arms.size():
		var arm := _spiral_arms[i]
		arm["angle"] = float(arm["angle"]) + spiral_spin_rate * delta
		arm["radius"] = float(arm["radius"]) + spiral_projectile_speed * delta
		_spiral_arms[i] = arm
		if float(arm["radius"]) >= spiral_max_radius:
			to_remove.append(i)
			continue
		if is_instance_valid(target) and DAMAGEABLE.can_take_damage(target) and float(_spiral_hit_cooldowns[i]) <= 0.0:
			var proj_pos := global_position + Vector2(cos(float(arm["angle"])), sin(float(arm["angle"]))) * float(arm["radius"])
			if proj_pos.distance_to(target.global_position) <= spiral_hit_radius + 14.0:
				if DAMAGEABLE.apply_damage(target, spiral_damage, {"source": "enemy_contact", "ability": "seamlock_spiral"}):
					_spiral_hit_cooldowns[i] = 0.35
					attack_anim_time_left = attack_anim_duration
					queue_redraw()
	for i in range(to_remove.size() - 1, -1, -1):
		var idx := to_remove[i]
		_spiral_arms.remove_at(idx)
		_spiral_hit_cooldowns.remove_at(idx)

func _enter_recover() -> void:
	_spiral_active = false
	seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.RECOVER
	state_time_left = randf_range(0.6, 1.1)
	queue_redraw()

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		seamlock_state = ENEMY_STATE_ENUMS.SeamlockState.STALK
		state_time_left = randf_range(stalk_duration_min, stalk_duration_max)

func _try_contact_attack() -> void:
	if contact_attack_cooldown_left > 0.0:
		return
	if not is_instance_valid(target) or not DAMAGEABLE.can_take_damage(target):
		return
	var touch_range := maxf(contact_attack_range, body_draw_radius + 34.0)
	if global_position.distance_to(target.global_position) > touch_range:
		return
	if DAMAGEABLE.apply_damage(target, contact_damage, {"source": "enemy_contact", "ability": "seamlock_strike"}):
		contact_attack_cooldown_left = contact_attack_interval
		attack_anim_time_left = attack_anim_duration
		queue_redraw()

# === Network Sync ===

func should_force_network_runtime_state_sampling() -> bool:
	return seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK \
		or seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL \
		or attack_anim_time_left > 0.0

func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and (
		seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK
		or seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL
		or seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE
	)

func get_priority_network_sync_interval_sec() -> float:
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK \
			or seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL:
		return 0.03
	return 0.0

func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active_states: Array[int] = [
		ENEMY_STATE_ENUMS.SeamlockState.TELEPORT,
		ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE,
		ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK,
		ENEMY_STATE_ENUMS.SeamlockState.SPIRAL,
	]
	var active := seamlock_state in active_states
	if not active and not _attack_sync_was_active:
		return {}
	var illusion_arr: Array = []
	for i in _illusion_positions.size():
		var pos := _illusion_positions[i]
		var shatter_t := _illusion_shatter_times[i] if i < _illusion_shatter_times.size() else 0.0
		illusion_arr.append({"x": pos.x, "y": pos.y, "shatter": float(shatter_t)})
	var arms_arr: Array = []
	for arm in _spiral_arms:
		arms_arr.append(arm.duplicate())
	var payload := {
		"active": active,
		"seamlock_state": seamlock_state,
		"state_time_left": state_time_left,
		"band_is_active": _band_is_active,
		"band_windup_left": _band_windup_left,
		"band_duration_left": _band_duration_left,
		"spiral_active": _spiral_active,
		"spiral_arms": arms_arr,
		"illusion_positions": illusion_arr,
		"illusion_phase_left": _illusion_phase_left,
		"arena_penalty_steps": arena_penalty_steps,
		"arena_center_world": _arena_center_anchor_world,
		"teleport_flash_left": _teleport_flash_left,
		"visual_facing_direction": visual_facing_direction,
		"attack_anim_time_left": attack_anim_time_left,
	}
	_attack_sync_was_active = active
	return payload

func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	if sync_state.is_empty():
		return
	seamlock_state = int(sync_state.get("seamlock_state", seamlock_state))
	state_time_left = float(sync_state.get("state_time_left", state_time_left))
	_band_is_active = bool(sync_state.get("band_is_active", _band_is_active))
	_band_windup_left = float(sync_state.get("band_windup_left", _band_windup_left))
	_band_duration_left = float(sync_state.get("band_duration_left", _band_duration_left))
	_spiral_active = bool(sync_state.get("spiral_active", _spiral_active))
	_illusion_phase_left = float(sync_state.get("illusion_phase_left", _illusion_phase_left))
	arena_penalty_steps = int(sync_state.get("arena_penalty_steps", arena_penalty_steps))
	_arena_center_anchor_world = sync_state.get("arena_center_world", _arena_center_anchor_world) as Vector2
	arena_center_world = _arena_center_anchor_world
	_arena_penalty_applied_steps = minf(_arena_penalty_applied_steps, float(arena_penalty_steps))
	_teleport_flash_left = float(sync_state.get("teleport_flash_left", _teleport_flash_left))
	visual_facing_direction = sync_state.get("visual_facing_direction", visual_facing_direction) as Vector2
	attack_anim_time_left = float(sync_state.get("attack_anim_time_left", attack_anim_time_left))
	var illusion_arr := sync_state.get("illusion_positions", []) as Array
	_illusion_positions.clear()
	_illusion_shatter_times.clear()
	for entry in illusion_arr:
		if entry is Dictionary:
			_illusion_positions.append(Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))))
			_illusion_shatter_times.append(float(entry.get("shatter", 0.0)))
	var arms_arr := sync_state.get("spiral_arms", []) as Array
	_spiral_arms.clear()
	_spiral_hit_cooldowns.clear()
	for arm in arms_arr:
		if arm is Dictionary:
			_spiral_arms.append(arm.duplicate())
			_spiral_hit_cooldowns.append(0.0)
	queue_redraw()

func _process_network_visuals(delta: float) -> void:
	var needs_redraw := false
	_sync_health_bar_visibility()
	_update_arena_penalty_lerp(delta)
	if _teleport_flash_left > 0.0:
		_teleport_flash_left = maxf(0.0, _teleport_flash_left - delta)
		needs_redraw = true
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE and _illusion_phase_left > 0.0:
		_illusion_phase_left = maxf(0.0, _illusion_phase_left - delta)
		needs_redraw = true
	if _band_windup_left > 0.0 or (_band_is_active and _band_duration_left > 0.0):
		needs_redraw = true
	if not _spiral_arms.is_empty():
		needs_redraw = true
	if needs_redraw:
		queue_redraw()

# === Draw ===

func _draw() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var attack_pulse := _get_attack_pulse()
	var body_radius := body_draw_radius + attack_pulse * 1.4

	const BODY_COLOR     := Color(0.16, 0.10, 0.38, 1.0)
	const CORE_COLOR     := Color(0.36, 0.86, 1.0, 1.0)
	const _GLOW_COLOR     := Color(0.42, 0.22, 0.74, 0.22)
	const RING_COLOR     := Color(0.44, 0.28, 0.86, 0.46)
	const BAND_WARN      := Color(1.0, 0.88, 0.26, 0.30)
	const BAND_ACTIVE    := Color(1.0, 0.40, 0.16, 0.64)
	const SPIRAL_COLOR   := Color(0.36, 1.0, 0.90, 1.0)
	const SPIRAL_GLOW    := Color(0.36, 1.0, 0.90, 0.26)
	const TELEPORT_BURST := Color(0.64, 0.92, 1.0, 0.92)
	var pulse_ring := 0.5 + 0.5 * sin(t * 2.4)
	var real_ring_radius := body_draw_radius + 10.0 + pulse_ring * 4.0
	var real_ring_alpha := 0.42 + pulse_ring * 0.22
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE:
		var tell_pulse := 0.5 + 0.5 * sin(t * 3.3)
		real_ring_radius = body_draw_radius + 10.0 + tell_pulse * 5.2
		real_ring_alpha = 0.40 + tell_pulse * 0.40

	# Band danger rings with safe zone pulsing
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.BAND_ATTACK:
		if _band_windup_left > 0.0:
			var wt := 1.0 - (_band_windup_left / band_attack_windup)
			_draw_band_danger_zones(Color(BAND_WARN.r, BAND_WARN.g, BAND_WARN.b, 0.18 + wt * 0.16))
			_draw_band_zone_details(t, 0.18 + wt * 0.38, 0.0)
		elif _band_is_active:
			var pulse := 0.5 + 0.5 * sin(t * 8.0)
			_draw_band_danger_zones(Color(BAND_ACTIVE.r, BAND_ACTIVE.g, BAND_ACTIVE.b, 0.24 + pulse * 0.18))
			var tick_flash: float = 0.0
			if band_tick_interval > 0.0:
				var tick_ratio: float = 1.0 - clamp(_band_tick_left / band_tick_interval, 0.0, 1.0)
				tick_flash = tick_ratio * tick_ratio
				_draw_band_danger_zones(Color(1.0, 0.95, 0.9, tick_flash * 0.12))
			_draw_band_zone_details(t, 0.52 + pulse * 0.36, tick_flash)

	# Spiral projectiles with trails
	for i in _spiral_arms.size():
		var arm := _spiral_arms[i]
		var proj_pos := Vector2(cos(float(arm["angle"])), sin(float(arm["angle"]))) * float(arm["radius"])
		# Quick fade as projectile reaches max radius
		var fade_start_radius := spiral_max_radius * 0.90
		var fade_alpha := 1.0
		if float(arm["radius"]) > fade_start_radius:
			fade_alpha = maxf(0.0, 1.0 - (float(arm["radius"]) - fade_start_radius) / (spiral_max_radius - fade_start_radius))
		# Trail: draw fading circles showing spiral path (rotation + expansion history)
		var trail_count := 6
		for ti in range(1, trail_count):
			var trail_t := float(ti) / float(trail_count)
			var frame_delta := 0.033 * float(trail_count - ti)
			var trail_angle := float(arm["angle"]) - spiral_spin_rate * frame_delta
			var trail_radius := float(arm["radius"]) - spiral_projectile_speed * frame_delta
			if trail_radius > body_draw_radius + 4.0:
				var trail_pos := Vector2(cos(trail_angle), sin(trail_angle)) * trail_radius
				var trail_alpha := (1.0 - trail_t) * 0.4 * fade_alpha
				draw_circle(trail_pos, spiral_hit_radius, Color(SPIRAL_COLOR.r, SPIRAL_COLOR.g, SPIRAL_COLOR.b, trail_alpha))
		# Main projectile
		draw_circle(proj_pos, spiral_hit_radius + 4.0, Color(SPIRAL_GLOW.r, SPIRAL_GLOW.g, SPIRAL_GLOW.b, SPIRAL_GLOW.a * fade_alpha))
		draw_circle(proj_pos, spiral_hit_radius, Color(SPIRAL_COLOR.r, SPIRAL_COLOR.g, SPIRAL_COLOR.b, SPIRAL_COLOR.a * fade_alpha))
		draw_circle(proj_pos, spiral_hit_radius * 0.42, Color(1.0, 1.0, 1.0, 0.92 * fade_alpha))

	# Spiral windup tell
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.SPIRAL and _spiral_windup_left > 0.0:
		var sw_t := 1.0 - (_spiral_windup_left / spiral_windup)
		for i in spiral_arm_count:
			var gather_angle := float(i) * (TAU / float(spiral_arm_count)) + t * 3.2
			var gather_r := body_draw_radius + 6.0 + sw_t * 24.0
			var tip := Vector2(cos(gather_angle), sin(gather_angle)) * gather_r
			draw_circle(tip, 4.0, Color(SPIRAL_COLOR.r, SPIRAL_COLOR.g, SPIRAL_COLOR.b, sw_t * 0.9))

	# Illusion decoys (identical to real body, but shatter when hit)
	if not _illusion_positions.is_empty():
		for i in _illusion_positions.size():
			var illusion_pos := _illusion_positions[i]
			var shatter_t := _illusion_shatter_times[i] if i < _illusion_shatter_times.size() else 0.0
			var lp := to_local(illusion_pos)
			if shatter_t > 0.0:
				# Shattering illusion: fragment into pieces flying outward
				var frag_count := 8
				for fi in range(frag_count):
					var fang := (TAU / float(frag_count)) * float(fi)
					var fspeed := 180.0 * (1.0 - shatter_t / 0.44)
					var fpos := lp + Vector2(cos(fang), sin(fang)) * fspeed * (0.44 - shatter_t)
					var alpha := shatter_t / 0.44
					draw_circle(fpos, 2.0, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, alpha))
			else:
				# Normal illusion body (identical to real body, no breathing)
				_draw_crystalline_body(lp, body_radius, BODY_COLOR, CORE_COLOR, 0.72)
				# Illusions keep a flatter pulse so the real ring breathing stands out.
				var illusion_pulse := 0.5 + 0.5 * sin(t * 2.4)
				var illusion_ring_radius := body_draw_radius + 10.0 + illusion_pulse * 1.8
				var illusion_ring_alpha := 0.34 + illusion_pulse * 0.12
				draw_arc(lp, illusion_ring_radius, 0.0, TAU, 36,
					Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, illusion_ring_alpha), 1.4)

	# Teleport windup glow
	if seamlock_state == ENEMY_STATE_ENUMS.SeamlockState.TELEPORT:
		var wt := 1.0 - (state_time_left / teleport_windup_time)
		draw_circle(Vector2.ZERO, body_draw_radius + 8.0 + wt * 20.0,
			Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, wt * 0.54))

	# Teleport arrival flash
	if _teleport_flash_left > 0.0:
		var ft := _teleport_flash_left / 0.40
		var burst_radius := body_draw_radius * (2.8 - ft * 1.8)
		var burst_color := Color(TELEPORT_BURST.r, TELEPORT_BURST.g, TELEPORT_BURST.b, ft * 0.68)
		draw_circle(Vector2.ZERO, burst_radius, burst_color)
		for illusion_pos in _illusion_positions:
			draw_circle(to_local(illusion_pos), burst_radius, burst_color)

	# Pulsing orbit ring — permanent identity mark
	draw_arc(Vector2.ZERO,
		real_ring_radius,
		0.0, TAU, 36,
		Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, real_ring_alpha),
		1.4)

	# Real body — angular/crystalline hexagon (distorted geometry theme)
	_draw_crystalline_body(Vector2.ZERO, body_radius, BODY_COLOR, CORE_COLOR, 0.72)

func _draw_crystalline_body(center: Vector2, radius: float, body_color: Color, core_color: Color, core_scale: float) -> void:
	# Multi-layer glow with depth
	draw_circle(center, radius + 10.0, Color(body_color.r * 0.4, body_color.g * 0.2, body_color.b * 0.5, 0.08))
	draw_circle(center, radius + 6.2, Color(body_color.r * 0.6, body_color.g * 0.3, body_color.b * 0.6, 0.18))
	
	# Main body: deterministic hexagon with subtle shading
	var facet_count := 6
	var facets: PackedVector2Array = PackedVector2Array()
	for i in range(facet_count):
		var angle := (TAU / float(facet_count)) * float(i)
		# Deterministic perturbation based on index (not random)
		var variation := sin(float(i) * 0.78) * 1.8
		var facet_radius := radius + variation
		facets.append(center + Vector2(cos(angle), sin(angle)) * facet_radius)
	draw_colored_polygon(facets, body_color)
	
	# Inner facet shading — darker triangles for depth
	var shade_dark := Color(body_color.r * 0.5, body_color.g * 0.3, body_color.b * 0.6, 0.22)
	for i in range(facet_count):
		var next_i := (i + 1) % facet_count
		var inner_t := 0.35
		var inner_v1 := center.lerp(facets[i], inner_t)
		var inner_v2 := center.lerp(facets[next_i], inner_t)
		draw_colored_polygon(PackedVector2Array([center, inner_v1, inner_v2]), shade_dark)
	
	# Facet outlines — crisp angular edges with gradient intensity
	for i in range(facet_count):
		var next_i := (i + 1) % facet_count
		var edge_alpha := 0.3 + sin(float(i) * 1.2) * 0.25
		draw_line(facets[i], facets[next_i], Color(0.08, 0.02, 0.18, edge_alpha), 1.6)
	
	# Core: bright inner geometric fragment with halo
	var core_glow_color := Color(core_color.r * 0.8, core_color.g, core_color.b * 0.9, 0.24)
	draw_circle(center, radius * core_scale * 1.2, core_glow_color)
	draw_circle(center, radius * core_scale, core_color)
	
	# Core highlight — sharp bright spot for polish
	var highlight_radius := radius * core_scale * 0.52
	var highlight_pos := center + Vector2(-highlight_radius * 0.4, -highlight_radius * 0.6)
	draw_circle(highlight_pos, highlight_radius * 0.4, Color(1.0, 1.0, 1.0, 0.5))
	
	# Angular spike accents — 3 sharp pieces radiating from core
	for spike_i in range(3):
		var spike_angle := (TAU / 3.0) * float(spike_i) + atan2(visual_facing_direction.y, visual_facing_direction.x)
		var spike_tip := center + Vector2(cos(spike_angle), sin(spike_angle)) * (radius * 1.2)
		var spike_base_l := center + Vector2(cos(spike_angle + 0.5), sin(spike_angle + 0.5)) * (radius * 0.65)
		var spike_base_r := center + Vector2(cos(spike_angle - 0.5), sin(spike_angle - 0.5)) * (radius * 0.65)
		draw_colored_polygon(
			PackedVector2Array([spike_tip, spike_base_l, spike_base_r]),
			Color(core_color.r * 0.9, core_color.g * 0.8, core_color.b, 0.85)
		)

func _draw_band_danger_zones(base_color: Color) -> void:
	var color := Color(base_color.r, base_color.g, base_color.b, clampf(base_color.a, 0.0, 1.0))
	_draw_filled_annulus(0.0, band_inner_danger_radius, color)
	_draw_filled_annulus(band_safe_1_outer_radius, band_mid_danger_outer_radius, color)

func _draw_band_zone_details(time_sec: float, intensity: float, tick_flash: float) -> void:
	var danger_edge := Color(1.0, 0.58, 0.26, clampf(0.22 + intensity * 0.56, 0.0, 1.0))
	var safe_edge := Color(0.52, 0.95, 0.92, clampf(0.14 + intensity * 0.42, 0.0, 1.0))
	var flash_alpha := clampf(tick_flash * 0.85, 0.0, 1.0)

	# Core boundary rings matching boss-style readability.
	draw_arc(Vector2.ZERO, band_inner_danger_radius, 0.0, TAU, 96, danger_edge, 3.0)
	draw_arc(Vector2.ZERO, band_safe_1_outer_radius, 0.0, TAU, 96, safe_edge, 2.2)
	draw_arc(Vector2.ZERO, band_mid_danger_outer_radius, 0.0, TAU, 96, danger_edge, 2.8)

	if flash_alpha > 0.0:
		var flash_color := Color(1.0, 0.96, 0.9, flash_alpha)
		draw_arc(Vector2.ZERO, band_inner_danger_radius, 0.0, TAU, 112, flash_color, 2.2 + flash_alpha * 2.6)
		draw_arc(Vector2.ZERO, band_mid_danger_outer_radius, 0.0, TAU, 112, flash_color, 2.0 + flash_alpha * 2.2)

	# Subtle rotating sweep accents to communicate attack state progression.
	var sweep_len := 0.44
	var sweep_a0 := time_sec * 0.92
	var sweep_a1 := sweep_a0 + sweep_len
	var sweep_color := Color(1.0, 0.82, 0.52, clampf(0.12 + intensity * 0.30, 0.0, 1.0))
	draw_arc(Vector2.ZERO, band_mid_danger_outer_radius, sweep_a0, sweep_a1, 28, sweep_color, 3.0)

func _draw_filled_annulus(inner_radius: float, outer_radius: float, fill_color: Color) -> void:
	if outer_radius <= inner_radius:
		return
	var segments := 96
	var outer_points := PackedVector2Array()
	var inner_points := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := t * TAU
		outer_points.append(Vector2(cos(angle), sin(angle)) * outer_radius)
		inner_points.append(Vector2(cos(angle), sin(angle)) * inner_radius)
	var poly := PackedVector2Array()
	for p in outer_points:
		poly.append(p)
	for i in range(segments, -1, -1):
		poly.append(inner_points[i])
	draw_colored_polygon(poly, fill_color)

func _draw_band_markers(radius: float, marker_color: Color, marker_count: int, marker_len: float, marker_thickness: float, spin_offset: float) -> void:
	if marker_count <= 0:
		return
	for i in range(marker_count):
		var angle := (TAU / float(marker_count)) * float(i) + spin_offset
		var dir := Vector2(cos(angle), sin(angle))
		var p0 := dir * radius
		var p1 := dir * (radius + marker_len)
		draw_line(p0, p1, marker_color, marker_thickness)

func _sync_health_bar_visibility() -> void:
	if health_bar == null:
		return
	health_bar.visible = seamlock_state != ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE
