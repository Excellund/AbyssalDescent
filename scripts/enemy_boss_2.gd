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
const ATTACK_POLAR_SHIFT := 4

@export var boss_max_health: int = 2000
@export var move_speed: float = 168.0
@export var acceleration: float = 980.0
@export var deceleration: float = 1380.0
@export var preferred_distance: float = 260.0
@export var action_cooldown: float = 0.52

@export var prism_windup: float = 0.95
@export var prism_radius: float = 300.0
@export var prism_spoke_count: int = 5
@export var prism_spoke_half_angle_degrees: float = 13.0
@export var prism_damage: int = 40

@export var gravity_windup: float = 1.1
@export var gravity_radius: float = 240.0
@export var gravity_damage: int = 54

@export var echo_dash_windup: float = 0.58
@export var echo_dash_speed: float = 680.0
@export var echo_dash_duration: float = 0.24
@export var echo_dash_count: int = 3
@export var echo_dash_width: float = 44.0
@export var echo_dash_damage: int = 36
@export var echo_dash_retarget_pause: float = 0.14
@export var echo_dash_max_turn_degrees: float = 40.0
@export var reposition_dash_chance: float = 0.46
@export var reposition_dash_speed: float = 760.0
@export var reposition_dash_duration: float = 0.23

@export var orb_count: int = 6
@export var orb_ring_radius: float = 54.0
@export var orb_rotation_speed: float = 0.95
@export var orbital_lance_windup: float = 0.88
@export var orbital_lance_length: float = 320.0
@export var orbital_lance_width: float = 24.0
@export var orbital_lance_damage: int = 38

@export var polar_shift_windup: float = 0.92
@export var polar_shift_radius: float = 440.0
@export var polar_shift_force: float = 820.0
@export var polar_shift_safe_arc_degrees: float = 52.0
@export var polar_shift_safe_force_mult: float = 0.0
@export var polar_shift_counter_velocity_threshold: float = 150.0
@export var polar_shift_counter_force_mult: float = 0.56
@export var polar_shift_anchor_radius: float = 92.0
@export var polar_shift_anchor_force_mult: float = 0.0
@export var polar_shift_pull_inner_radius: float = 160.0
@export var polar_shift_pull_inner_damage: int = 28
@export var polar_shift_pull_inner_delay: float = 0.32
@export var polar_shift_pull_afterglow_duration: float = 0.42

@export var recover_time: float = 0.42
@export var arena_size: Vector2 = Vector2(1360.0, 960.0)
@export var edge_soft_margin: float = 180.0
@export var edge_hard_margin: float = 112.0

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
var _echo_dash_reposition_only: bool = false
var _orbital_lance_indices: Array[int] = []
var _orbital_lance_positions: PackedVector2Array = PackedVector2Array()
var _edge_stall_time: float = 0.0
var _attack_cycle_step: int = 0
var _orbit_clockwise: bool = true
var _last_attack: int = -1
var _repeat_attack_streak: int = 0
var _polar_shift_is_pull: bool = true
var _polar_shift_safe_angles: Array[float] = []
var attack_afterglow_time_left: float = 0.0
var attack_afterglow_duration: float = 0.56
var impact_burst_time_left: float = 0.0
var impact_burst_duration: float = 0.2
var last_attack_for_fx: int = ATTACK_PRISM
var _polar_shift_pull_damage_pending: bool = false
var _polar_shift_pull_damage_delay_left: float = 0.0
var _polar_shift_pull_damage_just_started: bool = false
var _polar_shift_pull_afterglow_left: float = 0.0

func _ready() -> void:
	max_health = boss_max_health
	super._ready()
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 38.0
				break
	configure_health_bar_visuals(Vector2(-74.0, -82.0), Vector2(148.0, 12.0))

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
	_polar_shift_pull_afterglow_left = maxf(0.0, _polar_shift_pull_afterglow_left - delta)
	_process_polar_shift_pull_punish(delta)

	queue_redraw()

func _process_polar_shift_pull_punish(delta: float) -> void:
	if not _polar_shift_pull_damage_pending:
		return
	if _polar_shift_pull_damage_just_started:
		_polar_shift_pull_damage_just_started = false
		return
	_polar_shift_pull_damage_delay_left = maxf(0.0, _polar_shift_pull_damage_delay_left - delta)
	if _polar_shift_pull_damage_delay_left > 0.0:
		return
	_polar_shift_pull_damage_pending = false
	_polar_shift_pull_afterglow_left = polar_shift_pull_afterglow_duration
	if not DAMAGEABLE.can_take_damage(target):
		return
	if global_position.distance_to(target.global_position) <= polar_shift_pull_inner_radius:
		DAMAGEABLE.apply_damage(target, polar_shift_pull_inner_damage)

