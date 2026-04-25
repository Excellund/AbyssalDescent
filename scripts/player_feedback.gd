extends Node2D

const DEFAULT_IMPACT_SOUND := preload("res://sounds/impactPunch_medium_002.ogg")
const DEFAULT_ATTACK_SWING_SOUND := preload("res://sounds/impactSoft_medium_001.ogg")
const ENEMY_BASE := preload("res://scripts/enemy_base.gd")

# === SHARED TIMING & ANIMATION HELPERS ===
static func ease_in_out_quad(t: float) -> float:
	"""Smooth ease-in-out quad curve. t should be in [0, 1]."""
	if t < 0.5:
		return 2.0 * t * t
	else:
		return 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

static func pulse_sine(time: float, frequency: float) -> float:
	"""Continuous sine pulse for smooth breathing animations."""
	return 0.5 + 0.5 * sin(time * frequency)

static func fade_curve(elapsed: float, duration: float) -> float:
	"""Linear fade from 1.0 to 0.0 over duration."""
	return maxf(0.0, 1.0 - elapsed / duration)

# === TELEGRAPH-SPECIFIC HELPERS ===
static func telegraph_intensity_pulse(time: float, frequency: float = 3.0) -> float:
	"""Pulsing intensity for telegraph danger rings (0.3-1.0 range for safe alpha mult)."""
	return 0.3 + pulse_sine(time, frequency) * 0.7

static func telegraph_glow_width(base_width: float, time: float, frequency: float = 2.0) -> float:
	"""Pulsing width expansion for telegraph rings."""
	return base_width + pulse_sine(time, frequency) * (base_width * 0.4)

var health_bar_size: Vector2 = Vector2(80.0, 10.0)
var health_bar_offset: Vector2 = Vector2(-40.0, -42.0)
var impact_sound: AudioStream = DEFAULT_IMPACT_SOUND
var impact_volume_db: float = -6.0
var attack_swing_sound: AudioStream = DEFAULT_ATTACK_SWING_SOUND
var attack_swing_volume_db: float = -10.0
var damage_flash_color: Color = ENEMY_BASE.COLOR_DAMAGE_FLASH
var damage_flash_alpha: float = 0.45
var damage_flash_fade_time: float = 0.16

var health_bar: ProgressBar
var impact_sound_player: AudioStreamPlayer2D
var attack_swing_sound_player: AudioStreamPlayer2D
var damage_flash_layer: CanvasLayer
var damage_flash_rect: ColorRect
var damage_flash_tween: Tween

func setup(max_health: int, current_health: int) -> void:
	_create_health_bar(max_health, current_health)
	_create_impact_sound_player()
	_create_attack_swing_sound_player()
	_create_damage_flash()

func update_health_bar(new_health: int, new_max_health: int) -> void:
	if health_bar == null:
		return
	health_bar.max_value = float(new_max_health)
	health_bar.value = float(new_health)

func play_impact_sound() -> void:
	if impact_sound_player == null:
		return
	if impact_sound_player.stream == null:
		return
	impact_sound_player.play()

func play_attack_swing_sound() -> void:
	if attack_swing_sound_player == null:
		return
	if attack_swing_sound_player.stream == null:
		return
	attack_swing_sound_player.play()

func play_attack_swing_visual(direction: Vector2, swing_range: float, arc_degrees: float, tint: Color = ENEMY_BASE.COLOR_SWING_DEFAULT, lifetime: float = 0.11) -> void:
	var swing_shape := Polygon2D.new()
	swing_shape.visible = true
	swing_shape.color = tint
	swing_shape.rotation = direction.angle()
	add_child(swing_shape)

	var points := PackedVector2Array()
	points.push_back(Vector2.ZERO)
	var half_arc := deg_to_rad(arc_degrees * 0.5)
	var segments := maxi(8, int(arc_degrees / 8.0))
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := lerpf(-half_arc, half_arc, t)
		points.push_back(Vector2.RIGHT.rotated(angle) * swing_range)

	swing_shape.polygon = points
	swing_shape.modulate = Color(1.0, 1.0, 1.0, tint.a)
	swing_shape.scale = Vector2(0.92, 0.92)

	var attack_swing_tween := create_tween()
	attack_swing_tween.set_parallel(true)
	attack_swing_tween.tween_property(swing_shape, "modulate:a", 0.0, lifetime)
	attack_swing_tween.tween_property(swing_shape, "scale", Vector2(1.06, 1.06), lifetime)
	attack_swing_tween.set_parallel(false)
	attack_swing_tween.tween_interval(lifetime)
	attack_swing_tween.tween_callback(swing_shape.queue_free)

func play_world_ring(epicenter_global: Vector2, radius: float, color: Color, lifetime: float = 0.2) -> void:
	var ring := Line2D.new()
	ring.top_level = true
	ring.global_position = Vector2.ZERO
	ring.width = 4.0
	ring.default_color = color
	ring.closed = true
	ring.antialiased = true
	ring.z_index = 40

	var points := PackedVector2Array()
	var segments := 32
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(epicenter_global + Vector2.RIGHT.rotated(angle) * radius)
	ring.points = points

	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "modulate:a", 0.0, lifetime)
	tween.tween_property(ring, "width", 1.0, lifetime)
	tween.set_parallel(false)
	tween.tween_interval(lifetime)
	tween.tween_callback(ring.queue_free)

