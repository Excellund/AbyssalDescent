extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_ATTACK := 2
const STATE_RECOVER := 3

const ATTACK_PRISM := 0
const ATTACK_GRAVITY := 1
const ATTACK_ECHO_DASH := 2
const ATTACK_ORBITAL_LANCE := 3

@export var boss_max_health: int = 980
@export var move_speed: float = 156.0
@export var acceleration: float = 980.0
@export var deceleration: float = 1380.0
@export var preferred_distance: float = 260.0
@export var action_cooldown: float = 0.72

@export var prism_windup: float = 0.95
@export var prism_radius: float = 300.0
@export var prism_spoke_count: int = 5
@export var prism_spoke_half_angle_degrees: float = 13.0
@export var prism_damage: int = 26

@export var gravity_windup: float = 1.1
@export var gravity_radius: float = 240.0
@export var gravity_damage: int = 36

@export var echo_dash_windup: float = 0.58
@export var echo_dash_speed: float = 680.0
@export var echo_dash_duration: float = 0.24
@export var echo_dash_count: int = 3
@export var echo_dash_width: float = 44.0
@export var echo_dash_damage: int = 20
@export var echo_dash_retarget_pause: float = 0.14
@export var echo_dash_max_turn_degrees: float = 40.0

@export var orb_count: int = 6
@export var orb_ring_radius: float = 54.0
@export var orb_rotation_speed: float = 0.95
@export var orbital_lance_windup: float = 0.88
@export var orbital_lance_length: float = 320.0
@export var orbital_lance_width: float = 24.0
@export var orbital_lance_damage: int = 24

@export var recover_time: float = 0.48
@export var arena_size: Vector2 = Vector2(1360.0, 960.0)

var boss_state: int = STATE_STALK
var state_time_left: float = 0.0
var cooldown_left: float = 0.5
var active_attack: int = ATTACK_PRISM

var locked_direction: Vector2 = Vector2.RIGHT
var telegraph_alpha: float = 0.0
var _prism_base_angle: float = 0.0
var _echo_dash_hits: Dictionary = {}
var _echo_dash_remaining: int = 0
var _echo_dash_warning_line: PackedVector2Array = PackedVector2Array()
var _echo_dash_retargeting: bool = false
var _echo_dash_retarget_time_left: float = 0.0
var _orbital_lance_indices: Array[int] = []
var _orbital_lance_positions: PackedVector2Array = PackedVector2Array()
var attack_afterglow_time_left: float = 0.0
var attack_afterglow_duration: float = 0.56
var impact_burst_time_left: float = 0.0
var impact_burst_duration: float = 0.2
var last_attack_for_fx: int = ATTACK_PRISM

func _ready() -> void:
	max_health = boss_max_health
	super._ready()
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 38.0
				break
	if health_bar != null:
		health_bar.custom_minimum_size = Vector2(148.0, 12.0)
		health_bar.position = Vector2(-74.0, -82.0)

func _process_behavior(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)

	match boss_state:
		STATE_STALK:
			_process_stalk_state(delta)
		STATE_WINDUP:
			_process_windup_state(delta)
		STATE_ATTACK:
			_process_attack_state(delta)
		STATE_RECOVER:
			_process_recover_state(delta)

	attack_afterglow_time_left = maxf(0.0, attack_afterglow_time_left - delta)
	impact_burst_time_left = maxf(0.0, impact_burst_time_left - delta)

	queue_redraw()

func _process_stalk_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
		visual_facing_direction = locked_direction

	var orbit_dir := Vector2(-locked_direction.y, locked_direction.x)
	var desired := orbit_dir * move_speed * 0.62
	if distance > preferred_distance + 26.0:
		desired += locked_direction * move_speed
	elif distance < preferred_distance - 44.0:
		desired -= locked_direction * move_speed * 0.72
	desired *= slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

	if cooldown_left <= 0.0:
		_start_next_attack(distance)

