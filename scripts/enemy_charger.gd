extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_SEEK := 0
const STATE_WINDUP := 1
const STATE_CHARGE := 2
const STATE_RECOVER := 3

@export var seek_speed: float = 92.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var stop_distance: float = 8.0
@export var trigger_range: float = 180.0
@export var windup_time: float = 0.75
@export var charge_speed: float = 410.0
@export var charge_time: float = 0.34
@export var recover_time: float = 0.6
@export var charge_cooldown: float = 1.8
@export var charge_damage: int = 18
@export var path_width: float = 26.0

var attack_cooldown_left: float = 0.0
var charger_state: int = STATE_SEEK
var charger_state_time_left: float = 0.0
var charger_charge_direction: Vector2 = Vector2.LEFT
var charger_charge_preview_length: float = 0.0
var charger_charge_hit_applied: bool = false
var charge_enemy_exceptions: Dictionary = {}

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	_process_state_machine(delta)

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _process_state_machine(delta: float) -> void:
	if charger_state != STATE_CHARGE and not charge_enemy_exceptions.is_empty():
		_clear_charge_enemy_collision_exceptions()

	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	if charger_state == STATE_SEEK:
		_process_seek_state(delta)
		return

	if charger_state == STATE_WINDUP:
		_process_windup_state(delta)
		return

	if charger_state == STATE_CHARGE:
		_process_charge_state(delta)
		return

	_process_recover_state(delta)

func _get_seek_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length() <= stop_distance:
		return Vector2.ZERO
	return to_target.normalized() * seek_speed

func _process_seek_state(delta: float) -> void:
	var desired_velocity := _get_seek_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	if attack_cooldown_left <= 0.0 and global_position.distance_to(target.global_position) <= trigger_range:
		_enter_windup_state()

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	charger_state_time_left = maxf(0.0, charger_state_time_left - delta)
	if charger_state_time_left <= 0.0:
		_enter_charge_state()

func _process_charge_state(delta: float) -> void:
	_sync_charge_enemy_collision_exceptions()
	velocity = charger_charge_direction * charge_speed
	move_and_slide()
	_try_apply_charge_hit()
	charger_state_time_left = maxf(0.0, charger_state_time_left - delta)
	if charger_state_time_left <= 0.0:
		_enter_recover_state()

func _process_recover_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	charger_state_time_left = maxf(0.0, charger_state_time_left - delta)
	if charger_state_time_left <= 0.0:
		charger_state = STATE_SEEK

func _enter_windup_state() -> void:
	charger_state = STATE_WINDUP
	charger_state_time_left = windup_time
	charger_charge_hit_applied = false
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		charger_charge_direction = to_target.normalized()
	if charger_charge_direction.length_squared() <= 0.000001:
		charger_charge_direction = visual_facing_direction
	charger_charge_preview_length = charge_speed * charge_time
	visual_facing_direction = charger_charge_direction
	queue_redraw()

func _enter_charge_state() -> void:
	charger_state = STATE_CHARGE
	charger_state_time_left = charge_time
	visual_facing_direction = charger_charge_direction
	_sync_charge_enemy_collision_exceptions()
	queue_redraw()

func _enter_recover_state() -> void:
	charger_state = STATE_RECOVER
	charger_state_time_left = recover_time
	attack_cooldown_left = charge_cooldown
	velocity *= 0.25
	_clear_charge_enemy_collision_exceptions()
	queue_redraw()

func _sync_charge_enemy_collision_exceptions() -> void:
	var seen_ids: Dictionary = {}
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is PhysicsBody2D):
			continue
		var enemy_body := enemy_node as PhysicsBody2D
		if enemy_body == self:
			continue
		var enemy_id := enemy_body.get_instance_id()
		seen_ids[enemy_id] = true
		if charge_enemy_exceptions.has(enemy_id):
			continue
		add_collision_exception_with(enemy_body)
		charge_enemy_exceptions[enemy_id] = enemy_body

	for enemy_id in charge_enemy_exceptions.keys():
		if seen_ids.has(enemy_id):
			continue
		var enemy_ref = charge_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var existing: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if existing != null:
				remove_collision_exception_with(existing)
		charge_enemy_exceptions.erase(enemy_id)

func _clear_charge_enemy_collision_exceptions() -> void:
	for enemy_id in charge_enemy_exceptions.keys():
		var enemy_ref = charge_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var enemy_body: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if enemy_body != null:
				remove_collision_exception_with(enemy_body)
	charge_enemy_exceptions.clear()

func _try_apply_charge_hit() -> void:
	if charger_charge_hit_applied:
		return
	if not is_instance_valid(target):
		return
	if not DAMAGEABLE.can_take_damage(target):
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			DAMAGEABLE.apply_damage(target, charge_damage, {"source": "enemy_contact", "ability": "charger_charge"})
			charger_charge_hit_applied = true
			attack_anim_time_left = attack_anim_duration
			queue_redraw()
			return

	if global_position.distance_to(target.global_position) <= path_width:
		DAMAGEABLE.apply_damage(target, charge_damage, {"source": "enemy_contact", "ability": "charger_charge"})
		charger_charge_hit_applied = true
		attack_anim_time_left = attack_anim_duration
		queue_redraw()

func _distance_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.000001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_to(closest)

