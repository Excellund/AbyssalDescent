extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

# When the player enters melee range while the Chaser is mid-cooldown, snap the
# remaining cooldown down to this window so the hit registers quickly on contact.
const ATTACK_COMMIT_WINDOW := 0.15

@export var move_speed: float = 120.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var stop_distance: float = 30.0
@export var attack_range: float = 32.0
@export var damage: int = 10
@export var attack_interval: float = 0.85

var attack_cooldown_left: float = 0.0
var _player_was_in_range: bool = false
var _attack_sync_was_active: bool = false

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	var in_range := is_instance_valid(target) and global_position.distance_to(target.global_position) <= attack_range
	if in_range and not _player_was_in_range and attack_cooldown_left > ATTACK_COMMIT_WINDOW:
		attack_cooldown_left = ATTACK_COMMIT_WINDOW
	_player_was_in_range = in_range
	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_attack_target()

func should_force_network_runtime_state_sampling() -> bool:
	return attack_anim_time_left > 0.0

func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and attack_anim_time_left > 0.0

func get_priority_network_sync_interval_sec() -> float:
	if attack_anim_time_left > 0.0:
		return 0.03
	return 0.0

func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active := attack_anim_time_left > 0.0
	if not active and not _attack_sync_was_active:
		return {}
	var payload := {
		"active": active,
		"attack_anim_time_left": attack_anim_time_left,
		"visual_facing_direction": visual_facing_direction
	}
	_attack_sync_was_active = active
	return payload

func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	if sync_state.is_empty():
		return
	var active := bool(sync_state.get("active", false))
	if not active:
		if attack_anim_time_left > 0.0:
			attack_anim_time_left = 0.0
			queue_redraw()
		return
	attack_anim_time_left = float(sync_state.get("attack_anim_time_left", attack_anim_time_left))
	visual_facing_direction = sync_state.get("visual_facing_direction", visual_facing_direction) as Vector2
	queue_redraw()

func _process_network_visuals(delta: float) -> void:
	if attack_anim_time_left <= 0.0:
		return
	var previous_time_left := attack_anim_time_left
	attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
	if not is_equal_approx(previous_time_left, attack_anim_time_left):
		queue_redraw()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _get_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length() <= stop_distance:
		return Vector2.ZERO
	return to_target.normalized() * move_speed * slow_speed_mult

func _try_attack_target() -> void:
	if not is_instance_valid(target):
		return
	if attack_cooldown_left > 0.0:
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	if not DAMAGEABLE.apply_damage(target, damage, {"source": "enemy_contact", "ability": "chaser_strike"}):
		return
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 12.8 + attack_pulse + speed_t * 0.9
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var body_color := COLOR_CHASER_BODY
	var core_color := COLOR_CHASER_CORE
	if speed_t > 0.4:
		body_color = Color(1.0, 0.24, 0.3, 1.0)
	_draw_common_body(body_radius, body_color, core_color, facing)

	# Forward claw marks make chasers readable as melee rushers.
	var claw_base := facing * (body_radius + 4.5)
	draw_line(claw_base + side * 3.0, claw_base + side * 4.0 + facing * 8.0, Color(1.0, 0.72, 0.68, 0.86), 1.8)
	draw_line(claw_base - side * 3.0, claw_base - side * 4.0 + facing * 8.0, Color(1.0, 0.72, 0.68, 0.86), 1.8)

	if speed_t > 0.25:
		var trail_alpha := 0.08 + speed_t * 0.18
		draw_circle(-facing * (body_radius + 2.0), body_radius * 0.7, Color(0.9, 0.2, 0.24, trail_alpha))
	_draw_slow_indicator(body_radius)
