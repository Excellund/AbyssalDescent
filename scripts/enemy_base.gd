extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")

signal health_changed(current_health: int, max_health: int)
signal died

# === SHARED COLOR PALETTE ===
# Health bars
const COLOR_HEALTH_BAR_BG := Color(0.08, 0.08, 0.08, 0.92)
const COLOR_ENEMY_HEALTH_FILL := Color(0.9, 0.18, 0.2, 0.96)
const COLOR_PLAYER_HEALTH_FILL := Color(0.18, 0.85, 0.33, 0.96)

# Enemy base render template
const COLOR_BODY_OUTER_GLOW := Color(0.1, 0.02, 0.04, 0.46)
const COLOR_BODY_HORN := Color(1.0, 0.9, 0.9, 0.92)
const COLOR_BODY_EYE := Color(1.0, 0.96, 0.94, 0.9)
const COLOR_BODY_SPIKE := Color(0.95, 0.74, 0.74, 0.7)

# Player colors (cyan theme)
const COLOR_PLAYER_GLOW := Color(0.06, 0.24, 0.42, 0.16)
const COLOR_PLAYER_OUTER := Color(0.03, 0.06, 0.09, 0.46)
const COLOR_PLAYER_BODY := Color(0.15, 0.76, 1.0, 1.0)
const COLOR_PLAYER_CORE := Color(0.08, 0.45, 0.84, 1.0)
const COLOR_PLAYER_LIGHT := Color(0.68, 0.92, 1.0, 0.9)
const COLOR_PLAYER_POINTER := Color(0.97, 0.99, 1.0, 0.98)
const COLOR_PLAYER_EYE := Color(0.98, 1.0, 1.0, 0.95)
const COLOR_PLAYER_WING := Color(0.85, 0.96, 1.0, 0.72)
const COLOR_PLAYER_SPEED_ARC := Color(0.56, 0.89, 1.0, 0.26)
const COLOR_PLAYER_DASH_PHASE := Color(0.5, 1.0, 0.98, 0.24)
const COLOR_PLAYER_DASH_STREAK := Color(0.52, 1.0, 0.95, 0.2)

# Player attack colors
const COLOR_SWING_DEFAULT := Color(0.99, 0.96, 0.68, 0.72)
const COLOR_SWING_RAZOR_WIND := Color(0.58, 0.95, 0.86, 0.82)
const COLOR_SWING_RAZOR_WIND_EXTENDED := Color(0.56, 1.0, 0.86, 0.62)
const COLOR_EXECUTION_RING := Color(1.0, 0.62, 0.34, 0.9)
const COLOR_EXECUTION_PROC := Color(1.0, 0.58, 0.3, 0.86)
const COLOR_EXECUTION_PROC_EXTENDED := Color(1.0, 0.58, 0.3, 0.9)
const COLOR_EXECUTION_PIP_LIT := Color(1.0, 0.56, 0.26, 0.92)
const COLOR_EXECUTION_PIP_DARK := Color(0.48, 0.32, 0.25, 0.55)
const COLOR_EXECUTION_WIND_EXTENDED := Color(1.0, 0.62, 0.34, 0.74)
const COLOR_RUPTURE_WAVE_RING := Color(0.44, 0.96, 1.0, 0.86)
const COLOR_RUPTURE_WAVE_AURA := Color(0.46, 0.96, 1.0, 0.3)

# Player reward overlays
const COLOR_RAZOR_WIND_TRIANGLE := Color(0.56, 1.0, 0.86, 0.8)
const COLOR_RAZOR_WIND_LINE := Color(0.86, 1.0, 0.93, 0.86)

# Damage feedback
const COLOR_DAMAGE_FLASH := Color(0.95, 0.12, 0.12, 1.0)

# Enemy-specific colors (chaser = red)
const COLOR_CHASER_BODY := Color(0.95, 0.18, 0.26, 1.0)
const COLOR_CHASER_CORE := Color(0.62, 0.06, 0.12, 1.0)