func _update_visual_facing_direction() -> void:
	if charger_state == STATE_WINDUP or charger_state == STATE_CHARGE:
		if charger_charge_direction.length_squared() > 0.000001:
			visual_facing_direction = charger_charge_direction
		queue_redraw()
		return

	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.28)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	queue_redraw()

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var body_radius := 13.0 + attack_pulse
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var body_color := COLOR_CHARGER_BODY
	var core_color := COLOR_CHARGER_CORE

	if charger_state == STATE_WINDUP:
		var windup_phase := 1.0 - (charger_state_time_left / windup_time) if windup_time > 0.0 else 1.0
		var pulse := 0.45 + sin(windup_phase * PI * 4.0) * 0.25
		body_color = Color(1.0, 0.72, 0.25 + pulse * 0.1, 1.0)
	if charger_state == STATE_CHARGE:
		body_color = Color(1.0, 0.86, 0.35, 1.0)
		core_color = COLOR_CHARGER_CORE_CHARGED
		body_radius += 0.7

	_draw_common_body(body_radius, body_color, core_color, facing)

	# Ram plate and side bars keep charger silhouette distinct from other melee roles.
	var ram_tip := facing * (body_radius + 11.5)
	var ram_base := facing * (body_radius + 2.0)
	var ram_w := 6.4
	var ram_color := Color(1.0, 0.9, 0.54, 0.9)
	if charger_state == STATE_CHARGE:
		ram_color = Color(1.0, 0.98, 0.74, 0.98)
	var ram_plate := PackedVector2Array([ram_tip, ram_base + side * ram_w, ram_base - side * ram_w])
	draw_colored_polygon(ram_plate, ram_color)
	draw_line(ram_base + side * (ram_w + 2.0), ram_base + side * (ram_w + 2.0) - facing * 6.0, Color(1.0, 0.86, 0.44, 0.75), 1.8)
	draw_line(ram_base - side * (ram_w + 2.0), ram_base - side * (ram_w + 2.0) - facing * 6.0, Color(1.0, 0.86, 0.44, 0.75), 1.8)

	if charger_state == STATE_WINDUP:
		var preview_start := facing * (body_radius + 4.0)
		var preview_end := preview_start + facing * charger_charge_preview_length
		var windup_phase := 1.0 - (charger_state_time_left / windup_time) if windup_time > 0.0 else 1.0
		
		# Pulsing charge indicator (shows power building)
		var charge_pulse := 0.5 + 0.5 * sin(windup_phase * PI * 3.0)
		var glow_radius := body_radius + 8.0 + charge_pulse * 4.0
		draw_circle(Vector2.ZERO, glow_radius, Color(1.0, 0.82, 0.35, 0.08 * charge_pulse))
		
		var preview_side := Vector2(-facing.y, facing.x)
		var preview_impact := preview_end
		var lane_width_start := 6.0 + charge_pulse * 1.5
		var lane_width_end := 14.0 + charge_pulse * 4.0
		var telegraph_lane := PackedVector2Array([
			preview_start + preview_side * lane_width_start,
			preview_impact + preview_side * lane_width_end,
			preview_impact - preview_side * lane_width_end,
			preview_start - preview_side * lane_width_start
		])
		var telegraph_core := PackedVector2Array([
			preview_start + preview_side * 1.8,
			preview_impact + preview_side * (3.0 + charge_pulse * 1.2),
			preview_impact - preview_side * (3.0 + charge_pulse * 1.2),
			preview_start - preview_side * 1.8
		])
		
		# Soft lane glow reads as energy in space instead of a rigid beam.
		draw_colored_polygon(telegraph_lane, Color(1.0, 0.76, 0.28, 0.12 + charge_pulse * 0.08))
		draw_colored_polygon(telegraph_core, Color(1.0, 0.94, 0.7, 0.18 + charge_pulse * 0.08))
		draw_polyline(PackedVector2Array([
			preview_start + preview_side * lane_width_start,
			preview_impact + preview_side * lane_width_end
		]), Color(1.0, 0.86, 0.42, 0.3 + charge_pulse * 0.16), 1.5)
		draw_polyline(PackedVector2Array([
			preview_start - preview_side * lane_width_start,
			preview_impact - preview_side * lane_width_end
		]), Color(1.0, 0.86, 0.42, 0.3 + charge_pulse * 0.16), 1.5)
		
		# Impact halo and brackets make the endpoint feel like a danger zone.
		var impact_radius := 11.0 + charge_pulse * 5.0
		draw_circle(preview_impact, impact_radius, Color(1.0, 0.78, 0.32, 0.08 + charge_pulse * 0.06))
		draw_arc(preview_impact, impact_radius, 0.0, TAU, 30, Color(1.0, 0.9, 0.54, 0.48 + charge_pulse * 0.18), 2.0)
		var accent_len := 11.0
		draw_line(preview_impact + preview_side * (lane_width_end - 2.0), preview_impact + preview_side * (lane_width_end - 2.0) - facing * accent_len, Color(1.0, 0.9, 0.54, 0.62), 1.6)
		draw_line(preview_impact - preview_side * (lane_width_end - 2.0), preview_impact - preview_side * (lane_width_end - 2.0) - facing * accent_len, Color(1.0, 0.9, 0.54, 0.62), 1.6)
