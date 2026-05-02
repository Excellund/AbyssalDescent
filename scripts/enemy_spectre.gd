extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_STRIKE := 2
const STATE_RECOVER := 3

@export var move_speed: float = 84.0
@export var acceleration: float = 920.0
@export var deceleration: float = 1280.0
@export var preferred_range: float = 150.0
@export var range_tolerance: float = 42.0
@export var trigger_range: float = 228.0
@export var windup_time: float = 0.72
@export var prediction_time: float = 0.52
@export var prediction_speed_cap: float = 340.0
@export var post_blink_strike_delay: float = 0.5
@export var strike_range: float = 54.0
@export var strike_length: float = 78.0
@export var strike_half_width_near: float = 14.0
@export var strike_half_width_far: float = 26.0
@export var strike_damage: int = 24
@export var attack_cooldown: float = 1.6
@export var recover_time: float = 0.42
@export var arena_size: Vector2 = Vector2(940.0, 700.0)

var spectre_state: int = STATE_STALK
var state_time_left: float = 0.0
var attack_cooldown_left: float = 0.0
var _tracked_target_last_position: Vector2 = Vector2.ZERO
var _tracked_target_velocity: Vector2 = Vector2.ZERO
var _blink_target_global: Vector2 = Vector2.ZERO
var _strike_facing: Vector2 = Vector2.LEFT

func _ready() -> void:
	super()
	max_health = 78
	crowd_separation_radius = 68.0
	crowd_separation_strength = 104.0