# Charger (orange)
const COLOR_CHARGER_BODY := Color(0.95, 0.64, 0.18, 1.0)
const COLOR_CHARGER_CORE := Color(0.74, 0.4, 0.08, 1.0)
const COLOR_CHARGER_CORE_CHARGED := Color(0.86, 0.54, 0.1, 1.0)

# Archer (cyan)
const COLOR_ARCHER_BODY := Color(0.26, 0.74, 0.96, 0.9)
const COLOR_ARCHER_CORE := Color(0.55, 0.92, 1.0, 0.8)
const COLOR_ARCHER_AIM := Color(0.96, 0.74, 0.26, 0.72)
const COLOR_ARCHER_AIM_BRACKET := Color(0.96, 0.74, 0.26, 0.7)
const COLOR_ARCHER_PROJECTILE := Color(0.96, 0.76, 0.28, 0.8)

# Shielder (golden orange)
const COLOR_SHIELDER_BODY := Color(0.96, 0.68, 0.26, 0.9)
const COLOR_SHIELDER_CORE := Color(1.0, 0.82, 0.48, 0.8)
const COLOR_SHIELDER_BODY_WINDUP := Color(1.0, 0.74, 0.3, 1.0)
const COLOR_SHIELDER_BODY_THUMP := Color(1.0, 0.82, 0.38, 1.0)
const COLOR_SHIELDER_CORE_THUMP := Color(1.0, 0.9, 0.56, 0.9)
const COLOR_SHIELDER_SHIELD := Color(0.96, 0.74, 0.34, 0.86)
const COLOR_SHIELDER_SHIELD_OUTLINE := Color(1.0, 0.88, 0.6, 0.7)
const COLOR_SHIELDER_SLAM_WARNING_GLOW := Color(1.0, 0.44, 0.2, 0.18)
const COLOR_SHIELDER_SLAM_WARNING_RING := Color(1.0, 0.8, 0.38, 1.0)
const COLOR_SHIELDER_SLAM_SHOCK_GLOW := Color(1.0, 0.62, 0.28, 0.16)
const COLOR_SHIELDER_SLAM_SHOCK_RING := Color(1.0, 0.9, 0.58, 0.84)

# Boss (dark red)
const COLOR_BOSS_BODY := Color(0.78, 0.15, 0.16, 1.0)
const COLOR_BOSS_BODY_TELEGRAPH := Color(0.95, 0.25, 0.22, 1.0)
const COLOR_BOSS_BODY_ATTACK := Color(1.0, 0.34, 0.18, 1.0)
const COLOR_BOSS_CORE := Color(0.98, 0.45, 0.2, 1.0)
const COLOR_BOSS_CORE_TELEGRAPH := Color(1.0, 0.78, 0.28, 1.0)
const COLOR_BOSS_CORE_ATTACK := Color(1.0, 0.86, 0.34, 1.0)
const COLOR_BOSS_GLOW := Color(0.4, 0.04, 0.06, 0.34)
# Boss attack telegraphs
const COLOR_BOSS_CHARGE_LINE := Color(1.0, 0.84, 0.34, 1.0)
const COLOR_BOSS_CHARGE_LINE_INNER := Color(1.0, 0.9, 0.45, 1.0)
const COLOR_BOSS_NOVA_GLOW := Color(1.0, 0.35, 0.15, 1.0)
const COLOR_BOSS_NOVA_RING := Color(1.0, 0.74, 0.3, 1.0)
const COLOR_BOSS_CLEAVE_FILL := Color(1.0, 0.45, 0.18, 1.0)
const COLOR_BOSS_CLEAVE_OUTLINE := Color(1.0, 0.82, 0.4, 1.0)

@export var max_health: int = 40
@export var health_bar_size: Vector2 = Vector2(56.0, 8.0)
@export var health_bar_offset: Vector2 = Vector2(-28.0, -34.0)

var target: Node2D
var health_bar: ProgressBar
var health_state
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.1
var visual_facing_direction: Vector2 = Vector2.LEFT
var slow_time_left: float = 0.0
var slow_speed_mult: float = 1.0
var has_mutator_overlay: bool = false
var mutator_theme_color: Color = Color(1.0, 0.4, 0.4, 1.0)

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group("enemies")
	health_changed.connect(_update_health_bar)
	_create_health_bar()
	_create_health_state()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	_update_attack_animation(delta)
	_process_behavior(delta)
	_update_visual_facing_direction()

