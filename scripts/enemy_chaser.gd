extends "res://scripts/enemy_base.gd"

@export var move_speed: float = 120.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var stop_distance: float = 8.0
@export var attack_range: float = 28.0
@export var attack_damage: int = 10
@export var attack_interval: float = 0.85

var attack_cooldown_left: float = 0.0

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_attack_target()

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _get_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length() <= stop_distance:
		return Vector2.ZERO
	return to_target.normalized() * move_speed

func _try_attack_target() -> void:
	if not is_instance_valid(target):
		return
	if attack_cooldown_left > 0.0:
		return
	if not target.has_method("take_damage"):
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	target.call("take_damage", attack_damage)
	attack_cooldown_left = attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var body_radius := 13.0 + attack_pulse
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var body_color := Color(0.95, 0.18, 0.26, 1.0)
	var core_color := Color(0.62, 0.06, 0.12, 1.0)
	_draw_common_body(body_radius, body_color, core_color, facing)
