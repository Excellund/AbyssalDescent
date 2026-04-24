extends Node2D

const DEFAULT_IMPACT_SOUND := preload("res://sounds/impactPunch_medium_002.ogg")
const DEFAULT_ATTACK_SWING_SOUND := preload("res://sounds/impactSoft_medium_001.ogg")

var health_bar_size: Vector2 = Vector2(80.0, 10.0)
var health_bar_offset: Vector2 = Vector2(-40.0, -42.0)
var impact_sound: AudioStream = DEFAULT_IMPACT_SOUND
var impact_volume_db: float = -6.0
var attack_swing_sound: AudioStream = DEFAULT_ATTACK_SWING_SOUND
var attack_swing_volume_db: float = -10.0
var damage_flash_color: Color = Color(0.95, 0.12, 0.12, 1.0)
var damage_flash_alpha: float = 0.45
var damage_flash_fade_time: float = 0.16

var health_bar: ProgressBar
var impact_sound_player: AudioStreamPlayer2D
var attack_swing_sound_player: AudioStreamPlayer2D
var damage_flash_layer: CanvasLayer
var damage_flash_rect: ColorRect
var damage_flash_tween: Tween
var attack_swing_shape: Polygon2D
var attack_swing_tween: Tween

func setup(max_health: int, current_health: int) -> void:
	_create_health_bar(max_health, current_health)
	_create_impact_sound_player()
	_create_attack_swing_sound_player()
	_create_damage_flash()
	_create_attack_swing_visual()

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

func play_attack_swing_visual(direction: Vector2, swing_range: float, arc_degrees: float) -> void:
	if attack_swing_shape == null:
		return

	var points := PackedVector2Array()
	points.push_back(Vector2.ZERO)
	var half_arc := deg_to_rad(arc_degrees * 0.5)
	var segments := maxi(8, int(arc_degrees / 8.0))
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := lerpf(-half_arc, half_arc, t)
		points.push_back(Vector2.RIGHT.rotated(angle) * swing_range)

	attack_swing_shape.polygon = points
	attack_swing_shape.rotation = direction.angle()
	attack_swing_shape.visible = true
	attack_swing_shape.modulate = Color(1.0, 1.0, 1.0, 0.72)

	if attack_swing_tween != null and attack_swing_tween.is_valid():
		attack_swing_tween.kill()
	attack_swing_shape.scale = Vector2(0.92, 0.92)
	attack_swing_tween = create_tween()
	attack_swing_tween.set_parallel(true)
	attack_swing_tween.tween_property(attack_swing_shape, "modulate:a", 0.0, 0.11)
	attack_swing_tween.tween_property(attack_swing_shape, "scale", Vector2(1.06, 1.06), 0.11)

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

func _create_attack_swing_visual() -> void:
	attack_swing_shape = Polygon2D.new()
	attack_swing_shape.visible = false
	attack_swing_shape.color = Color(0.99, 0.96, 0.68, 0.72)
	add_child(attack_swing_shape)
