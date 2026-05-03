extends Node2D

const DEFAULT_IMPACT_SOUND := preload("res://sounds/impactPunch_medium_002.ogg")
const DEFAULT_ATTACK_SWING_SOUND := preload("res://sounds/impactSoft_medium_001.ogg")
const ENEMY_BASE := preload("res://scripts/enemy_base.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")

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
var voidfire_bar_size: Vector2 = Vector2(80.0, 6.0)
var voidfire_bar_offset: Vector2 = Vector2(-40.0, -51.0)
var oath_bar_size: Vector2 = Vector2(80.0, 5.0)
var oath_bar_offset: Vector2 = Vector2(-40.0, -51.0)
const VOIDFIRE_DANGER_RATIO: float = 0.70
var impact_sound: AudioStream = DEFAULT_IMPACT_SOUND
var impact_volume_db: float = -6.0
var attack_swing_sound: AudioStream = DEFAULT_ATTACK_SWING_SOUND
var attack_swing_volume_db: float = -10.0
var sfx_volume_db: float = 0.0
var damage_flash_color: Color = ENEMY_BASE.COLOR_DAMAGE_FLASH
var damage_flash_alpha: float = 0.45
var damage_flash_fade_time: float = 0.16

var health_bar: ProgressBar
var voidfire_bar: ProgressBar
var voidfire_sweetspot_zone: ColorRect
var voidfire_threshold_line: ColorRect
var voidfire_glow: ColorRect
var voidfire_bar_background_style: StyleBoxFlat
var voidfire_bar_fill_style: StyleBoxFlat
var oath_bar: ProgressBar
var oath_bar_background_style: StyleBoxFlat
var oath_bar_fill_style: StyleBoxFlat
var oath_bar_glow: ColorRect
var impact_sound_player: AudioStreamPlayer2D
var attack_swing_sound_player: AudioStreamPlayer2D
var damage_flash_layer: CanvasLayer
var damage_flash_rect: ColorRect
var damage_flash_tween: Tween
var _eclipse_mark_decals: Dictionary = {}
var _eclipse_mark_decal_token_seed: int = 1
var _eclipse_mark_pulse_tweens: Dictionary = {}
var _eclipse_mark_life_tweens: Dictionary = {}
var _tempo_indicator_root: Node2D
var _tempo_outer_ring: Line2D
var _tempo_inner_ring: Line2D
var _tempo_ready_ring: Line2D
var _tempo_pips: Array[Polygon2D] = []
var _tempo_state_active: bool = false
var _tempo_stacks: int = 0
var _tempo_max_stacks: int = 0
var _tempo_time_left: float = 0.0
var _tempo_duration: float = 0.0
var _tempo_phase: float = 0.0
var _tempo_ready_flash_left: float = 0.0
var _tempo_urgency_triggered: bool = false

func setup(max_health: int, current_health: int) -> void:
	_create_health_bar(max_health, current_health)
	_create_voidfire_bar()
	_create_oath_bank_bar()
	_create_impact_sound_player()
	_create_attack_swing_sound_player()
	_create_damage_flash()
	_apply_sfx_volume()

func set_sfx_volume_db(volume_db: float) -> void:
	sfx_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	_apply_sfx_volume()

func _process(delta: float) -> void:
	if not _tempo_state_active:
		return
	_ensure_tempo_indicator()
	if _tempo_indicator_root == null:
		return
	_tempo_phase += delta
	_tempo_ready_flash_left = maxf(0.0, _tempo_ready_flash_left - delta)
	var max_stacks := maxi(1, _tempo_max_stacks)
	var stack_ratio := clampf(float(_tempo_stacks) / float(max_stacks), 0.0, 1.0)
	var life_ratio := clampf(_tempo_time_left / maxf(0.001, _tempo_duration), 0.0, 1.0)
	var urgency := clampf((0.35 - life_ratio) / 0.35, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_tempo_phase * (5.5 + urgency * 4.5))
	var outer_color := Color(1.0, 0.82 - urgency * 0.20, 0.42 + urgency * 0.10, 0.34 + 0.22 * pulse)
	var inner_color := Color(1.0, 0.94 - urgency * 0.20, 0.70, 0.24 + 0.18 * pulse)
	_tempo_outer_ring.default_color = outer_color
	_tempo_outer_ring.width = 1.4 + stack_ratio * 1.8 + urgency * 0.8
	_tempo_inner_ring.default_color = inner_color
	_tempo_inner_ring.width = 1.0 + stack_ratio * 1.0
	var show_ready := _tempo_stacks >= max_stacks
	_tempo_ready_ring.visible = show_ready
	if show_ready:
		var ready_pulse := 0.5 + 0.5 * sin(_tempo_phase * 9.0)
		var flash_boost := clampf(_tempo_ready_flash_left / 0.26, 0.0, 1.0)
		_tempo_ready_ring.default_color = Color(1.0, 0.96, 0.76, 0.18 + ready_pulse * 0.32 + flash_boost * 0.36)
		_tempo_ready_ring.width = 1.4 + ready_pulse * 1.6 + flash_boost * 1.2
	for i in range(_tempo_pips.size()):
		var pip := _tempo_pips[i]
		if pip == null:
			continue
		var filled := i < _tempo_stacks
		if filled:
			pip.color = Color(1.0, 0.88, 0.56, 0.44 + 0.42 * pulse)
			pip.scale = Vector2.ONE * (1.0 + 0.08 * pulse)
		else:
			pip.color = Color(0.96, 0.86, 0.70, 0.14)
			pip.scale = Vector2.ONE * 0.92

func _ensure_tempo_indicator() -> void:
	if is_instance_valid(_tempo_indicator_root):
		return
	_tempo_indicator_root = Node2D.new()
	_tempo_indicator_root.z_index = 58
	_tempo_indicator_root.visible = false
	add_child(_tempo_indicator_root)
	_tempo_outer_ring = Line2D.new()
	_tempo_outer_ring.width = 2.0
	_tempo_outer_ring.closed = true
	_tempo_outer_ring.antialiased = true
	_tempo_outer_ring.default_color = Color(1.0, 0.84, 0.48, 0.42)
	_tempo_outer_ring.points = _build_circle_polygon(22.0, 26)
	_tempo_indicator_root.add_child(_tempo_outer_ring)
	_tempo_inner_ring = Line2D.new()
	_tempo_inner_ring.width = 1.2
	_tempo_inner_ring.closed = true
	_tempo_inner_ring.antialiased = true
	_tempo_inner_ring.default_color = Color(1.0, 0.94, 0.72, 0.3)
	_tempo_inner_ring.points = _build_circle_polygon(15.0, 22)
	_tempo_indicator_root.add_child(_tempo_inner_ring)
	_tempo_ready_ring = Line2D.new()
	_tempo_ready_ring.width = 1.8
	_tempo_ready_ring.closed = true
	_tempo_ready_ring.antialiased = true
	_tempo_ready_ring.default_color = Color(1.0, 0.98, 0.84, 0.0)
	_tempo_ready_ring.points = _build_circle_polygon(29.0, 30)
	_tempo_ready_ring.visible = false
	_tempo_indicator_root.add_child(_tempo_ready_ring)
	_tempo_pips.clear()
	for i in range(6):
		var pip := Polygon2D.new()
		var angle := -PI * 0.5 + TAU * float(i) / 6.0
		pip.position = Vector2.RIGHT.rotated(angle) * 26.0
		pip.polygon = _build_circle_polygon(2.2, 10)
		pip.color = Color(0.96, 0.86, 0.70, 0.14)
		_tempo_indicator_root.add_child(pip)
		_tempo_pips.append(pip)