func _start_next_attack(distance_to_target: float) -> void:
	var enrage_t := _get_enrage_ratio()
	if distance_to_target > 310.0:
		active_attack = ATTACK_ECHO_DASH
	elif distance_to_target < 150.0:
		if _orbital_attack_unlocked() and randf() < 0.24:
			active_attack = ATTACK_ORBITAL_LANCE
		else:
			active_attack = ATTACK_GRAVITY if randf() < 0.72 else ATTACK_PRISM
	else:
		var roll := randf()
		if _orbital_attack_unlocked() and roll < 0.22:
			active_attack = ATTACK_ORBITAL_LANCE
		elif roll < 0.36:
			active_attack = ATTACK_PRISM
		elif roll < 0.68:
			active_attack = ATTACK_GRAVITY
		else:
			active_attack = ATTACK_ECHO_DASH
	if enrage_t > 0.65 and randf() < 0.28:
		active_attack = ATTACK_ECHO_DASH
	if active_attack == ATTACK_PRISM:
		_prism_base_angle = locked_direction.angle() + randf_range(-0.22, 0.22)
	elif active_attack == ATTACK_ORBITAL_LANCE:
		_capture_orbital_lance_pattern()

	boss_state = STATE_WINDUP
	state_time_left = _get_windup_time(active_attack)
	telegraph_alpha = 0.0
	_echo_dash_hits.clear()
	_echo_dash_remaining = 0
	_echo_dash_warning_line = PackedVector2Array()
	_echo_dash_retargeting = false
	_echo_dash_retarget_time_left = 0.0
	velocity = Vector2.ZERO

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	var windup := _get_windup_time(active_attack)
	telegraph_alpha = 1.0 - (state_time_left / maxf(0.001, windup))

	if active_attack == ATTACK_ECHO_DASH and is_instance_valid(target):
		var dash_dir := (target.global_position - global_position).normalized()
		_echo_dash_warning_line = PackedVector2Array([Vector2.ZERO, dash_dir * 320.0])

	if state_time_left <= 0.0:
		_enter_attack_state()

func _enter_attack_state() -> void:
	boss_state = STATE_ATTACK
	attack_anim_time_left = attack_anim_duration
	last_attack_for_fx = active_attack
	attack_afterglow_time_left = attack_afterglow_duration
	impact_burst_time_left = impact_burst_duration
	match active_attack:
		ATTACK_PRISM:
			state_time_left = 0.06
			velocity = Vector2.ZERO
			_apply_prism_burst()
		ATTACK_GRAVITY:
			state_time_left = 0.06
			velocity = Vector2.ZERO
			_apply_gravity_burst()
		ATTACK_ECHO_DASH:
			_echo_dash_remaining = echo_dash_count
			_begin_echo_dash_leg()
		ATTACK_ORBITAL_LANCE:
			state_time_left = 0.08
			velocity = Vector2.ZERO
			_apply_orbital_lance_hits()

func _process_attack_state(delta: float) -> void:
	if active_attack == ATTACK_ECHO_DASH:
		if _echo_dash_retargeting:
			velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
			move_and_slide()
			_echo_dash_retarget_time_left = maxf(0.0, _echo_dash_retarget_time_left - delta)
			var retarget_total := maxf(0.001, echo_dash_retarget_pause)
			telegraph_alpha = 1.0 - (_echo_dash_retarget_time_left / retarget_total)
			_echo_dash_warning_line = PackedVector2Array([Vector2.ZERO, locked_direction * 320.0])
			if _echo_dash_retarget_time_left <= 0.0:
				_begin_echo_dash_leg(false)
			return

		telegraph_alpha = 0.0
		velocity = locked_direction * echo_dash_speed * lerpf(1.0, 1.16, _get_enrage_ratio())
		move_and_slide()
		_apply_echo_dash_hit()
		state_time_left = maxf(0.0, state_time_left - delta)
		if state_time_left <= 0.0:
			_echo_dash_remaining -= 1
			if _echo_dash_remaining > 0:
				_start_echo_dash_retarget_pause()
			else:
				_echo_dash_retargeting = false
				_echo_dash_retarget_time_left = 0.0
				_echo_dash_warning_line = PackedVector2Array()
				boss_state = STATE_RECOVER
				state_time_left = recover_time * 0.8
		return

	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_RECOVER
		state_time_left = recover_time

