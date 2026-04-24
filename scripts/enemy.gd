extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")

signal health_changed(current_health: int, max_health: int)
signal died

@export var target_path: NodePath
@export var move_speed: float = 160.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var stop_distance: float = 8.0
@export var max_health: int = 40
@export var health_bar_size: Vector2 = Vector2(56.0, 8.0)
@export var health_bar_offset: Vector2 = Vector2(-28.0, -34.0)

var target: Node2D
var health_bar: ProgressBar
var health_state

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group("enemies")
	health_changed.connect(_update_health_bar)
	_create_health_bar()
	_create_health_state()
	target = get_node_or_null(target_path) as Node2D

func _physics_process(delta: float) -> void:
	_refresh_target_if_missing()
	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()

func _refresh_target_if_missing() -> void:
	if is_instance_valid(target):
		return
	if target_path != NodePath():
		target = get_node_or_null(target_path) as Node2D

func _get_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length() <= stop_distance:
		return Vector2.ZERO
	return to_target.normalized() * move_speed

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	health_state.take_damage(amount)

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func is_dead() -> bool:
	return health_state.is_dead()

func _create_health_bar() -> void:
	health_bar = ProgressBar.new()
	health_bar.min_value = 0.0
	health_bar.max_value = float(max_health)
	health_bar.value = float(_get_current_health())
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
	fill_style.bg_color = Color(0.9, 0.18, 0.2, 0.96)
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

func _create_health_state() -> void:
	health_state = HEALTH_STATE_SCRIPT.new()
	health_state.health_changed.connect(_on_health_state_changed)
	health_state.died.connect(_on_health_state_died)
	add_child(health_state)
	health_state.setup(max_health)

func _on_health_state_changed(new_health: int, new_max_health: int) -> void:
	health_changed.emit(new_health, new_max_health)

func _on_health_state_died() -> void:
	died.emit()
	queue_free()

func _get_current_health() -> int:
	if health_state == null:
		return max_health
	return health_state.current_health
