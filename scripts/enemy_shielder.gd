extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ENEMY_STATE_ENUMS := preload("res://scripts/shared/enemy_state_enums.gd")

@export var move_speed: float = 50.0
@export var acceleration: float = 560.0
@export var deceleration: float = 900.0
@export var preferred_distance: float = 54.0
@export var distance_tolerance: float = 10.0
@export var attack_range: float = 31.0
@export var damage: int = 14
@export var attack_interval: float = 1.05
@export var slam_trigger_range: float = 195.0
@export var slam_windup_time: float = 0.88
@export var slam_thump_time: float = 0.28
@export var slam_recover_time: float = 0.65
@export var slam_cooldown: float = 3.8
@export var slam_damage: int = 28
@export var slam_radius: float = 92.0
@export var shield_damage_reduction: float = 0.8
@export var shield_protection_angle_degrees: float = 60.0
@export var shield_reaim_interval: float = 0.9
@export var shield_turn_speed: float = 0.08
@export var shield_attack_reaim_blend: float = 0.45
@export var shield_max_health: int = 108
@export var body_size_scale: float = 1.22
@export var shield_length: float = 16.0
@export var shield_width: float = 24.0
@export var body_check_damage: int = 8
@export var body_check_cooldown: float = 0.85
@export var body_check_shove_force: float = 450.0
@export var body_check_overlap_padding: float = 4.0
@export var body_check_trigger_margin: float = 5.0
@export var body_check_post_dash_immunity: float = 0.15
@export var body_check_min_approach_speed: float = 0.0
@export var body_check_anim_duration: float = 0.35

var attack_cooldown_left: float = 0.0
var slam_cooldown_left: float = 0.0
var slam_state: int = ENEMY_STATE_ENUMS.ShielderSlamState.IDLE
var slam_state_time_left: float = 0.0
var slam_direction: Vector2 = Vector2.LEFT
var slam_hit_applied: bool = false
var shield_facing: Vector2 = Vector2.LEFT
var shield_target_facing: Vector2 = Vector2.LEFT
var shield_reaim_left: float = 0.0
var body_check_cooldown_left: float = 0.0
var body_check_anim_time_left: float = 0.0
var body_check_dash_immunity_left: float = 0.0
var player_was_dashing_last_frame: bool = false
var _attack_sync_was_active: bool = false
var _shielder_visual_redraw_left: float = 0.0

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
	_update_body_check_cooldown(delta)
	_update_body_check_anim(delta)
	_update_body_check_dash_immunity(delta)
	_update_shield_reaim(delta)
	_update_shield_facing(delta)

	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.WINDUP:
		_process_slam_windup(delta)
		return
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.THUMP:
		_process_slam_thump(delta)
		return
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.RECOVER:
		_process_slam_recover(delta)
		return

	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_body_check_target()
	_try_start_slam()
	_try_attack_target()


func should_force_network_runtime_state_sampling() -> bool:
	return slam_state != ENEMY_STATE_ENUMS.ShielderSlamState.IDLE or body_check_anim_time_left > 0.0 or attack_anim_time_left > 0.0


func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and (slam_state != ENEMY_STATE_ENUMS.ShielderSlamState.IDLE or body_check_anim_time_left > 0.0 or attack_anim_time_left > 0.0)


func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active := slam_state != ENEMY_STATE_ENUMS.ShielderSlamState.IDLE or body_check_anim_time_left > 0.0 or attack_anim_time_left > 0.0
	if not active and not _attack_sync_was_active:
		return {}
	var payload := {
		"active": active,
		"slam_state": slam_state,
		"slam_state_time_left": slam_state_time_left,
		"slam_direction": slam_direction,
		"body_check_anim_time_left": body_check_anim_time_left,
		"attack_anim_time_left": attack_anim_time_left,
		"visual_facing_direction": visual_facing_direction,
		"shield_facing": shield_facing,
		"shield_target_facing": shield_target_facing
	}
	_attack_sync_was_active = active
	return payload


func _get_custom_network_runtime_state() -> Dictionary:
	return {}