func update_boss_tempo_state(stacks: int, max_stacks: int, time_left: float, stack_duration: float) -> void:
	_ensure_tempo_indicator()
	_tempo_stacks = maxi(0, stacks)
	_tempo_max_stacks = maxi(1, max_stacks)
	_tempo_time_left = maxf(0.0, time_left)
	_tempo_duration = maxf(0.001, stack_duration)
	var active := _tempo_stacks > 0
	_tempo_state_active = active
	if _tempo_indicator_root != null:
		_tempo_indicator_root.visible = active
	if not active:
		_tempo_urgency_triggered = false
		return
	if _tempo_stacks >= _tempo_max_stacks:
		_tempo_ready_flash_left = maxf(_tempo_ready_flash_left, 0.26)
	var life_ratio := clampf(_tempo_time_left / _tempo_duration, 0.0, 1.0)
	if life_ratio <= 0.22 and not _tempo_urgency_triggered:
		_tempo_urgency_triggered = true
		play_world_ring(global_position, 30.0, Color(1.0, 0.64, 0.34, 0.56), 0.14)
	if life_ratio > 0.30:
		_tempo_urgency_triggered = false

func clear_boss_tempo_state() -> void:
	_tempo_state_active = false
	_tempo_stacks = 0
	_tempo_time_left = 0.0
	_tempo_urgency_triggered = false
	_tempo_ready_flash_left = 0.0
	if _tempo_indicator_root != null:
		_tempo_indicator_root.visible = false

func update_health_bar(new_health: int, new_max_health: int) -> void:
	if health_bar == null:
		return
	health_bar.max_value = float(new_max_health)
	health_bar.value = float(new_health)

func update_voidfire_heat_bar(heat: float, heat_cap: float, enabled: bool, lockout_left: float = 0.0, danger_ratio: float = VOIDFIRE_DANGER_RATIO) -> void:
	if voidfire_bar == null:
		return
	voidfire_bar.visible = enabled
	if voidfire_sweetspot_zone != null:
		voidfire_sweetspot_zone.visible = enabled
	if voidfire_threshold_line != null:
		voidfire_threshold_line.visible = enabled
	if voidfire_glow != null:
		voidfire_glow.visible = enabled
	_layout_status_bars()
	if not enabled:
		return

	var clamped_cap := maxf(1.0, heat_cap)
	var clamped_heat := clampf(heat, 0.0, clamped_cap)
	var heat_ratio := clampf(clamped_heat / clamped_cap, 0.0, 1.0)
	var sweetspot_ratio := clampf(danger_ratio, 0.0, 0.98)
	var in_sweetspot := heat_ratio >= sweetspot_ratio and lockout_left <= 0.0
	var warm_t := clampf((heat_ratio - sweetspot_ratio) / maxf(0.001, 1.0 - sweetspot_ratio), 0.0, 1.0)

	voidfire_bar.max_value = clamped_cap
	voidfire_bar.value = clamped_heat

	var cool_fill := Color(0.26, 0.72, 0.98, 0.88)
	var hot_fill := Color(1.0, 0.78, 0.34, 0.96)
	var fill_color := cool_fill.lerp(hot_fill, warm_t)
	fill_color.a = 0.62 + heat_ratio * 0.34
	if lockout_left > 0.0:
		fill_color = Color(0.52, 0.82, 1.0, 0.84)
	if voidfire_bar_fill_style != null:
		voidfire_bar_fill_style.bg_color = fill_color

	var threshold_base := Color(0.76, 0.9, 1.0, 0.72)
	var threshold_hot := Color(1.0, 0.94, 0.74, 0.96)
	if voidfire_threshold_line != null:
		voidfire_threshold_line.position = voidfire_bar_offset + Vector2(voidfire_bar_size.x * sweetspot_ratio - 1.0, -1.0)
		voidfire_threshold_line.color = threshold_base.lerp(threshold_hot, warm_t)

	if voidfire_sweetspot_zone != null:
		voidfire_sweetspot_zone.position = voidfire_bar_offset + Vector2(voidfire_bar_size.x * sweetspot_ratio, 0.0)
		voidfire_sweetspot_zone.size = Vector2(voidfire_bar_size.x * (1.0 - sweetspot_ratio), voidfire_bar_size.y)
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * 9.0)
		var sweet_alpha := 0.08 + heat_ratio * 0.12
		if in_sweetspot:
			sweet_alpha = 0.24 + pulse * 0.22
		voidfire_sweetspot_zone.color = Color(1.0, 0.84, 0.44, sweet_alpha)

	if voidfire_glow != null:
		var glow_alpha := 0.0
		if lockout_left > 0.0:
			var lock_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * 14.0)
			glow_alpha = 0.24 + lock_pulse * 0.28
			voidfire_glow.color = Color(0.56, 0.84, 1.0, glow_alpha)
		elif in_sweetspot:
			var sweet_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * 10.0)
			glow_alpha = 0.22 + sweet_pulse * 0.24
			voidfire_glow.color = Color(1.0, 0.86, 0.48, glow_alpha)
		else:
			glow_alpha = 0.08 + heat_ratio * 0.1
			voidfire_glow.color = Color(0.48, 0.78, 1.0, glow_alpha)

func update_oath_bank_bar(bank: float, bank_reference: float, enabled: bool) -> void:
	if oath_bar == null:
		return
	var clamped_bank := maxf(0.0, bank)
	var max_bank := maxf(1.0, bank_reference)
	var visible := enabled or clamped_bank > 0.0
	oath_bar.visible = visible
	if oath_bar_glow != null:
		oath_bar_glow.visible = visible
	_layout_status_bars()
	if not visible:
		return
	var bank_ratio := clampf(clamped_bank / max_bank, 0.0, 1.0)
	oath_bar.max_value = max_bank
	oath_bar.value = minf(clamped_bank, max_bank)
	var cold_fill := Color(0.64, 0.46, 0.94, 0.88)
	var hot_fill := Color(0.96, 0.72, 1.0, 0.96)
	if oath_bar_fill_style != null:
		oath_bar_fill_style.bg_color = cold_fill.lerp(hot_fill, bank_ratio)
	if oath_bar_glow != null:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * 8.0)
		var glow_alpha := 0.06 + bank_ratio * 0.16 + pulse * 0.08 * bank_ratio
		oath_bar_glow.color = Color(0.88, 0.66, 1.0, glow_alpha)

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

