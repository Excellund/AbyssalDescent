extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const COLOR_PALETTE := preload("res://scripts/shared/color_palette.gd")

signal health_changed(current_health: int, max_health: int)
signal died

# === SHARED COLOR PALETTE ===
const COLOR_HEALTH_BAR_BG := COLOR_PALETTE.COLOR_HEALTH_BAR_BG
const COLOR_ENEMY_HEALTH_FILL := COLOR_PALETTE.COLOR_ENEMY_HEALTH_FILL
const COLOR_PLAYER_HEALTH_FILL := COLOR_PALETTE.COLOR_PLAYER_HEALTH_FILL
const COLOR_BODY_OUTER_GLOW := COLOR_PALETTE.COLOR_BODY_OUTER_GLOW
const COLOR_BODY_HORN := COLOR_PALETTE.COLOR_BODY_HORN
const COLOR_BODY_EYE := COLOR_PALETTE.COLOR_BODY_EYE
const COLOR_BODY_SPIKE := COLOR_PALETTE.COLOR_BODY_SPIKE
const COLOR_PLAYER_GLOW := COLOR_PALETTE.COLOR_PLAYER_GLOW
const COLOR_PLAYER_OUTER := COLOR_PALETTE.COLOR_PLAYER_OUTER
const COLOR_PLAYER_BODY := COLOR_PALETTE.COLOR_PLAYER_BODY
const COLOR_PLAYER_CORE := COLOR_PALETTE.COLOR_PLAYER_CORE
const COLOR_PLAYER_LIGHT := COLOR_PALETTE.COLOR_PLAYER_LIGHT
const COLOR_PLAYER_POINTER := COLOR_PALETTE.COLOR_PLAYER_POINTER
const COLOR_PLAYER_EYE := COLOR_PALETTE.COLOR_PLAYER_EYE
const COLOR_PLAYER_WING := COLOR_PALETTE.COLOR_PLAYER_WING
const COLOR_PLAYER_SPEED_ARC := COLOR_PALETTE.COLOR_PLAYER_SPEED_ARC
const COLOR_PLAYER_DASH_PHASE := COLOR_PALETTE.COLOR_PLAYER_DASH_PHASE
const COLOR_PLAYER_DASH_STREAK := COLOR_PALETTE.COLOR_PLAYER_DASH_STREAK
const COLOR_SWING_DEFAULT := COLOR_PALETTE.COLOR_SWING_DEFAULT
const COLOR_SWING_RAZOR_WIND := COLOR_PALETTE.COLOR_SWING_RAZOR_WIND
const COLOR_SWING_RAZOR_WIND_EXTENDED := COLOR_PALETTE.COLOR_SWING_RAZOR_WIND_EXTENDED
const COLOR_EXECUTION_RING := COLOR_PALETTE.COLOR_EXECUTION_RING
const COLOR_EXECUTION_PROC := COLOR_PALETTE.COLOR_EXECUTION_PROC
const COLOR_EXECUTION_PROC_EXTENDED := COLOR_PALETTE.COLOR_EXECUTION_PROC_EXTENDED
const COLOR_EXECUTION_PIP_LIT := COLOR_PALETTE.COLOR_EXECUTION_PIP_LIT
const COLOR_EXECUTION_PIP_DARK := COLOR_PALETTE.COLOR_EXECUTION_PIP_DARK
const COLOR_EXECUTION_WIND_EXTENDED := COLOR_PALETTE.COLOR_EXECUTION_WIND_EXTENDED
const COLOR_RUPTURE_WAVE_RING := COLOR_PALETTE.COLOR_RUPTURE_WAVE_RING
const COLOR_RUPTURE_WAVE_AURA := COLOR_PALETTE.COLOR_RUPTURE_WAVE_AURA
const COLOR_RAZOR_WIND_TRIANGLE := COLOR_PALETTE.COLOR_RAZOR_WIND_TRIANGLE
const COLOR_RAZOR_WIND_LINE := COLOR_PALETTE.COLOR_RAZOR_WIND_LINE
const COLOR_DAMAGE_FLASH := COLOR_PALETTE.COLOR_DAMAGE_FLASH
const COLOR_CHASER_BODY := COLOR_PALETTE.COLOR_CHASER_BODY
const COLOR_CHASER_CORE := COLOR_PALETTE.COLOR_CHASER_CORE
const COLOR_CHARGER_BODY := COLOR_PALETTE.COLOR_CHARGER_BODY
const COLOR_CHARGER_CORE := COLOR_PALETTE.COLOR_CHARGER_CORE
const COLOR_CHARGER_CORE_CHARGED := COLOR_PALETTE.COLOR_CHARGER_CORE_CHARGED
const COLOR_ARCHER_BODY := COLOR_PALETTE.COLOR_ARCHER_BODY
const COLOR_ARCHER_CORE := COLOR_PALETTE.COLOR_ARCHER_CORE
const COLOR_ARCHER_AIM := COLOR_PALETTE.COLOR_ARCHER_AIM
const COLOR_ARCHER_AIM_BRACKET := COLOR_PALETTE.COLOR_ARCHER_AIM_BRACKET
const COLOR_ARCHER_PROJECTILE := COLOR_PALETTE.COLOR_ARCHER_PROJECTILE
const COLOR_SHIELDER_BODY := COLOR_PALETTE.COLOR_SHIELDER_BODY
const COLOR_SHIELDER_CORE := COLOR_PALETTE.COLOR_SHIELDER_CORE
const COLOR_SHIELDER_BODY_WINDUP := COLOR_PALETTE.COLOR_SHIELDER_BODY_WINDUP
const COLOR_SHIELDER_BODY_THUMP := COLOR_PALETTE.COLOR_SHIELDER_BODY_THUMP
const COLOR_SHIELDER_CORE_THUMP := COLOR_PALETTE.COLOR_SHIELDER_CORE_THUMP
const COLOR_SHIELDER_SHIELD := COLOR_PALETTE.COLOR_SHIELDER_SHIELD
const COLOR_SHIELDER_SHIELD_OUTLINE := COLOR_PALETTE.COLOR_SHIELDER_SHIELD_OUTLINE
const COLOR_SHIELDER_SLAM_WARNING_GLOW := COLOR_PALETTE.COLOR_SHIELDER_SLAM_WARNING_GLOW
const COLOR_SHIELDER_SLAM_WARNING_RING := COLOR_PALETTE.COLOR_SHIELDER_SLAM_WARNING_RING
const COLOR_SHIELDER_SLAM_SHOCK_GLOW := COLOR_PALETTE.COLOR_SHIELDER_SLAM_SHOCK_GLOW
const COLOR_SHIELDER_SLAM_SHOCK_RING := COLOR_PALETTE.COLOR_SHIELDER_SLAM_SHOCK_RING
const COLOR_BOSS_BODY := COLOR_PALETTE.COLOR_BOSS_BODY
const COLOR_BOSS_BODY_TELEGRAPH := COLOR_PALETTE.COLOR_BOSS_BODY_TELEGRAPH
const COLOR_BOSS_BODY_ATTACK := COLOR_PALETTE.COLOR_BOSS_BODY_ATTACK
const COLOR_BOSS_CORE := COLOR_PALETTE.COLOR_BOSS_CORE
const COLOR_BOSS_CORE_TELEGRAPH := COLOR_PALETTE.COLOR_BOSS_CORE_TELEGRAPH
const COLOR_BOSS_CORE_ATTACK := COLOR_PALETTE.COLOR_BOSS_CORE_ATTACK
const COLOR_BOSS_GLOW := COLOR_PALETTE.COLOR_BOSS_GLOW
const COLOR_BOSS_CHARGE_LINE := COLOR_PALETTE.COLOR_BOSS_CHARGE_LINE
const COLOR_BOSS_CHARGE_LINE_INNER := COLOR_PALETTE.COLOR_BOSS_CHARGE_LINE_INNER
const COLOR_BOSS_NOVA_GLOW := COLOR_PALETTE.COLOR_BOSS_NOVA_GLOW
const COLOR_BOSS_NOVA_RING := COLOR_PALETTE.COLOR_BOSS_NOVA_RING
const COLOR_BOSS_CLEAVE_FILL := COLOR_PALETTE.COLOR_BOSS_CLEAVE_FILL
const COLOR_BOSS_CLEAVE_OUTLINE := COLOR_PALETTE.COLOR_BOSS_CLEAVE_OUTLINE

