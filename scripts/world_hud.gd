extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

const MUTATOR_ICON_BLOOD_RUSH: Texture2D = preload("res://assets/ui/mutators/blood_rush.svg")
const MUTATOR_ICON_FLASHPOINT: Texture2D = preload("res://assets/ui/mutators/flashpoint.svg")
const MUTATOR_ICON_SIEGEBREAK: Texture2D = preload("res://assets/ui/mutators/siegebreak.svg")
const MUTATOR_ICON_IRON_VOLLEY: Texture2D = preload("res://assets/ui/mutators/iron_volley.svg")

var status_panel: Panel
var status_label: RichTextLabel
var status_mutator_icon: TextureRect
var status_mutator_label: Label
var stats_panel: Panel
var stats_label: RichTextLabel
var room_banner_title_label: Label
var room_banner_subtitle_label: Label
var room_banner_tween: Tween

var _encounter_count: int = 5
var _banner_top_margin: float = 18.0
var _cached_room_size: Vector2 = Vector2.ZERO

func setup(encounter_count: int, banner_top_margin: float = 18.0) -> void:
	_encounter_count = encounter_count
	_banner_top_margin = banner_top_margin
	_create_hud()

func refresh(state: Dictionary, player: Node) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	_cached_room_size = state.get("room_size", Vector2.ZERO) as Vector2
	var viewport_size := viewport.get_visible_rect().size
	_update_banner_layout(_cached_room_size, viewport.get_canvas_transform(), viewport_size)
	_layout_hud_panels(viewport_size)
	_update_status_panel_text(state)
	_update_stats_panel_text(player)