func _play_world_line(points: PackedVector2Array, color: Color, width: float, lifetime: float, final_width: float = 1.0) -> void:
	if points.size() < 2:
		return
	var line := Line2D.new()
	line.top_level = true
	line.global_position = Vector2.ZERO
	line.width = width
	line.default_color = color
	line.antialiased = true
	line.z_index = 41
	line.points = points
	add_child(line)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(line, "modulate:a", 0.0, lifetime)
	tween.tween_property(line, "width", final_width, lifetime)
	tween.set_parallel(false)
	tween.tween_interval(lifetime)
	tween.tween_callback(line.queue_free)

func _play_world_soft_pulse(epicenter_global: Vector2, radius: float, color: Color, lifetime: float, start_scale: float = 0.7, end_scale: float = 1.16) -> void:
	var pulse := Polygon2D.new()
	pulse.top_level = true
	pulse.global_position = epicenter_global
	pulse.polygon = _build_circle_polygon(radius, 28)
	pulse.color = color
	pulse.z_index = 39
	pulse.scale = Vector2.ONE * start_scale
	add_child(pulse)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "modulate:a", 0.0, lifetime)
	tween.tween_property(pulse, "scale", Vector2.ONE * end_scale, lifetime)
	tween.set_parallel(false)
	tween.tween_interval(lifetime)
	tween.tween_callback(pulse.queue_free)

func _play_world_star_burst(epicenter_global: Vector2, radius: float, ray_count: int, color: Color, lifetime: float) -> void:
	var clamped_rays := maxi(4, ray_count)
	for i in range(clamped_rays):
		var angle := TAU * float(i) / float(clamped_rays)
		var dir := Vector2.RIGHT.rotated(angle)
		var inner := epicenter_global + dir * (radius * 0.18)
		var outer := epicenter_global + dir * (radius * 0.72)
		_play_world_line(PackedVector2Array([inner, outer]), color, 2.2, lifetime, 0.7)

func _build_circle_polygon(radius: float, segments: int = 20) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var clamped_segments := maxi(8, segments)
	for i in range(clamped_segments):
		var angle := TAU * float(i) / float(clamped_segments)
		polygon.append(Vector2(cos(angle), sin(angle)) * radius)
	return polygon

func _spawn_heal_cross(epicenter_global: Vector2, start_offset: Vector2, drift: Vector2, duration: float, base_scale: float, rotation_bias: float) -> void:
	var cross := Node2D.new()
	cross.top_level = true
	cross.global_position = epicenter_global + start_offset
	cross.scale = Vector2(base_scale, base_scale)
	cross.rotation = rotation_bias
	cross.z_index = 45

	var arm_length := 16.0
	var arm_width := 6.0
	var cross_color := Color(ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.r, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.g, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.b, 0.9)

	var vertical := ColorRect.new()
	vertical.color = cross_color
	vertical.size = Vector2(arm_width, arm_length)
	vertical.position = Vector2(-arm_width * 0.5, -arm_length * 0.5)
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.add_child(vertical)

	var horizontal := ColorRect.new()
	horizontal.color = cross_color
	horizontal.size = Vector2(arm_length, arm_width)
	horizontal.position = Vector2(-arm_length * 0.5, -arm_width * 0.5)
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.add_child(horizontal)

	add_child(cross)

	var end_position := cross.global_position + drift
	var end_rotation := rotation_bias + randf_range(-0.22, 0.22)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cross, "global_position", end_position, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cross, "rotation", end_rotation, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cross, "scale", Vector2(base_scale * 1.08, base_scale * 1.08), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cross, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_interval(duration)
	tween.tween_callback(cross.queue_free)

func _spawn_heal_pulse(epicenter_global: Vector2) -> void:
	var pulse := Polygon2D.new()
	pulse.top_level = true
	pulse.global_position = epicenter_global
	pulse.z_index = 44
	pulse.polygon = _build_circle_polygon(20.0, 24)
	pulse.color = Color(ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.r, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.g, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.b, 0.24)
	pulse.scale = Vector2(0.6, 0.6)
	add_child(pulse)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2(1.55, 1.55), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(0.2)
	tween.tween_callback(pulse.queue_free)

func play_rest_site_heal(epicenter_global: Vector2) -> void:
	_spawn_heal_pulse(epicenter_global)
	play_world_ring(epicenter_global, 20.0, Color(ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.r, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.g, ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL.b, 0.92), 0.11)
	play_world_ring(epicenter_global, 34.0, Color(0.84, 1.0, 0.86, 0.54), 0.18)
	play_world_ring(epicenter_global, 48.0, Color(0.72, 0.94, 0.76, 0.28), 0.24)

	for i in range(5):
		var angle := TAU * (float(i) / 5.0) + randf_range(-0.14, 0.14)
		var spawn_radius := randf_range(10.0, 20.0)
		var start_offset := Vector2(cos(angle), sin(angle)) * spawn_radius
		var radial_dir := start_offset.normalized() if start_offset.length_squared() > 0.00001 else Vector2.RIGHT
		var radial_drift := radial_dir * randf_range(14.0, 22.0)
		var tangential_drift := Vector2(-radial_dir.y, radial_dir.x) * randf_range(-5.0, 5.0)
		var lift_drift := Vector2(0.0, randf_range(-16.0, -8.0))
		var drift := radial_drift + tangential_drift + lift_drift
		var duration := randf_range(0.34, 0.44)
		var cross_scale := randf_range(0.9, 1.02)
		var rotation_bias := randf_range(-0.06, 0.06)
		_spawn_heal_cross(epicenter_global, start_offset, drift, duration, cross_scale, rotation_bias)