@export var max_health: int = 40
@export var health_bar_size: Vector2 = Vector2(56.0, 8.0)
@export var health_bar_offset: Vector2 = Vector2(-28.0, -34.0)
@export var health_recent_damage_burst_window: float = 0.28
@export var health_recent_damage_hold_time: float = 0.6
@export var health_recent_damage_catchup_ratio_per_sec: float = 0.9
@export var crowd_separation_radius: float = 42.0
@export var crowd_separation_strength: float = 68.0

var target: Node2D
var health_bar: ProgressBar
var health_bar_recent_damage_overlay: Panel
var health_bar_threshold_overlay: Control
var health_bar_threshold_markers: Array[ColorRect] = []
var health_recent_damage_display_health: float = 0.0
var health_recent_damage_hold_left: float = 0.0
var health_recent_damage_time_since_last_hit: float = 999.0
var health_recent_damage_flash_strength: float = 0.0
var health_recent_damage_burst_active: bool = false
var health_state
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.1
var visual_facing_direction: Vector2 = Vector2.LEFT
var slow_time_left: float = 0.0
var slow_speed_mult: float = 1.0
var has_mutator_overlay: bool = false
var mutator_theme_color: Color = Color(1.0, 0.4, 0.4, 1.0)
var damage_blocked: bool = false

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
	_update_recent_damage_overlay(delta)
	_apply_crowd_separation(delta)
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
	if damage_blocked:
		return
	health_state.take_damage(amount)

