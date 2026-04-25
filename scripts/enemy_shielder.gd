extends "res://scripts/enemy_base.gd"

@export var move_speed: float = 64.0
@export var acceleration: float = 700.0
@export var deceleration: float = 1200.0
@export var preferred_distance: float = 130.0
@export var distance_tolerance: float = 35.0
@export var attack_range: float = 45.0
@export var attack_damage: int = 8
@export var attack_interval: float = 1.2
@export var shield_damage_reduction: float = 0.75
@export var shield_protection_angle_degrees: float = 60.0
@export var shield_reaim_interval: float = 0.9
@export var shield_turn_speed: float = 0.08
@export var shield_attack_reaim_blend: float = 0.45
@export var shield_max_health: int = 65

var attack_cooldown_left: float = 0.0
var shield_facing: Vector2 = Vector2.LEFT
var shield_target_facing: Vector2 = Vector2.LEFT
var shield_reaim_left: float = 0.0

func _ready() -> void:
	max_health = shield_max_health
	super._ready()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			shield_facing = to_target.normalized()
			shield_target_facing = shield_facing

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	_update_shield_reaim(delta)
	_update_shield_facing(delta)
	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_attack_target()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _update_shield_reaim(delta: float) -> void:
	if shield_reaim_left > 0.0:
		shield_reaim_left = maxf(0.0, shield_reaim_left - delta)
	if shield_reaim_left > 0.0:
		return
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	if to_target.length_squared() <= 0.000001:
		return
	shield_target_facing = to_target.normalized()
	shield_reaim_left = shield_reaim_interval

func _update_shield_facing(delta: float) -> void:
	if shield_target_facing.length_squared() <= 0.000001:
		return
	var turn_alpha := clampf(shield_turn_speed * delta * 60.0, 0.0, 1.0)
	shield_facing = shield_facing.slerp(shield_target_facing, turn_alpha)

func _get_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	
	if dist <= preferred_distance - distance_tolerance:
		return -to_target.normalized() * move_speed  # Back away
	if dist >= preferred_distance + distance_tolerance:
		return to_target.normalized() * move_speed  # Move closer
	return Vector2.ZERO  # At ideal range

func _try_attack_target() -> void:
	if not is_instance_valid(target):
		return
	if attack_cooldown_left > 0.0:
		return
	if not target.has_method("take_damage"):
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	# Briefly re-align shield when committing to an attack, but do not perfect-track.
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		shield_target_facing = shield_facing.slerp(to_target.normalized(), clampf(shield_attack_reaim_blend, 0.0, 1.0))
		shield_reaim_left = maxf(shield_reaim_left, shield_reaim_interval * 0.6)

	target.call("take_damage", attack_damage)
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func take_damage(amount: int, damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return

	if bool(damage_context.get("is_ground_attack", false)):
		health_state.take_damage(amount)
		return
	
	# Compare the attacker direction against current shield-facing direction.
	var to_attacker := target.global_position - global_position if is_instance_valid(target) else Vector2.ZERO
	var attacker_dir := to_attacker.normalized() if to_attacker.length_squared() > 0.000001 else Vector2.LEFT
	
	var damage_from_shield_angle := acos(clampf(attacker_dir.dot(shield_facing), -1.0, 1.0))
	var shield_protection_angle := deg_to_rad(shield_protection_angle_degrees)
	
	var mitigated_damage := amount
	if damage_from_shield_angle < shield_protection_angle:
		# Damage from protected zone: 75% reduction (only 25% gets through)
		mitigated_damage = int(float(amount) * (1.0 - shield_damage_reduction))
	else:
		# Damage from unprotected side: full damage
		mitigated_damage = amount
	
	if mitigated_damage <= 0:
		return
	health_state.take_damage(mitigated_damage)

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var body_radius := 13.0 + attack_pulse
	var body_color := Color(0.96, 0.68, 0.26, 0.9)
	var core_color := Color(1.0, 0.82, 0.48, 0.8)
	_draw_common_body(body_radius, body_color, core_color, visual_facing_direction)
	
	# Draw shield
	var shield_arm := shield_facing * (body_radius + 12.0)
	var shield_perp := Vector2(-shield_facing.y, shield_facing.x)
	var shield_width := 16.0
	var shield_points := PackedVector2Array([
		shield_arm,
		shield_arm + shield_perp * (shield_width * 0.5),
		shield_arm - shield_perp * (shield_width * 0.5)
	])
	draw_colored_polygon(shield_points, Color(0.96, 0.74, 0.34, 0.86))
	
	# Shield outline
	var shield_outline_color := Color(1.0, 0.88, 0.6, 0.7)
	draw_line(shield_arm + shield_perp * (shield_width * 0.5), shield_arm - shield_perp * (shield_width * 0.5), shield_outline_color, 1.4)
	draw_line(shield_arm, shield_arm + shield_perp * (shield_width * 0.5), shield_outline_color, 1.4)
	draw_line(shield_arm, shield_arm - shield_perp * (shield_width * 0.5), shield_outline_color, 1.4)