func play_combo_relay_kill(epicenter_global: Vector2, stack_count: int, max_stacks: int, color: Color, lifetime: float = 0.2) -> void:
	var clamped_max := maxi(1, max_stacks)
	var clamped_stack := clampi(stack_count, 1, clamped_max)
	var stack_ratio := float(clamped_stack) / float(clamped_max)
	var radius := 22.0 + float(clamped_stack) * 3.5

	# Outer clock face pulse.
	play_world_ring(epicenter_global, radius, Color(color.r, color.g, color.b, 0.82), lifetime)

	# Four stack pips at cardinal points to mirror the mutator icon language.
	for i in range(4):
		var angle := -PI * 0.5 + TAU * float(i) * 0.25
		var pip_pos := epicenter_global + Vector2(cos(angle), sin(angle)) * radius
		play_world_ring(pip_pos, 2.6, Color(color.r, color.g, color.b, 0.7), lifetime * 0.82)

	# Sweeping arc communicates relay progress from current stack fill.
	var sweep_points := PackedVector2Array()
	var sweep_start := -PI * 0.5
	var sweep_end := sweep_start + TAU * stack_ratio
	var sweep_segments := maxi(8, int(22.0 * stack_ratio))
	for i in range(sweep_segments + 1):
		var t := float(i) / float(maxi(1, sweep_segments))
		var angle := lerpf(sweep_start, sweep_end, t)
		sweep_points.append(epicenter_global + Vector2(cos(angle), sin(angle)) * (radius + 1.8))
	_play_world_line(sweep_points, Color(color.r, color.g, color.b, 0.95), 2.4, lifetime * 0.95, 1.0)

	# Main hand plus trailing blur lines for speed-up motion feel.
	var hand_angle := sweep_end
	var hand_len := radius - 3.2
	for i in range(2, -1, -1):
		var trail_offset := float(i) * 0.22
		var alpha := 0.25 + (2.0 - float(i)) * 0.24
		var line_points := PackedVector2Array([
			epicenter_global,
			epicenter_global + Vector2(cos(hand_angle - trail_offset), sin(hand_angle - trail_offset)) * hand_len
		])
		_play_world_line(line_points, Color(color.r, color.g, color.b, alpha), 1.2 + (2.0 - float(i)) * 0.35, lifetime * 0.9, 0.8)

func play_iron_retort_window_open(epicenter_global: Vector2) -> void:
	var core := Color(1.0, 0.56, 0.3, 0.76)
	play_world_ring(epicenter_global, 28.0, core, 0.16)
	play_world_ring(epicenter_global, 46.0, Color(1.0, 0.78, 0.56, 0.58), 0.2)
	for i in range(4):
		var angle := -PI * 0.5 + TAU * float(i) / 4.0
		var p0 := epicenter_global + Vector2(cos(angle), sin(angle)) * 18.0
		var p1 := epicenter_global + Vector2(cos(angle), sin(angle)) * 36.0
		_play_world_line(PackedVector2Array([p0, p1]), Color(1.0, 0.74, 0.5, 0.62), 1.6, 0.14, 0.7)

func play_iron_retort_consume(player_global: Vector2, impact_global: Vector2) -> void:
	var dir := impact_global - player_global
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var forward := dir.normalized()
	var side := Vector2(-forward.y, forward.x)
	play_world_ring(player_global, 20.0, Color(1.0, 0.6, 0.34, 0.58), 0.1)
	play_world_ring(impact_global, 30.0, Color(1.0, 0.44, 0.24, 0.72), 0.12)
	for i in range(0, 2):
		var lane := -1.0 if i == 0 else 1.0
		var offset := side * (lane * 7.0)
		var start := player_global + forward * 10.0 + offset
		var end := impact_global + forward * 8.0 + offset
		_play_world_line(PackedVector2Array([start, end]), Color(1.0, 0.74, 0.5, 0.72), 1.8, 0.09, 0.65)

func play_fracture_field_fault_lines(epicenter_global: Vector2, radius: float, beam_count: int, base_angle: float, beam_width: float = 12.0) -> void:
	var core_color := Color(0.86, 0.96, 1.0, 0.9)
	var fault_color := Color(0.38, 0.86, 1.0, 0.82)
	var ember_color := Color(1.0, 0.78, 0.42, 0.6)
	var halo_color := Color(0.42, 0.9, 1.0, 0.14)

	play_world_ring(epicenter_global, 14.0, core_color, 0.08)
	play_world_ring(epicenter_global, 24.0, Color(fault_color.r, fault_color.g, fault_color.b, 0.45), 0.14)

	for i in range(beam_count):
		var ang := base_angle + TAU * (float(i) / float(beam_count))
		var dir := Vector2.RIGHT.rotated(ang)
		var tip := epicenter_global + dir * radius

		_play_world_line(
			PackedVector2Array([epicenter_global, tip]),
			halo_color,
			beam_width * 2.0,
			0.22,
			0.9
		)

		_play_world_line(
			PackedVector2Array([epicenter_global, tip]),
			fault_color,
			3.0,
			0.2,
			0.9
		)
		_play_world_line(
			PackedVector2Array([epicenter_global + dir * 8.0, tip]),
			ember_color,
			1.7,
			0.16,
			0.6
		)

# === IMPACT FEEDBACK HIERARCHY ===
func play_impact_light(epicenter_global: Vector2, radius: float = 60.0) -> void:
	"""Light hit feedback: subtle ring + gentle flash (standard hits)."""
	# Subtle ring
	play_world_ring(epicenter_global, radius, Color(0.7, 0.7, 0.8, 0.4), 0.18)
	# Light flash
	play_damage_flash()

func play_impact_medium(epicenter_global: Vector2, radius: float = 80.0) -> void:
	"""Medium impact feedback: stronger than light, cleaner than heavy (contact hits)."""
	play_world_ring(epicenter_global, radius, Color(0.92, 0.74, 0.5, 0.56), 0.2)
	if damage_flash_rect != null:
		if damage_flash_tween != null and damage_flash_tween.is_valid():
			damage_flash_tween.kill()
		damage_flash_rect.modulate.a = damage_flash_alpha * 1.1
		damage_flash_tween = create_tween()
		damage_flash_tween.tween_property(damage_flash_rect, "modulate:a", 0.0, 0.18)

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

func play_chain_lightning(from_global: Vector2, target_global: Vector2, color: Color = Color(0.98, 0.98, 0.76, 0.92), lifetime: float = 0.14) -> void:
	var dir := target_global - from_global
	var length := dir.length()
	if length < 1.0:
		return
	var perp := dir.normalized().rotated(PI * 0.5)
	var jag_scale := length * 0.22
	var pts := PackedVector2Array()
	pts.push_back(from_global)
	for i in range(1, 5):
		var tt := float(i) / 5.0
		pts.push_back(from_global.lerp(target_global, tt) + perp * randf_range(-jag_scale, jag_scale))
	pts.push_back(target_global)

	# Outer glow bolt
	var bolt := Line2D.new()
	bolt.top_level = true
	bolt.global_position = Vector2.ZERO
	bolt.width = 3.2
	bolt.default_color = color
	bolt.antialiased = true
	bolt.z_index = 42
	bolt.points = pts
	add_child(bolt)
	var t1 := create_tween()
	t1.set_parallel(true)
	t1.tween_property(bolt, "modulate:a", 0.0, lifetime)
	t1.tween_property(bolt, "width", 0.8, lifetime)
	t1.set_parallel(false)
	t1.tween_interval(lifetime)
	t1.tween_callback(bolt.queue_free)

	# Inner white core
	var core := Line2D.new()
	core.top_level = true
	core.global_position = Vector2.ZERO
	core.width = 1.4
	core.default_color = Color(1.0, 1.0, 1.0, 0.8)
	core.antialiased = true
	core.z_index = 43
	core.points = pts
	add_child(core)
	var t2 := create_tween()
	t2.tween_property(core, "modulate:a", 0.0, lifetime * 0.45)
	t2.tween_callback(core.queue_free)

