extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")

signal health_changed(current_health: int, max_health: int)
signal died

@export var target_path: NodePath
@export var move_speed: float = 160.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var stop_distance: float = 8.0
@export var attack_range: float = 30.0
@export var attack_damage: int = 10
@export var attack_interval: float = 0.65
@export var max_health: int = 40
@export var health_bar_size: Vector2 = Vector2(56.0, 8.0)
@export var health_bar_offset: Vector2 = Vector2(-28.0, -34.0)

var target: Node2D
var health_bar: ProgressBar
var health_state
var attack_cooldown_left: float = 0.0
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.1
var visual_facing_direction: Vector2 = Vector2.LEFT

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group("enemies")
	health_changed.connect(_update_health_bar)
	_create_health_bar()
	_create_health_state()
	target = get_node_or_null(target_path) as Node2D
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	_refresh_target_if_missing()
	_update_attack_cooldown(delta)
	_update_attack_animation(delta)
	_update_visual_facing_direction()
	var desired_velocity := _get_desired_velocity()
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	_try_attack_target()

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

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

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

func _update_attack_animation(delta: float) -> void:
	if attack_anim_time_left > 0.0:
		attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
		queue_redraw()

func _update_visual_facing_direction() -> void:
	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.28)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	queue_redraw()

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

func _draw() -> void:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	var attack_pulse := sin(attack_t * PI) * 1.8 if attack_anim_time_left > 0.0 else 0.0
	var body_radius := 13.0 + attack_pulse
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)

	draw_circle(Vector2.ZERO, body_radius + 3.0, Color(0.12, 0.02, 0.04, 0.44))
	draw_circle(Vector2.ZERO, body_radius, Color(0.95, 0.18, 0.26, 1.0))
	draw_circle(Vector2.ZERO, body_radius * 0.72, Color(0.62, 0.06, 0.12, 1.0))

	var horn_tip := facing * (body_radius + 8.0)
	var horn_base := facing * (body_radius - 2.0)
	var horn_w := 4.6
	var horn := PackedVector2Array([horn_tip, horn_base + side * horn_w, horn_base - side * horn_w])
	draw_colored_polygon(horn, Color(1.0, 0.9, 0.9, 0.92))

	var spike_l := side * (body_radius - 1.0)
	var spike_r := -side * (body_radius - 1.0)
	draw_line(spike_l, spike_l + side * 6.0, Color(0.95, 0.74, 0.74, 0.7), 1.8)
	draw_line(spike_r, spike_r - side * 6.0, Color(0.95, 0.74, 0.74, 0.7), 1.8)
