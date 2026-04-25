extends "res://scripts/enemy_base.gd"

const SLAM_STATE_IDLE := 0
const SLAM_STATE_WINDUP := 1
const SLAM_STATE_THUMP := 2
const SLAM_STATE_RECOVER := 3

@export var move_speed: float = 46.0
@export var acceleration: float = 560.0
@export var deceleration: float = 900.0
@export var preferred_distance: float = 54.0
@export var distance_tolerance: float = 10.0
@export var attack_range: float = 31.0
@export var attack_damage: int = 14
@export var attack_interval: float = 1.05
@export var slam_trigger_range: float = 220.0
@export var slam_windup_time: float = 0.7
@export var slam_thump_time: float = 0.28
@export var slam_recover_time: float = 0.65
@export var slam_cooldown: float = 3.4
@export var slam_damage: int = 34
@export var slam_radius: float = 92.0
@export var shield_damage_reduction: float = 0.8
@export var shield_protection_angle_degrees: float = 60.0
@export var shield_reaim_interval: float = 0.9
@export var shield_turn_speed: float = 0.08
@export var shield_attack_reaim_blend: float = 0.45
@export var shield_max_health: int = 108
@export var body_size_scale: float = 1.22

var attack_cooldown_left: float = 0.0
var slam_cooldown_left: float = 0.0
var slam_state: int = SLAM_STATE_IDLE
var slam_state_time_left: float = 0.0
var slam_direction: Vector2 = Vector2.LEFT
var slam_hit_applied: bool = false
var shield_facing: Vector2 = Vector2.LEFT
var shield_target_facing: Vector2 = Vector2.LEFT
var shield_reaim_left: float = 0.0

func _ready() -> void:
	max_health = shield_max_health
	super._ready()
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 13.0 * body_size_scale
				break
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			shield_facing = to_target.normalized()
			shield_target_facing = shield_facing

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	_update_slam_cooldown(delta)
	_update_shield_reaim(delta)
	_update_shield_facing(delta)

	if slam_state == SLAM_STATE_WINDUP:
		_process_slam_windup(delta)
		return
	if slam_state == SLAM_STATE_THUMP:
		_process_slam_thump(delta)
		return
	if slam_state == SLAM_STATE_RECOVER:
		_process_slam_recover(delta)
		return

	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_start_slam()
	_try_attack_target()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _update_slam_cooldown(delta: float) -> void:
	if slam_cooldown_left > 0.0:
		slam_cooldown_left = maxf(0.0, slam_cooldown_left - delta)

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
	if slam_state != SLAM_STATE_IDLE:
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

	target.call("take_damage", attack_damage, {"source": "enemy_contact"})
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _try_start_slam() -> void:
	if not is_instance_valid(target):
		return
	if slam_state != SLAM_STATE_IDLE:
		return
	if slam_cooldown_left > 0.0:
		return
	var to_target := target.global_position - global_position
	var target_distance := to_target.length()
	if target_distance > slam_trigger_range:
		return
	if target_distance <= attack_range + 10.0:
		return
	if to_target.length_squared() <= 0.000001:
		return
	slam_direction = to_target.normalized()
	slam_state = SLAM_STATE_WINDUP
	slam_state_time_left = slam_windup_time
	slam_hit_applied = false
	velocity = Vector2.ZERO
	visual_facing_direction = slam_direction
	shield_target_facing = slam_direction
	queue_redraw()

func _process_slam_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			slam_direction = to_target.normalized()
			visual_facing_direction = slam_direction
			shield_target_facing = slam_direction
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	queue_redraw()
	if slam_state_time_left <= 0.0:
		slam_state = SLAM_STATE_THUMP
		slam_state_time_left = slam_thump_time
		slam_hit_applied = false
		attack_anim_time_left = attack_anim_duration

