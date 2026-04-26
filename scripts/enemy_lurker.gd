extends "res://scripts/enemy_base.gd"

# Lurker — late-game melee predator. Shares the Chaser's fast approach but has a
# distinct combat identity: it stops just outside striking range, holds position
# briefly while visibly tensing (the lurk), then lunges with a single high-damage
# pounce before retreating. The pause-then-pounce rhythm demands a different read
# from the player than the Chaser's continuous pressure.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_LURK := 1
const STATE_STRIKE := 2
const STATE_RECOVER := 3

@export var move_speed: float = 178.0
@export var acceleration: float = 1250.0
@export var deceleration: float = 1400.0
@export var stop_distance: float = 28.0
@export var trigger_range: float = 96.0
@export var strike_range: float = 48.0
@export var strike_damage: int = 34
@export var lurk_duration: float = 0.22
@export var strike_speed_mult: float = 3.2
@export var strike_duration: float = 0.16
@export var recover_duration: float = 0.42
@export var attack_cooldown: float = 0.55

var lurker_state: int = STATE_STALK
var state_time_left: float = 0.0
var attack_cooldown_left: float = 0.0
var _lunge_direction: Vector2 = Vector2.LEFT
var _strike_hit_applied: bool = false
var _strike_previous_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	max_health = 95
	# Override crowd separation for better swarm navigation
	crowd_separation_radius = 72.0
	crowd_separation_strength = 110.0

