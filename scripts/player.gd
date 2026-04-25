extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const PLAYER_FEEDBACK_SCRIPT := preload("res://scripts/player_feedback.gd")

signal health_changed(current_health: int, max_health: int)
signal died

@export var max_speed: float = 220.0
@export var acceleration: float = 1400.0
@export var deceleration: float = 1800.0
@export var turn_boost: float = 1.25
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.12
@export var dash_cooldown: float = 0.35
@export var max_health: int = 100
@export var attack_damage: int = 20
@export var attack_range: float = 74.0
@export var attack_arc_degrees: float = 130.0
@export var attack_cooldown: float = 0.28
@export var attack_lock_duration: float = 0.12

var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.ZERO
var attack_cooldown_left: float = 0.0
var scene_restart_queued: bool = false
var health_state
var player_feedback
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.12
var visual_facing_direction: Vector2 = Vector2.RIGHT
var attack_lock_time_left: float = 0.0
var attack_lock_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	died.connect(_restart_current_scene)
	_create_health_state()
	_create_player_feedback()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	var direction := _read_movement_direction()
	_update_last_move_direction(direction)
	_update_dash_cooldown(delta)
	_update_attack_cooldown(delta)
	_update_attack_lock(delta)
	_update_attack_animation(delta)
	_update_visual_facing_direction()
	_try_start_dash(direction)
	_try_attack()

	if _is_attack_locked():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _process_active_dash(delta):
		return

	_update_ground_movement(direction, delta)
	move_and_slide()

func _read_movement_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _update_last_move_direction(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		last_move_direction = direction

func _update_dash_cooldown(delta: float) -> void:
	if dash_cooldown_left > 0.0:
		dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _try_start_dash(direction: Vector2) -> void:
	if _is_attack_locked():
		return
	if not Input.is_action_just_pressed("dash"):
		return
	if dash_cooldown_left > 0.0:
		return

	dash_direction = direction if direction != Vector2.ZERO else last_move_direction
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown

func _try_attack() -> void:
	if not Input.is_action_just_pressed("attack"):
		return
	if attack_cooldown_left > 0.0:
		return

	attack_cooldown_left = attack_cooldown
	attack_anim_time_left = attack_anim_duration
	player_feedback.play_attack_swing_sound()

	var attack_direction := _get_mouse_attack_direction()
	attack_lock_time_left = attack_lock_duration
	attack_lock_direction = attack_direction
	visual_facing_direction = attack_direction
	velocity = Vector2.ZERO
	dash_time_left = 0.0
	player_feedback.play_attack_swing_visual(attack_direction, attack_range, attack_arc_degrees)
	if _perform_melee_attack(attack_direction):
		player_feedback.play_impact_sound()

func _update_attack_lock(delta: float) -> void:
	if attack_lock_time_left > 0.0:
		attack_lock_time_left = maxf(0.0, attack_lock_time_left - delta)

func _is_attack_locked() -> bool:
	return attack_lock_time_left > 0.0

func _get_mouse_attack_direction() -> Vector2:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 0.000001:
		return to_mouse.normalized()
	if last_move_direction != Vector2.ZERO:
		return last_move_direction
	return Vector2.RIGHT

func _process_active_dash(delta: float) -> bool:
	if dash_time_left <= 0.0:
		return false

	dash_time_left = maxf(0.0, dash_time_left - delta)
	velocity = dash_direction * dash_speed
	move_and_slide()
	return true

func _update_ground_movement(direction: Vector2, delta: float) -> void:
	var target_velocity := direction * max_speed
	var applied_acceleration := _get_applied_acceleration(target_velocity)
	var move_rate := applied_acceleration if direction != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(target_velocity, move_rate * delta)

func _get_applied_acceleration(target_velocity: Vector2) -> float:
	if target_velocity == Vector2.ZERO:
		return acceleration
	if velocity.dot(target_velocity) < 0.0:
		return acceleration * turn_boost
	return acceleration

func _update_attack_animation(delta: float) -> void:
	if attack_anim_time_left > 0.0:
		attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
		queue_redraw()

func _update_visual_facing_direction() -> void:
	if _is_attack_locked():
		if attack_lock_direction.length_squared() > 0.000001:
			visual_facing_direction = attack_lock_direction
		queue_redraw()
		return

	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.32)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	queue_redraw()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	var health_before := _get_current_health()
	health_state.take_damage(amount)
	if _get_current_health() < health_before:
		player_feedback.play_damage_flash()
		player_feedback.play_impact_sound()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func is_dead() -> bool:
	return health_state.is_dead()