func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	if sync_state.is_empty():
		return
	var active := bool(sync_state.get("active", false))
	if not active:
		slam_state = ENEMY_STATE_ENUMS.ShielderSlamState.IDLE
		slam_state_time_left = 0.0
		body_check_anim_time_left = 0.0
		attack_anim_time_left = 0.0
		queue_redraw()
		return
	slam_state = int(sync_state.get("slam_state", slam_state))
	slam_state_time_left = float(sync_state.get("slam_state_time_left", slam_state_time_left))
	slam_direction = sync_state.get("slam_direction", slam_direction) as Vector2
	body_check_anim_time_left = float(sync_state.get("body_check_anim_time_left", body_check_anim_time_left))
	attack_anim_time_left = float(sync_state.get("attack_anim_time_left", attack_anim_time_left))
	visual_facing_direction = sync_state.get("visual_facing_direction", visual_facing_direction) as Vector2
	shield_facing = sync_state.get("shield_facing", shield_facing) as Vector2
	shield_target_facing = sync_state.get("shield_target_facing", shield_target_facing) as Vector2
	queue_redraw()


func _process_network_visuals(delta: float) -> void:
	var changed := false
	if slam_state_time_left > 0.0:
		var prev_slam_left := slam_state_time_left
		slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
		if not is_equal_approx(prev_slam_left, slam_state_time_left):
			changed = true
	if body_check_anim_time_left > 0.0:
		var prev_body_check_anim_left := body_check_anim_time_left
		body_check_anim_time_left = maxf(0.0, body_check_anim_time_left - delta)
		if not is_equal_approx(prev_body_check_anim_left, body_check_anim_time_left):
			changed = true
	if changed:
		_queue_shielder_visual_redraw()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _update_slam_cooldown(delta: float) -> void:
	if slam_cooldown_left > 0.0:
		slam_cooldown_left = maxf(0.0, slam_cooldown_left - delta)

func _update_body_check_cooldown(delta: float) -> void:
	if body_check_cooldown_left > 0.0:
		body_check_cooldown_left = maxf(0.0, body_check_cooldown_left - delta)

func _update_body_check_anim(delta: float) -> void:
	if body_check_anim_time_left > 0.0:
		body_check_anim_time_left = maxf(0.0, body_check_anim_time_left - delta)
		_queue_shielder_visual_redraw()

func _queue_shielder_visual_redraw(force_immediate: bool = false) -> void:
	if force_immediate:
		_shielder_visual_redraw_left = 0.0
		queue_redraw()
		return
	if _shielder_visual_redraw_left > 0.0:
		return
	var interval := _get_shielder_visual_redraw_interval()
	_shielder_visual_redraw_left = interval
	queue_redraw()

func _get_shielder_visual_redraw_interval() -> float:
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.THUMP:
		return 0.012
	if _visual_lod_enemy_count >= 48:
		return 0.05
	if _visual_lod_enemy_count >= 32:
		return 0.038
	if _visual_lod_enemy_count >= 20:
		return 0.03
	return 0.02

func _update_body_check_dash_immunity(delta: float) -> void:
	if not is_instance_valid(target):
		player_was_dashing_last_frame = false
		return
	
	var target_body := target as CharacterBody2D
	if target_body == null:
		player_was_dashing_last_frame = false
		return
	
	var is_dashing_now := bool(target_body.get("dash_phasing_active"))
	
	# Detect transition from dashing to not dashing
	if player_was_dashing_last_frame and not is_dashing_now:
		body_check_dash_immunity_left = body_check_post_dash_immunity
	
	player_was_dashing_last_frame = is_dashing_now
	
	# Decrement immunity timer
	if body_check_dash_immunity_left > 0.0:
		body_check_dash_immunity_left = maxf(0.0, body_check_dash_immunity_left - delta)

func _update_shield_reaim(delta: float) -> void:
	if _shielder_visual_redraw_left > 0.0:
		_shielder_visual_redraw_left = maxf(0.0, _shielder_visual_redraw_left - delta)
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
	if slam_state != ENEMY_STATE_ENUMS.ShielderSlamState.IDLE:
		return
	if attack_cooldown_left > 0.0:
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	# Briefly re-align shield when committing to an attack, but do not perfect-track.
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		shield_target_facing = shield_facing.slerp(to_target.normalized(), clampf(shield_attack_reaim_blend, 0.0, 1.0))
		shield_reaim_left = maxf(shield_reaim_left, shield_reaim_interval * 0.6)

	if not DAMAGEABLE.apply_damage(target, damage, {"source": "enemy_contact", "ability": "shielder_strike"}):
		return
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _try_start_slam() -> void:
	if not is_instance_valid(target):
		return
	if slam_state != ENEMY_STATE_ENUMS.ShielderSlamState.IDLE:
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
	slam_state = ENEMY_STATE_ENUMS.ShielderSlamState.WINDUP
	slam_state_time_left = slam_windup_time
	slam_hit_applied = false
	velocity = Vector2.ZERO
	visual_facing_direction = slam_direction
	shield_target_facing = slam_direction
	_queue_shielder_visual_redraw(true)