func _apply_crowd_separation(delta: float) -> void:
	if crowd_separation_radius <= 0.0 or crowd_separation_strength <= 0.0:
		return
	var total_push := Vector2.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not (enemy is Node2D):
			continue
		var neighbor := enemy as Node2D
		var offset := global_position - neighbor.global_position
		var dist_sq := offset.length_squared()
		if dist_sq <= 0.0001:
			offset = Vector2.RIGHT.rotated(float(get_instance_id() % 360) * 0.0174533)
			dist_sq = 1.0
		var distance := sqrt(dist_sq)
		if distance >= crowd_separation_radius:
			continue
		var weight := 1.0 - (distance / crowd_separation_radius)
		total_push += (offset / distance) * weight
	if total_push.length_squared() <= 0.000001:
		return
	# Apply separation to velocity rather than warping position after movement
	var separation_impulse := total_push.normalized() * crowd_separation_strength
	velocity = velocity.move_toward(velocity + separation_impulse, crowd_separation_strength * delta)

func apply_slow(duration: float, mult: float) -> void:
	if duration > slow_time_left:
		slow_time_left = duration
	if mult < slow_speed_mult:
		slow_speed_mult = mult

func is_slowed() -> bool:
	return slow_time_left > 0.0

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
	health_bar.size = health_bar_size
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.clip_contents = true

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
	health_bar_recent_damage_overlay = Panel.new()
	health_bar_recent_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var recent_damage_style := StyleBoxFlat.new()
	recent_damage_style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	recent_damage_style.corner_radius_top_left = 0
	recent_damage_style.corner_radius_top_right = 3
	recent_damage_style.corner_radius_bottom_left = 0
	recent_damage_style.corner_radius_bottom_right = 3
	health_bar_recent_damage_overlay.add_theme_stylebox_override("panel", recent_damage_style)
	health_bar_recent_damage_overlay.visible = false
	health_bar.add_child(health_bar_recent_damage_overlay)
	health_bar_threshold_overlay = Control.new()
	health_bar_threshold_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar_threshold_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_child(health_bar_threshold_overlay)
	add_child(health_bar)
	health_recent_damage_display_health = float(_get_current_health())
	health_recent_damage_hold_left = 0.0
	health_recent_damage_time_since_last_hit = health_recent_damage_hold_time + 1.0
	health_recent_damage_flash_strength = 0.0
	health_recent_damage_burst_active = false
	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func _update_health_bar(new_health: int, new_max_health: int) -> void:
	if health_bar == null:
		return
	var previous_health := float(health_bar.value)
	health_bar.max_value = float(new_max_health)
	health_bar.value = float(new_health)

	if float(new_health) < previous_health:
		var lost_ratio := (previous_health - float(new_health)) / maxf(1.0, float(new_max_health))
		var continuing_stack := health_recent_damage_burst_active

		if not continuing_stack:
			health_recent_damage_display_health = previous_health
		else:
			health_recent_damage_display_health = maxf(health_recent_damage_display_health, previous_health)
		health_recent_damage_burst_active = true

		health_recent_damage_time_since_last_hit = 0.0
		health_recent_damage_hold_left = health_recent_damage_hold_time
		health_recent_damage_flash_strength = clampf(health_recent_damage_flash_strength + 0.34 + lost_ratio * 2.1, 0.0, 1.0)
	else:
		health_recent_damage_display_health = float(new_health)
		health_recent_damage_hold_left = 0.0
		health_recent_damage_time_since_last_hit = health_recent_damage_hold_time + 1.0
		health_recent_damage_flash_strength = 0.0
		health_recent_damage_burst_active = false

	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func configure_health_bar_visuals(offset: Vector2, size: Vector2 = Vector2.ZERO) -> void:
	health_bar_offset = offset
	if size != Vector2.ZERO:
		health_bar_size = size
	if health_bar == null:
		return
	health_bar.position = health_bar_offset
	health_bar.custom_minimum_size = health_bar_size
	health_bar.size = health_bar_size
	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func _update_recent_damage_overlay(delta: float) -> void:
	if health_bar == null:
		return
	if health_bar_recent_damage_overlay == null:
		return
	var current_health := float(health_bar.value)
	var max_health_value := maxf(1.0, float(health_bar.max_value))
	health_recent_damage_time_since_last_hit += delta

	if health_recent_damage_time_since_last_hit <= health_recent_damage_hold_time:
		health_recent_damage_hold_left = health_recent_damage_hold_time - health_recent_damage_time_since_last_hit
	else:
		health_recent_damage_hold_left = 0.0
		var old_display := health_recent_damage_display_health
		var catchup := max_health_value * maxf(0.1, health_recent_damage_catchup_ratio_per_sec) * delta
		health_recent_damage_display_health = maxf(current_health, health_recent_damage_display_health - catchup)
		if health_recent_damage_burst_active and old_display > current_health and health_recent_damage_display_health <= current_health + 0.001:
			health_recent_damage_display_health = current_health
			health_recent_damage_burst_active = false

	health_recent_damage_flash_strength = maxf(0.0, health_recent_damage_flash_strength - delta * 1.9)
	_update_recent_damage_overlay_layout()