func play_wraithstep_chain_echo(from_global: Vector2, target_global: Vector2, lifetime: float = 0.18) -> void:
	var dir := target_global - from_global
	var length := dir.length()
	if length < 1.0:
		return
	var perp := dir.normalized().rotated(PI * 0.5)
	var bend := minf(26.0, length * 0.22)
	var arc_mid := from_global.lerp(target_global, 0.5) + perp * randf_range(-bend, bend)

	var ribbon := Line2D.new()
	ribbon.top_level = true
	ribbon.global_position = Vector2.ZERO
	ribbon.width = 2.8
	ribbon.default_color = Color(0.72, 0.94, 1.0, 0.86)
	ribbon.antialiased = true
	ribbon.z_index = 42
	ribbon.points = PackedVector2Array([from_global, arc_mid, target_global])
	add_child(ribbon)

	var core := Line2D.new()
	core.top_level = true
	core.global_position = Vector2.ZERO
	core.width = 1.2
	core.default_color = Color(0.96, 1.0, 1.0, 0.76)
	core.antialiased = true
	core.z_index = 43
	core.points = ribbon.points
	add_child(core)

	var t1 := create_tween()
	t1.set_parallel(true)
	t1.tween_property(ribbon, "modulate:a", 0.0, lifetime)
	t1.tween_property(ribbon, "width", 0.8, lifetime)
	t1.tween_property(core, "modulate:a", 0.0, lifetime * 0.72)
	t1.tween_property(core, "width", 0.5, lifetime * 0.72)
	t1.set_parallel(false)
	t1.tween_interval(lifetime)
	t1.tween_callback(ribbon.queue_free)
	t1.tween_callback(core.queue_free)

	play_world_ring(target_global, 12.0, Color(0.86, 0.98, 1.0, 0.7), lifetime * 0.7)

func play_polar_shift_dash_lockout(epicenter_global: Vector2) -> void:
	play_world_ring(epicenter_global, 16.0, Color(0.96, 0.98, 1.0, 0.94), 0.07)
	play_world_ring(epicenter_global, 26.0, Color(0.32, 0.78, 0.98, 0.62), 0.14)
	play_world_ring(epicenter_global, 36.0, Color(1.0, 0.58, 0.28, 0.28), 0.18)

func play_storm_crown_discharge(epicenter_global: Vector2) -> void:
	# Tight white core flash
	play_world_ring(epicenter_global, 20.0, Color(1.0, 1.0, 0.95, 0.95), 0.09)
	# Electric yellow mid ring
	play_world_ring(epicenter_global, 38.0, Color(0.98, 0.95, 0.48, 0.82), 0.16)
	# Outer blue-white drift ring
	play_world_ring(epicenter_global, 62.0, Color(0.82, 0.94, 1.0, 0.44), 0.26)

func play_boss_predator_mark(enemy_global: Vector2, stack_count: int, required_stacks: int) -> void:
	var ratio := clampf(float(stack_count) / maxf(1.0, float(required_stacks)), 0.0, 1.0)
	var clamped_required := maxi(1, required_stacks)
	var clamped_stack := clampi(stack_count, 1, clamped_required)
	var radius := 14.0 + ratio * 6.0
	# Charge-only visuals: soft rings + cadence pips (no slash/star burst language).
	play_world_ring(enemy_global, radius, Color(0.96, 0.78, 0.54, 0.22 + ratio * 0.14), 0.14)
	play_world_ring(enemy_global, radius * 0.68, Color(1.0, 0.94, 0.76, 0.16 + ratio * 0.10), 0.11)
	for i in range(clamped_required):
		var angle := -PI * 0.5 + TAU * float(i) / float(clamped_required)
		var pip_pos := enemy_global + Vector2.RIGHT.rotated(angle) * (radius * 0.9)
		if i < clamped_stack:
			play_world_ring(pip_pos, 2.4, Color(1.0, 0.90, 0.68, 0.50), 0.10)
		else:
			play_world_ring(pip_pos, 1.9, Color(0.94, 0.84, 0.68, 0.18), 0.10)

func play_boss_predator_burst(enemy_global: Vector2) -> void:
	_play_world_soft_pulse(enemy_global, 34.0, Color(0.96, 0.24, 0.16, 0.24), 0.18, 0.64, 1.2)
	_play_world_soft_pulse(enemy_global, 24.0, Color(1.0, 0.76, 0.42, 0.2), 0.14, 0.72, 1.16)
	play_world_ring(enemy_global, 24.0, Color(1.0, 0.52, 0.24, 0.98), 0.12)
	play_world_ring(enemy_global, 40.0, Color(1.0, 0.72, 0.38, 0.78), 0.16)
	play_world_ring(enemy_global, 58.0, Color(1.0, 0.88, 0.62, 0.46), 0.22)
	_play_world_star_burst(enemy_global, 54.0, 10, Color(1.0, 0.82, 0.56, 0.62), 0.12)
	_play_world_line(PackedVector2Array([
		enemy_global + Vector2(-28.0, -28.0),
		enemy_global + Vector2(28.0, 28.0)
	]), Color(1.0, 0.92, 0.74, 0.66), 2.8, 0.11, 0.8)
	_play_world_line(PackedVector2Array([
		enemy_global + Vector2(-28.0, 28.0),
		enemy_global + Vector2(28.0, -28.0)
	]), Color(1.0, 0.92, 0.74, 0.66), 2.8, 0.11, 0.8)

func play_boss_void_zone_spawn(epicenter_global: Vector2, radius: float) -> void:
	_play_world_soft_pulse(epicenter_global, radius * 0.94, Color(0.14, 0.48, 0.78, 0.18), 0.34, 0.78, 1.08)
	play_world_ring(epicenter_global, radius * 0.96, Color(0.22, 0.72, 1.0, 0.48), 0.3)
	play_world_ring(epicenter_global, radius * 0.72, Color(0.56, 0.92, 1.0, 0.82), 0.24)
	play_world_ring(epicenter_global, radius * 0.44, Color(0.92, 1.0, 1.0, 0.7), 0.17)
	_play_world_star_burst(epicenter_global, radius, 8, Color(0.72, 0.96, 1.0, 0.54), 0.22)

