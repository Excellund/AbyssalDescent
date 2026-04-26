extends Node2D

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

const MUTATOR_ICON_BLOOD_RUSH: Texture2D = preload("res://assets/ui/mutators/blood_rush.svg")
const MUTATOR_ICON_FLASHPOINT: Texture2D = preload("res://assets/ui/mutators/flashpoint.svg")
const MUTATOR_ICON_SIEGEBREAK: Texture2D = preload("res://assets/ui/mutators/siegebreak.svg")
const MUTATOR_ICON_IRON_VOLLEY: Texture2D = preload("res://assets/ui/mutators/iron_volley.svg")

# Draw state — updated each frame by world_generator
var room_size: Vector2 = Vector2.ZERO
var choosing_next_room: bool = false
var door_options: Array[Dictionary] = []
var door_use_radius: float = 72.0
var player_global_position: Vector2 = Vector2.ZERO

# Visual config — set once via configure()
var ambient_backdrop_alpha: float = 0.96
var arena_glow_strength: float = 0.22
var floor_coarse_grid_alpha: float = 0.075
var floor_fine_grid_alpha: float = 0.024
var floor_border_alpha: float = 0.72
var floor_grid_step: float = 70.0
var floor_grid_fine_step: float = 35.0

var _art_time: float = 0.0

func _ready() -> void:
	# Keep floor and door FX behind gameplay actors.
	z_as_relative = false
	z_index = -100

func configure(config: Dictionary) -> void:
	ambient_backdrop_alpha = float(config.get("ambient_backdrop_alpha", ambient_backdrop_alpha))
	arena_glow_strength = float(config.get("arena_glow_strength", arena_glow_strength))
	floor_coarse_grid_alpha = float(config.get("floor_coarse_grid_alpha", floor_coarse_grid_alpha))
	floor_fine_grid_alpha = float(config.get("floor_fine_grid_alpha", floor_fine_grid_alpha))
	floor_border_alpha = float(config.get("floor_border_alpha", floor_border_alpha))
	floor_grid_step = float(config.get("floor_grid_step", floor_grid_step))
	floor_grid_fine_step = float(config.get("floor_grid_fine_step", floor_grid_fine_step))
	door_use_radius = float(config.get("door_use_radius", door_use_radius))

func _process(delta: float) -> void:
	_art_time += delta
	queue_redraw()

func _draw() -> void:
	if room_size == Vector2.ZERO:
		return
	var t := _art_time
	var room_rect := Rect2(-room_size * 0.5, room_size)
	var pulse := 0.5 + 0.5 * sin(t * 0.9)
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_to_world := get_viewport().get_canvas_transform().affine_inverse()
	var viewport_world_rect := viewport_to_world * viewport_rect
	draw_rect(viewport_world_rect.grow(50.0), Color(0.01, 0.02, 0.04, clampf(ambient_backdrop_alpha, 0.7, 1.0)), true)

	for i in range(10):
		var ratio := float(i) / 9.0
		var inset := lerpf(0.0, minf(room_rect.size.x, room_rect.size.y) * 0.22, ratio)
		var layer_rect := room_rect.grow(-inset)
		var layer_color := Color(0.03, 0.08, 0.12, 0.17).lerp(Color(0.09, 0.16, 0.23, 0.09 + arena_glow_strength * pulse * 0.32), 1.0 - ratio)
		draw_rect(layer_rect, layer_color, true)

	var coarse_step := maxf(28.0, floor_grid_step)
	var fine_step := maxf(16.0, floor_grid_fine_step)
	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + coarse_step), int(coarse_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.36, 0.56, 0.78, clampf(floor_coarse_grid_alpha, 0.01, 0.2)), 2.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + coarse_step), int(coarse_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.36, 0.56, 0.78, clampf(floor_coarse_grid_alpha, 0.01, 0.2)), 2.0)

	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + fine_step), int(fine_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.55, 0.74, 0.92, clampf(floor_fine_grid_alpha, 0.0, 0.08)), 1.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + fine_step), int(fine_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.55, 0.74, 0.92, clampf(floor_fine_grid_alpha, 0.0, 0.08)), 1.0)

	var corners := [
		room_rect.position,
		room_rect.position + Vector2(room_rect.size.x, 0.0),
		room_rect.position + Vector2(0.0, room_rect.size.y),
		room_rect.position + room_rect.size
	]
	for corner in corners:
		draw_circle(corner, 32.0, Color(0.42, 0.74, 1.0, 0.03 + pulse * 0.012))

	draw_rect(room_rect, Color(0.56, 0.78, 0.95, clampf(floor_border_alpha, 0.2, 0.95)), false, 4.0)
	draw_rect(room_rect.grow(-16.0), Color(0.22, 0.42, 0.62, 0.28), false, 2.0)

	if choosing_next_room:
		for door in door_options:
			var door_pos: Vector2 = door["position"]
			var color: Color = door["color"]
			var door_pulse := 0.75 + 0.25 * sin(t * 4.2 + door_pos.x * 0.01)
			draw_circle(door_pos, 34.0 + 4.0 * door_pulse, Color(color.r, color.g, color.b, 0.12))
			draw_circle(door_pos, 22.0 + 2.0 * door_pulse, Color(color.r, color.g, color.b, 0.24))
			draw_circle(door_pos, 14.0, color)
			draw_arc(door_pos, 30.0, -PI * 0.35, PI * 1.35, 36, Color(color.r, color.g, color.b, 0.7), 2.0)
			_draw_door_icon(door)

		var nearest_door := _get_nearest_door_for_prompt()
		if not nearest_door.is_empty() and float(nearest_door.get("distance", INF)) <= door_use_radius * 1.45:
			_draw_door_interaction_prompt(nearest_door)