func _draw_polar_shift_pull_delayed_indicator() -> void:
	if not _polar_shift_pull_damage_pending and _polar_shift_pull_afterglow_left <= 0.0:
		return
	var delay_total := maxf(0.001, polar_shift_pull_inner_delay)
	var radius := polar_shift_pull_inner_radius
	if _polar_shift_pull_damage_pending:
		var remaining_t := clampf(_polar_shift_pull_damage_delay_left / delay_total, 0.0, 1.0)
		var progress := 1.0 - remaining_t
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.022)
		var base_alpha := 0.1 + progress * 0.18 + pulse * 0.05
		var ring_alpha := 0.32 + progress * 0.58

		# Persistent danger area while the delayed hit is armed.
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.34, 0.2, base_alpha))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(1.0, 0.5, 0.3, ring_alpha), 3.2)

		# Countdown sweep that fills toward the damage moment.
		var sweep_start := -PI * 0.5
		var sweep_end := sweep_start + TAU * progress
		draw_arc(Vector2.ZERO, radius + 7.0, sweep_start, sweep_end, 56, Color(1.0, 0.92, 0.64, 0.78), 4.0)

		# Clock hand marker for quick read of time-to-hit.
		var marker := Vector2.RIGHT.rotated(sweep_end) * (radius + 7.0)
		draw_circle(marker, 3.2, Color(1.0, 0.95, 0.76, 0.9))
		return

	# Afterglow lingers briefly after the hit resolves.
	var glow_t := clampf(_polar_shift_pull_afterglow_left / maxf(0.001, polar_shift_pull_afterglow_duration), 0.0, 1.0)
	var expanded_radius := radius + (1.0 - glow_t) * 16.0
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.36, 0.22, 0.08 * glow_t))
	draw_arc(Vector2.ZERO, expanded_radius, 0.0, TAU, 72, Color(1.0, 0.58, 0.36, 0.62 * glow_t), 3.4)
	draw_arc(Vector2.ZERO, expanded_radius + 6.0, 0.0, TAU, 72, Color(1.0, 0.9, 0.7, 0.26 * glow_t), 1.8)

func _process_stalk_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var inward_bias := _get_inward_edge_bias()
	var wall_pressure := inward_bias.length()
	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
		visual_facing_direction = locked_direction

	var orbit_dir := Vector2(-locked_direction.y, locked_direction.x)
	if not _orbit_clockwise:
		orbit_dir = -orbit_dir
	var desired := orbit_dir * move_speed * 0.84
	if wall_pressure >= 0.74:
		desired = inward_bias * move_speed * (1.18 + wall_pressure * 0.92) + orbit_dir * move_speed * 0.22
	if wall_pressure > 0.0:
		desired += inward_bias * move_speed * (0.95 + wall_pressure * 0.58)
	if distance > preferred_distance + 54.0:
		desired += locked_direction * move_speed * 0.6
	elif distance < preferred_distance - 28.0:
		desired -= locked_direction * move_speed * 0.96
	if wall_pressure > 0.62 and desired.length_squared() > 0.000001:
		desired = desired.normalized() * move_speed
	desired *= slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

	var is_edge_stalled := wall_pressure > 0.58 and velocity.length() < move_speed * 0.22
	if is_edge_stalled:
		_edge_stall_time += delta
	else:
		_edge_stall_time = 0.0

	if wall_pressure >= 0.82:
		cooldown_left = minf(cooldown_left, 0.08)

	if cooldown_left <= 0.0 and (wall_pressure < 0.68 or _edge_stall_time >= 0.28):
		_start_next_attack(distance, wall_pressure)

func _start_next_attack(distance_to_target: float, wall_pressure: float = 0.0) -> void:
	var enrage_t := _get_enrage_ratio()
	var cycle_step := _attack_cycle_step % 3
	var force_reposition := wall_pressure >= 0.82 or _edge_stall_time >= 0.18
	if force_reposition:
		active_attack = ATTACK_ECHO_DASH
		_echo_dash_reposition_only = true
	elif wall_pressure >= 0.68:
		if randf() < 0.24:
			active_attack = ATTACK_POLAR_SHIFT
		elif _orbital_attack_unlocked() and randf() < 0.34:
			active_attack = ATTACK_ORBITAL_LANCE
		else:
			active_attack = ATTACK_GRAVITY if distance_to_target < 190.0 else ATTACK_PRISM
	elif cycle_step == 0:
		if randf() < 0.26:
			active_attack = ATTACK_POLAR_SHIFT
		elif _orbital_attack_unlocked() and (distance_to_target > 210.0 or randf() < 0.58):
			active_attack = ATTACK_ORBITAL_LANCE
		else:
			active_attack = ATTACK_PRISM
	elif cycle_step == 1:
		if randf() < 0.36:
			active_attack = ATTACK_POLAR_SHIFT
		else:
			active_attack = ATTACK_GRAVITY if distance_to_target < 235.0 else ATTACK_PRISM
	elif distance_to_target > 360.0 and enrage_t > 0.32:
		active_attack = ATTACK_ECHO_DASH
	elif distance_to_target < 150.0:
		if _orbital_attack_unlocked() and randf() < 0.42:
			active_attack = ATTACK_ORBITAL_LANCE
		else:
			active_attack = ATTACK_GRAVITY if randf() < 0.84 else ATTACK_PRISM
	else:
		var roll := randf()
		if roll < 0.24:
			active_attack = ATTACK_POLAR_SHIFT
		elif _orbital_attack_unlocked() and roll < 0.5:
			active_attack = ATTACK_ORBITAL_LANCE
		elif roll < 0.8:
			active_attack = ATTACK_PRISM
		elif roll < 0.96:
			active_attack = ATTACK_GRAVITY
		else:
			active_attack = ATTACK_ECHO_DASH

	if active_attack == _last_attack:
		var avoid_repeat_chance := clampf(0.74 + float(_repeat_attack_streak) * 0.12, 0.0, 0.95)
		if randf() < avoid_repeat_chance:
			active_attack = _pick_non_repeating_attack(distance_to_target, wall_pressure, active_attack)

	if active_attack == _last_attack:
		_repeat_attack_streak += 1
	else:
		_repeat_attack_streak = 0
	_last_attack = active_attack

	if enrage_t > 0.72 and active_attack == ATTACK_PRISM and randf() < 0.3:
		active_attack = ATTACK_ORBITAL_LANCE
	if active_attack == ATTACK_PRISM:
		_capture_prism_pattern()
	elif active_attack == ATTACK_ORBITAL_LANCE:
		_capture_orbital_lance_pattern()
	elif active_attack == ATTACK_POLAR_SHIFT:
		_polar_shift_is_pull = distance_to_target > preferred_distance or randf() < 0.56
		_capture_polar_shift_pattern()

	if active_attack != ATTACK_ECHO_DASH:
		_echo_dash_reposition_only = false
	if active_attack == ATTACK_ECHO_DASH:
		var reposition_chance := reposition_dash_chance
		if wall_pressure > 0.45:
			reposition_chance += 0.24
		if distance_to_target < preferred_distance - 30.0:
			reposition_chance += 0.16
		if _edge_stall_time > 0.0:
			reposition_chance += 0.22
		reposition_chance = clampf(reposition_chance, 0.0, 0.96)
		if force_reposition or randf() < reposition_chance:
			locked_direction = _get_reposition_dash_direction()
			visual_facing_direction = locked_direction
			_echo_dash_reposition_only = true
			_echo_dash_retargeting = false
			_echo_dash_retarget_time_left = 0.0
			_echo_dash_warning_line = PackedVector2Array([Vector2.ZERO, locked_direction * 340.0])
	_attack_cycle_step += 1
	if active_attack == ATTACK_GRAVITY or active_attack == ATTACK_ECHO_DASH or active_attack == ATTACK_POLAR_SHIFT:
		_orbit_clockwise = not _orbit_clockwise

	boss_state = STATE_WINDUP
	state_time_left = _get_windup_time(active_attack)
	if active_attack == ATTACK_POLAR_SHIFT and _polar_shift_is_pull:
		_polar_shift_pull_damage_pending = true
		_polar_shift_pull_damage_delay_left = state_time_left + polar_shift_pull_inner_delay
		_polar_shift_pull_damage_just_started = true
		_polar_shift_pull_afterglow_left = 0.0
	else:
		_polar_shift_pull_damage_pending = false
		_polar_shift_pull_damage_delay_left = 0.0
		_polar_shift_pull_damage_just_started = false
	telegraph_alpha = 0.0
	_echo_dash_hits.clear()
	_echo_dash_remaining = 0
	_echo_dash_warning_line = PackedVector2Array()
	_echo_dash_retargeting = false
	_echo_dash_retarget_time_left = 0.0
	_edge_stall_time = 0.0
	velocity = Vector2.ZERO