func play_boss_void_zone_pulse(epicenter_global: Vector2, radius: float) -> void:
	_play_world_soft_pulse(epicenter_global, radius * 0.64, Color(0.18, 0.56, 0.92, 0.2), 0.18, 0.76, 1.12)
	play_world_ring(epicenter_global, radius * 0.72, Color(0.18, 0.68, 1.0, 0.4), 0.18)
	play_world_ring(epicenter_global, radius * 0.56, Color(0.44, 0.86, 1.0, 0.7), 0.13)
	play_world_ring(epicenter_global, radius * 0.34, Color(0.9, 1.0, 1.0, 0.56), 0.1)
	_play_world_star_burst(epicenter_global, radius * 0.62, 6, Color(0.8, 0.98, 1.0, 0.42), 0.14)

func play_boss_void_zone_empowered_hit(target_global: Vector2) -> void:
	_play_world_soft_pulse(target_global, 14.0, Color(0.24, 0.78, 1.0, 0.26), 0.14, 0.72, 1.14)
	play_world_ring(target_global, 20.0, Color(0.46, 0.88, 1.0, 0.84), 0.13)
	play_world_ring(target_global, 11.0, Color(0.98, 1.0, 1.0, 0.8), 0.09)
	_play_world_line(PackedVector2Array([
		target_global + Vector2(-8.0, 0.0),
		target_global + Vector2(8.0, 0.0)
	]), Color(0.92, 1.0, 1.0, 0.62), 2.0, 0.09, 0.8)
	_play_world_line(PackedVector2Array([
		target_global + Vector2(0.0, -8.0),
		target_global + Vector2(0.0, 8.0)
	]), Color(0.92, 1.0, 1.0, 0.62), 2.0, 0.09, 0.8)
	_play_world_star_burst(target_global, 14.0, 4, Color(0.84, 1.0, 1.0, 0.58), 0.08)

func play_boss_tempo_stack(player_global: Vector2, stacks: int, max_stacks: int) -> void:
	var ratio := clampf(float(stacks) / maxf(1.0, float(max_stacks)), 0.0, 1.0)
	var radius := 12.0 + ratio * 10.0
	play_world_ring(player_global, radius, Color(1.0, 0.86, 0.42, 0.44 + ratio * 0.34), 0.1)
	play_world_ring(player_global, radius * 0.56, Color(1.0, 0.96, 0.74, 0.24 + ratio * 0.22), 0.08)

func play_boss_tempo_dash_wave(epicenter_global: Vector2, radius: float, landed: bool) -> void:
	if landed:
		play_world_ring(epicenter_global, radius * 0.74, Color(1.0, 0.84, 0.46, 0.9), 0.16)
		play_world_ring(epicenter_global, radius * 0.42, Color(1.0, 0.96, 0.74, 0.62), 0.1)
	else:
		play_world_ring(epicenter_global, radius * 0.6, Color(1.0, 0.48, 0.3, 0.8), 0.14)
		play_world_ring(epicenter_global, radius * 0.34, Color(1.0, 0.74, 0.56, 0.54), 0.1)

func play_boss_convergence_start(epicenter_global: Vector2, power_ratio: float) -> void:
	var ratio := clampf(power_ratio, 0.0, 1.0)
	var radius := 24.0 + 52.0 * ratio
	_play_world_soft_pulse(epicenter_global, radius * 1.06, Color(0.56, 0.34, 0.96, 0.20 + ratio * 0.14), 0.24, 0.72, 1.14)
	_play_world_soft_pulse(epicenter_global, radius * 0.74, Color(0.82, 0.72, 1.0, 0.18 + ratio * 0.12), 0.18, 0.76, 1.10)
	play_world_ring(epicenter_global, radius * 0.96, Color(0.90, 0.72, 1.0, 0.92), 0.20)
	play_world_ring(epicenter_global, radius * 0.66, Color(0.78, 0.92, 1.0, 0.66), 0.15)
	play_world_ring(epicenter_global, radius * 0.42, Color(0.98, 0.98, 1.0, 0.56), 0.10)
	_play_world_star_burst(epicenter_global, radius * 0.92, 10, Color(0.90, 0.80, 1.0, 0.54), 0.14)
	for i in range(4):
		var angle := PI * 0.25 + PI * 0.5 * float(i)
		var dir := Vector2.RIGHT.rotated(angle)
		var start_pos := epicenter_global + dir * (radius * 0.26)
		var end_pos := epicenter_global + dir * (radius * 0.88)
		_play_world_line(PackedVector2Array([start_pos, end_pos]), Color(1.0, 0.94, 1.0, 0.58), 2.4, 0.12, 0.8)

func play_boss_convergence_pulse(epicenter_global: Vector2, radius: float) -> void:
	_play_world_soft_pulse(epicenter_global, radius * 0.62, Color(0.44, 0.32, 0.90, 0.16), 0.16, 0.74, 1.12)
	play_world_ring(epicenter_global, radius * 0.66, Color(0.78, 0.88, 1.0, 0.76), 0.14)
	play_world_ring(epicenter_global, radius * 0.50, Color(0.66, 0.84, 1.0, 0.66), 0.11)
	play_world_ring(epicenter_global, radius * 0.32, Color(0.98, 1.0, 1.0, 0.52), 0.08)
	_play_world_star_burst(epicenter_global, radius * 0.64, 8, Color(0.86, 0.96, 1.0, 0.48), 0.10)

func play_boss_unbroken_bank_gain(epicenter_global: Vector2, bank_ratio: float) -> void:
	var r := clampf(bank_ratio, 0.0, 1.0)
	play_world_ring(epicenter_global, 18.0 + 16.0 * r, Color(0.92, 0.98, 1.0, 0.36 + 0.32 * r), 0.11)

func play_boss_unbroken_retaliation(epicenter_global: Vector2, bonus_ratio: float) -> void:
	var r := clampf(bonus_ratio, 0.0, 1.6)
	play_world_ring(epicenter_global, 20.0 + 26.0 * r, Color(0.84, 0.96, 1.0, 0.86), 0.14)
	play_world_ring(epicenter_global, 12.0 + 12.0 * r, Color(1.0, 1.0, 1.0, 0.6), 0.08)