func show_banner(title: String, subtitle: String, subtitle_color: Color = Color(0.78, 0.9, 1.0, 0.92)) -> void:
	if room_banner_title_label == null or room_banner_subtitle_label == null:
		return
	if is_instance_valid(room_banner_tween):
		room_banner_tween.kill()
	room_banner_subtitle_label.add_theme_color_override("font_color", subtitle_color)
	room_banner_title_label.text = title
	room_banner_subtitle_label.text = subtitle
	var viewport := get_viewport()
	if viewport != null:
		_update_banner_layout(_cached_room_size, viewport.get_canvas_transform(), viewport.get_visible_rect().size)
	room_banner_title_label.modulate.a = 0.0
	room_banner_subtitle_label.modulate.a = 0.0
	room_banner_tween = create_tween()
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 1.0, 0.2)
	if subtitle.is_empty():
		room_banner_subtitle_label.visible = false
	else:
		room_banner_subtitle_label.visible = true
		room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 1.0, 0.2)
	room_banner_tween.tween_interval(0.95)
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 0.0, 0.24)
	room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 0.0, 0.24)

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	status_panel = Panel.new()
	status_panel.custom_minimum_size = Vector2(302.0, 84.0)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.03, 0.06, 0.1, 0.44)
	status_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	status_style.corner_radius_top_left = 10
	status_style.corner_radius_top_right = 10
	status_style.corner_radius_bottom_left = 10
	status_style.corner_radius_bottom_right = 10
	status_panel.add_theme_stylebox_override("panel", status_style)
	layer.add_child(status_panel)

	status_label = RichTextLabel.new()
	status_label.position = Vector2(0.0, 8.0)
	status_label.custom_minimum_size = Vector2(302.0, 34.0)
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.selection_enabled = false
	status_label.add_theme_font_size_override("normal_font_size", 16)
	status_label.add_theme_color_override("default_color", Color(0.94, 0.98, 1.0, 0.98))
	status_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.06, 0.95))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_panel.add_child(status_label)

	status_mutator_icon = TextureRect.new()
	status_mutator_icon.position = Vector2(10.0, 41.0)
	status_mutator_icon.custom_minimum_size = Vector2(18.0, 18.0)
	status_mutator_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_mutator_icon.visible = false
	status_panel.add_child(status_mutator_icon)

	status_mutator_label = Label.new()
	status_mutator_label.position = Vector2(34.0, 39.0)
	status_mutator_label.custom_minimum_size = Vector2(256.0, 24.0)
	status_mutator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_mutator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_mutator_label.add_theme_font_size_override("font_size", 16)
	status_mutator_label.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0, 0.96))
	status_mutator_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.06, 0.92))
	status_mutator_label.add_theme_constant_override("shadow_offset_x", 1)
	status_mutator_label.add_theme_constant_override("shadow_offset_y", 1)
	status_mutator_label.visible = false
	status_panel.add_child(status_mutator_label)

	stats_panel = Panel.new()
	stats_panel.custom_minimum_size = Vector2(360.0, 214.0)
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.03, 0.06, 0.1, 0.44)
	stats_style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	stats_style.corner_radius_top_left = 10
	stats_style.corner_radius_top_right = 10
	stats_style.corner_radius_bottom_left = 10
	stats_style.corner_radius_bottom_right = 10
	stats_panel.add_theme_stylebox_override("panel", stats_style)
	layer.add_child(stats_panel)

	stats_label = RichTextLabel.new()
	stats_label.position = Vector2(10.0, 8.0)
	stats_label.custom_minimum_size = Vector2(340.0, 198.0)
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.selection_enabled = false
	stats_label.add_theme_font_size_override("normal_font_size", 15)
	stats_label.add_theme_color_override("default_color", Color(0.94, 0.98, 1.0, 0.98))
	stats_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.06, 0.95))
	stats_label.add_theme_constant_override("shadow_offset_x", 1)
	stats_label.add_theme_constant_override("shadow_offset_y", 1)
	stats_panel.add_child(stats_label)

	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 110
	banner_layer.follow_viewport_enabled = false
	banner_layer.follow_viewport_scale = 1.0
	add_child(banner_layer)

	var banner_container := Control.new()
	banner_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_layer.add_child(banner_container)

	room_banner_title_label = Label.new()
	room_banner_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	room_banner_title_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_banner_title_label.grow_vertical = Control.GROW_DIRECTION_END
	room_banner_title_label.offset_left = 0.0
	room_banner_title_label.offset_right = 0.0
	room_banner_title_label.offset_top = 92.0
	room_banner_title_label.offset_bottom = 126.0
	room_banner_title_label.add_theme_font_size_override("font_size", 30)
	room_banner_title_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.84, 0.96))
	room_banner_title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	room_banner_title_label.add_theme_constant_override("shadow_offset_x", 2)
	room_banner_title_label.add_theme_constant_override("shadow_offset_y", 2)
	room_banner_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_banner_title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	room_banner_title_label.modulate.a = 0.0
	banner_container.add_child(room_banner_title_label)

	room_banner_subtitle_label = Label.new()
	room_banner_subtitle_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	room_banner_subtitle_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_banner_subtitle_label.grow_vertical = Control.GROW_DIRECTION_END
	room_banner_subtitle_label.offset_left = 0.0
	room_banner_subtitle_label.offset_right = 0.0
	room_banner_subtitle_label.offset_top = 124.0
	room_banner_subtitle_label.offset_bottom = 152.0
	room_banner_subtitle_label.add_theme_font_size_override("font_size", 18)
	room_banner_subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0, 0.92))
	room_banner_subtitle_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	room_banner_subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	room_banner_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	room_banner_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_banner_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	room_banner_subtitle_label.modulate.a = 0.0
	banner_container.add_child(room_banner_subtitle_label)

func _update_banner_layout(room_size: Vector2, canvas_xform: Transform2D, viewport_size: Vector2) -> void:
	if room_banner_title_label == null or room_banner_subtitle_label == null:
		return
	var top_y := 92.0
	if room_size != Vector2.ZERO:
		var room_top_world := Vector2(0.0, -room_size.y * 0.5)
		var room_top_screen := canvas_xform * room_top_world
		top_y = clampf(room_top_screen.y + _banner_top_margin, 16.0, viewport_size.y * 0.45)
	room_banner_title_label.offset_top = top_y
	room_banner_title_label.offset_bottom = top_y + 34.0
	room_banner_subtitle_label.offset_top = top_y + 32.0
	room_banner_subtitle_label.offset_bottom = top_y + 60.0

func _layout_hud_panels(viewport_size: Vector2) -> void:
	if status_panel != null:
		var panel_width := status_panel.size.x
		if panel_width <= 0.0:
			panel_width = status_panel.custom_minimum_size.x
		status_panel.position = Vector2((viewport_size.x - panel_width) * 0.5, 14.0)
	if stats_panel != null:
		stats_panel.position = Vector2(14.0, 14.0)