func _pick_non_repeating_attack(distance_to_target: float, wall_pressure: float, excluded_attack: int) -> int:
	var candidates: Array[int] = []
	if wall_pressure > 0.6:
		candidates = [ATTACK_ECHO_DASH, ATTACK_POLAR_SHIFT, ATTACK_GRAVITY, ATTACK_PRISM]
	elif distance_to_target > 330.0:
		candidates = [ATTACK_ORBITAL_LANCE, ATTACK_POLAR_SHIFT, ATTACK_PRISM, ATTACK_ECHO_DASH]
	elif distance_to_target < 170.0:
		candidates = [ATTACK_GRAVITY, ATTACK_ECHO_DASH, ATTACK_POLAR_SHIFT, ATTACK_PRISM]
	else:
		candidates = [ATTACK_POLAR_SHIFT, ATTACK_ORBITAL_LANCE, ATTACK_PRISM, ATTACK_GRAVITY, ATTACK_ECHO_DASH]
	for candidate in candidates:
		if candidate == ATTACK_ORBITAL_LANCE and not _orbital_attack_unlocked():
			continue
		if candidate != excluded_attack:
			return candidate
	return ATTACK_GRAVITY if excluded_attack != ATTACK_GRAVITY else ATTACK_PRISM

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	var windup := _get_windup_time(active_attack)
	telegraph_alpha = 1.0 - (state_time_left / maxf(0.001, windup))

	if active_attack == ATTACK_ECHO_DASH and is_instance_valid(target):
		var dash_dir := locked_direction
		if _echo_dash_reposition_only:
			if dash_dir.length_squared() <= 0.000001:
				dash_dir = _get_reposition_dash_direction()
			locked_direction = dash_dir
			visual_facing_direction = dash_dir
		else:
			dash_dir = (target.global_position - global_position).normalized()
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
			_echo_dash_remaining = 1 if _echo_dash_reposition_only else echo_dash_count
			_begin_echo_dash_leg()
		ATTACK_ORBITAL_LANCE:
			state_time_left = 0.08
			velocity = Vector2.ZERO
			_apply_orbital_lance_hits()
		ATTACK_POLAR_SHIFT:
			state_time_left = 0.08
			velocity = Vector2.ZERO
			_apply_polar_shift()

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
		var dash_speed := reposition_dash_speed if _echo_dash_reposition_only else echo_dash_speed * lerpf(1.0, 1.16, _get_enrage_ratio())
		velocity = locked_direction * dash_speed
		move_and_slide()
		if not _echo_dash_reposition_only:
			_apply_echo_dash_hit()
		state_time_left = maxf(0.0, state_time_left - delta)
		if state_time_left <= 0.0:
			_echo_dash_remaining -= 1
			if _echo_dash_remaining > 0 and not _echo_dash_reposition_only:
				_start_echo_dash_retarget_pause()
			else:
				var reposition_recover := _echo_dash_reposition_only
				_echo_dash_retargeting = false
				_echo_dash_retarget_time_left = 0.0
				_echo_dash_warning_line = PackedVector2Array()
				_echo_dash_reposition_only = false
				boss_state = STATE_RECOVER
				state_time_left = recover_time * (0.62 if reposition_recover else 0.8)
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
		if _echo_dash_reposition_only:
			if locked_direction.length_squared() <= 0.000001:
				locked_direction = _get_reposition_dash_direction()
			visual_facing_direction = locked_direction
		else:
			var to_target := target.global_position - global_position
			if to_target.length_squared() > 0.000001:
				locked_direction = to_target.normalized()
				visual_facing_direction = locked_direction
	_echo_dash_retargeting = false
	_echo_dash_retarget_time_left = 0.0
	_echo_dash_warning_line = PackedVector2Array()
	telegraph_alpha = 0.0
	state_time_left = reposition_dash_duration if _echo_dash_reposition_only else echo_dash_duration

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
	var inward_bias := _get_inward_edge_bias()
	var recover_target := inward_bias * move_speed * 0.54
	velocity = velocity.move_toward(recover_target, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_STALK
		cooldown_left = action_cooldown * lerpf(1.0, 0.7, _get_enrage_ratio())

func _get_inward_edge_bias() -> Vector2:
	var half := arena_size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return Vector2.ZERO

	var x_to_edge := half.x - absf(global_position.x)
	var y_to_edge := half.y - absf(global_position.y)
	var pressure_denominator := maxf(1.0, edge_soft_margin - edge_hard_margin)
	var x_pressure := clampf((edge_soft_margin - x_to_edge) / pressure_denominator, 0.0, 1.0)
	var y_pressure := clampf((edge_soft_margin - y_to_edge) / pressure_denominator, 0.0, 1.0)

	var bias := Vector2.ZERO
	if x_pressure > 0.0:
		bias.x = -signf(global_position.x) * x_pressure
	if y_pressure > 0.0:
		bias.y = -signf(global_position.y) * y_pressure

	if bias.length_squared() <= 0.000001:
		return Vector2.ZERO
	return bias.normalized() * maxf(x_pressure, y_pressure)

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

func _apply_polar_shift() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	var to_target := target.global_position - global_position
	if to_target.length() > polar_shift_radius:
		return
	if target is CharacterBody2D:
		var target_body := target as CharacterBody2D
		var dir := (global_position - target_body.global_position)
		if dir.length_squared() <= 0.000001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		if not _polar_shift_is_pull:
			dir = -dir
		var force_mult := 1.0
		if to_target.length() <= polar_shift_anchor_radius:
			force_mult *= polar_shift_anchor_force_mult
		if _is_polar_shift_in_safe_lane(to_target.angle()):
			force_mult *= polar_shift_safe_force_mult
		var counter_velocity := target_body.velocity.dot(-dir)
		if counter_velocity >= polar_shift_counter_velocity_threshold:
			force_mult *= polar_shift_counter_force_mult
		target_body.velocity += dir * polar_shift_force * force_mult

func _capture_polar_shift_pattern() -> void:
	_polar_shift_safe_angles.clear()
	var positions := _get_orb_positions(float(Time.get_ticks_msec()) * 0.001)
	if positions.size() >= 4:
		var base_angle := locked_direction.angle()
		if is_instance_valid(target):
			var to_target := target.global_position - global_position
			if to_target.length_squared() > 0.000001:
				base_angle = to_target.angle()
		var player_index := 0
		var best_delta := INF
		for i in range(positions.size()):
			var d := absf(wrapf(base_angle - positions[i].angle(), -PI, PI))
			if d < best_delta:
				best_delta = d
				player_index = i
		var quarter_count := maxi(1, ceili(float(positions.size()) * 0.25))
		var base_index := player_index + quarter_count
		if not _orbit_clockwise:
			base_index = player_index - quarter_count
		base_index = posmod(base_index, positions.size())
		var half_count := int(positions.size() * 0.5)
		var opposite_index := (base_index + half_count) % positions.size()
		_polar_shift_safe_angles.append(positions[base_index].angle())
		_polar_shift_safe_angles.append(positions[opposite_index].angle())
		return
	var base := locked_direction.angle() + PI * 0.5
	_polar_shift_safe_angles.append(base)
	_polar_shift_safe_angles.append(base + PI)

func _is_polar_shift_in_safe_lane(target_angle: float) -> bool:
	if _polar_shift_safe_angles.is_empty():
		return false
	var half_arc := deg_to_rad(polar_shift_safe_arc_degrees) * 0.5
	for lane_angle in _polar_shift_safe_angles:
		if absf(wrapf(target_angle - lane_angle, -PI, PI)) <= half_arc:
			return true
	return false

func _get_reposition_dash_direction() -> Vector2:
	if not is_instance_valid(target):
		return locked_direction
	var to_target := target.global_position - global_position
	if to_target.length_squared() <= 0.000001:
		return locked_direction
	var toward := to_target.normalized()
	var orbit := Vector2(-toward.y, toward.x)
	if not _orbit_clockwise:
		orbit = -orbit
	var inward_bias := _get_inward_edge_bias() * 0.8
	var wall_pressure := inward_bias.length()
	var mixed := orbit * 0.78 + inward_bias * (1.2 + wall_pressure * 2.8) + (-toward) * 0.14
	if wall_pressure >= 0.38:
		mixed = inward_bias * (2.4 + wall_pressure * 1.8) + orbit * 0.34 + (-toward) * 0.08
	if mixed.length_squared() <= 0.000001:
		mixed = orbit
	return mixed.normalized()

func _distance_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_to(closest)

func _orbital_attack_unlocked() -> bool:
	return _get_enrage_ratio() >= 0.12

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

func _capture_prism_pattern() -> void:
	var positions := _get_orb_positions(float(Time.get_ticks_msec()) * 0.001)
	if positions.is_empty():
		_prism_base_angle = locked_direction.angle() + randf_range(-0.22, 0.22)
		return
	var source_index := _attack_cycle_step % positions.size()
	_prism_base_angle = positions[source_index].angle() + PI * 0.5
	if not _orbit_clockwise:
		_prism_base_angle += PI / float(prism_spoke_count)

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
			if _echo_dash_reposition_only:
				return maxf(0.24, echo_dash_windup * 0.68)
			return echo_dash_windup * lerpf(1.0, 0.8, enrage_t)
		ATTACK_ORBITAL_LANCE:
			return orbital_lance_windup * lerpf(1.0, 0.84, enrage_t)
		ATTACK_POLAR_SHIFT:
			return polar_shift_windup * lerpf(1.0, 0.86, enrage_t)
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

	if boss_state == STATE_WINDUP or (boss_state == STATE_ATTACK and active_attack == ATTACK_ECHO_DASH and _echo_dash_retargeting):
		var halo_radius := body_radius + 17.0 + threat_t * 10.0
		draw_circle(Vector2.ZERO, halo_radius, Color(1.0, 0.26, 0.14, 0.06 + threat_t * 0.12))
		draw_arc(Vector2.ZERO, halo_radius + 3.0, 0.0, TAU, 52, Color(1.0, 0.82, 0.46, 0.24 + threat_t * 0.3), 2.8)
	if boss_state == STATE_WINDUP and active_attack == ATTACK_ORBITAL_LANCE:
		var lattice_radius := body_radius + 25.0 + telegraph_alpha * 10.0
		draw_arc(Vector2.ZERO, lattice_radius, 0.0, TAU, 64, Color(1.0, 0.76, 0.46, 0.26 + telegraph_alpha * 0.34), 3.2)
		draw_circle(Vector2.ZERO, lattice_radius * 0.72, Color(1.0, 0.52, 0.24, 0.05 + telegraph_alpha * 0.08))

	_draw_sovereign_floor_sigil(body_radius, enrage_t)
	_draw_sovereign_body(body_radius, body_color, core_color, facing, enrage_t)
	_draw_mutator_overlay(body_radius)
	_draw_damage_blocked_indicator(body_radius)
	_draw_slow_indicator(body_radius)
	_draw_attack_afterglow(facing)
	_draw_attack_impact_burst(facing)
	_draw_polar_shift_pull_delayed_indicator()

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

func _draw_sovereign_floor_sigil(body_radius: float, enrage_t: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var spin := t * (0.32 + enrage_t * 0.12)
	var sigil_radius := body_radius + 15.0
	var inner_radius := sigil_radius - 8.0
	draw_circle(Vector2.ZERO, sigil_radius + 6.0, Color(0.05, 0.14, 0.22, 0.12 + enrage_t * 0.04))
	draw_arc(Vector2.ZERO, sigil_radius, spin, spin + TAU, 48, Color(0.28, 0.68, 0.96, 0.14 + enrage_t * 0.08), 1.8)
	draw_arc(Vector2.ZERO, sigil_radius + 7.0, -spin * 1.2, -spin * 1.2 + TAU, 56, Color(1.0, 0.58, 0.28, 0.08 + enrage_t * 0.08), 1.4)
	draw_arc(Vector2.ZERO, inner_radius, -spin * 0.55, -spin * 0.55 + TAU, 36, Color(0.82, 0.96, 1.0, 0.12), 1.2)
	for i in range(3):
		var angle_a := spin + TAU * float(i) / 3.0
		var angle_b := angle_a + TAU / 6.0
		draw_line(Vector2.RIGHT.rotated(angle_a) * (sigil_radius - 7.0), Vector2.RIGHT.rotated(angle_b) * (sigil_radius + 7.0), Color(0.9, 0.98, 1.0, 0.12), 1.4)
		var shard_center := Vector2.RIGHT.rotated(angle_a + TAU / 12.0) * (sigil_radius + 3.5)
		draw_circle(shard_center, 1.8, Color(1.0, 0.82, 0.58, 0.24))

func _draw_sovereign_body(body_radius: float, body_color: Color, core_color: Color, facing: Vector2, enrage_t: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var side := Vector2(-facing.y, facing.x)
	var pulse := 0.5 + 0.5 * sin(t * 4.2 + enrage_t * 2.1)
	var shell_outer := PackedVector2Array([
		facing * (body_radius + 7.0),
		facing * (body_radius * 0.24) + side * (body_radius + 8.0),
		-facing * (body_radius * 0.92),
		facing * (body_radius * 0.24) - side * (body_radius + 8.0)
	])
	var shell_inner := PackedVector2Array([
		facing * (body_radius * 0.72),
		facing * (body_radius * 0.14) + side * (body_radius * 0.68),
		-facing * (body_radius * 0.62),
		facing * (body_radius * 0.14) - side * (body_radius * 0.68)
	])
	var crest_tip := -facing * (body_radius + 11.0)
	var crest_left := -facing * (body_radius * 0.12) + side * (body_radius * 0.34)
	var crest_right := -facing * (body_radius * 0.12) - side * (body_radius * 0.34)
	var crown_left := facing * (body_radius * 0.08) + side * (body_radius + 4.0)
	var crown_right := facing * (body_radius * 0.08) - side * (body_radius + 4.0)
	var shell_highlight := PackedVector2Array([
		facing * (body_radius * 0.6),
		facing * (body_radius * 0.12) + side * (body_radius * 0.48),
		-facing * (body_radius * 0.28),
		facing * (body_radius * 0.12) - side * (body_radius * 0.48)
	])

	draw_circle(Vector2.ZERO, body_radius + 10.0, Color(0.08, 0.22, 0.4, 0.18 + enrage_t * 0.1))
	draw_circle(Vector2.ZERO, body_radius + 4.0 + pulse * 1.8, Color(0.22, 0.58, 0.84, 0.08 + pulse * 0.05 + enrage_t * 0.06))
	draw_colored_polygon(shell_outer, Color(body_color.r * 0.58, body_color.g * 0.74, body_color.b * 0.96, 0.34))
	draw_colored_polygon(shell_inner, body_color)
	draw_colored_polygon(shell_highlight, Color(0.84, 0.95, 1.0, 0.12 + pulse * 0.08))
	draw_line(shell_inner[0], shell_inner[1], Color(0.9, 0.98, 1.0, 0.26), 1.8)
	draw_line(shell_inner[0], shell_inner[3], Color(0.9, 0.98, 1.0, 0.26), 1.8)
	draw_line(shell_inner[2], shell_inner[1], Color(0.1, 0.18, 0.28, 0.22), 1.4)
	draw_line(shell_inner[2], shell_inner[3], Color(0.1, 0.18, 0.28, 0.22), 1.4)
	draw_colored_polygon(PackedVector2Array([crest_tip, crest_left, crest_right]), Color(0.96, 0.78, 0.5, 0.92))
	draw_line(crown_left, crest_tip, Color(1.0, 0.84, 0.58, 0.46), 2.0)
	draw_line(crown_right, crest_tip, Color(1.0, 0.84, 0.58, 0.46), 2.0)
	draw_arc(crest_tip, 5.4 + pulse * 1.2, 0.0, TAU, 18, Color(1.0, 0.86, 0.62, 0.34 + pulse * 0.12), 1.4)

	var core_offset := facing * (body_radius * 0.04)
	var core_glow := body_radius * (0.5 + pulse * 0.04)
	draw_circle(core_offset, core_glow, Color(core_color.r, core_color.g, core_color.b, 0.16 + pulse * 0.08))
	draw_circle(core_offset, body_radius * 0.44, Color(core_color.r, core_color.g, core_color.b, 0.92))
	draw_circle(core_offset, body_radius * 0.22, Color(0.96, 0.99, 1.0, 0.38))
	var slit_top := core_offset + side * (body_radius * 0.24)
	var slit_bottom := core_offset - side * (body_radius * 0.24)
	draw_line(slit_top, slit_bottom, Color(0.06, 0.16, 0.24, 0.72), 3.0)
	draw_line(core_offset - facing * (body_radius * 0.12), core_offset + facing * (body_radius * 0.18), Color(1.0, 0.98, 0.9, 0.24 + pulse * 0.16), 1.6)

	var wing_left := PackedVector2Array([
		facing * (body_radius * 0.08) + side * (body_radius * 0.72),
		-facing * (body_radius * 0.18) + side * (body_radius + 10.0),
		-facing * (body_radius * 0.5) + side * (body_radius * 0.62)
	])
	var wing_right := PackedVector2Array([
		facing * (body_radius * 0.08) - side * (body_radius * 0.72),
		-facing * (body_radius * 0.18) - side * (body_radius + 10.0),
		-facing * (body_radius * 0.5) - side * (body_radius * 0.62)
	])
	draw_colored_polygon(wing_left, Color(body_color.r * 0.82, body_color.g * 0.92, body_color.b, 0.84))
	draw_colored_polygon(wing_right, Color(body_color.r * 0.82, body_color.g * 0.92, body_color.b, 0.84))
	draw_line(wing_left[0], wing_left[1], Color(0.92, 0.98, 1.0, 0.18), 1.4)
	draw_line(wing_right[0], wing_right[1], Color(0.92, 0.98, 1.0, 0.18), 1.4)
	for offset_sign: float in [-1.0, 1.0]:
		var anchor: Vector2 = core_offset + side * body_radius * 0.62 * offset_sign
		draw_line(anchor, anchor - facing * (body_radius * 0.42), Color(1.0, 0.72, 0.42, 0.2 + pulse * 0.08), 1.2)

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
			var dash_color := Color(0.72, 0.94, 1.0, icon_alpha) if _echo_dash_reposition_only else Color(1.0, 0.84, 0.48, icon_alpha)
			draw_colored_polygon(PackedVector2Array([tip, base + side * 5.8, base - side * 5.8]), dash_color)
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				draw_circle(orb_pos, 4.8, Color(1.0, 0.86, 0.54, icon_alpha * 0.92))
		ATTACK_POLAR_SHIFT:
			var ring_color := Color(0.58, 0.84, 1.0, icon_alpha) if _polar_shift_is_pull else Color(1.0, 0.58, 0.38, icon_alpha)
			draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 42, ring_color, 2.6)

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
				var dash_fill := Color(0.38, 0.8, 1.0, alpha * 0.2) if _echo_dash_reposition_only else Color(1.0, 0.52, 0.24, alpha * 0.24)
				var dash_edge := Color(0.62, 0.9, 1.0, alpha) if _echo_dash_reposition_only else Color(1.0, 0.7, 0.38, alpha)
				var dash_center := Color(0.9, 0.98, 1.0, alpha * 0.88) if _echo_dash_reposition_only else Color(1.0, 0.94, 0.66, alpha * 0.88)
				draw_colored_polygon(lane, dash_fill)
				draw_line(from + side * lane_half, to + side * lane_half, dash_edge, 2.8)
				draw_line(from - side * lane_half, to - side * lane_half, dash_edge, 2.8)
				draw_line(from, to, dash_center, 2.0)
		ATTACK_POLAR_SHIFT:
			var cc_color := Color(0.52, 0.84, 1.0, alpha) if _polar_shift_is_pull else Color(1.0, 0.56, 0.34, alpha)
			var fill_inner := maxf(polar_shift_anchor_radius, 24.0)
			var fill_outer := polar_shift_radius
			var sweep_t := float(Time.get_ticks_msec()) * 0.001
			for step in range(88):
				var a0 := TAU * float(step) / 88.0
				var a1 := TAU * float(step + 1) / 88.0
				var mid_angle := (a0 + a1) * 0.5
				if _is_polar_shift_in_safe_lane(mid_angle):
					continue
				var outer0 := Vector2.RIGHT.rotated(a0) * fill_outer
				var outer1 := Vector2.RIGHT.rotated(a1) * fill_outer
				var inner0 := Vector2.RIGHT.rotated(a0) * fill_inner
				var inner1 := Vector2.RIGHT.rotated(a1) * fill_inner
				var shimmer := 0.86 + 0.14 * sin(sweep_t * 5.2 + mid_angle * 3.0)
				draw_colored_polygon(PackedVector2Array([inner0, outer0, outer1, inner1]), Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.2 * shimmer))
				draw_colored_polygon(PackedVector2Array([
					inner0.lerp(outer0, 0.46),
					inner0.lerp(outer0, 0.88),
					inner1.lerp(outer1, 0.88),
					inner1.lerp(outer1, 0.46)
				]), Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.16 * shimmer))
				draw_arc(Vector2.ZERO, fill_outer, a0, a1, 2, Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.96), 3.8)
				draw_arc(Vector2.ZERO, fill_inner, a0, a1, 2, Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.68), 2.1)
				draw_arc(Vector2.ZERO, lerpf(fill_inner, fill_outer, 0.62), a0, a1, 2, Color(1.0, 0.96, 0.84, alpha * 0.28 * shimmer), 1.8)
			draw_arc(Vector2.ZERO, fill_outer + 8.0, 0.0, TAU, 84, Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.22), 2.2)
			draw_arc(Vector2.ZERO, fill_inner - 6.0, 0.0, TAU, 72, Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.16), 1.8)
			for i in range(10):
				var a := TAU * float(i) / 10.0
				if _is_polar_shift_in_safe_lane(a):
					continue
				var dir := Vector2.RIGHT.rotated(a)
				var outer := dir * (polar_shift_radius - 10.0)
				var inner := dir * (polar_shift_radius * 0.34)
				var tip := inner if _polar_shift_is_pull else outer
				var base := outer if _polar_shift_is_pull else inner
				var arrow_dir := (tip - base).normalized()
				var side := Vector2(-dir.y, dir.x) * 6.0
				draw_line(base, tip, Color(cc_color.r, cc_color.g, cc_color.b, alpha * 1.0), 2.8)
				draw_colored_polygon(PackedVector2Array([tip, tip - arrow_dir * 12.0 + side, tip - arrow_dir * 12.0 - side]), Color(cc_color.r, cc_color.g, cc_color.b, alpha * 0.96))
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
			if _echo_dash_reposition_only:
				draw_line(-facing * 8.0, -facing * glow_len, Color(0.4, 0.84, 1.0, 0.26 * fade), 10.0)
				draw_line(-facing * 5.0, -facing * (glow_len * 0.8), Color(0.88, 0.98, 1.0, 0.32 * fade), 3.6)
			else:
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
		ATTACK_POLAR_SHIFT:
			var cc_color := Color(0.52, 0.84, 1.0, 0.38 * fade) if _polar_shift_is_pull else Color(1.0, 0.56, 0.34, 0.38 * fade)
			var ring_r := polar_shift_radius * (0.86 + (1.0 - t) * 0.18)
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 72, cc_color, 5.0)