func show_eclipse_mark_decal(enemy_node: Node2D, duration: float) -> void:
	if not is_instance_valid(enemy_node):
		return
	var enemy_id := enemy_node.get_instance_id()
	_clear_eclipse_mark_decal_by_id(enemy_id)

	var marker_root := Node2D.new()
	marker_root.position = Vector2(0.0, -20.0)
	marker_root.z_as_relative = false
	marker_root.z_index = 220

	var outer_ring := Line2D.new()
	outer_ring.width = 2.0
	outer_ring.default_color = Color(0.26, 0.98, 0.68, 0.76)
	outer_ring.closed = true
	outer_ring.antialiased = true
	outer_ring.points = _build_circle_polygon(9.5, 20)
	marker_root.add_child(outer_ring)

	var inner_ring := Line2D.new()
	inner_ring.width = 1.1
	inner_ring.default_color = Color(0.94, 1.0, 0.98, 0.74)
	inner_ring.closed = true
	inner_ring.antialiased = true
	inner_ring.points = _build_circle_polygon(5.5, 16)
	inner_ring.rotation = PI * 0.25
	marker_root.add_child(inner_ring)

	enemy_node.add_child(marker_root)
	var token: int = _eclipse_mark_decal_token_seed
	_eclipse_mark_decal_token_seed += 1
	_eclipse_mark_decals[enemy_id] = {
		"node": marker_root,
		"token": token
	}
	_pulse_eclipse_mark_decal(enemy_id, token, true)

	var life_tween := create_tween()
	_eclipse_mark_life_tweens[enemy_id] = life_tween
	life_tween.tween_interval(maxf(0.05, duration))
	life_tween.tween_callback(func() -> void:
		var active: Dictionary = _eclipse_mark_decals.get(enemy_id, {}) as Dictionary
		if int(active.get("token", -1)) != token:
			return
		_clear_eclipse_mark_decal_by_id(enemy_id)
	)

func clear_eclipse_mark_decal(enemy_node: Object) -> void:
	if not is_instance_valid(enemy_node):
		return
	_clear_eclipse_mark_decal_by_id(enemy_node.get_instance_id())

func clear_all_eclipse_mark_decals() -> void:
	for enemy_id in _eclipse_mark_decals.keys():
		if _eclipse_mark_pulse_tweens.has(enemy_id):
			var pulse_tween: Tween = _eclipse_mark_pulse_tweens[enemy_id]
			if pulse_tween and pulse_tween.is_valid():
				pulse_tween.kill()
			_eclipse_mark_pulse_tweens.erase(enemy_id)
		if _eclipse_mark_life_tweens.has(enemy_id):
			var life_tween: Tween = _eclipse_mark_life_tweens[enemy_id]
			if life_tween and life_tween.is_valid():
				life_tween.kill()
			_eclipse_mark_life_tweens.erase(enemy_id)
		var entry: Dictionary = _eclipse_mark_decals[enemy_id] as Dictionary
		var marker_variant: Variant = entry.get("node", null)
		if is_instance_valid(marker_variant) and marker_variant is Node:
			(marker_variant as Node).queue_free()
	_eclipse_mark_decals.clear()

func _clear_eclipse_mark_decal_by_id(enemy_id: int) -> void:
	if not _eclipse_mark_decals.has(enemy_id):
		return
	if _eclipse_mark_pulse_tweens.has(enemy_id):
		var pulse_tween: Tween = _eclipse_mark_pulse_tweens[enemy_id]
		if pulse_tween and pulse_tween.is_valid():
			pulse_tween.kill()
		_eclipse_mark_pulse_tweens.erase(enemy_id)
	if _eclipse_mark_life_tweens.has(enemy_id):
		var life_tween: Tween = _eclipse_mark_life_tweens[enemy_id]
		if life_tween and life_tween.is_valid():
			life_tween.kill()
		_eclipse_mark_life_tweens.erase(enemy_id)
	var entry: Dictionary = _eclipse_mark_decals[enemy_id] as Dictionary
	var marker_variant: Variant = entry.get("node", null)
	if is_instance_valid(marker_variant) and marker_variant is Node:
		(marker_variant as Node).queue_free()
	_eclipse_mark_decals.erase(enemy_id)

func _pulse_eclipse_mark_decal(enemy_id: int, token: int, grow_phase: bool) -> void:
	var active: Dictionary = _eclipse_mark_decals.get(enemy_id, {}) as Dictionary
	if int(active.get("token", -1)) != token:
		return
	var marker_variant: Variant = active.get("node", null)
	if not (is_instance_valid(marker_variant) and marker_variant is Node):
		return
	var marker_root: Node2D = marker_variant as Node2D
	var tween := create_tween()
	_eclipse_mark_pulse_tweens[enemy_id] = tween
	var target_scale := Vector2(1.08, 1.08) if grow_phase else Vector2(0.96, 0.96)
	tween.tween_property(marker_root, "scale", target_scale, 0.22)
	tween.tween_callback(func() -> void:
		if _eclipse_mark_decals.has(enemy_id):
			_pulse_eclipse_mark_decal(enemy_id, token, not grow_phase)
	)

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
	background_style.border_width_left = 1
	background_style.border_width_top = 1
	background_style.border_width_right = 1
	background_style.border_width_bottom = 1
	background_style.border_color = Color(0.88, 0.92, 1.0, 0.78)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = ENEMY_BASE.COLOR_PLAYER_HEALTH_FILL
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3

	health_bar.add_theme_stylebox_override("background", background_style)
	health_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(health_bar)