func _get_nearest_door_for_prompt() -> Dictionary:
	if door_options.is_empty():
		return {}
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for door in door_options:
		var door_pos := door.get("position", Vector2.ZERO) as Vector2
		var dist := player_global_position.distance_to(door_pos)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest = door.duplicate(true)
	if nearest.is_empty():
		return {}
	nearest["distance"] = nearest_distance
	return nearest

func _build_door_prompt_text(door: Dictionary) -> String:
	var label := String(door.get("label", "Encounter"))
	var kind_id: int = ENCOUNTER_CONTRACTS.normalize_door_kind(door.get("kind_id", door.get("kind", ENCOUNTER_CONTRACTS.DOOR_KIND_ENCOUNTER)))
	if kind_id == ENUMS.DoorKind.BOSS:
		return label
	if kind_id == ENUMS.DoorKind.REST:
		return "Rest Site"
	return label

func _build_door_prompt_name(door: Dictionary) -> String:
	var label := String(door.get("label", "Encounter"))
	var kind_id: int = ENCOUNTER_CONTRACTS.normalize_door_kind(door.get("kind_id", door.get("kind", ENCOUNTER_CONTRACTS.DOOR_KIND_ENCOUNTER)))
	if kind_id == ENUMS.DoorKind.BOSS:
		return "%s Gate" % label
	if kind_id == ENUMS.DoorKind.REST:
		return "Rest Site"
	return label