func _draw_attack_impact_burst(facing: Vector2) -> void:
	if impact_burst_time_left <= 0.0:
		return
	var t := 1.0 - clampf(impact_burst_time_left / maxf(impact_burst_duration, 0.001), 0.0, 1.0)
	var eased_t := 1.0 - pow(1.0 - t, 3.0)
	var alpha := (1.0 - t) * (1.0 - t)
	var side := Vector2(-facing.y, facing.x)
	match last_attack_for_fx:
		ATTACK_PRISM:
			var burst_r := 24.0 + eased_t * 38.0
			draw_arc(Vector2.ZERO, burst_r, 0.0, TAU, 28, Color(1.0, 0.86, 0.56, 0.6 * alpha), 3.4)
			for i in range(prism_spoke_count):
				var a := _prism_base_angle + TAU * float(i) / float(prism_spoke_count)
				draw_line(Vector2.RIGHT.rotated(a) * (burst_r * 0.45), Vector2.RIGHT.rotated(a) * (burst_r + 16.0), Color(1.0, 0.72, 0.36, 0.46 * alpha), 2.2)
		ATTACK_GRAVITY:
			var grav_r := 42.0 + eased_t * (gravity_radius * 0.64)
			draw_circle(Vector2.ZERO, grav_r, Color(1.0, 0.5, 0.2, 0.18 * alpha))
			draw_arc(Vector2.ZERO, grav_r, 0.0, TAU, 48, Color(1.0, 0.86, 0.56, 0.62 * alpha), 4.0)
		ATTACK_ECHO_DASH:
			var center := facing * (26.0 + eased_t * 32.0)
			var burst := 18.0 + eased_t * 26.0
			draw_circle(center, burst, Color(1.0, 0.64, 0.3, 0.24 * alpha))
			draw_arc(center, burst + 4.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.6, 0.62 * alpha), 2.8)
			draw_line(center + side * 16.0, center + side * 34.0, Color(1.0, 0.86, 0.58, 0.45 * alpha), 2.0)
			draw_line(center - side * 16.0, center - side * 34.0, Color(1.0, 0.86, 0.58, 0.45 * alpha), 2.0)
		ATTACK_ORBITAL_LANCE:
			for orb_pos in _orbital_lance_positions:
				var burst_r := 10.0 + eased_t * 18.0
				draw_circle(orb_pos, burst_r, Color(1.0, 0.64, 0.28, 0.22 * alpha))
				draw_arc(orb_pos, burst_r + 3.0, 0.0, TAU, 20, Color(1.0, 0.92, 0.66, 0.6 * alpha), 2.2)
		ATTACK_POLAR_SHIFT:
			var cc_color := Color(0.62, 0.9, 1.0, 0.52 * alpha) if _polar_shift_is_pull else Color(1.0, 0.62, 0.4, 0.52 * alpha)
			var ring_r := polar_shift_radius * (0.54 + eased_t * 0.52)
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 72, cc_color, 4.6)