func _process_slam_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_try_body_check_target()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			slam_direction = to_target.normalized()
			visual_facing_direction = slam_direction
			shield_target_facing = slam_direction
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	_queue_shielder_visual_redraw()
	if slam_state_time_left <= 0.0:
		slam_state = ENEMY_STATE_ENUMS.ShielderSlamState.THUMP
		slam_state_time_left = slam_thump_time
		slam_hit_applied = false
		_try_apply_slam_aoe_hit()
		attack_anim_time_left = attack_anim_duration
		_queue_shielder_visual_redraw(true)

func _process_slam_thump(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_try_body_check_target()
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	_queue_shielder_visual_redraw()
	if slam_state_time_left <= 0.0:
		slam_state = ENEMY_STATE_ENUMS.ShielderSlamState.RECOVER
		slam_state_time_left = slam_recover_time
		slam_cooldown_left = slam_cooldown
		_queue_shielder_visual_redraw(true)

func _process_slam_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	_try_body_check_target()
	slam_state_time_left = maxf(0.0, slam_state_time_left - delta)
	if slam_state_time_left <= 0.0:
		slam_state = ENEMY_STATE_ENUMS.ShielderSlamState.IDLE

func _try_apply_slam_aoe_hit() -> void:
	if slam_hit_applied:
		return
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= slam_radius:
		if not DAMAGEABLE.apply_damage(target, slam_damage, {"source": "enemy_ability", "ability": "shielder_slam"}):
			return
		slam_hit_applied = true
		# Heavy impact feedback for slam ability
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null:
				feedback.play_impact_heavy(target.global_position, slam_radius * 0.95)

func _try_body_check_target() -> void:
	if not is_instance_valid(target):
		return
	var target_body := target as CharacterBody2D
	if target_body == null:
		return
	if body_check_cooldown_left > 0.0:
		return
	if bool(target_body.get("dash_phasing_active")):
		return
	if body_check_dash_immunity_left > 0.0:
		return

	var shielder_radius := 13.0 * body_size_scale
	var target_radius_value: Variant = target_body.get("body_radius_cache")
	var target_radius := float(target_radius_value) if target_radius_value != null else 13.0
	var distance := global_position.distance_to(target_body.global_position)
	if distance > shielder_radius + target_radius + body_check_overlap_padding + body_check_trigger_margin:
		return

	var toward_shielder := global_position - target_body.global_position
	if toward_shielder.length_squared() <= 0.000001:
		return

	# Trigger animation before damage for synchronized feedback
	body_check_anim_time_left = body_check_anim_duration

	if not DAMAGEABLE.apply_damage(target_body, body_check_damage, {"source": "enemy_contact", "ability": "shielder_body_check"}):
		return

	var shove_direction := target_body.global_position - global_position
	if shove_direction.length_squared() > 0.000001:
		target_body.velocity += shove_direction.normalized() * body_check_shove_force

	# Play impact feedback if available
	var feedback: Object = target_body.get("player_feedback") as Object
	if feedback != null:
		feedback.play_impact_medium(target_body.global_position, shielder_radius + 30.0)

	body_check_cooldown_left = body_check_cooldown

func take_damage(amount: int, damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return

	if bool(damage_context.get("is_ground_attack", false)):
		health_state.take_damage(amount)
		return
	
	# Use the same concrete shield wedge for both visuals and blocking.
	var to_attacker := target.global_position - global_position if is_instance_valid(target) else Vector2.ZERO
	var body_radius := 13.0 * body_size_scale
	var shield_points := _get_shield_points(body_radius)
	var mitigated_damage := amount
	if _is_attack_blocked_by_shield(to_attacker, shield_points):
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
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.WINDUP:
		body_color = COLOR_SHIELDER_BODY_WINDUP
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.THUMP:
		body_color = COLOR_SHIELDER_BODY_THUMP
		core_color = COLOR_SHIELDER_CORE_THUMP
	_draw_common_body(body_radius, body_color, core_color, visual_facing_direction)

	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.WINDUP:
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
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.THUMP:
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

	# Body check visual effect
	if body_check_anim_time_left > 0.0:
		var body_check_t := 1.0 - (body_check_anim_time_left / body_check_anim_duration) if body_check_anim_duration > 0.0 else 1.0
		var check_base_radius := body_radius + 8.0
		var check_expand_radius := lerpf(check_base_radius, body_radius + 45.0, clampf(body_check_t, 0.0, 1.0))
		var check_alpha := clampf(1.0 - body_check_t, 0.0, 1.0)
		# Expanding burst glow
		draw_circle(Vector2.ZERO, check_expand_radius, Color(1.0, 0.6, 0.3, check_alpha * 0.25))
		# Expanding burst ring
		draw_arc(Vector2.ZERO, check_expand_radius, 0.0, TAU, 40, Color(1.0, 0.7, 0.4, check_alpha * 0.8), 3.0)
	
	if not _is_finite_vec2(shield_facing) or shield_facing.length_squared() <= 0.000001:
		shield_facing = Vector2.LEFT

	# Draw shield
	var shield_points := _get_shield_points(body_radius)
	var shield_front := shield_points[0]
	var shield_shoulder_left := shield_points[1]
	var shield_back_left := shield_points[2]
	var shield_back_right := shield_points[3]
	var shield_shoulder_right := shield_points[4]
	var shield_outline_color := COLOR_SHIELDER_SHIELD_OUTLINE
	var shield_fill_color := COLOR_SHIELDER_SHIELD
	if slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.WINDUP:
		shield_fill_color = Color(1.0, 0.8, 0.4, 0.95)
		shield_outline_color = Color(1.0, 0.92, 0.66, 0.82)
	elif slam_state == ENEMY_STATE_ENUMS.ShielderSlamState.THUMP:
		shield_fill_color = Color(1.0, 0.9, 0.58, 0.98)
		shield_outline_color = Color(1.0, 0.96, 0.78, 0.9)
	if _is_finite_vec2(shield_front) and _is_finite_vec2(shield_shoulder_left) and _is_finite_vec2(shield_back_left) and _is_finite_vec2(shield_back_right) and _is_finite_vec2(shield_shoulder_right):
		# Outer glow improves readability without changing gameplay footprint.
		draw_colored_polygon(shield_points, Color(shield_fill_color.r, shield_fill_color.g, shield_fill_color.b, shield_fill_color.a * 0.32))
		draw_colored_polygon(shield_points, shield_fill_color)
		draw_polyline(PackedVector2Array([
			shield_front,
			shield_shoulder_left,
			shield_back_left,
			shield_back_right,
			shield_shoulder_right,
			shield_front
		]), shield_outline_color, 1.8)
		# Mid rib emphasizes a plated shield silhouette.
		var back_mid := (shield_back_left + shield_back_right) * 0.5
		draw_line(back_mid, shield_front, Color(1.0, 0.95, 0.82, 0.72), 1.2)

		# Shield boss dot clarifies facing at a glance.
		var boss_center := shield_front.lerp(back_mid, 0.58)
		draw_circle(boss_center, 2.8, Color(1.0, 0.95, 0.82, 0.84))

func _get_shield_points(body_radius: float) -> PackedVector2Array:
	var facing := shield_facing.normalized() if shield_facing.length_squared() > 0.000001 else Vector2.LEFT
	var shield_perp := Vector2(-facing.y, facing.x)
	var anchor := body_radius + 14.0 * body_size_scale
	var front := facing * (anchor + shield_length * 0.65)
	var shoulder_center := facing * (anchor + shield_length * 0.15)
	var back_center := facing * (anchor - shield_length * 0.55)
	var shoulder_half := shield_width * body_size_scale * 0.5
	var back_half := shoulder_half * 0.62
	var shoulder_left := shoulder_center + shield_perp * shoulder_half
	var shoulder_right := shoulder_center - shield_perp * shoulder_half
	var back_left := back_center + shield_perp * back_half
	var back_right := back_center - shield_perp * back_half
	return PackedVector2Array([front, shoulder_left, back_left, back_right, shoulder_right])

func _is_attack_blocked_by_shield(attacker_local_pos: Vector2, shield_points: PackedVector2Array) -> bool:
	if attacker_local_pos.length_squared() <= 0.000001:
		return false
	if shield_points.size() < 3:
		return false

	# If attacker center is inside shield wedge, it is blocked.
	if Geometry2D.is_point_in_polygon(attacker_local_pos, shield_points):
		return true

	# Otherwise, block only when the attack path from center to attacker crosses shield edges.
	var o := Vector2.ZERO
	for i in range(shield_points.size()):
		var a := shield_points[i]
		var b := shield_points[(i + 1) % shield_points.size()]
		if Geometry2D.segment_intersects_segment(o, attacker_local_pos, a, b) != null:
			return true
	return false

func _is_finite_vec2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)