func _begin_echo_dash_leg(should_retarget: bool = true) -> void:
	if not is_instance_valid(target):
		_echo_dash_remaining = 0
		_echo_dash_retargeting = false
		_echo_dash_retarget_time_left = 0.0
		return
	if should_retarget:
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			locked_direction = to_target.normalized()
			visual_facing_direction = locked_direction
	_echo_dash_retargeting = false
	_echo_dash_retarget_time_left = 0.0
	_echo_dash_warning_line = PackedVector2Array()
	telegraph_alpha = 0.0
	state_time_left = echo_dash_duration

func _start_echo_dash_retarget_pause() -> void:
	if not is_instance_valid(target):
		_echo_dash_remaining = 0
		_echo_dash_retargeting = false
		_echo_dash_retarget_time_left = 0.0
		return
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		var desired_dir := to_target.normalized()
		var max_turn_radians := deg_to_rad(echo_dash_max_turn_degrees)
		locked_direction = _clamp_turn_toward(locked_direction, desired_dir, max_turn_radians)
		visual_facing_direction = locked_direction
	_echo_dash_retargeting = true
	_echo_dash_retarget_time_left = maxf(0.001, echo_dash_retarget_pause)
	telegraph_alpha = 0.0
	_echo_dash_warning_line = PackedVector2Array([Vector2.ZERO, locked_direction * 320.0])

func _clamp_turn_toward(current_dir: Vector2, desired_dir: Vector2, max_turn_radians: float) -> Vector2:
	if desired_dir.length_squared() <= 0.000001:
		return current_dir.normalized() if current_dir.length_squared() > 0.000001 else Vector2.RIGHT
	if current_dir.length_squared() <= 0.000001:
		return desired_dir.normalized()
	var current_angle := current_dir.angle()
	var desired_angle := desired_dir.angle()
	var delta := wrapf(desired_angle - current_angle, -PI, PI)
	var clamped_delta := clampf(delta, -max_turn_radians, max_turn_radians)
	return Vector2.RIGHT.rotated(current_angle + clamped_delta).normalized()

func _process_recover_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_STALK
		cooldown_left = action_cooldown * lerpf(1.0, 0.7, _get_enrage_ratio())

func _apply_prism_burst() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	var to_target := target.global_position - global_position
	if to_target.length() > prism_radius:
		return
	var target_angle := to_target.angle()
	var half_arc := deg_to_rad(prism_spoke_half_angle_degrees)
	for i in range(prism_spoke_count):
		var spoke_angle := _prism_base_angle + TAU * float(i) / float(prism_spoke_count)
		if absf(wrapf(target_angle - spoke_angle, -PI, PI)) <= half_arc:
			DAMAGEABLE.apply_damage(target, prism_damage)
			return

func _apply_gravity_burst() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	if global_position.distance_to(target.global_position) <= gravity_radius:
		DAMAGEABLE.apply_damage(target, gravity_damage)
		if target is CharacterBody2D:
			var body := target as CharacterBody2D
			var pull_dir := (global_position - body.global_position)
			if pull_dir.length_squared() > 0.000001:
				body.velocity += pull_dir.normalized() * 120.0

func _apply_echo_dash_hit() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	var target_id := target.get_instance_id()
	if _echo_dash_hits.has(target_id):
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			DAMAGEABLE.apply_damage(target, echo_dash_damage)
			_echo_dash_hits[target_id] = true
			return
	var seg_start := global_position - locked_direction * 40.0
	var seg_end := global_position + locked_direction * 40.0
	if _distance_point_to_segment(target.global_position, seg_start, seg_end) <= echo_dash_width:
		DAMAGEABLE.apply_damage(target, echo_dash_damage)
		_echo_dash_hits[target_id] = true

func _apply_orbital_lance_hits() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	if _orbital_lance_positions.is_empty():
		return
	for orb_pos in _orbital_lance_positions:
		var outward := orb_pos.normalized()
		if outward.length_squared() <= 0.000001:
			continue
		var beam_end := orb_pos + outward * orbital_lance_length
		if _distance_point_to_segment(target.global_position - global_position, orb_pos, beam_end) <= orbital_lance_width:
			DAMAGEABLE.apply_damage(target, orbital_lance_damage)
			return

func _distance_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_to(closest)

func _orbital_attack_unlocked() -> bool:
	return _get_enrage_ratio() >= 0.3

