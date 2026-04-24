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
@export var contact_damage: int = 10
@export var contact_damage_cooldown: float = 0.4

var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.ZERO
var contact_damage_cooldown_left: float = 0.0
var scene_restart_queued: bool = false
var health_state
var player_feedback

func _ready() -> void:
	died.connect(_restart_current_scene)
	_create_health_state()
	_create_player_feedback()

func _physics_process(delta: float) -> void:
	var direction := _read_movement_direction()
	_update_last_move_direction(direction)
	_update_dash_cooldown(delta)
	_update_contact_damage_cooldown(delta)
	_try_start_dash(direction)

	if _process_active_dash(delta):
		_process_enemy_collisions()
		return

	_update_ground_movement(direction, delta)
	move_and_slide()
	_process_enemy_collisions()

func _read_movement_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _update_last_move_direction(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		last_move_direction = direction

func _update_dash_cooldown(delta: float) -> void:
	if dash_cooldown_left > 0.0:
		dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

func _update_contact_damage_cooldown(delta: float) -> void:
	if contact_damage_cooldown_left > 0.0:
		contact_damage_cooldown_left = maxf(0.0, contact_damage_cooldown_left - delta)

func _try_start_dash(direction: Vector2) -> void:
	if not Input.is_action_just_pressed("dash"):
		return
	if dash_cooldown_left > 0.0:
		return

	dash_direction = direction if direction != Vector2.ZERO else last_move_direction
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown

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

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	var health_before := _get_current_health()
	health_state.take_damage(amount)
	if _get_current_health() < health_before:
		player_feedback.play_damage_flash()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func is_dead() -> bool:
	return health_state.is_dead()

func _process_enemy_collisions() -> void:
	if contact_damage_cooldown_left > 0.0:
		return

	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var collider := collision.get_collider()
		if not _is_enemy_collider(collider):
			continue
		take_damage(contact_damage)
		player_feedback.play_impact_sound()
		contact_damage_cooldown_left = contact_damage_cooldown
		break

func _is_enemy_collider(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var collider_node := collider as Node
	return collider_node.is_in_group("enemies") or collider_node.is_in_group("enemy")

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