func _update_status_panel_text(state: Dictionary) -> void:
	if status_label == null:
		return
	var run_cleared := bool(state.get("run_cleared", false))
	var rooms_cleared := int(state.get("rooms_cleared", 0))
	var room_depth := int(state.get("room_depth", 0))
	var current_room_enemy_mutator := state.get("current_room_enemy_mutator", {}) as Dictionary

	if run_cleared:
		status_label.text = "[center][b]Depth %d[/b]\n[color=#A8FFB0]Run Clear[/color][/center]" % room_depth
		if status_mutator_icon != null:
			status_mutator_icon.visible = false
		if status_mutator_label != null:
			status_mutator_label.visible = false
		return

	if rooms_cleared >= _encounter_count:
		status_label.text = "[center][b]Depth %d[/b][/center]" % room_depth
	else:
		status_label.text = "[center][b]Depth %d[/b]  [color=#A5B6C9]%d/%d[/color][/center]" % [room_depth, rooms_cleared, _encounter_count]

	if current_room_enemy_mutator.is_empty():
		if status_mutator_icon != null:
			status_mutator_icon.visible = false
		if status_mutator_label != null:
			status_mutator_label.visible = false
		return

	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(current_room_enemy_mutator)
	var mutator_color := ENCOUNTER_CONTRACTS.mutator_theme_color(current_room_enemy_mutator)
	var ui_mutator_color := mutator_color
	ui_mutator_color.a = 1.0
	var icon_shape := ENCOUNTER_CONTRACTS.mutator_icon_shape_id(current_room_enemy_mutator)
	var icon_texture := _get_mutator_icon_texture(icon_shape)

	if status_mutator_icon != null:
		status_mutator_icon.texture = icon_texture
		status_mutator_icon.modulate = ui_mutator_color
		status_mutator_icon.visible = (icon_texture != null)
	if status_mutator_label != null:
		status_mutator_label.text = mutator_name
		status_mutator_label.add_theme_color_override("font_color", ui_mutator_color)
		status_mutator_label.visible = true

	var hud_font := ThemeDB.fallback_font
	var text_w := 0.0
	if hud_font != null:
		text_w = hud_font.get_string_size(mutator_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	var icon_visible := (icon_texture != null)
	var icon_w := 18.0 if icon_visible else 0.0
	var gap := 6.0 if icon_visible else 0.0
	var row_w := icon_w + gap + text_w
	var panel_w := 302.0
	var start_x := maxf(8.0, (panel_w - row_w) * 0.5)
	var row_top := 38.0
	if status_mutator_icon != null:
		status_mutator_icon.position = Vector2(start_x, row_top + 1.0)
	if status_mutator_label != null:
		status_mutator_label.position = Vector2(start_x + icon_w + gap, row_top)
		status_mutator_label.custom_minimum_size = Vector2(maxf(text_w + 2.0, 60.0), 24.0)

func _update_stats_panel_text(player: Node) -> void:
	if stats_label == null:
		return
	if not is_instance_valid(player):
		stats_label.text = "[b]Stats[/b]\nNo player"
		return

	var hp := int(player.get("max_health"))
	var hp_now := hp
	if player.has_method("_get_current_health"):
		hp_now = int(player.call("_get_current_health"))
	var dmg := int(player.get("attack_damage"))
	var atk_range := float(player.get("attack_range"))
	var atk_cd := float(player.get("attack_cooldown"))
	var move_spd := float(player.get("max_speed"))
	var dash_cd := float(player.get("dash_cooldown"))
	var armor := int(player.get("iron_skin_armor"))
	var trial_stacks := 0
	if player.has_method("get_trial_power_stack_count"):
		for trial_id in ["razor_wind", "execution_edge", "rupture_wave", "phantom_step", "reaper_step", "static_wake"]:
			trial_stacks += int(player.call("get_trial_power_stack_count", trial_id))

	stats_label.text = "[b]Stats[/b]\nHealth: [color=#C8FFD8]%d/%d[/color]\nAttack Damage: [color=#FFD8AA]%d[/color]\nAttack Range: [color=#FFD8AA]%.0f[/color]\nAttack Speed: [color=#BFD8FF]%.2fs[/color]\nMove Speed: [color=#BFD8FF]%.0f[/color]\nDash Cooldown: [color=#BFD8FF]%.2fs[/color]\nArmor: [color=#E8E8FF]%d[/color]\nArcana Stacks: [color=#FFE6B2]%d[/color]" % [hp_now, hp, dmg, atk_range, atk_cd, move_spd, dash_cd, armor, trial_stacks]

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