func _capture_orbital_lance_pattern() -> void:
	_orbital_lance_indices.clear()
	_orbital_lance_positions = PackedVector2Array()
	var positions := _get_orb_positions(float(Time.get_ticks_msec()) * 0.001)
	if positions.is_empty():
		return
	var start_index := randi() % 2
	for step in range(3):
		var orb_index := (start_index + step * 2) % positions.size()
		_orbital_lance_indices.append(orb_index)
		_orbital_lance_positions.append(positions[orb_index])

func _get_orb_positions(time_seconds: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(1, orb_count)
	for i in range(count):
		var angle := time_seconds * orb_rotation_speed + TAU * float(i) / float(count)
		var radius := orb_ring_radius + 5.0 * sin(time_seconds * 2.4 + float(i) * 0.9)
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	return points

func _get_windup_time(attack_id: int) -> float:
	var enrage_t := _get_enrage_ratio()
	match attack_id:
		ATTACK_PRISM:
			return prism_windup * lerpf(1.0, 0.82, enrage_t)
		ATTACK_GRAVITY:
			return gravity_windup * lerpf(1.0, 0.86, enrage_t)
		ATTACK_ECHO_DASH:
			return echo_dash_windup * lerpf(1.0, 0.8, enrage_t)
		ATTACK_ORBITAL_LANCE:
			return orbital_lance_windup * lerpf(1.0, 0.84, enrage_t)
		_:
			return 0.8

func _get_enrage_ratio() -> float:
	var health_ratio := float(_get_current_health()) / maxf(1.0, float(max_health))
	if health_ratio >= 0.72:
		return 0.0
	if health_ratio <= 0.2:
		return 1.0
	return clampf((0.72 - health_ratio) / 0.52, 0.0, 1.0)

func _draw() -> void:
	var pulse := _get_attack_pulse()
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var body_radius := 36.0 + pulse * 0.78
	var enrage_t := _get_enrage_ratio()
	var threat_t := telegraph_alpha if boss_state == STATE_WINDUP or (boss_state == STATE_ATTACK and active_attack == ATTACK_ECHO_DASH and _echo_dash_retargeting) else 0.0

	var body_color := Color(0.18, 0.44, 0.72, 0.97)
	var core_color := Color(0.66, 0.88, 1.0, 0.86)
	if boss_state == STATE_WINDUP:
		body_color = Color(0.78, 0.28, 0.16, 0.97)
		core_color = Color(1.0, 0.72, 0.42, 0.92)
	elif boss_state == STATE_ATTACK:
		body_color = Color(0.92, 0.34, 0.14, 0.98)
		core_color = Color(1.0, 0.82, 0.52, 0.96)

	body_color = body_color.lerp(Color(0.98, 0.36, 0.18, 1.0), enrage_t * 0.28)
	core_color = core_color.lerp(Color(1.0, 0.88, 0.56, 1.0), enrage_t * 0.35)

	_draw_enrage_scaling_indicator(body_radius, facing, enrage_t)

	if boss_state == STATE_WINDUP:
		var halo_radius := body_radius + 17.0 + threat_t * 10.0
		draw_circle(Vector2.ZERO, halo_radius, Color(1.0, 0.26, 0.14, 0.06 + threat_t * 0.12))
		draw_arc(Vector2.ZERO, halo_radius + 3.0, 0.0, TAU, 52, Color(1.0, 0.82, 0.46, 0.24 + threat_t * 0.3), 2.8)

	draw_circle(Vector2.ZERO, body_radius + 11.0, Color(0.08, 0.24, 0.4, 0.2 + enrage_t * 0.13))
	_draw_common_body(body_radius, body_color, core_color, facing)
	_draw_slow_indicator(body_radius)
	_draw_attack_afterglow(facing)
	_draw_attack_impact_burst(facing)

	_draw_orbital_satellites()

	if boss_state == STATE_WINDUP:
		_draw_attack_telegraph()
		_draw_role_state_icon(facing, body_radius)
	elif boss_state == STATE_ATTACK and active_attack == ATTACK_ECHO_DASH and _echo_dash_retargeting:
		_draw_attack_telegraph()
		_draw_role_state_icon(facing, body_radius)

	if boss_state == STATE_ATTACK and active_attack == ATTACK_ECHO_DASH:
		var tail_end := -locked_direction * 110.0
		draw_line(Vector2.ZERO, tail_end, Color(1.0, 0.62, 0.26, 0.44), 8.0)
		draw_line(Vector2.ZERO, tail_end * 0.8, Color(1.0, 0.9, 0.62, 0.62), 2.6)

func _draw_role_state_icon(facing: Vector2, body_radius: float) -> void:
	var icon_alpha := 0.35 + telegraph_alpha * 0.58
	match active_attack:
		ATTACK_PRISM:
			draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 40, Color(1.0, 0.78, 0.4, icon_alpha), 2.6)
		ATTACK_GRAVITY:
			draw_circle(Vector2.ZERO, body_radius + 11.0, Color(1.0, 0.48, 0.24, icon_alpha * 0.22))
			draw_arc(Vector2.ZERO, body_radius + 11.0, 0.0, TAU, 36, Color(1.0, 0.76, 0.42, icon_alpha), 2.2)
		ATTACK_ECHO_DASH:
			var side := Vector2(-facing.y, facing.x)
			var tip := facing * (body_radius + 14.0)
			var base := facing * (body_radius + 2.0)
			draw_colored_polygon(PackedVector2Array([tip, base + side * 5.8, base - side * 5.8]), Color(1.0, 0.84, 0.48, icon_alpha))
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				draw_circle(orb_pos, 4.8, Color(1.0, 0.86, 0.54, icon_alpha * 0.92))