func _draw_door_interaction_prompt(door: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var door_pos := door.get("position", Vector2.ZERO) as Vector2
	var door_color := door.get("color", Color(0.78, 0.9, 1.0, 1.0)) as Color
	var info_text := _build_door_prompt_text(door)
	var action_text := "[E] Enter"
	var action_font_size := 13
	var info_font_size := 17
	var action_size := font.get_string_size(action_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, action_font_size)
	var info_size := font.get_string_size(info_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, info_font_size)
	var plate_w := clampf(maxf(action_size.x, info_size.x) + 52.0, 210.0, 460.0)
	var plate_h := 56.0
	var radius := plate_h * 0.5
	var plate_x := door_pos.x - plate_w * 0.5
	var plate_y := door_pos.y - 100.0
	var fill := Color(0.035, 0.055, 0.09, 0.88)
	var glow := Color(door_color.r, door_color.g, door_color.b, 0.16)
	var border := Color(door_color.r, door_color.g, door_color.b, 0.68)
	draw_circle(Vector2(plate_x + radius, plate_y + radius), radius + 5.0, glow)
	draw_circle(Vector2(plate_x + plate_w - radius, plate_y + radius), radius + 5.0, glow)
	draw_rect(Rect2(Vector2(plate_x + radius, plate_y - 5.0), Vector2(plate_w - radius * 2.0, plate_h + 10.0)), glow, true)
	draw_circle(Vector2(plate_x + radius, plate_y + radius), radius, fill)
	draw_circle(Vector2(plate_x + plate_w - radius, plate_y + radius), radius, fill)
	draw_rect(Rect2(Vector2(plate_x + radius, plate_y), Vector2(plate_w - radius * 2.0, plate_h)), fill, true)
	draw_arc(Vector2(plate_x + radius, plate_y + radius), radius, PI * 0.5, PI * 1.5, 22, border, 1.6)
	draw_arc(Vector2(plate_x + plate_w - radius, plate_y + radius), radius, -PI * 0.5, PI * 0.5, 22, border, 1.6)
	draw_line(Vector2(plate_x + radius, plate_y), Vector2(plate_x + plate_w - radius, plate_y), border, 1.6)
	draw_line(Vector2(plate_x + radius, plate_y + plate_h), Vector2(plate_x + plate_w - radius, plate_y + plate_h), border, 1.6)
	draw_line(Vector2(plate_x + radius * 0.6, plate_y + 22.0), Vector2(plate_x + plate_w - radius * 0.6, plate_y + 22.0), Color(door_color.r, door_color.g, door_color.b, 0.32), 1.0)
	var text_shadow := Color(0.0, 0.0, 0.0, 0.56)
	var text_color := Color(0.95, 0.98, 1.0, 0.98)
	draw_string(font, Vector2(plate_x, plate_y + 17.0) + Vector2(1.0, 1.0), action_text, HORIZONTAL_ALIGNMENT_CENTER, plate_w, action_font_size, text_shadow)
	draw_string(font, Vector2(plate_x, plate_y + 17.0), action_text, HORIZONTAL_ALIGNMENT_CENTER, plate_w, action_font_size, text_color)
	draw_string(font, Vector2(plate_x, plate_y + 46.0) + Vector2(1.0, 1.0), info_text, HORIZONTAL_ALIGNMENT_CENTER, plate_w, info_font_size, text_shadow)
	draw_string(font, Vector2(plate_x, plate_y + 46.0), info_text, HORIZONTAL_ALIGNMENT_CENTER, plate_w, info_font_size, text_color)

func _draw_door_icon(door: Dictionary) -> void:
	var door_pos: Vector2 = door["position"]
	var icon_color := Color(0.97, 0.98, 1.0, 0.96)
	var outline_color := Color(0.08, 0.1, 0.14, 0.88)
	var kind_id: int = ENCOUNTER_CONTRACTS.normalize_door_kind(door.get("kind_id", door.get("kind", ENCOUNTER_CONTRACTS.DOOR_KIND_ENCOUNTER)))
	var icon := String(door.get("icon", "easy"))

	if kind_id == ENUMS.DoorKind.BOSS:
		var left_tip := door_pos + Vector2(-8.0, -5.0)
		var peak := door_pos + Vector2(0.0, -12.0)
		var right_tip := door_pos + Vector2(8.0, -5.0)
		var crown_base_l := door_pos + Vector2(-9.0, 2.0)
		var crown_base_r := door_pos + Vector2(9.0, 2.0)
		var crown := PackedVector2Array([crown_base_l, left_tip, door_pos + Vector2(-3.0, -2.0), peak, door_pos + Vector2(3.0, -2.0), right_tip, crown_base_r])
		draw_polyline(crown, outline_color, 4.8)
		draw_polyline(crown, icon_color, 3.0)
		draw_circle(door_pos + Vector2(0.0, 0.8), 2.4, outline_color)
		draw_circle(door_pos + Vector2(0.0, 0.8), 1.5, Color(1.0, 0.86, 0.42, 0.96))
		return

	if icon == "hard" or icon == "easy":
		var blade_a_l := door_pos + Vector2(-9.5, -7.0)
		var blade_a_r := door_pos + Vector2(9.5, 7.0)
		var blade_b_l := door_pos + Vector2(-9.5, 7.0)
		var blade_b_r := door_pos + Vector2(9.5, -7.0)
		draw_line(blade_a_l, blade_a_r, outline_color, 5.6)
		draw_line(blade_b_l, blade_b_r, outline_color, 5.6)
		draw_line(blade_a_l, blade_a_r, icon_color, 2.9)
		draw_line(blade_b_l, blade_b_r, icon_color, 2.9)
		draw_circle(door_pos, 3.4, outline_color)
		draw_circle(door_pos, 2.0, Color(1.0, 0.92, 0.74, 0.95))
		return

	if icon == "trial":
		var trial_mutator: Dictionary = door.get("profile", {}).get("enemy_mutator", {})
		var shape_id := String(trial_mutator.get("icon_shape_id", ""))
		var theme: Color = trial_mutator.get("theme_color", icon_color)
		theme.a = 1.0
		var icon_texture := _get_mutator_icon_texture(shape_id)
		if icon_texture != null:
			draw_circle(door_pos, 11.8, Color(outline_color.r, outline_color.g, outline_color.b, 0.74))
			draw_circle(door_pos, 9.8, Color(theme.r, theme.g, theme.b, 0.24))
			var icon_rect := Rect2(door_pos - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
			draw_texture_rect(icon_texture, icon_rect, false, theme)
		else:
			_draw_trial_mutator_icon(door_pos, shape_id, theme, icon_color, outline_color)
		return

	if icon == "objective":
		draw_arc(door_pos, 11.0, -PI * 0.15, PI * 1.15, 26, outline_color, 4.8)
		draw_arc(door_pos, 11.0, -PI * 0.15, PI * 1.15, 26, Color(0.98, 0.8, 0.42, 0.96), 2.8)
		var diamond := PackedVector2Array([
			door_pos + Vector2(0.0, -7.0),
			door_pos + Vector2(6.0, 0.0),
			door_pos + Vector2(0.0, 7.0),
			door_pos + Vector2(-6.0, 0.0)
		])
		draw_colored_polygon(diamond, Color(0.24, 0.17, 0.08, 0.95))
		draw_polyline(PackedVector2Array([
			door_pos + Vector2(0.0, -7.0),
			door_pos + Vector2(6.0, 0.0),
			door_pos + Vector2(0.0, 7.0),
			door_pos + Vector2(-6.0, 0.0),
			door_pos + Vector2(0.0, -7.0)
		]), Color(1.0, 0.92, 0.72, 0.96), 2.0)
		return

	if icon == "rest":
		draw_circle(door_pos, 10.0, outline_color)
		draw_circle(door_pos, 8.0, Color(0.24, 0.56, 0.34, 0.75))
		var rest_h_l := door_pos + Vector2(-8.0, 0.0)
		var rest_h_r := door_pos + Vector2(8.0, 0.0)
		var rest_v_t := door_pos + Vector2(0.0, -8.0)
		var rest_v_b := door_pos + Vector2(0.0, 8.0)
		draw_line(rest_h_l, rest_h_r, outline_color, 5.0)
		draw_line(rest_v_t, rest_v_b, outline_color, 5.0)
		draw_line(rest_h_l, rest_h_r, Color(0.84, 1.0, 0.86, 0.96), 3.0)
		draw_line(rest_v_t, rest_v_b, Color(0.84, 1.0, 0.86, 0.96), 3.0)
		return

	var h_l := door_pos + Vector2(-8.0, 0.0)
	var h_r := door_pos + Vector2(8.0, 0.0)
	var v_t := door_pos + Vector2(0.0, -8.0)
	var v_b := door_pos + Vector2(0.0, 8.0)
	draw_line(h_l, h_r, outline_color, 4.7)
	draw_line(v_t, v_b, outline_color, 4.7)
	draw_line(h_l, h_r, icon_color, 2.5)
	draw_line(v_t, v_b, icon_color, 2.5)
	draw_circle(door_pos, 1.7, Color(0.92, 0.98, 1.0, 0.92))

func _draw_trial_mutator_icon(door_pos: Vector2, shape_id: String, theme: Color, icon_color: Color, outline_color: Color) -> void:
	draw_arc(door_pos, 11.4, 0.0, TAU, 28, outline_color, 3.6)
	draw_arc(door_pos, 11.4, 0.0, TAU, 28, Color(theme.r, theme.g, theme.b, 0.86), 2.2)

	match shape_id:
		"blood_rush":
			for a in [0.0, PI * 0.667, PI * 1.333]:
				var dir := Vector2.RIGHT.rotated(a)
				var tip := door_pos + dir * 10.5
				var base := door_pos + dir * 3.6
				var side := Vector2(-dir.y, dir.x)
				var left_wing := base + side * 2.9
				var right_wing := base - side * 2.9
				var arrow := PackedVector2Array([left_wing, tip, right_wing])
				draw_colored_polygon(arrow, theme)
			draw_circle(door_pos, 2.9, outline_color)
			draw_circle(door_pos, 1.8, theme)

		"flashpoint":
			var top_pt := door_pos + Vector2(-1.0, -11.0)
			var mid_r  := door_pos + Vector2(5.0, -1.0)
			var mid_l  := door_pos + Vector2(-4.5, 1.0)
			var bot_pt := door_pos + Vector2(1.0, 11.0)
			draw_line(top_pt, mid_r, outline_color, 5.6)
			draw_line(mid_r,  bot_pt, outline_color, 5.6)
			draw_line(top_pt, mid_r, theme, 3.4)
			draw_line(mid_r,  bot_pt, theme, 3.4)
			draw_line(mid_l, mid_r, outline_color, 3.4)
			draw_line(mid_l, mid_r, theme, 2.1)

		"siegebreak":
			var tip_r := door_pos + Vector2(12.0, 0.0)
			var body_tr := door_pos + Vector2(6.0, -6.0)
			var body_tl := door_pos + Vector2(-8.0, -6.0)
			var body_bl := door_pos + Vector2(-8.0, 6.0)
			var body_br := door_pos + Vector2(6.0, 6.0)
			var ram := PackedVector2Array([tip_r, body_tr, body_tl, body_bl, body_br])
			draw_colored_polygon(ram, Color(outline_color.r, outline_color.g, outline_color.b, 0.9))
			var ram_inner := PackedVector2Array([
				door_pos + Vector2(10.0, 0.0),
				door_pos + Vector2(5.0, -4.5),
				door_pos + Vector2(-6.5, -4.5),
				door_pos + Vector2(-6.5, 4.5),
				door_pos + Vector2(5.0, 4.5)
			])
			draw_colored_polygon(ram_inner, theme)
			draw_line(door_pos + Vector2(-4.5, -4.0), door_pos + Vector2(-4.5, 4.0), outline_color, 1.7)

		"iron_volley":
			var shield := PackedVector2Array([
				door_pos + Vector2(0.0, -10.0),
				door_pos + Vector2(8.0, -3.0),
				door_pos + Vector2(6.0, 7.0),
				door_pos + Vector2(0.0, 10.0),
				door_pos + Vector2(-6.0, 7.0),
				door_pos + Vector2(-8.0, -3.0)
			])
			draw_colored_polygon(shield, Color(outline_color.r, outline_color.g, outline_color.b, 0.86))
			var shield_inner := PackedVector2Array([
				door_pos + Vector2(0.0, -8.0),
				door_pos + Vector2(6.0, -2.2),
				door_pos + Vector2(4.6, 5.5),
				door_pos + Vector2(0.0, 8.0),
				door_pos + Vector2(-4.6, 5.5),
				door_pos + Vector2(-6.0, -2.2)
			])
			draw_colored_polygon(shield_inner, theme)
			for sx: float in [-1.0, 1.0]:
				var tip := door_pos + Vector2(sx * 10.0, -4.0)
				var base_l := tip + Vector2(-sx * 2.8, 3.8)
				var base_r := tip + Vector2(sx * 2.8, 3.8)
				var arrow := PackedVector2Array([base_l, tip, base_r])
				draw_colored_polygon(arrow, theme)

		_:
			var top := door_pos + Vector2(0.0, -10.0)
			var right := door_pos + Vector2(10.0, 0.0)
			var bottom := door_pos + Vector2(0.0, 10.0)
			var left := door_pos + Vector2(-10.0, 0.0)
			var diamond := PackedVector2Array([top, right, bottom, left, top])
			draw_polyline(diamond, outline_color, 4.4)
			draw_polyline(diamond, icon_color, 2.6)
			draw_line(top, bottom, outline_color, 3.4)
			draw_line(top, bottom, icon_color, 1.9)

func _get_mutator_icon_texture(icon_shape_id: String) -> Texture2D:
	match icon_shape_id:
		"blood_rush":
			return MUTATOR_ICON_BLOOD_RUSH
		"flashpoint":
			return MUTATOR_ICON_FLASHPOINT
		"siegebreak":
			return MUTATOR_ICON_SIEGEBREAK
		"iron_volley":
			return MUTATOR_ICON_IRON_VOLLEY
		_:
			return null