func _update_recent_damage_overlay_layout() -> void:
	if health_bar == null:
		return
	if health_bar_recent_damage_overlay == null:
		return
	var max_health_value := maxf(1.0, float(health_bar.max_value))
	var current_ratio := clampf(float(health_bar.value) / max_health_value, 0.0, 1.0)
	var recent_ratio := clampf(health_recent_damage_display_health / max_health_value, 0.0, 1.0)
	var recent_width_ratio := maxf(0.0, recent_ratio - current_ratio)

	if recent_width_ratio <= 0.001:
		health_bar_recent_damage_overlay.visible = false
		return

	var bar_w := maxf(1.0, health_bar_size.x)
	var bar_h := maxf(1.0, health_bar_size.y)
	health_bar_recent_damage_overlay.visible = true
	health_bar_recent_damage_overlay.position = Vector2(bar_w * current_ratio, 0.0)
	var overlay_size := Vector2(maxf(1.0, bar_w * recent_width_ratio), bar_h)
	health_bar_recent_damage_overlay.custom_minimum_size = overlay_size
	health_bar_recent_damage_overlay.size = overlay_size

	var pulse := 1.0
	if health_recent_damage_hold_left > 0.0:
		pulse = 0.78 + 0.22 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.028))
	var alpha := clampf((0.18 + health_recent_damage_flash_strength * 0.56) * pulse, 0.08, 0.92)
	var panel_style := health_bar_recent_damage_overlay.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style != null:
		panel_style.bg_color = Color(1.0, 1.0, 1.0, alpha)

func set_health_threshold_markers(thresholds: Array, used_count: int = 0) -> void:
	if health_bar_threshold_overlay == null:
		return
	for marker in health_bar_threshold_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	health_bar_threshold_markers.clear()
	for index in range(thresholds.size()):
		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(2.0, maxf(health_bar_size.y + 2.0, 10.0))
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health_bar_threshold_overlay.add_child(marker)
		health_bar_threshold_markers.append(marker)
	set_health_threshold_marker_progress(used_count)
	_update_health_bar_threshold_layout()

func set_health_threshold_marker_progress(used_count: int) -> void:
	for index in range(health_bar_threshold_markers.size()):
		var marker := health_bar_threshold_markers[index]
		if not is_instance_valid(marker):
			continue
		if index < used_count:
			marker.color = Color(0.42, 0.48, 0.56, 0.95)
		else:
			marker.color = Color(1.0, 0.84, 0.3, 0.98)

func _update_health_bar_threshold_layout() -> void:
	if health_bar == null or health_bar_threshold_overlay == null:
		return
	if health_bar_threshold_markers.is_empty():
		return
	var marker_count := health_bar_threshold_markers.size()
	for index in range(marker_count):
		var marker := health_bar_threshold_markers[index]
		if not is_instance_valid(marker):
			continue
		var threshold_ratio := 1.0 - (float(index + 1) / float(marker_count + 1))
		var x := health_bar_size.x * threshold_ratio - 1.0
		marker.position = Vector2(x, -1.0)

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
	_draw_damage_blocked_indicator(body_radius)

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

func _draw_damage_blocked_indicator(body_radius: float) -> void:
	if not damage_blocked:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.009)
	var ring_color := Color(0.7, 0.94, 1.0, 0.56 + pulse * 0.2)
	draw_arc(Vector2.ZERO, body_radius + 13.0, 0.0, TAU, 40, ring_color, 2.6)
	draw_circle(Vector2.ZERO, body_radius + 11.2, Color(0.64, 0.9, 1.0, 0.05 + pulse * 0.03))

func _get_attack_pulse() -> float:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	return sin(attack_t * PI) * 1.8 if attack_anim_time_left > 0.0 else 0.0