func _draw_attack_telegraph() -> void:
	var alpha := 0.22 + telegraph_alpha * 0.7
	match active_attack:
		ATTACK_PRISM:
			var half_arc := deg_to_rad(prism_spoke_half_angle_degrees)
			for i in range(prism_spoke_count):
				var spoke_angle := _prism_base_angle + TAU * float(i) / float(prism_spoke_count)
				# Draw exact damaging lane as a sector wedge so visual and hitbox align.
				var sector_points := PackedVector2Array([Vector2.ZERO])
				var segments := 16
				for step in range(segments + 1):
					var t := float(step) / float(segments)
					var angle := lerpf(spoke_angle - half_arc, spoke_angle + half_arc, t)
					sector_points.append(Vector2.RIGHT.rotated(angle) * prism_radius)
				draw_colored_polygon(sector_points, Color(1.0, 0.42, 0.2, alpha * 0.26))
				draw_arc(Vector2.ZERO, prism_radius, spoke_angle - half_arc, spoke_angle + half_arc, 16, Color(1.0, 0.9, 0.6, alpha * 0.92), 2.4)
				draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(spoke_angle - half_arc) * prism_radius, Color(1.0, 0.72, 0.4, alpha * 0.68), 1.8)
				draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(spoke_angle + half_arc) * prism_radius, Color(1.0, 0.72, 0.4, alpha * 0.68), 1.8)
			draw_arc(Vector2.ZERO, prism_radius, 0.0, TAU, 64, Color(1.0, 0.54, 0.3, alpha * 0.62), 2.0)
		ATTACK_GRAVITY:
			var pulse := 0.5 + 0.5 * sin(telegraph_alpha * PI * 2.0)
			draw_circle(Vector2.ZERO, gravity_radius, Color(1.0, 0.2, 0.16, alpha * 0.22 * (0.75 + pulse * 0.25)))
			draw_arc(Vector2.ZERO, gravity_radius, 0.0, TAU, 64, Color(1.0, 0.44, 0.3, alpha), 3.4)
			draw_arc(Vector2.ZERO, gravity_radius * 0.64, 0.0, TAU, 48, Color(1.0, 0.78, 0.44, alpha * 0.62), 2.0)
			for i in range(6):
				var a := TAU * float(i) / 6.0 + float(Time.get_ticks_msec()) * 0.0015
				var p0 := Vector2.RIGHT.rotated(a) * (gravity_radius + 24.0)
				var p1 := Vector2.RIGHT.rotated(a) * (gravity_radius + 6.0)
				draw_line(p0, p1, Color(1.0, 0.82, 0.54, alpha * 0.75), 2.1)
		ATTACK_ECHO_DASH:
			if _echo_dash_warning_line.size() >= 2:
				var from := _echo_dash_warning_line[0]
				var to := _echo_dash_warning_line[1]
				var dir := (to - from).normalized()
				var side := Vector2(-dir.y, dir.x)
				var lane_half := echo_dash_width * 1.3
				var lane := PackedVector2Array([
					from + side * lane_half,
					to + side * lane_half,
					to - side * lane_half,
					from - side * lane_half
				])
				draw_colored_polygon(lane, Color(1.0, 0.52, 0.24, alpha * 0.24))
				draw_line(from + side * lane_half, to + side * lane_half, Color(1.0, 0.7, 0.38, alpha), 2.8)
				draw_line(from - side * lane_half, to - side * lane_half, Color(1.0, 0.7, 0.38, alpha), 2.8)
				draw_line(from, to, Color(1.0, 0.94, 0.66, alpha * 0.88), 2.0)
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				var outward := orb_pos.normalized()
				if outward.length_squared() <= 0.000001:
					continue
				var beam_end := orb_pos + outward * orbital_lance_length
				var side := Vector2(-outward.y, outward.x)
				var lane_half := orbital_lance_width
				var lane := PackedVector2Array([
					orb_pos + side * lane_half,
					beam_end + side * lane_half,
					beam_end - side * lane_half,
					orb_pos - side * lane_half
				])
				draw_colored_polygon(lane, Color(1.0, 0.46, 0.22, alpha * 0.22))
				draw_circle(orb_pos, 8.0 + telegraph_alpha * 4.0, Color(1.0, 0.72, 0.42, alpha * 0.34))
				draw_line(orb_pos + side * lane_half, beam_end + side * lane_half, Color(1.0, 0.82, 0.52, alpha), 2.2)
				draw_line(orb_pos - side * lane_half, beam_end - side * lane_half, Color(1.0, 0.82, 0.52, alpha), 2.2)
				draw_line(orb_pos, beam_end, Color(1.0, 0.96, 0.72, alpha * 0.88), 1.8)