func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	match lurker_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_LURK:
			_process_lurk(delta)
		STATE_STRIKE:
			_process_strike(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _process_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	var to_target := target.global_position - global_position
	var desired := Vector2.ZERO
	if to_target.length() > stop_distance:
		desired = to_target.normalized() * move_speed * slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()
	if attack_cooldown_left <= 0.0 and to_target.length() <= trigger_range:
		_enter_lurk_state()

func _enter_lurk_state() -> void:
	lurker_state = STATE_LURK
	state_time_left = lurk_duration
	velocity = Vector2.ZERO
	if is_instance_valid(target):
		_lunge_direction = (target.global_position - global_position).normalized()
		visual_facing_direction = _lunge_direction
	queue_redraw()

func _process_lurk(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			_lunge_direction = to_target.normalized()
			visual_facing_direction = _lunge_direction
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_strike_state()

func _enter_strike_state() -> void:
	lurker_state = STATE_STRIKE
	state_time_left = strike_duration
	_strike_hit_applied = false
	_strike_previous_position = global_position
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			_lunge_direction = to_target.normalized()
	visual_facing_direction = _lunge_direction
	velocity = _lunge_direction * move_speed * strike_speed_mult
	queue_redraw()

func _process_strike(delta: float) -> void:
	var strike_start := _strike_previous_position
	move_and_slide()
	var strike_end := global_position
	if not _strike_hit_applied and is_instance_valid(target) and DAMAGEABLE.can_take_damage(target):
		var target_pos := target.global_position
		var closest := Geometry2D.get_closest_point_to_segment(target_pos, strike_start, strike_end)
		if closest.distance_to(target_pos) <= strike_range:
			if DAMAGEABLE.apply_damage(target, strike_damage, {"source": "enemy_contact"}):
				_strike_hit_applied = true
				attack_anim_time_left = attack_anim_duration
				queue_redraw()
	_strike_previous_position = strike_end
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		_enter_recover_state()

func _enter_recover_state() -> void:
	lurker_state = STATE_RECOVER
	state_time_left = recover_duration
	attack_cooldown_left = attack_cooldown
	velocity *= 0.28
	queue_redraw()

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		lurker_state = STATE_STALK

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 14.0 + attack_pulse + speed_t * 1.2  # Larger base size for visibility
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)

	# Persistent predatory aura — always visible to distinguish from Chasers
	var aura_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.008)
	var aura_alpha := 0.12 + aura_pulse * 0.08
	draw_circle(Vector2.ZERO, body_radius + 10.0, Color(1.0, 0.32, 0.2, aura_alpha))
	if lurker_state == STATE_STALK and is_instance_valid(target):
		var proximity_dist := global_position.distance_to(target.global_position)
		var proximity_window := trigger_range * 1.8
		if proximity_dist <= proximity_window:
			var proximity_t := 1.0 - (proximity_dist / proximity_window)
			draw_arc(Vector2.ZERO, body_radius + 12.0 + proximity_t * 5.0, 0.0, TAU, 44,
				Color(1.0, 0.5, 0.26, 0.16 + proximity_t * 0.28), 2.2)

	# Deep crimson body — visually distinct predator, darker and more menacing than Chaser
	var body_color := COLOR_PALETTE.COLOR_LURKER_BODY
	var core_color := COLOR_PALETTE.COLOR_LURKER_CORE
	
	if lurker_state == STATE_LURK:
		var tension_t := 1.0 - (state_time_left / maxf(0.001, lurk_duration))
		body_color = body_color.lerp(COLOR_PALETTE.COLOR_LURKER_BODY_LURK, tension_t)
		core_color = core_color.lerp(COLOR_PALETTE.COLOR_LURKER_CORE_LURK, tension_t)
	elif lurker_state == STATE_STRIKE:
		body_color = COLOR_PALETTE.COLOR_LURKER_BODY_STRIKE
		core_color = COLOR_PALETTE.COLOR_LURKER_CORE_STRIKE
	
	_draw_common_body(body_radius, body_color, core_color, facing)

	# Predatory inward-curving fangs — larger and more prominent for threat readability
	var fang_base := facing * (body_radius + 4.5)
	var fang_color := COLOR_PALETTE.COLOR_LURKER_FANG
	draw_line(fang_base + side * 6.0, fang_base + side * 2.2 + facing * 9.0, fang_color, 2.2)
	draw_line(fang_base - side * 6.0, fang_base - side * 2.2 + facing * 9.0, fang_color, 2.2)
	
	# Distinctive armor ridges on sides — makes silhouette instantly recognizable
	var ridge_alpha := 0.7
	for ridge_i in range(3):
		var ridge_offset := 0.3 + float(ridge_i) * 0.35
		var ridge_pos := side * (body_radius * ridge_offset)
		draw_circle(ridge_pos, 2.2, Color(0.72, 0.12, 0.16, ridge_alpha))
		draw_circle(-ridge_pos, 2.2, Color(0.72, 0.12, 0.16, ridge_alpha))
	
	# Predatory eye glow — intensifies during lurk state (shows "watching" state)
	if lurker_state == STATE_LURK or lurker_state == STATE_STRIKE:
		var tension_t := 1.0 if lurker_state == STATE_STRIKE else (1.0 - (state_time_left / maxf(0.001, lurk_duration)))
		var eye_pos := facing * (body_radius * 0.34) + side * 2.0
		var glow_pulse := 0.4 + 0.6 * sin(float(Time.get_ticks_msec()) * 0.012)
		var eye_glow_alpha := 0.3 + tension_t * 0.5 + glow_pulse * 0.2
		draw_circle(eye_pos, 3.2, Color(1.0, 0.32, 0.2, eye_glow_alpha))
		draw_circle(eye_pos, 2.4, Color(1.0, 0.32, 0.2, eye_glow_alpha * 0.6))

	# Predatory aura during lurk — growing threat indicator
	if lurker_state == STATE_LURK:
		var tension_t := 1.0 - (state_time_left / maxf(0.001, lurk_duration))
		# Growing hunting aura
		var hunt_aura_alpha := 0.08 + tension_t * 0.16
		draw_circle(Vector2.ZERO, body_radius + 7.0, Color(1.0, 0.32, 0.2, hunt_aura_alpha))
		# Growing ring telegraph for the pounce
		var ring_radius := body_radius + 6.0 + tension_t * 12.0
		var ring_alpha := 0.42 + tension_t * 0.48
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, Color(1.0, 0.68, 0.28, ring_alpha), 2.6)

	# Speed streaks on lunge — motion blur on strike state
	if lurker_state == STATE_STRIKE and speed_t > 0.5:
		var streak_alpha := 0.12 + speed_t * 0.18
		draw_circle(-facing * (body_radius + 3.0), body_radius * 0.7, Color(0.86, 0.16, 0.2, streak_alpha * 0.6))
		draw_circle(-facing * (body_radius + 8.0), body_radius * 0.5, Color(0.72, 0.12, 0.16, streak_alpha * 0.3))

	_draw_slow_indicator(body_radius)
