extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_BEAM := 2
const STATE_RECOVER := 3

@export var move_speed: float = 96.0
@export var acceleration: float = 820.0
@export var deceleration: float = 1140.0
@export var preferred_range: float = 176.0
@export var range_tolerance: float = 40.0
@export var beam_thickness: float = 18.0
@export var beam_damage: int = 9
@export var beam_tick_interval: float = 0.34
@export var beam_windup_time: float = 0.78
@export var beam_duration: float = 2.1
@export var beam_cooldown: float = 3.0
@export var recover_time: float = 0.38

var tether_state: int = STATE_STALK
var state_time_left: float = 0.0
var beam_cooldown_left: float = 0.0
var beam_tick_left: float = 0.0
var beam_partner: CharacterBody2D
var _orbit_sign: float = 1.0

func _ready() -> void:
	super()
	max_health = 84
	crowd_separation_radius = 62.0
	crowd_separation_strength = 90.0
	_orbit_sign = 1.0 if int(get_instance_id()) % 2 == 0 else -1.0

func is_tether_enemy() -> bool:
	return true

func is_beam_state_active() -> bool:
	return tether_state == STATE_BEAM

func _process_behavior(delta: float) -> void:
	if beam_cooldown_left > 0.0:
		beam_cooldown_left = maxf(0.0, beam_cooldown_left - delta)
	beam_partner = _find_beam_partner()
	match tether_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_BEAM:
			_process_beam(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _find_beam_partner() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not (enemy is CharacterBody2D):
			continue
		var enemy_body := enemy as CharacterBody2D
		if not enemy_body.has_method("is_tether_enemy"):
			continue
		if not bool(enemy_body.call("is_tether_enemy")):
			continue
		var distance := global_position.distance_to(enemy_body.global_position)
		if distance >= nearest_distance:
			continue
		nearest = enemy_body
		nearest_distance = distance
	return nearest

func _is_primary_pair() -> bool:
	return is_instance_valid(beam_partner) and get_instance_id() < beam_partner.get_instance_id()

func _process_stalk(delta: float) -> void:
	var desired := _orbit_desired_velocity() * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	if beam_cooldown_left <= 0.0 and _is_primary_pair():
		_enter_windup_state()

func _orbit_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length_squared() <= 0.000001:
		return Vector2.ZERO
	var dir := to_target.normalized()
	var tangent := Vector2(-dir.y, dir.x) * _orbit_sign
	var dist := to_target.length()
	if dist < preferred_range - range_tolerance:
		return (-dir + tangent * 0.48).normalized() * move_speed * 0.72
	if dist > preferred_range + range_tolerance:
		return (dir + tangent * 0.34).normalized() * move_speed
	return tangent * move_speed * 0.9

func _enter_windup_state() -> void:
	tether_state = STATE_WINDUP
	state_time_left = beam_windup_time
	velocity = Vector2.ZERO
	queue_redraw()

func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if not _is_primary_pair():
		tether_state = STATE_STALK
		beam_cooldown_left = 0.4
		return
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_beam_state()

func _enter_beam_state() -> void:
	tether_state = STATE_BEAM
	state_time_left = beam_duration
	beam_tick_left = 0.0
	queue_redraw()

func _process_beam(delta: float) -> void:
	velocity = velocity.move_toward(_orbit_desired_velocity() * 0.82 * slow_speed_mult, acceleration * delta)
	move_and_slide()
	if not _is_primary_pair():
		_enter_recover_state()
		return
	state_time_left = maxf(0.0, state_time_left - delta)
	beam_tick_left = maxf(0.0, beam_tick_left - delta)
	if beam_tick_left <= 0.0:
		beam_tick_left = beam_tick_interval
		_try_apply_beam_damage()
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_recover_state()

func _try_apply_beam_damage() -> void:
	if not is_instance_valid(target) or not is_instance_valid(beam_partner):
		return
	var closest := Geometry2D.get_closest_point_to_segment(target.global_position, global_position, beam_partner.global_position)
	if closest.distance_to(target.global_position) > beam_thickness:
		return
	if DAMAGEABLE.apply_damage(target, beam_damage, {"source": "enemy_ability", "ability": "tether_beam_tick"}):
		attack_anim_time_left = attack_anim_duration

func _enter_recover_state() -> void:
	tether_state = STATE_RECOVER
	state_time_left = recover_time
	beam_cooldown_left = beam_cooldown

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(_orbit_desired_velocity() * 0.4 * slow_speed_mult, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		tether_state = STATE_STALK

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 14.0 + attack_pulse + speed_t * 0.7
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var body_color := Color(0.3, 0.42, 0.92, 0.94)
	var core_color := Color(0.86, 0.92, 1.0, 0.94)
	var state_charge := 0.0
	var beam_link_active := tether_state == STATE_BEAM
	if not beam_link_active and is_instance_valid(beam_partner) and beam_partner.has_method("is_beam_state_active"):
		beam_link_active = bool(beam_partner.call("is_beam_state_active"))
	if tether_state == STATE_WINDUP:
		body_color = Color(0.4, 0.58, 1.0, 0.96)
		core_color = Color(1.0, 1.0, 1.0, 0.96)
		state_charge = 1.0 - clampf(state_time_left / maxf(0.001, beam_windup_time), 0.0, 1.0)
	elif beam_link_active:
		body_color = Color(0.22, 0.9, 0.96, 0.96)
		core_color = Color(0.94, 1.0, 1.0, 0.98)
		state_charge = 1.0
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
	var spin := float(Time.get_ticks_msec()) * 0.0011
	var has_partner := is_instance_valid(beam_partner)
	var link_factor := 0.0
	if has_partner:
		link_factor = 0.4
	if beam_link_active:
		link_factor = 1.0

	draw_circle(Vector2.ZERO, body_radius + 10.0, Color(body_color.r, body_color.g + 0.08, 1.0, 0.08 + pulse * 0.06 + link_factor * 0.1))
	draw_circle(Vector2.ZERO, body_radius + 6.2, Color(body_color.r, body_color.g, body_color.b, 0.11 + link_factor * 0.12))

	var shell := PackedVector2Array()
	var shell_points := 12
	for i in range(shell_points):
		var angle := float(i) / float(shell_points) * TAU
		var modulation := 1.2 if (i % 2) == 0 else -1.5
		var ripple := sin(angle * 3.0 + spin * 1.7) * 0.6
		var radius := body_radius + modulation + ripple
		shell.append(Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(shell, Color(body_color.r * 0.86, body_color.g * 0.9, body_color.b, 0.88))
	var closed_shell := shell.duplicate()
	closed_shell.append(shell[0])
	draw_polyline(closed_shell, Color(core_color.r, core_color.g, core_color.b, 0.84), 2.0, false)

	var core_pos := facing * 1.4
	draw_circle(core_pos, body_radius * 0.58, Color(core_color.r, core_color.g, core_color.b, 0.62 + state_charge * 0.2))
	draw_circle(core_pos, body_radius * 0.32 + pulse * 0.8, Color(1.0, 1.0, 1.0, 0.34 + link_factor * 0.22))

	for rune_i in range(3):
		var rune_angle := spin + float(rune_i) * TAU / 3.0
		var rune_dir := Vector2(cos(rune_angle), sin(rune_angle))
		var rune_a := rune_dir * (body_radius * 0.36)
		var rune_b := rune_dir * (body_radius + 3.0 + state_charge * 2.0)
		draw_line(rune_a, rune_b, Color(0.62, 0.94, 1.0, 0.64 + link_factor * 0.2), 1.9)

	var anchor_offset := 6.4 + state_charge * 1.2
	var anchor_alpha := 0.76 + link_factor * 0.2
	draw_circle(side * anchor_offset, 3.1, Color(0.68, 0.94, 1.0, anchor_alpha))
	draw_circle(-side * anchor_offset, 3.1, Color(0.68, 0.94, 1.0, anchor_alpha))
	draw_circle(side * anchor_offset, 1.5, Color(1.0, 1.0, 1.0, 0.72))
	draw_circle(-side * anchor_offset, 1.5, Color(1.0, 1.0, 1.0, 0.72))
	draw_line(side * (anchor_offset - 1.8), facing * 3.6, Color(0.62, 0.9, 1.0, 0.6), 1.4)
	draw_line(-side * (anchor_offset - 1.8), facing * 3.6, Color(0.62, 0.9, 1.0, 0.6), 1.4)

	draw_line(facing * (body_radius + 1.0), facing * (body_radius + 8.8), Color(0.86, 0.98, 1.0, 0.84), 1.9)
	draw_line(side * 4.7, side * 8.2 + facing * 3.9, Color(0.58, 0.9, 1.0, 0.74), 1.6)
	draw_line(-side * 4.7, -side * 8.2 + facing * 3.9, Color(0.58, 0.9, 1.0, 0.74), 1.6)

	if is_instance_valid(beam_partner):
		var partner_local := beam_partner.global_position - global_position
		var alpha := 0.22
		var width := 1.6
		if tether_state == STATE_WINDUP:
			alpha = 0.46
			width = 2.2
		elif beam_link_active:
			alpha = 0.9
			width = 4.4
		draw_line(Vector2.ZERO, partner_local, Color(0.46, 0.94, 1.0, alpha), width)
		draw_line(side * anchor_offset, partner_local, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
		draw_line(-side * anchor_offset, partner_local, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
		if beam_link_active:
			draw_line(Vector2.ZERO, partner_local, Color(0.92, 1.0, 1.0, 0.52), 1.8)
	_draw_slow_indicator(body_radius)