func _draw_attack_afterglow(facing: Vector2) -> void:
	if attack_afterglow_time_left <= 0.0:
		return
	var t := clampf(attack_afterglow_time_left / maxf(attack_afterglow_duration, 0.001), 0.0, 1.0)
	var fade := t * t
	match last_attack_for_fx:
		ATTACK_PRISM:
			var ring_r := prism_radius * (1.0 + (1.0 - t) * 0.2)
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 56, Color(1.0, 0.54, 0.24, 0.38 * fade), 4.0)
		ATTACK_GRAVITY:
			var shock_r := gravity_radius * (0.7 + (1.0 - t) * 0.58)
			draw_circle(Vector2.ZERO, shock_r, Color(1.0, 0.4, 0.18, 0.1 * fade))
			draw_arc(Vector2.ZERO, shock_r, 0.0, TAU, 48, Color(1.0, 0.8, 0.52, 0.44 * fade), 4.4)
		ATTACK_ECHO_DASH:
			var glow_len := 104.0 + 52.0 * t
			draw_line(-facing * 8.0, -facing * glow_len, Color(1.0, 0.62, 0.28, 0.26 * fade), 10.0)
			draw_line(-facing * 5.0, -facing * (glow_len * 0.8), Color(1.0, 0.9, 0.58, 0.32 * fade), 3.6)
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				var outward := orb_pos.normalized()
				if outward.length_squared() <= 0.000001:
					continue
				var beam_end := orb_pos + outward * orbital_lance_length * (0.84 + (1.0 - t) * 0.2)
				draw_line(orb_pos, beam_end, Color(1.0, 0.74, 0.34, 0.28 * fade), 7.0)
				draw_line(orb_pos, beam_end, Color(1.0, 0.94, 0.7, 0.18 * fade), 2.4)

