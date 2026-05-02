extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const PYRE_FIELD_SCRIPT := preload("res://scripts/pyre_field.gd")

@export var move_speed: float = 88.0
@export var acceleration: float = 860.0
@export var deceleration: float = 1180.0
@export var stop_distance: float = 28.0
@export var attack_range: float = 34.0
@export var contact_damage: int = 12
@export var attack_interval: float = 0.92
@export var death_field_radius: float = 84.0
@export var death_field_duration: float = 6.5
@export var death_field_tick_interval: float = 0.42
@export var death_field_tick_damage: int = 7

var attack_cooldown_left: float = 0.0

func _ready() -> void:
	super()
	max_health = 62
	crowd_separation_radius = 54.0
	crowd_separation_strength = 86.0

func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	var desired := Vector2.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length() > stop_distance:
			desired = to_target.normalized() * move_speed * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	_try_attack_target()

func _try_attack_target() -> void:
	if not is_instance_valid(target):
		return
	if attack_cooldown_left > 0.0:
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return
	if not DAMAGEABLE.apply_damage(target, contact_damage, {"source": "enemy_contact", "ability": "pyre_strike"}):
		return
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _on_health_state_died() -> void:
	_spawn_death_field()
	died.emit()
	queue_free()

func _spawn_death_field() -> void:
	if not is_instance_valid(get_parent()):
		return
	var field := PYRE_FIELD_SCRIPT.new()
	get_parent().add_child(field)
	field.global_position = global_position
	field.initialize(target, death_field_radius, death_field_duration, death_field_tick_interval, death_field_tick_damage)

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 14.6 + attack_pulse + speed_t * 0.85
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var time := float(Time.get_ticks_msec())
	var ember_pulse := 0.5 + 0.5 * sin(time * 0.007)
	var heat_pulse := 0.5 + 0.5 * sin(time * 0.011)
	var strike_readiness := 1.0 - clampf(attack_cooldown_left / maxf(0.001, attack_interval), 0.0, 1.0)
	var aura_alpha := 0.1 + ember_pulse * 0.05 + strike_readiness * 0.08
	draw_circle(Vector2.ZERO, body_radius + 13.0, Color(0.95, 0.34, 0.1, aura_alpha))
	draw_circle(Vector2.ZERO, body_radius + 8.4, Color(0.92, 0.44, 0.16, aura_alpha * 0.7))

	var prow := facing * (body_radius + 3.0)
	var shoulder_left := side * (body_radius * 1.05) + facing * (body_radius * 0.14)
	var shoulder_right := -side * (body_radius * 1.05) + facing * (body_radius * 0.14)
	var flank_left := side * (body_radius * 0.96) - facing * (body_radius * 0.58)
	var flank_right := -side * (body_radius * 0.96) - facing * (body_radius * 0.58)
	var rear_left := side * (body_radius * 0.54) - facing * (body_radius * 1.04)
	var rear_right := -side * (body_radius * 0.54) - facing * (body_radius * 1.04)
	var hull := PackedVector2Array([prow, shoulder_left, flank_left, rear_left, rear_right, flank_right, shoulder_right])
	draw_colored_polygon(hull, Color(0.18, 0.12, 0.08, 0.92))
	var closed_hull := hull.duplicate()
	closed_hull.append(hull[0])
	draw_polyline(closed_hull, Color(0.42, 0.28, 0.16, 0.84), 2.2, false)

	var chest_left := side * (body_radius * 0.66) + facing * (body_radius * 0.32)
	var chest_right := -side * (body_radius * 0.66) + facing * (body_radius * 0.32)
	var chest_bottom := -facing * (body_radius * 0.08)
	var chest_plate := PackedVector2Array([chest_left, prow * 0.88, chest_right, chest_bottom])
	draw_colored_polygon(chest_plate, Color(0.26, 0.18, 0.12, 0.78))

	var plate_left := PackedVector2Array([
		shoulder_left * 0.95,
		flank_left * 0.9 + facing * 0.8,
		rear_left * 0.88,
		flank_left * 0.78 - facing * 1.0
	])
	var plate_right := PackedVector2Array([
		shoulder_right * 0.95,
		flank_right * 0.9 + facing * 0.8,
		rear_right * 0.88,
		flank_right * 0.78 - facing * 1.0
	])
	draw_colored_polygon(plate_left, Color(0.13, 0.09, 0.06, 0.88))
	draw_colored_polygon(plate_right, Color(0.13, 0.09, 0.06, 0.88))

	for crack_i in range(6):
		var crack_ratio := 0.26 + float(crack_i) * 0.12
		var crack_base := prow.lerp((rear_left + rear_right) * 0.5, crack_ratio)
		var crack_span := 2.2 + float(crack_i) * 0.8
		var crack_shift := sin(time * 0.0004 + float(crack_i) * 1.6) * 0.7
		var a := crack_base + side * crack_span
		var b := crack_base + side * crack_shift + facing * 0.5
		var c := crack_base - side * crack_shift - facing * 0.7
		var d := crack_base - side * crack_span + facing * 0.3
		var seam := PackedVector2Array([a, b, c, d])
		draw_polyline(seam, Color(0.36, 0.24, 0.14, 0.6), 2.4)
		draw_polyline(seam, Color(0.98, 0.7, 0.3, 0.36 + heat_pulse * 0.18), 1.35)

	var core_pos := facing * 0.8
	draw_circle(core_pos, body_radius * 0.56, Color(0.96, 0.52, 0.16, 0.74 + heat_pulse * 0.16 + strike_readiness * 0.08))
	draw_circle(core_pos, body_radius * 0.3, Color(1.0, 0.78, 0.34, 0.62 + heat_pulse * 0.16))
	draw_circle(core_pos, body_radius * 0.14 + heat_pulse * 0.5, Color(1.0, 0.94, 0.64, 0.56 + strike_readiness * 0.22))

	var eye_forward := facing * (body_radius * 0.24)
	var eye_offset := side * (body_radius * 0.44)
	var eye_radius := 2.6 + heat_pulse * 0.45
	var left_eye := eye_forward + eye_offset
	var right_eye := eye_forward - eye_offset
	draw_circle(left_eye, eye_radius + 1.2, Color(0.98, 0.64, 0.24, 0.28 + strike_readiness * 0.16))
	draw_circle(right_eye, eye_radius + 1.2, Color(0.98, 0.64, 0.24, 0.28 + strike_readiness * 0.16))
	draw_circle(left_eye, eye_radius, Color(1.0, 0.86, 0.46, 0.84))
	draw_circle(right_eye, eye_radius, Color(1.0, 0.86, 0.46, 0.84))
	draw_circle(left_eye, eye_radius * 0.42, Color(1.0, 0.98, 0.78, 0.72))
	draw_circle(right_eye, eye_radius * 0.42, Color(1.0, 0.98, 0.78, 0.72))

	var vent_left := side * (body_radius * 0.78) - facing * (body_radius * 0.36)
	var vent_right := -side * (body_radius * 0.78) - facing * (body_radius * 0.36)
	draw_line(vent_left, vent_left + facing * 4.6, Color(0.88, 0.56, 0.22, 0.62), 1.7)
	draw_line(vent_right, vent_right + facing * 4.6, Color(0.88, 0.56, 0.22, 0.62), 1.7)

	for ember_i in range(5):
		var ember_phase := time * 0.0011 + float(ember_i) * 1.37 + float(get_instance_id() % 31)
		var ember_dir := (facing * 0.55 + Vector2(cos(ember_phase), sin(ember_phase)) * 0.6).normalized()
		var ember_pos := core_pos + ember_dir * (2.2 + float(ember_i) * 1.55 + ember_pulse * 1.1)
		var ember_radius := 0.9 + float(ember_i) * 0.22
		var ember_alpha := (0.5 - float(ember_i) * 0.07) * (0.62 + ember_pulse * 0.42)
		draw_circle(ember_pos, ember_radius, Color(1.0, 0.74, 0.3, ember_alpha))

	draw_line(facing * (body_radius + 1.0), facing * (body_radius + 8.0), Color(1.0, 0.88, 0.56, 0.86), 2.3)
	draw_line(side * 4.8, side * 8.4 + facing * 3.8, Color(0.86, 0.56, 0.24, 0.74), 1.8)
	draw_line(-side * 4.8, -side * 8.4 + facing * 3.8, Color(0.86, 0.56, 0.24, 0.74), 1.8)

	if strike_readiness > 0.01:
		draw_circle(Vector2.ZERO, body_radius + 9.2 + heat_pulse * 0.8, Color(0.98, 0.58, 0.18, strike_readiness * 0.12))
	_draw_mutator_overlay(body_radius)
	_draw_slow_indicator(body_radius)