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
		var scale := randf_range(0.9, 1.02)
		var rotation_bias := randf_range(-0.06, 0.06)
		_spawn_heal_cross(epicenter_global, start_offset, drift, duration, scale, rotation_bias)

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