func _draw_attack_impact_burst(facing: Vector2) -> void:
	if impact_burst_time_left <= 0.0:
		return
	var t := 1.0 - clampf(impact_burst_time_left / maxf(impact_burst_duration, 0.001), 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - t, 3.0)
	var alpha := (1.0 - t) * (1.0 - t)
	var side := Vector2(-facing.y, facing.x)
	match last_attack_for_fx:
		ATTACK_PRISM:
			var burst_r := 24.0 + ease * 38.0
			draw_arc(Vector2.ZERO, burst_r, 0.0, TAU, 28, Color(1.0, 0.86, 0.56, 0.6 * alpha), 3.4)
			for i in range(prism_spoke_count):
				var a := _prism_base_angle + TAU * float(i) / float(prism_spoke_count)
				draw_line(Vector2.RIGHT.rotated(a) * (burst_r * 0.45), Vector2.RIGHT.rotated(a) * (burst_r + 16.0), Color(1.0, 0.72, 0.36, 0.46 * alpha), 2.2)
		ATTACK_GRAVITY:
			var grav_r := 42.0 + ease * (gravity_radius * 0.64)
			draw_circle(Vector2.ZERO, grav_r, Color(1.0, 0.5, 0.2, 0.18 * alpha))
			draw_arc(Vector2.ZERO, grav_r, 0.0, TAU, 48, Color(1.0, 0.86, 0.56, 0.62 * alpha), 4.0)
		ATTACK_ECHO_DASH:
			var center := facing * (26.0 + ease * 32.0)
			var burst := 18.0 + ease * 26.0
			draw_circle(center, burst, Color(1.0, 0.64, 0.3, 0.24 * alpha))
			draw_arc(center, burst + 4.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.6, 0.62 * alpha), 2.8)
			draw_line(center + side * 16.0, center + side * 34.0, Color(1.0, 0.86, 0.58, 0.45 * alpha), 2.0)
			draw_line(center - side * 16.0, center - side * 34.0, Color(1.0, 0.86, 0.58, 0.45 * alpha), 2.0)
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				var burst_r := 10.0 + ease * 18.0
				draw_circle(orb_pos, burst_r, Color(1.0, 0.64, 0.28, 0.22 * alpha))
				draw_arc(orb_pos, burst_r + 3.0, 0.0, TAU, 20, Color(1.0, 0.92, 0.66, 0.6 * alpha), 2.2)

func _draw_orbital_satellites() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var positions := _get_orb_positions(t)
	var awakened := _orbital_attack_unlocked()
	for i in range(positions.size()):
		var orb_pos := positions[i]
		var highlighted := i in _orbital_lance_indices and active_attack == ATTACK_ORBITAL_LANCE and (boss_state == STATE_WINDUP or boss_state == STATE_ATTACK)
		var orb_color := Color(0.95, 0.4, 0.22, 0.82)
		var orb_radius := 3.6
		if awakened:
			orb_color = Color(1.0, 0.62, 0.28, 0.9)
			orb_radius = 4.2
		if highlighted:
			orb_color = Color(1.0, 0.9, 0.64, 0.96)
			orb_radius = 5.2
			draw_circle(orb_pos, orb_radius + 4.8, Color(1.0, 0.56, 0.24, 0.2 + telegraph_alpha * 0.18))
		draw_circle(orb_pos, orb_radius, orb_color)

func _draw_enrage_scaling_indicator(body_radius: float, facing: Vector2, enrage_t: float) -> void:
	if enrage_t <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * (0.012 + enrage_t * 0.02))
	var side := Vector2(-facing.y, facing.x)
	var aura_radius := body_radius + 14.0 + enrage_t * 15.0
	var aura_alpha := 0.05 + enrage_t * 0.12 + pulse * 0.05
	draw_circle(Vector2.ZERO, aura_radius, Color(1.0, 0.26, 0.1, aura_alpha))
	draw_arc(Vector2.ZERO, aura_radius + 2.0, 0.0, TAU, 44, Color(1.0, 0.8, 0.42, 0.2 + enrage_t * 0.35), 2.1 + enrage_t * 1.4)
	var tier := _get_enrage_tier(enrage_t)
	var pip_anchor := -facing * (body_radius + 18.0)
	for i in range(3):
		var offset := side * ((float(i) - 1.0) * 10.0)
		var pip_pos := pip_anchor + offset
		var lit := i < tier
		var pip_color := Color(1.0, 0.46, 0.16, 0.88) if lit else Color(0.44, 0.22, 0.18, 0.45)
		draw_circle(pip_pos, 2.9, pip_color)
		if lit:
			draw_arc(pip_pos, 5.0, 0.0, TAU, 18, Color(1.0, 0.86, 0.54, 0.62), 1.4)

func _get_enrage_tier(enrage_t: float) -> int:
	if enrage_t >= 0.85:
		return 3
	if enrage_t >= 0.5:
		return 2
	if enrage_t > 0.0:
		return 1
	return 0
