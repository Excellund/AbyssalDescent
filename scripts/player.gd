extends CharacterBody2D

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
@export var health_bar_size: Vector2 = Vector2(80.0, 10.0)
@export var health_bar_offset: Vector2 = Vector2(-40.0, -42.0)
@export var impact_sound: AudioStream = preload("res://sounds/impactPunch_medium_002.ogg")
@export var impact_volume_db: float = -6.0
@export var damage_flash_color: Color = Color(0.95, 0.12, 0.12, 1.0)
@export_range(0.0, 1.0, 0.01) var damage_flash_alpha: float = 0.45
@export var damage_flash_fade_time: float = 0.16

var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.ZERO
var current_health: int = 100
var contact_damage_cooldown_left: float = 0.0
var health_bar: ProgressBar
var impact_sound_player: AudioStreamPlayer2D
var scene_restart_queued: bool = false
var damage_flash_layer: CanvasLayer
var damage_flash_rect: ColorRect
var damage_flash_tween: Tween

func _ready() -> void:
	died.connect(_restart_current_scene)
	health_changed.connect(_update_health_bar)
	_create_damage_flash()
	_create_health_bar()
	_create_impact_sound_player()
	current_health = clampi(current_health, 0, max_health)
	health_changed.emit(current_health, max_health)

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
	var health_before := current_health
	_set_health(current_health - amount)
	if current_health < health_before:
		_play_damage_flash()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	_set_health(current_health + amount)

func is_dead() -> bool:
	return current_health <= 0

func _set_health(value: int) -> void:
	var previous_health := current_health
	current_health = clampi(value, 0, max_health)
	if current_health == previous_health:
		return
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()

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
		_play_impact_sound()
		contact_damage_cooldown_left = contact_damage_cooldown
		break

func _is_enemy_collider(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var collider_node := collider as Node
	return collider_node.is_in_group("enemies") or collider_node.is_in_group("enemy")

func _create_health_bar() -> void:
	health_bar = ProgressBar.new()
	health_bar.min_value = 0.0
	health_bar.max_value = float(max_health)
	health_bar.value = float(current_health)
	health_bar.show_percentage = false
	health_bar.position = health_bar_offset
	health_bar.custom_minimum_size = health_bar_size
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(0.08, 0.08, 0.08, 0.92)
	background_style.corner_radius_top_left = 3
	background_style.corner_radius_top_right = 3
	background_style.corner_radius_bottom_left = 3
	background_style.corner_radius_bottom_right = 3

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.18, 0.85, 0.33, 0.96)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3

	health_bar.add_theme_stylebox_override("background", background_style)
	health_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(health_bar)

func _update_health_bar(new_health: int, new_max_health: int) -> void:
	if health_bar == null:
		return
	health_bar.max_value = float(new_max_health)
	health_bar.value = float(new_health)

func _create_impact_sound_player() -> void:
	impact_sound_player = AudioStreamPlayer2D.new()
	impact_sound_player.stream = impact_sound
	impact_sound_player.volume_db = impact_volume_db
	add_child(impact_sound_player)

func _play_impact_sound() -> void:
	if impact_sound_player == null:
		return
	if impact_sound_player.stream == null:
		return
	impact_sound_player.play()

func _restart_current_scene() -> void:
	if scene_restart_queued:
		return
	scene_restart_queued = true
	get_tree().call_deferred("reload_current_scene")

func _create_damage_flash() -> void:
	damage_flash_layer = CanvasLayer.new()
	damage_flash_layer.layer = 100

	damage_flash_rect = ColorRect.new()
	damage_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash_rect.offset_left = 0.0
	damage_flash_rect.offset_top = 0.0
	damage_flash_rect.offset_right = 0.0
	damage_flash_rect.offset_bottom = 0.0
	damage_flash_rect.color = damage_flash_color
	damage_flash_rect.modulate = Color(1.0, 1.0, 1.0, 0.0)
	damage_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	damage_flash_layer.add_child(damage_flash_rect)
	add_child(damage_flash_layer)

func _play_damage_flash() -> void:
	if damage_flash_rect == null:
		return
	if damage_flash_tween != null and damage_flash_tween.is_valid():
		damage_flash_tween.kill()
	damage_flash_rect.modulate.a = damage_flash_alpha
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(damage_flash_rect, "modulate:a", 0.0, damage_flash_fade_time)