func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	_update_target_tracking(delta)
	match spectre_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_STRIKE:
			_process_strike(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _update_target_tracking(delta: float) -> void:
	if not is_instance_valid(target) or delta <= 0.000001:
		_tracked_target_velocity = Vector2.ZERO
		return
	var current_target_position := target.global_position
	if _tracked_target_last_position == Vector2.ZERO:
		_tracked_target_last_position = current_target_position
		_tracked_target_velocity = Vector2.ZERO
		return
	var sampled_velocity := (current_target_position - _tracked_target_last_position) / delta
	var blend := clampf(delta * 9.0, 0.0, 1.0)
	_tracked_target_velocity = _tracked_target_velocity.lerp(sampled_velocity, blend)
	_tracked_target_last_position = current_target_position

func _process_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var desired_dir := to_target.normalized()
	var tangent := Vector2(-desired_dir.y, desired_dir.x)
	var tangent_bias := 1.0 if int(get_instance_id()) % 2 == 0 else -1.0
	var desired := Vector2.ZERO
	if dist < preferred_range - range_tolerance:
		desired = (-desired_dir + tangent * 0.42 * tangent_bias).normalized() * move_speed * 0.72 * slow_speed_mult
	elif dist > preferred_range + range_tolerance:
		desired = (desired_dir + tangent * 0.22 * tangent_bias).normalized() * move_speed * slow_speed_mult
	else:
		desired = tangent * move_speed * 0.82 * tangent_bias * slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()
	if attack_cooldown_left <= 0.0 and dist <= trigger_range:
		_enter_windup_state()

func _enter_windup_state() -> void:
	spectre_state = STATE_WINDUP
	state_time_left = windup_time
	velocity = Vector2.ZERO
	_update_blink_target()
	queue_redraw()

func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_update_blink_target()
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_execute_blink()

func _update_blink_target() -> void:
	if not is_instance_valid(target):
		_blink_target_global = global_position
		return
	var predicted_velocity := _tracked_target_velocity
	if prediction_speed_cap > 0.0 and predicted_velocity.length() > prediction_speed_cap:
		predicted_velocity = predicted_velocity.normalized() * prediction_speed_cap
	var predicted := target.global_position + predicted_velocity * prediction_time
	_blink_target_global = _clamp_to_arena(predicted)
	var to_blink := _blink_target_global - global_position
	if to_blink.length_squared() > 0.000001:
		visual_facing_direction = to_blink.normalized()

func _find_safe_blink_position(target_pos: Vector2) -> Vector2:
	if not _is_position_occupied(target_pos):
		return target_pos
	
	var search_radius := 48.0
	var max_attempts := 40
	var best_pos := target_pos
	var best_dist_to_occupied := 0.0
	
	# Randomized starting angle to break ties between simultaneous spectres
	var start_angle := float(randi() % 100) * 0.1
	
	for attempt in range(max_attempts):
		var angle := start_angle + (float(attempt) / max_attempts) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * search_radius
		var candidate := target_pos + offset
		candidate = _clamp_to_arena(candidate)
		
		if not _is_position_occupied(candidate):
			return candidate
		
		# Prefer positions further from occupied areas, with margin for safety
		var dist_to_occupied := _get_min_occupied_distance(candidate)
		if dist_to_occupied > best_dist_to_occupied + 1.0:
			best_dist_to_occupied = dist_to_occupied
			best_pos = candidate
	
	# As fallback, also try concentric rings at larger radii
	for ring in range(2, 4):
		var ring_radius := search_radius * float(ring) * 0.6
		for attempt in range(20):
			var angle := start_angle + (float(attempt) / 20.0) * TAU
			var offset := Vector2(cos(angle), sin(angle)) * ring_radius
			var candidate := target_pos + offset
			candidate = _clamp_to_arena(candidate)
			
			if not _is_position_occupied(candidate):
				return candidate
			
			var dist_to_occupied := _get_min_occupied_distance(candidate)
			if dist_to_occupied > best_dist_to_occupied + 1.0:
				best_dist_to_occupied = dist_to_occupied
				best_pos = candidate
	
	# If still no safe spot, add small random offset to avoid stacking
	if best_pos == target_pos:
		var random_offset := Vector2(randf() - 0.5, randf() - 0.5).normalized() * 20.0
		best_pos = _clamp_to_arena(target_pos + random_offset)
	
	return best_pos

func _is_position_occupied(check_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = 18.0
	query.transform.origin = check_pos
	var result := space_state.intersect_shape(query)
	for res in result:
		var collider = res.collider
		if collider == self:
			continue
		if collider == target:
			return true
		if collider.is_in_group("enemy") and collider != self:
			return true
	return false

func _get_min_occupied_distance(check_pos: Vector2) -> float:
	var min_dist := 999999.0
	if is_instance_valid(target):
		min_dist = minf(min_dist, check_pos.distance_to(target.global_position))
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = 80.0
	query.transform.origin = check_pos
	var result := space_state.intersect_shape(query)
	for res in result:
		var collider = res.collider
		if collider == self or collider == target:
			continue
		if collider.is_in_group("enemy") and collider != self:
			min_dist = minf(min_dist, check_pos.distance_to(collider.global_position))
	return min_dist

func _execute_blink() -> void:
	var safe_blink_pos := _find_safe_blink_position(_blink_target_global)
	global_position = safe_blink_pos
	velocity = Vector2.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			_strike_facing = to_target.normalized()
		else:
			_strike_facing = visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	else:
		_strike_facing = visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	visual_facing_direction = _strike_facing
	spectre_state = STATE_STRIKE
	state_time_left = post_blink_strike_delay
	queue_redraw()

func _process_strike(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	visual_facing_direction = _strike_facing
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_perform_strike()

func _perform_strike() -> void:
	attack_anim_time_left = attack_anim_duration
	if is_instance_valid(target) and DAMAGEABLE.can_take_damage(target):
		if _is_point_in_strike_lance(target.global_position):
			DAMAGEABLE.apply_damage(target, strike_damage, {"source": "enemy_ability", "ability": "spectre_blink_strike"})
	attack_cooldown_left = attack_cooldown
	spectre_state = STATE_RECOVER
	state_time_left = recover_time
	queue_redraw()

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		spectre_state = STATE_STALK

func _is_point_in_strike_lance(point_global: Vector2) -> bool:
	var facing := _strike_facing if _strike_facing.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var local := point_global - global_position
	var forward := local.dot(facing)
	if forward < 0.0 or forward > strike_length:
		return false
	var width_t := 0.0 if strike_length <= 0.000001 else clampf(forward / strike_length, 0.0, 1.0)
	var half_width := lerpf(strike_half_width_near, strike_half_width_far, width_t)
	return absf(local.dot(side)) <= half_width

func _clamp_to_arena(position: Vector2) -> Vector2:
	if arena_size == Vector2.ZERO:
		return position
	var half := arena_size * 0.5 - Vector2.ONE * 22.0
	return Vector2(
		clampf(position.x, -half.x, half.x),
		clampf(position.y, -half.y, half.y)
	)

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 14.0 + attack_pulse + speed_t * 0.8
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)

	# Persistent spectral aura — always visible to distinguish from Chasers and other fast enemies
	var aura_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.010)
	var aura_alpha := 0.14 + aura_pulse * 0.08
	draw_circle(Vector2.ZERO, body_radius + 11.0, Color(0.34, 0.92, 0.88, aura_alpha))

	# Base spectral body — cyan-white reads as "future-touched" essence
	var body_color := Color(0.16, 0.72, 0.8, 0.94)
	var core_color := Color(0.72, 1.0, 0.98, 0.92)
	
	if spectre_state == STATE_WINDUP:
		# Brightening during prediction — preparing to collapse position
		body_color = Color(0.28, 0.92, 0.92, 0.98)
		core_color = Color(0.9, 1.0, 1.0, 0.96)
	elif spectre_state == STATE_STRIKE:
		# Maximum brightness and saturation during strike — attack is crystallizing
		body_color = Color(0.42, 0.98, 0.94, 0.98)
		core_color = Color(0.98, 1.0, 1.0, 0.98)
	
	# Temporal echo layers — multiple overlapping phase images showing prediction at work
	var echo_offset := 6.0 + attack_pulse * 2.0
	for echo_i in range(2, 0, -1):
		var echo_alpha := (0.12 - float(echo_i - 1) * 0.08) * (1.0 - speed_t)
		var echo_pos := -facing * echo_offset * float(echo_i)
		draw_circle(echo_pos, body_radius + 2.0, Color(body_color.r, body_color.g, body_color.b, echo_alpha * 0.5))
		draw_circle(echo_pos, body_radius * 0.74, Color(core_color.r, core_color.g, core_color.b, echo_alpha * 0.4))
	
	# Primary crystalline body — angular edges instead of smooth circles
	var vertices := PackedVector2Array()
	var num_points := 12
	for i in range(num_points):
		var angle := float(i) / float(num_points) * TAU
		var jitter_angle := sin(float(i) * 0.8) * 0.12
		var radius_var := body_radius + (1.0 if (i % 2) == 0 else -2.0)
		var vertex := Vector2(cos(angle + jitter_angle), sin(angle + jitter_angle)) * radius_var
		vertices.append(vertex)
	draw_colored_polygon(vertices, Color(body_color.r * 0.8, body_color.g, body_color.b, body_color.a * 0.7))
	draw_polyline(vertices, body_color, 2.0, true)
	
	# Jagged rift segments across body — shows temporal instability
	for rift_i in range(4):
		var rift_angle := float(rift_i) * TAU / 4.0 + float(Time.get_ticks_msec()) * 0.0008
		var rift_dir := Vector2(cos(rift_angle), sin(rift_angle))
		var rift_inner := rift_dir * (body_radius * 0.4)
		var rift_outer := rift_dir * (body_radius + 4.0)
		var rift_left := rift_inner + Vector2(-rift_dir.y, rift_dir.x) * 1.8
		var rift_right := rift_inner - Vector2(-rift_dir.y, rift_dir.x) * 1.8
		var rift_color := Color(core_color.r, core_color.g, core_color.b, core_color.a * 0.6)
		draw_line(rift_left, rift_outer, rift_color, 2.4)
		draw_line(rift_right, rift_outer, rift_color, 2.4)
	
	# Pulsing core with prediction intensity
	var prediction_intensity := 1.0 - (state_time_left / maxf(0.001, windup_time)) if spectre_state == STATE_WINDUP else 0.0
	draw_circle(Vector2.ZERO, body_radius * 0.52, Color(core_color.r, core_color.g, core_color.b, core_color.a * (0.8 + prediction_intensity * 0.2)))
	draw_circle(Vector2.ZERO, body_radius * 0.26, Color(1.0, 1.0, 1.0, 0.3 + prediction_intensity * 0.3))

	# Directional crystalline edges — threat pointer that shows strike direction
	draw_line(facing * (body_radius + 1.5), facing * (body_radius + 9.0), Color(0.82, 1.0, 1.0, 0.88), 2.2)
	draw_line(side * 4.5, side * 8.5 + facing * 4.0, Color(0.42, 0.98, 0.96, 0.74), 1.6)
	draw_line(-side * 4.5, -side * 8.5 + facing * 4.0, Color(0.42, 0.98, 0.96, 0.74), 1.6)

	# Distinctive phase tear rifts on sides — signals "position-collapsing" specialist identity
	var rift_alpha := 0.52
	for rift_i in range(3):
		var rift_offset := 0.28 + float(rift_i) * 0.32
		var rift_pos := side * (body_radius * rift_offset)
		var rift_size := 2.4 - float(rift_i) * 0.6
		draw_circle(rift_pos, rift_size, Color(0.54, 1.0, 0.94, rift_alpha))
		draw_circle(-rift_pos, rift_size, Color(0.54, 1.0, 0.94, rift_alpha))

	# Predictive targeting glow during windup — intensifies as attack builds
	if spectre_state == STATE_WINDUP:
		var target_lock_alpha := 0.1 + (1.0 - (state_time_left / maxf(0.001, windup_time))) * 0.22
		draw_circle(Vector2.ZERO, body_radius + 8.0, Color(0.54, 0.96, 0.92, target_lock_alpha))
		
		# Concentric prediction rings — shows prediction is active
		var ring_count := 2
		for ring_i in range(ring_count):
			var ring_scale := 1.0 + float(ring_i) * 0.42
			var ring_alpha := (0.16 - float(ring_i) * 0.08) * (aura_pulse + 0.5)
			draw_arc(Vector2.ZERO, (body_radius + 10.0) * ring_scale, 0.0, TAU, 28, Color(0.34, 0.92, 0.88, ring_alpha), 1.8)
	
	# Strike state — attack ready indicator with intensifying visual
	if spectre_state == STATE_STRIKE:
		var strike_progress := 1.0 - clampf(state_time_left / post_blink_strike_delay, 0.0, 1.0)
		var pulse_freq := 0.014 + strike_progress * 0.006
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * pulse_freq)
		
		# Strike impact building aura
		var impact_alpha := 0.08 + strike_progress * 0.14
		draw_circle(Vector2.ZERO, body_radius + 6.0, Color(0.54, 1.0, 0.94, impact_alpha))
		
		# Lance strike indicator 
		var lance_facing := _strike_facing if _strike_facing.length_squared() > 0.000001 else facing
		var lance_side := Vector2(-lance_facing.y, lance_facing.x)
		var tip := lance_facing * strike_length
		var near_left := lance_side * strike_half_width_near
		var near_right := -lance_side * strike_half_width_near
		var far_left := tip + lance_side * strike_half_width_far
		var far_right := tip - lance_side * strike_half_width_far
		var rift_fill := PackedVector2Array([near_left, far_left, far_right, near_right])
		var fill_alpha := 0.4 + strike_progress * 0.24
		draw_colored_polygon(rift_fill, Color(0.24, 0.98, 0.92, fill_alpha))
		var outline_width := 2.6 + strike_progress * 1.0
		draw_polyline(PackedVector2Array([near_left, far_left, tip, far_right, near_right]), Color(0.9, 1.0, 0.98, 0.94), outline_width, true)
		draw_line(near_left.lerp(far_left, 0.45), near_left.lerp(far_left, 0.8), Color(1.0, 1.0, 1.0, 0.82 + strike_progress * 0.18), 2.2)
		draw_line(near_right.lerp(far_right, 0.45), near_right.lerp(far_right, 0.8), Color(1.0, 1.0, 1.0, 0.82 + strike_progress * 0.18), 2.2)
		draw_line(Vector2.ZERO, tip * 0.88, Color(1.0, 1.0, 1.0, 0.88 + strike_progress * 0.12), 2.4)
		var tip_arc_radius := 7.0 + strike_progress * 3.0
		draw_arc(tip, tip_arc_radius, 0.0, TAU, 24, Color(0.54, 1.0, 0.94, 0.84 + strike_progress * 0.16), 2.2)
	
	# Prediction windup telegraph to target
	if spectre_state == STATE_WINDUP:
		var telegraph_pos := _blink_target_global - global_position
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018)
		var windup_progress := 1.0 - clampf(state_time_left / windup_time, 0.0, 1.0)
		draw_line(Vector2.ZERO, telegraph_pos, Color(0.44, 1.0, 0.96, 0.52 + windup_progress * 0.3), 2.4 + pulse * 0.8)
		draw_arc(telegraph_pos, strike_range - 8.0 + pulse * 6.0 + windup_progress * 3.0, 0.0, TAU, 32, Color(0.54, 1.0, 0.94, 0.92 + pulse * 0.08), 2.8 + pulse * 0.4)
		draw_circle(telegraph_pos, 10.0 + pulse * 6.0 + windup_progress * 2.0, Color(0.2, 0.92, 0.86, 0.22 + pulse * 0.12))
		for i in range(3):
			var ring_scale := 1.0 + float(i) * 0.35
			var ring_alpha := (0.18 - float(i) * 0.06) * (pulse + 0.5)
			draw_arc(telegraph_pos, (strike_range - 8.0) * ring_scale, 0.0, TAU, 24, Color(0.54, 1.0, 0.94, ring_alpha), 1.6)
	
	_draw_mutator_overlay(body_radius)
	_draw_slow_indicator(body_radius)