func _process_slam_thump(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_try_apply_slam_aoe_hit()
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	queue_redraw()
	if slam_state_time_left <= 0.0:
		slam_state = SLAM_STATE_RECOVER
		slam_state_time_left = slam_recover_time
		slam_cooldown_left = slam_cooldown

func _process_slam_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	if slam_state_time_left <= 0.0:
		slam_state = SLAM_STATE_IDLE

func _try_apply_slam_aoe_hit() -> void:
	if slam_hit_applied:
		return
	if not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	if global_position.distance_to(target.global_position) <= slam_radius:
		target.call("take_damage", slam_damage, {"source": "enemy_ability", "ability": "shielder_slam"})
		slam_hit_applied = true
		# Heavy impact feedback for slam ability
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null and feedback.has_method("play_impact_heavy"):
				feedback.play_impact_heavy(target.global_position, slam_radius * 0.95)

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
	var body_radius := 13.0 * body_size_scale + attack_pulse
	var body_color := COLOR_SHIELDER_BODY
	var core_color := COLOR_SHIELDER_CORE
	if slam_state == SLAM_STATE_WINDUP:
		body_color = COLOR_SHIELDER_BODY_WINDUP
	if slam_state == SLAM_STATE_THUMP:
		body_color = COLOR_SHIELDER_BODY_THUMP
		core_color = COLOR_SHIELDER_CORE_THUMP
	_draw_common_body(body_radius, body_color, core_color, visual_facing_direction)

	if slam_state == SLAM_STATE_WINDUP:
		var windup_t := 1.0 - (slam_state_time_left / slam_windup_time) if slam_windup_time > 0.0 else 1.0
		var warning_alpha := 0.28 + windup_t * 0.45
		# Pulsing glow
		var glow_pulse := 0.5 + 0.5 * sin(windup_t * PI * 2.0)
		draw_circle(Vector2.ZERO, slam_radius, Color(COLOR_SHIELDER_SLAM_WARNING_GLOW.r, COLOR_SHIELDER_SLAM_WARNING_GLOW.g, COLOR_SHIELDER_SLAM_WARNING_GLOW.b, warning_alpha * (0.7 + glow_pulse * 0.3)))
		# Inner danger ring
		draw_arc(Vector2.ZERO, slam_radius * 0.6, 0.0, TAU, 42, Color(COLOR_SHIELDER_SLAM_WARNING_RING.r, COLOR_SHIELDER_SLAM_WARNING_RING.g, COLOR_SHIELDER_SLAM_WARNING_RING.b, warning_alpha * 0.6), 2.0)
		# Outer danger ring (pulsing)
		var ring_width := 3.0 + glow_pulse * 2.0
		draw_arc(Vector2.ZERO, slam_radius, 0.0, TAU, 52, Color(COLOR_SHIELDER_SLAM_WARNING_RING.r, COLOR_SHIELDER_SLAM_WARNING_RING.g, COLOR_SHIELDER_SLAM_WARNING_RING.b, warning_alpha), ring_width)
	if slam_state == SLAM_STATE_THUMP:
		var thump_t := 1.0 - (slam_state_time_left / slam_thump_time) if slam_thump_time > 0.0 else 1.0
		var shock_radius := lerpf(body_radius + 6.0, slam_radius, clampf(thump_t, 0.0, 1.0))
		# Main impact glow
		var impact_glow_alpha := clampf(1.0 - thump_t * 1.2, 0.0, 1.0)
		draw_circle(Vector2.ZERO, shock_radius, Color(COLOR_SHIELDER_SLAM_SHOCK_GLOW.r, COLOR_SHIELDER_SLAM_SHOCK_GLOW.g, COLOR_SHIELDER_SLAM_SHOCK_GLOW.b, impact_glow_alpha * 0.3))
		# Expanding shock ring (main impact)
		draw_arc(Vector2.ZERO, shock_radius, 0.0, TAU, 52, Color(COLOR_SHIELDER_SLAM_SHOCK_RING.r, COLOR_SHIELDER_SLAM_SHOCK_RING.g, COLOR_SHIELDER_SLAM_SHOCK_RING.b, impact_glow_alpha * 0.9), 5.0)
		# Secondary fading ring (layered impact effect)
		var secondary_radius := shock_radius * 1.15
		var secondary_alpha := clampf((0.6 - thump_t) * 1.5, 0.0, 0.6)
		draw_arc(Vector2.ZERO, secondary_radius, 0.0, TAU, 48, Color(COLOR_SHIELDER_SLAM_SHOCK_RING.r, COLOR_SHIELDER_SLAM_SHOCK_RING.g, COLOR_SHIELDER_SLAM_SHOCK_RING.b, secondary_alpha), 2.0)
	
	if not _is_finite_vec2(shield_facing) or shield_facing.length_squared() <= 0.000001:
		shield_facing = Vector2.LEFT

	# Draw shield
	var facing := shield_facing.normalized()
	var shield_arm := facing * (body_radius + 14.0 * body_size_scale)
	var shield_perp := Vector2(-facing.y, facing.x)
	var shield_width := 18.0 * body_size_scale
	var shield_left := shield_arm + shield_perp * (shield_width * 0.5)
	var shield_right := shield_arm - shield_perp * (shield_width * 0.5)
	var shield_points := PackedVector2Array([
		shield_arm,
		shield_left,
		shield_right
	])
	var shield_outline_color := COLOR_SHIELDER_SHIELD_OUTLINE
	var shield_fill_color := COLOR_SHIELDER_SHIELD
	if slam_state == SLAM_STATE_WINDUP:
		shield_fill_color = Color(1.0, 0.8, 0.4, 0.95)
		shield_outline_color = Color(1.0, 0.92, 0.66, 0.82)
	elif slam_state == SLAM_STATE_THUMP:
		shield_fill_color = Color(1.0, 0.9, 0.58, 0.98)
		shield_outline_color = Color(1.0, 0.96, 0.78, 0.9)
	if _is_finite_vec2(shield_arm) and _is_finite_vec2(shield_left) and _is_finite_vec2(shield_right):
		var tri_area := absf((shield_left - shield_arm).cross(shield_right - shield_arm))
		if tri_area > 0.001:
			draw_colored_polygon(shield_points, shield_fill_color)
			draw_line(shield_left, shield_right, shield_outline_color, 1.4)
			draw_line(shield_arm, shield_left, shield_outline_color, 1.4)
			draw_line(shield_arm, shield_right, shield_outline_color, 1.4)

			# Shield boss dot clarifies facing at a glance.
			var boss_center := shield_arm - facing * 3.2
			draw_circle(boss_center, 2.8, Color(1.0, 0.95, 0.82, 0.84))

func _is_finite_vec2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)