# === IMPACT FEEDBACK HIERARCHY ===
func play_impact_light(epicenter_global: Vector2, radius: float = 60.0) -> void:
	"""Light hit feedback: subtle ring + gentle flash (standard hits)."""
	# Subtle ring
	play_world_ring(epicenter_global, radius, Color(0.7, 0.7, 0.8, 0.4), 0.18)
	# Light flash
	play_damage_flash()

func play_impact_heavy(epicenter_global: Vector2, radius: float = 100.0) -> void:
	"""Heavy impact feedback: layered rings + strong flash + pulsing afterglow (abilities)."""
	# Inner danger pulse ring
	var inner_ring := Line2D.new()
	inner_ring.top_level = true
	inner_ring.global_position = Vector2.ZERO
	inner_ring.width = 6.0
	inner_ring.default_color = Color(1.0, 0.5, 0.3, 0.85)
	inner_ring.closed = true
	inner_ring.antialiased = true
	inner_ring.z_index = 41

	var inner_points := PackedVector2Array()
	var segments := 40
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		inner_points.append(epicenter_global + Vector2.RIGHT.rotated(angle) * (radius * 0.5))
	inner_ring.points = inner_points
	add_child(inner_ring)

	var inner_tween := create_tween()
	inner_tween.set_parallel(true)
	inner_tween.tween_property(inner_ring, "modulate:a", 0.0, 0.12)
	inner_tween.tween_property(inner_ring, "width", 2.0, 0.12)
	inner_tween.set_parallel(false)
	inner_tween.tween_interval(0.12)
	inner_tween.tween_callback(inner_ring.queue_free)

	# Outer expansion ring (main impact zone)
	play_world_ring(epicenter_global, radius, Color(1.0, 0.6, 0.2, 0.7), 0.25)

	# Pulsing afterglow (lingers with intensity wave)
	var afterglow := Line2D.new()
	afterglow.top_level = true
	afterglow.global_position = Vector2.ZERO
	afterglow.width = 2.0
	afterglow.default_color = Color(1.0, 0.4, 0.0, 0.3)
	afterglow.closed = true
	afterglow.antialiased = true
	afterglow.z_index = 39

	var afterglow_points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		afterglow_points.append(epicenter_global + Vector2.RIGHT.rotated(angle) * (radius * 0.7))
	afterglow.points = afterglow_points
	add_child(afterglow)

	var afterglow_tween := create_tween()
	afterglow_tween.set_parallel(true)
	afterglow_tween.tween_property(afterglow, "modulate:a", 0.0, 0.35)
	afterglow_tween.tween_property(afterglow, "width", 1.0, 0.35)
	afterglow_tween.set_parallel(false)
	afterglow_tween.tween_interval(0.35)
	afterglow_tween.tween_callback(afterglow.queue_free)

	# Strong flash (heavier visual punch)
	if damage_flash_rect != null:
		if damage_flash_tween != null and damage_flash_tween.is_valid():
			damage_flash_tween.kill()
		damage_flash_rect.modulate.a = damage_flash_alpha * 1.3
		damage_flash_tween = create_tween()
		damage_flash_tween.tween_property(damage_flash_rect, "modulate:a", 0.0, 0.22)

func play_damage_flash() -> void:
	if damage_flash_rect == null:
		return
	if damage_flash_tween != null and damage_flash_tween.is_valid():
		damage_flash_tween.kill()
	damage_flash_rect.modulate.a = damage_flash_alpha
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(damage_flash_rect, "modulate:a", 0.0, damage_flash_fade_time)

func _create_health_bar(max_health: int, current_health: int) -> void:
	health_bar = ProgressBar.new()
	health_bar.min_value = 0.0
	health_bar.max_value = float(max_health)
	health_bar.value = float(current_health)
	health_bar.show_percentage = false
	health_bar.position = health_bar_offset
	health_bar.custom_minimum_size = health_bar_size
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = ENEMY_BASE.COLOR_HEALTH_BAR_BG
	background_style.corner_radius_top_left = 3
	background_style.corner_radius_top_right = 3
	background_style.corner_radius_bottom_left = 3
	background_style.corner_radius_bottom_right = 3

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3

	health_bar.add_theme_stylebox_override("background", background_style)
	health_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(health_bar)

func _create_impact_sound_player() -> void:
	impact_sound_player = AudioStreamPlayer2D.new()
	impact_sound_player.stream = impact_sound
	impact_sound_player.volume_db = impact_volume_db
	add_child(impact_sound_player)

func _create_attack_swing_sound_player() -> void:
	attack_swing_sound_player = AudioStreamPlayer2D.new()
	attack_swing_sound_player.stream = attack_swing_sound
	attack_swing_sound_player.volume_db = attack_swing_volume_db
	add_child(attack_swing_sound_player)

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