func apply_boon(boon_id: String) -> void:
	match boon_id:
		"swift_strike":
			attack_cooldown = maxf(0.08, attack_cooldown * 0.86)
		"heavy_blow":
			attack_damage += 8
		"wide_arc":
			attack_arc_degrees = clampf(attack_arc_degrees + 18.0, 60.0, 240.0)
		"long_reach":
			attack_range += 14.0
		"fleet_foot":
			max_speed += 18.0
		"blink_dash":
			dash_cooldown = maxf(0.12, dash_cooldown * 0.85)
		"iron_skin":
			if health_state != null:
				health_state.max_health += 20
				health_state.set_health(health_state.current_health + 20)
				max_health = health_state.max_health
		_:
			pass

func _perform_melee_attack(attack_direction: Vector2) -> bool:
	var did_hit := false
	var max_angle_radians := deg_to_rad(attack_arc_degrees * 0.5)

	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage"):
			continue

		var enemy_body := enemy_node as Node2D
		var to_enemy := enemy_body.global_position - global_position
		if to_enemy.length() > attack_range:
			continue
		if attack_direction.angle_to(to_enemy.normalized()) > max_angle_radians:
			continue

		enemy_node.call("take_damage", attack_damage)
		did_hit = true

	return did_hit

func _restart_current_scene() -> void:
	if scene_restart_queued:
		return
	scene_restart_queued = true
	get_tree().call_deferred("reload_current_scene")

func _create_health_state() -> void:
	health_state = HEALTH_STATE_SCRIPT.new()
	health_state.health_changed.connect(_on_health_state_changed)
	health_state.died.connect(_on_health_state_died)
	add_child(health_state)
	health_state.setup(max_health)

func _create_player_feedback() -> void:
	player_feedback = PLAYER_FEEDBACK_SCRIPT.new()
	add_child(player_feedback)
	player_feedback.setup(max_health, _get_current_health())

func _on_health_state_changed(new_health: int, new_max_health: int) -> void:
	health_changed.emit(new_health, new_max_health)
	if player_feedback != null:
		player_feedback.update_health_bar(new_health, new_max_health)

func _on_health_state_died() -> void:
	died.emit()

func _get_current_health() -> int:
	if health_state == null:
		return max_health
	return health_state.current_health

func _draw() -> void:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	var attack_pulse := sin(attack_t * PI) * 1.9 if attack_anim_time_left > 0.0 else 0.0
	var body_radius := 14.0 + attack_pulse
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.RIGHT
	var side := Vector2(-facing.y, facing.x)

	draw_circle(Vector2.ZERO, body_radius + 3.0, Color(0.03, 0.06, 0.09, 0.42))
	draw_circle(Vector2.ZERO, body_radius, Color(0.12, 0.72, 0.98, 1.0))
	draw_circle(Vector2.ZERO, body_radius * 0.7, Color(0.07, 0.42, 0.78, 1.0))

	var tip := facing * (body_radius + 9.0)
	var base_center := facing * (body_radius - 1.5)
	var fin := 4.9
	var pointer := PackedVector2Array([tip, base_center + side * fin, base_center - side * fin])
	draw_colored_polygon(pointer, Color(0.96, 0.99, 1.0, 0.95))

	var wing_l := facing * (body_radius - 2.0) + side * 6.3
	var wing_r := facing * (body_radius - 2.0) - side * 6.3
	draw_line(wing_l, wing_l - facing * 6.0, Color(0.85, 0.96, 1.0, 0.72), 2.0)
	draw_line(wing_r, wing_r - facing * 6.0, Color(0.85, 0.96, 1.0, 0.72), 2.0)