func _process_behavior(_delta: float) -> void:
	pass

func _update_attack_animation(delta: float) -> void:
	if attack_anim_time_left > 0.0:
		attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
		queue_redraw()
	if slow_time_left > 0.0:
		slow_time_left -= delta
		if slow_time_left <= 0.0:
			slow_time_left = 0.0
			slow_speed_mult = 1.0

func _update_visual_facing_direction() -> void:
	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.28)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	queue_redraw()

func take_damage(amount: int, _damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	health_state.take_damage(amount)

func apply_slow(duration: float, mult: float) -> void:
	if duration > slow_time_left:
		slow_time_left = duration
	if mult < slow_speed_mult:
		slow_speed_mult = mult

func _draw_slow_indicator(body_radius: float) -> void:
	if slow_time_left <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.011)
	var fade := clampf(slow_time_left * 4.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, body_radius + 8.0, Color(0.46, 1.0, 0.92, 0.07 * fade))
	draw_arc(Vector2.ZERO, body_radius + 7.0, 0.0, TAU, 32,
		Color(0.46, 1.0, 0.92, (0.52 + pulse * 0.28) * fade), 2.6)

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
	background_style.bg_color = COLOR_HEALTH_BAR_BG
	background_style.corner_radius_top_left = 3
	background_style.corner_radius_top_right = 3
	background_style.corner_radius_bottom_left = 3
	background_style.corner_radius_bottom_right = 3

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_ENEMY_HEALTH_FILL
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

func _draw_common_body(body_radius: float, body_color: Color, core_color: Color, facing: Vector2) -> void:
	var side := Vector2(-facing.y, facing.x)
	var outer_color := COLOR_BODY_OUTER_GLOW
	
	draw_circle(Vector2.ZERO, body_radius + 6.2, Color(body_color.r * 0.6, body_color.g * 0.3, body_color.b * 0.3, 0.14))
	draw_circle(Vector2.ZERO, body_radius + 3.0, outer_color)
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(Vector2.ZERO, body_radius * 0.72, core_color)
	draw_circle(Vector2.ZERO, body_radius * 0.38, Color(1.0, 0.9, 0.88, 0.2))

	var horn_tip := facing * (body_radius + 8.0)
	var horn_base := facing * (body_radius - 2.0)
	var horn_w := 4.6
	var horn := PackedVector2Array([horn_tip, horn_base + side * horn_w, horn_base - side * horn_w])
	draw_colored_polygon(horn, COLOR_BODY_HORN)

	var eye := facing * (body_radius * 0.34) + side * 2.0
	draw_circle(eye, 1.8, COLOR_BODY_EYE)

	var spike_l := side * (body_radius - 1.0)
	var spike_r := -side * (body_radius - 1.0)
	draw_line(spike_l, spike_l + side * 6.0, COLOR_BODY_SPIKE, 1.8)
	draw_line(spike_r, spike_r - side * 6.0, COLOR_BODY_SPIKE, 1.8)
	_draw_mutator_overlay(body_radius)

func _draw_mutator_overlay(body_radius: float) -> void:
	if not has_mutator_overlay:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 3.4)
	# Outer ring: theme-colored, slow pulse — persistent identity marker
	var ring_color := mutator_theme_color
	ring_color.a = 0.44 + pulse * 0.22
	draw_arc(Vector2.ZERO, body_radius + 9.0, 0.0, TAU, 32, ring_color, 2.2)
	# Inner accent fill: very subtle so role silhouette stays primary
	var fill_color := mutator_theme_color
	fill_color.a = 0.06 + pulse * 0.04
	draw_circle(Vector2.ZERO, body_radius + 8.0, fill_color)

func _get_attack_pulse() -> float:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	return sin(attack_t * PI) * 1.8 if attack_anim_time_left > 0.0 else 0.0