func _create_voidfire_bar() -> void:
	voidfire_bar = ProgressBar.new()
	voidfire_bar.min_value = 0.0
	voidfire_bar.max_value = 100.0
	voidfire_bar.value = 0.0
	voidfire_bar.show_percentage = false
	voidfire_bar.position = voidfire_bar_offset
	voidfire_bar.custom_minimum_size = voidfire_bar_size
	voidfire_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voidfire_bar.z_index = 6

	voidfire_bar_background_style = StyleBoxFlat.new()
	voidfire_bar_background_style.bg_color = Color(0.06, 0.12, 0.18, 0.7)
	voidfire_bar_background_style.corner_radius_top_left = 2
	voidfire_bar_background_style.corner_radius_top_right = 2
	voidfire_bar_background_style.corner_radius_bottom_left = 2
	voidfire_bar_background_style.corner_radius_bottom_right = 2
	voidfire_bar_background_style.border_width_left = 1
	voidfire_bar_background_style.border_width_top = 1
	voidfire_bar_background_style.border_width_right = 1
	voidfire_bar_background_style.border_width_bottom = 1
	voidfire_bar_background_style.border_color = Color(0.72, 0.84, 0.98, 0.7)

	voidfire_bar_fill_style = StyleBoxFlat.new()
	voidfire_bar_fill_style.bg_color = Color(0.26, 0.72, 0.98, 0.88)
	voidfire_bar_fill_style.corner_radius_top_left = 2
	voidfire_bar_fill_style.corner_radius_top_right = 2
	voidfire_bar_fill_style.corner_radius_bottom_left = 2
	voidfire_bar_fill_style.corner_radius_bottom_right = 2

	voidfire_bar.add_theme_stylebox_override("background", voidfire_bar_background_style)
	voidfire_bar.add_theme_stylebox_override("fill", voidfire_bar_fill_style)
	add_child(voidfire_bar)

	voidfire_sweetspot_zone = ColorRect.new()
	voidfire_sweetspot_zone.position = voidfire_bar_offset + Vector2(voidfire_bar_size.x * VOIDFIRE_DANGER_RATIO, 0.0)
	voidfire_sweetspot_zone.size = Vector2(voidfire_bar_size.x * (1.0 - VOIDFIRE_DANGER_RATIO), voidfire_bar_size.y)
	voidfire_sweetspot_zone.color = Color(1.0, 0.84, 0.44, 0.08)
	voidfire_sweetspot_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voidfire_sweetspot_zone.z_index = 7
	add_child(voidfire_sweetspot_zone)

	voidfire_threshold_line = ColorRect.new()
	voidfire_threshold_line.position = voidfire_bar_offset + Vector2(voidfire_bar_size.x * VOIDFIRE_DANGER_RATIO - 1.0, -1.0)
	voidfire_threshold_line.size = Vector2(2.0, voidfire_bar_size.y + 2.0)
	voidfire_threshold_line.color = Color(0.76, 0.9, 1.0, 0.72)
	voidfire_threshold_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voidfire_threshold_line.z_index = 8
	add_child(voidfire_threshold_line)

	voidfire_glow = ColorRect.new()
	voidfire_glow.position = voidfire_bar_offset + Vector2(-1.0, -1.0)
	voidfire_glow.size = voidfire_bar_size + Vector2(2.0, 2.0)
	voidfire_glow.color = Color(0.48, 0.78, 1.0, 0.0)
	voidfire_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voidfire_glow.z_index = 9
	add_child(voidfire_glow)

	update_voidfire_heat_bar(0.0, 100.0, false, 0.0)

func _create_oath_bank_bar() -> void:
	oath_bar = ProgressBar.new()
	oath_bar.min_value = 0.0
	oath_bar.max_value = 100.0
	oath_bar.value = 0.0
	oath_bar.show_percentage = false
	oath_bar.position = oath_bar_offset
	oath_bar.custom_minimum_size = oath_bar_size
	oath_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oath_bar.z_index = 10

	oath_bar_background_style = StyleBoxFlat.new()
	oath_bar_background_style.bg_color = Color(0.12, 0.08, 0.16, 0.72)
	oath_bar_background_style.corner_radius_top_left = 2
	oath_bar_background_style.corner_radius_top_right = 2
	oath_bar_background_style.corner_radius_bottom_left = 2
	oath_bar_background_style.corner_radius_bottom_right = 2
	oath_bar_background_style.border_width_left = 1
	oath_bar_background_style.border_width_top = 1
	oath_bar_background_style.border_width_right = 1
	oath_bar_background_style.border_width_bottom = 1
	oath_bar_background_style.border_color = Color(0.86, 0.7, 0.98, 0.74)

	oath_bar_fill_style = StyleBoxFlat.new()
	oath_bar_fill_style.bg_color = Color(0.76, 0.58, 0.98, 0.9)
	oath_bar_fill_style.corner_radius_top_left = 2
	oath_bar_fill_style.corner_radius_top_right = 2
	oath_bar_fill_style.corner_radius_bottom_left = 2
	oath_bar_fill_style.corner_radius_bottom_right = 2

	oath_bar.add_theme_stylebox_override("background", oath_bar_background_style)
	oath_bar.add_theme_stylebox_override("fill", oath_bar_fill_style)
	add_child(oath_bar)

	oath_bar_glow = ColorRect.new()
	oath_bar_glow.position = oath_bar_offset + Vector2(-1.0, -1.0)
	oath_bar_glow.size = oath_bar_size + Vector2(2.0, 2.0)
	oath_bar_glow.color = Color(0.88, 0.66, 1.0, 0.0)
	oath_bar_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oath_bar_glow.z_index = 11
	add_child(oath_bar_glow)

	update_oath_bank_bar(0.0, 100.0, false)

func _layout_status_bars() -> void:
	if health_bar == null:
		return
	health_bar.position = health_bar_offset
	var row_gap := 2.0
	var first_row_y := health_bar_offset.y - voidfire_bar_size.y - row_gap
	var second_row_y := first_row_y - oath_bar_size.y - row_gap
	var voidfire_visible := voidfire_bar != null and voidfire_bar.visible
	var oath_visible := oath_bar != null and oath_bar.visible
	if voidfire_visible and oath_visible:
		_set_voidfire_bar_y(first_row_y)
		_set_oath_bar_y(second_row_y)
	elif voidfire_visible:
		_set_voidfire_bar_y(first_row_y)
		_set_oath_bar_y(first_row_y)
	elif oath_visible:
		_set_oath_bar_y(first_row_y)
		_set_voidfire_bar_y(first_row_y)
	else:
		_set_voidfire_bar_y(first_row_y)
		_set_oath_bar_y(first_row_y)

func _set_voidfire_bar_y(y: float) -> void:
	if voidfire_bar != null:
		voidfire_bar.position.y = y
	if voidfire_sweetspot_zone != null:
		voidfire_sweetspot_zone.position.y = y
	if voidfire_threshold_line != null:
		voidfire_threshold_line.position.y = y - 1.0
	if voidfire_glow != null:
		voidfire_glow.position.y = y - 1.0

func _set_oath_bar_y(y: float) -> void:
	if oath_bar != null:
		oath_bar.position.y = y
	if oath_bar_glow != null:
		oath_bar_glow.position.y = y - 1.0

func _create_impact_sound_player() -> void:
	impact_sound_player = AudioStreamPlayer2D.new()
	impact_sound_player.stream = impact_sound
	impact_sound_player.volume_db = AUDIO_LEVELS.clamp_db(impact_volume_db + sfx_volume_db)
	add_child(impact_sound_player)

func _create_attack_swing_sound_player() -> void:
	attack_swing_sound_player = AudioStreamPlayer2D.new()
	attack_swing_sound_player.stream = attack_swing_sound
	attack_swing_sound_player.volume_db = AUDIO_LEVELS.clamp_db(attack_swing_volume_db + sfx_volume_db)
	add_child(attack_swing_sound_player)

func _apply_sfx_volume() -> void:
	if impact_sound_player != null:
		impact_sound_player.volume_db = AUDIO_LEVELS.clamp_db(impact_volume_db + sfx_volume_db)
	if attack_swing_sound_player != null:
		attack_swing_sound_player.volume_db = AUDIO_LEVELS.clamp_db(attack_swing_volume_db + sfx_volume_db)

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
