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
@export var partner_refresh_interval: float = 0.22
@export var partner_switch_margin: float = 34.0
@export var beam_thickness: float = 24.0
@export var beam_damage: int = 9
@export var beam_tick_interval: float = 0.2
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
var _partner_refresh_left: float = 0.0
var _last_beam_sample_target_position: Vector2 = Vector2.ZERO
var _has_last_beam_sample_target_position: bool = false
var _last_beam_sample_a: Vector2 = Vector2.ZERO
var _last_beam_sample_b: Vector2 = Vector2.ZERO
var _has_last_beam_sample_segment: bool = false

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

func is_on_kill_run() -> bool:
	if tether_state == STATE_BEAM or tether_state == STATE_WINDUP:
		return true
	if _is_valid_tether_partner(beam_partner) and beam_partner.has_method("is_beam_state_active") and bool(beam_partner.call("is_beam_state_active")):
		return true
	return false

func _process_behavior(delta: float) -> void:
	if beam_cooldown_left > 0.0:
		beam_cooldown_left = maxf(0.0, beam_cooldown_left - delta)
	_update_beam_partner(delta)
	match tether_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_BEAM:
			_process_beam(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _update_beam_partner(delta: float) -> void:
	_partner_refresh_left = maxf(0.0, _partner_refresh_left - delta)
	if tether_state == STATE_WINDUP or tether_state == STATE_BEAM:
		if _is_valid_tether_partner(beam_partner):
			return
		beam_partner = _find_beam_partner()
		return
	if _partner_refresh_left > 0.0 and _is_valid_tether_partner(beam_partner):
		return
	beam_partner = _find_beam_partner_with_hysteresis(beam_partner)
	_partner_refresh_left = partner_refresh_interval

func _is_valid_tether_partner(candidate: Variant) -> bool:
	if typeof(candidate) != TYPE_OBJECT:
		return false
	if not is_instance_valid(candidate):
		return false
	var candidate_body := candidate as CharacterBody2D
	if candidate_body == null:
		return false
	if candidate_body == self:
		return false
	if not candidate_body.has_method("is_tether_enemy"):
		return false
	return bool(candidate_body.call("is_tether_enemy"))

func _find_beam_partner_with_hysteresis(current_partner: Variant) -> CharacterBody2D:
	var nearest := _find_beam_partner()
	if not _is_valid_tether_partner(current_partner):
		return nearest
	var current_partner_body := current_partner as CharacterBody2D
	if current_partner_body == null:
		return nearest
	if nearest == null or nearest == current_partner:
		return current_partner_body
	var current_distance := global_position.distance_to(current_partner_body.global_position)
	var nearest_distance := global_position.distance_to(nearest.global_position)
	if nearest_distance + partner_switch_margin < current_distance:
		return nearest
	return current_partner_body

func _find_beam_partner() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy == self:
			continue
		var enemy_body := enemy as CharacterBody2D
		if enemy_body == null:
			continue
		if not _is_valid_tether_partner(enemy_body):
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
	var desired := _stalk_desired_velocity() * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	if beam_cooldown_left <= 0.0 and _is_primary_pair():
		_enter_windup_state()

func _stalk_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	if _is_valid_tether_partner(beam_partner) and beam_partner.has_method("is_beam_state_active") and bool(beam_partner.call("is_beam_state_active")):
		return _beam_crossing_support_velocity()
	return _web_desired_velocity()

func _beam_crossing_support_velocity() -> Vector2:
	var player_pos := target.global_position
	var partner_pos := beam_partner.global_position
	var from_partner := player_pos - partner_pos
	if from_partner.length_squared() <= 0.000001:
		return Vector2.ZERO
	var cross_anchor := player_pos + from_partner.normalized() * (preferred_range * 1.45)
	var to_cross := cross_anchor - global_position
	if to_cross.length_squared() <= 0.000001:
		return Vector2.ZERO
	return to_cross.normalized() * move_speed * slow_speed_mult

func _web_desired_velocity() -> Vector2:
	var player_pos := target.global_position
	var to_player := player_pos - global_position
	if to_player.length_squared() <= 0.000001:
		return Vector2.ZERO
	var player_dist := to_player.length()
	var to_player_dir := to_player / player_dist

	# Slots are anchored far out to fill the arena — not a ring around the player
	var ring_radius := preferred_range * 3.6
	var slot_target := _hivemind_slot_position(player_pos, ring_radius)
	var to_slot := slot_target - global_position
	var desired_vec := Vector2.ZERO
	if to_slot.length_squared() > 0.000001:
		desired_vec += to_slot.normalized() * 1.1

	# Repulsion from peers is the dominant spreading force
	desired_vec += _tether_group_repulsion()

	# Only hard-push if the player walks directly underneath
	if player_dist < preferred_range * 0.7:
		desired_vec += (-to_player_dir) * 2.2

	# Partner spacing — keep beam pairs linkable but not fused
	if _is_valid_tether_partner(beam_partner):
		var partner_dist := global_position.distance_to(beam_partner.global_position)
		var min_partner_dist := preferred_range * 1.2
		var max_partner_dist := preferred_range * 3.2
		if partner_dist < min_partner_dist:
			var away := global_position - beam_partner.global_position
			if away.length_squared() > 0.000001:
				desired_vec += (away / partner_dist) * 1.8
		elif partner_dist > max_partner_dist:
			var toward_partner := beam_partner.global_position - global_position
			if toward_partner.length_squared() > 0.000001:
				desired_vec += toward_partner.normalized() * 0.6

	if desired_vec.length_squared() <= 0.000001:
		return Vector2.ZERO
	return desired_vec.normalized() * move_speed

func _hivemind_slot_position(player_pos: Vector2, ring_radius: float) -> Vector2:
	var tether_total: int = _count_tether_enemies()
	var slot_count: int = clampi(tether_total, 4, 12)
	var slot_index: int = absi(int(get_instance_id())) % slot_count
	var time_s := float(Time.get_ticks_msec()) * 0.001
	# Each slot drifts on its own slow sine so slots don't all pulse in/out together
	var drift := 0.5 + 0.5 * sin(time_s * 0.55 + float(slot_index) * 1.1)
	var spread_mult := lerpf(0.7, 1.0, drift)
	var angle := (TAU * float(slot_index) / float(slot_count)) + sin(time_s * 0.3 + float(slot_index) * 0.9) * 0.22
	return player_pos + Vector2(cos(angle), sin(angle)) * ring_radius * spread_mult

func _count_tether_enemies() -> int:
	var total := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy_body := enemy as CharacterBody2D
		if enemy_body == null:
			continue
		if enemy_body == self:
			total += 1
			continue
		if not _is_valid_tether_partner(enemy_body):
			continue
		total += 1
	return maxi(1, total)

func _tether_group_repulsion() -> Vector2:
	# Kill-committed tethers (beaming or crossing support) don't get pushed off their aim.
	if is_on_kill_run():
		return Vector2.ZERO
	var repel_sum := Vector2.ZERO
	var contributors := 0
	var spacing_radius := preferred_range * 3.2
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy == self:
			continue
		var enemy_body := enemy as CharacterBody2D
		if enemy_body == null:
			continue
		if not _is_valid_tether_partner(enemy_body):
			continue
		var offset := global_position - enemy_body.global_position
		var distance := offset.length()
		if distance < 0.000001 or distance >= spacing_radius:
			continue
		var push_scale := clampf((spacing_radius - distance) / maxf(1.0, spacing_radius), 0.0, 1.0)
		# Idle tethers spread much harder away from kill-committed pairs.
		var enemy_on_kill_run := enemy_body.has_method("is_on_kill_run") and bool(enemy_body.call("is_on_kill_run"))
		var push_strength := 3.2 if enemy_on_kill_run else 2.4
		repel_sum += (offset / distance) * (push_strength * push_scale)
		contributors += 1
	if contributors <= 0:
		return Vector2.ZERO
	return repel_sum / float(contributors)

func _beam_aim_velocity() -> Vector2:
	if not is_instance_valid(target) or not _is_valid_tether_partner(beam_partner):
		return _orbit_desired_velocity()
	var player_pos := target.global_position
	var partner_pos := beam_partner.global_position
	var from_partner := player_pos - partner_pos
	if from_partner.length_squared() <= 0.000001:
		return _orbit_desired_velocity()
	# Move to the opposite side of the player from our partner so the beam segment crosses through them
	var aim_pos := player_pos + from_partner.normalized() * (preferred_range * 1.45)
	var to_aim := aim_pos - global_position
	if to_aim.length_squared() <= 0.000001:
		return Vector2.ZERO
	return to_aim.normalized() * move_speed * 1.1 * slow_speed_mult

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
	if is_instance_valid(target):
		_last_beam_sample_target_position = target.global_position
		_has_last_beam_sample_target_position = true
	else:
		_has_last_beam_sample_target_position = false
	if is_instance_valid(beam_partner):
		_last_beam_sample_a = global_position
		_last_beam_sample_b = beam_partner.global_position
		_has_last_beam_sample_segment = true
	else:
		_has_last_beam_sample_segment = false
	queue_redraw()

func _process_beam(delta: float) -> void:
	velocity = velocity.move_toward(_beam_aim_velocity(), acceleration * delta)
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
	var target_pos := target.global_position
	var current_beam_a := global_position
	var current_beam_b := beam_partner.global_position
	var sweep_start := target_pos
	if _has_last_beam_sample_target_position:
		sweep_start = _last_beam_sample_target_position
	var nearest_distance := _segment_to_segment_distance(sweep_start, target_pos, current_beam_a, current_beam_b)
	if _has_last_beam_sample_segment:
		nearest_distance = minf(nearest_distance, _moving_beam_sweep_nearest_distance(sweep_start, target_pos, _last_beam_sample_a, _last_beam_sample_b, current_beam_a, current_beam_b))
	_last_beam_sample_target_position = target_pos
	_has_last_beam_sample_target_position = true
	_last_beam_sample_a = current_beam_a
	_last_beam_sample_b = current_beam_b
	_has_last_beam_sample_segment = true
	if nearest_distance > beam_thickness:
		return
	if DAMAGEABLE.apply_damage(target, beam_damage, {"source": "enemy_ability", "ability": "tether_beam_tick"}):
		attack_anim_time_left = attack_anim_duration

func _distance_to_segment(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var closest := Geometry2D.get_closest_point_to_segment(point, seg_a, seg_b)
	return closest.distance_to(point)

func _segment_to_segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var nearest := _distance_to_segment(a0, b0, b1)
	nearest = minf(nearest, _distance_to_segment(a1, b0, b1))
	nearest = minf(nearest, _distance_to_segment(b0, a0, a1))
	nearest = minf(nearest, _distance_to_segment(b1, a0, a1))
	return nearest

func _moving_beam_sweep_nearest_distance(player_from: Vector2, player_to: Vector2, beam_prev_a: Vector2, beam_prev_b: Vector2, beam_current_a: Vector2, beam_current_b: Vector2) -> float:
	var player_path_length := player_from.distance_to(player_to)
	var beam_motion := maxf(beam_prev_a.distance_to(beam_current_a), beam_prev_b.distance_to(beam_current_b))
	var sample_budget := maxf(player_path_length, beam_motion)
	var sample_step := maxf(beam_thickness * 0.4, 6.0)
	var steps := maxi(2, mini(24, int(ceil(sample_budget / sample_step))))
	var nearest := INF
	for i in range(0, steps + 1):
		var t := float(i) / float(steps)
		var beam_a := beam_prev_a.lerp(beam_current_a, t)
		var beam_b := beam_prev_b.lerp(beam_current_b, t)
		nearest = minf(nearest, _segment_to_segment_distance(player_from, player_to, beam_a, beam_b))
	return nearest

func _enter_recover_state() -> void:
	tether_state = STATE_RECOVER
	state_time_left = recover_time
	beam_cooldown_left = beam_cooldown
	_has_last_beam_sample_target_position = false
	_has_last_beam_sample_segment = false

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
		var beam_visual_width := clampf(beam_thickness * 0.48, 3.6, 14.0)
		if tether_state == STATE_WINDUP:
			alpha = 0.46
			width = 2.2
		elif beam_link_active:
			alpha = 0.9
			width = beam_visual_width
		draw_line(Vector2.ZERO, partner_local, Color(0.46, 0.94, 1.0, alpha), width)
		draw_line(side * anchor_offset, partner_local, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
		draw_line(-side * anchor_offset, partner_local, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
		if beam_link_active:
			draw_line(Vector2.ZERO, partner_local, Color(0.92, 1.0, 1.0, 0.52), maxf(1.8, beam_visual_width * 0.34))
	_draw_slow_indicator(body_radius)