func _draw_orbital_satellites() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var positions := _get_orb_positions(t)
	var awakened := _orbital_attack_unlocked()
	var ring_pulse := 0.5 + 0.5 * sin(t * 3.2)
	if positions.size() >= 2:
		var ring_color := Color(0.34, 0.62, 0.9, 0.18)
		var ring_width := 1.4
		if awakened:
			ring_color = Color(0.96, 0.58, 0.3, 0.16 + ring_pulse * 0.14)
			ring_width = 1.8 + ring_pulse * 0.4
		if active_attack == ATTACK_ORBITAL_LANCE and not _orbital_lance_positions.is_empty() and (boss_state == STATE_WINDUP or boss_state == STATE_ATTACK):
			ring_color = Color(1.0, 0.76, 0.5, 0.26 + telegraph_alpha * 0.18)
			ring_width = 2.2
		for i in range(positions.size()):
			var next_index := (i + 1) % positions.size()
			draw_line(positions[i], positions[next_index], ring_color, ring_width)
			var mid := positions[i].lerp(positions[next_index], 0.5)
			draw_circle(mid, 1.3, Color(0.98, 0.96, 0.88, 0.12 + ring_pulse * 0.08))
		if awakened:
			draw_arc(Vector2.ZERO, orb_ring_radius + 7.0, 0.0, TAU, 48, Color(1.0, 0.56, 0.28, 0.12), 1.4)
			draw_arc(Vector2.ZERO, orb_ring_radius - 8.0, t * 0.55, t * 0.55 + TAU, 40, Color(0.78, 0.94, 1.0, 0.09), 1.0)

	if active_attack == ATTACK_ORBITAL_LANCE and not _orbital_lance_positions.is_empty() and (boss_state == STATE_WINDUP or boss_state == STATE_ATTACK):
		var nexus_color := Color(1.0, 0.84, 0.58, 0.18 + telegraph_alpha * 0.18)
		for orb_pos in _orbital_lance_positions:
			draw_line(Vector2.ZERO, orb_pos, nexus_color, 2.1)
		for i in range(_orbital_lance_positions.size()):
			for j in range(i + 1, _orbital_lance_positions.size()):
				draw_line(_orbital_lance_positions[i], _orbital_lance_positions[j], Color(1.0, 0.72, 0.42, 0.12 + telegraph_alpha * 0.16), 1.6)
	elif active_attack == ATTACK_POLAR_SHIFT and (boss_state == STATE_WINDUP or boss_state == STATE_ATTACK):
		var cc_color := Color(0.62, 0.9, 1.0, 0.22 + telegraph_alpha * 0.2) if _polar_shift_is_pull else Color(1.0, 0.62, 0.4, 0.22 + telegraph_alpha * 0.2)
		for orb_pos in positions:
			var dir := orb_pos.normalized()
			if dir.length_squared() <= 0.000001:
				continue
			if _is_polar_shift_in_safe_lane(dir.angle()):
				continue
			var toward_center := -dir if _polar_shift_is_pull else dir
			draw_line(orb_pos, orb_pos + toward_center * 22.0, cc_color, 1.8)

	for i in range(positions.size()):
		var orb_pos := positions[i]
		var highlighted := i in _orbital_lance_indices and active_attack == ATTACK_ORBITAL_LANCE and (boss_state == STATE_WINDUP or boss_state == STATE_ATTACK)
		var orb_color := Color(0.95, 0.4, 0.22, 0.82)
		var orb_radius := 3.6
		var trail_dir := orb_pos.normalized().orthogonal()
		var outward := orb_pos.normalized()
		if outward.length_squared() <= 0.000001:
			outward = Vector2.RIGHT
		var tangential := Vector2(-outward.y, outward.x)
		if awakened:
			orb_color = Color(1.0, 0.62, 0.28, 0.9)
			orb_radius = 4.2
			draw_circle(orb_pos, orb_radius + 3.8, Color(1.0, 0.52, 0.24, 0.08))
			draw_line(orb_pos - trail_dir * 7.0, orb_pos + trail_dir * 4.0, Color(1.0, 0.58, 0.28, 0.18), 1.2)
			draw_line(orb_pos - tangential * 10.0, orb_pos - tangential * 2.0, Color(0.98, 0.82, 0.58, 0.12 + ring_pulse * 0.08), 1.0)
		if highlighted:
			orb_color = Color(1.0, 0.9, 0.64, 0.96)
			orb_radius = 5.2
			draw_circle(orb_pos, orb_radius + 4.8, Color(1.0, 0.56, 0.24, 0.2 + telegraph_alpha * 0.18))
			draw_arc(orb_pos, orb_radius + 7.4, 0.0, TAU, 18, Color(1.0, 0.92, 0.68, 0.38 + telegraph_alpha * 0.24), 1.6)
			draw_arc(orb_pos, orb_radius + 10.0, t * 4.0, t * 4.0 + PI * 1.3, 14, Color(1.0, 0.96, 0.8, 0.22 + telegraph_alpha * 0.18), 1.2)
		draw_circle(orb_pos, maxf(1.8, orb_radius * 0.4), Color(1.0, 0.98, 0.86, 0.72))
		draw_circle(orb_pos, orb_radius, orb_color)
		draw_circle(orb_pos + tangential * 0.9 - outward * 0.9, maxf(1.2, orb_radius * 0.22), Color(1.0, 1.0, 0.96, 0.72))

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
