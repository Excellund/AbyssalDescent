extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

const MUTATOR_ICON_BLOOD_RUSH: Texture2D = preload("res://assets/ui/mutators/blood_rush.svg")
const MUTATOR_ICON_FLASHPOINT: Texture2D = preload("res://assets/ui/mutators/flashpoint.svg")
const MUTATOR_ICON_SIEGEBREAK: Texture2D = preload("res://assets/ui/mutators/siegebreak.svg")
const MUTATOR_ICON_IRON_VOLLEY: Texture2D = preload("res://assets/ui/mutators/iron_volley.svg")
const MUTATOR_ICON_FORTIFIED_PATH := "res://assets/ui/mutators/fortified.svg"
const MUTATOR_ICON_HUNTERS_FOCUS_PATH := "res://assets/ui/mutators/hunters_focus.svg"
const MUTATOR_ICON_KILLBOX_PATH := "res://assets/ui/mutators/killbox.svg"
const MUTATOR_ICON_COMBO_RELAY_PATH := "res://assets/ui/mutators/combo_relay.svg"
const HUD_INFO_PANEL_WIDTH := 302.0

var status_panel: Panel
var status_label: RichTextLabel
var status_bearing_badge_panel: Panel
var status_bearing_badge_label: Label
var status_mutator_icon: TextureRect
var status_mutator_label: Label
var stats_panel: Panel
var stats_label: RichTextLabel
var player_mutator_panel: Panel
var player_mutator_rows: Array[HBoxContainer] = []
var player_mutator_icons: Array[TextureRect] = []
var player_mutator_labels: Array[Label] = []
var room_banner_title_label: Label
var room_banner_subtitle_label: Label
var room_banner_tween: Tween
var _mutator_icon_killbox: Texture2D
var _mutator_icon_fortified: Texture2D
var _mutator_icon_hunters_focus: Texture2D
var _mutator_icon_combo_relay: Texture2D

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
	_layout_hud_panels(viewport_size, _cached_room_size, viewport.get_canvas_transform())
	_update_status_panel_text(state)
	_update_player_mutator_panel(state)
	_update_stats_panel_text(player)

func show_banner(title: String, subtitle: String, subtitle_color: Color = Color(0.78, 0.9, 1.0, 0.92)) -> void:
	if room_banner_title_label == null or room_banner_subtitle_label == null:
		return
	if subtitle_color.a < -1.0:
		room_banner_title_label.text = subtitle
	if is_instance_valid(room_banner_tween):
		room_banner_tween.kill()
	var has_subtitle := not subtitle.strip_edges().is_empty()
	room_banner_title_label.text = title
	room_banner_subtitle_label.text = subtitle
	room_banner_subtitle_label.add_theme_color_override("font_color", subtitle_color)
	var viewport := get_viewport()
	if viewport != null:
		_update_banner_layout(_cached_room_size, viewport.get_canvas_transform(), viewport.get_visible_rect().size)
	room_banner_title_label.modulate.a = 0.0
	room_banner_subtitle_label.modulate.a = 0.0
	room_banner_subtitle_label.visible = has_subtitle
	room_banner_tween = create_tween()
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 1.0, 0.2)
	if has_subtitle:
		room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 1.0, 0.2)
	room_banner_tween.tween_interval(0.95)
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 0.0, 0.24)
	if has_subtitle:
		room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 0.0, 0.24)

func show_notice(text: String, text_color: Color = Color(0.78, 0.9, 1.0, 0.92), duration: float = -1.0) -> void:
	# Transient combat notices were removed to keep gameplay readable.
	if duration < -9999.0 and text_color.a < -1.0:
		room_banner_subtitle_label.text = text

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	status_panel = Panel.new()
	status_panel.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH, 84.0)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.03, 0.06, 0.1, 0.56)
	status_style.border_color = Color(0.62, 0.77, 0.9, 0.32)
	status_style.border_width_left = 1
	status_style.border_width_top = 1
	status_style.border_width_right = 1
	status_style.border_width_bottom = 1
	status_style.corner_radius_top_left = 12
	status_style.corner_radius_top_right = 12
	status_style.corner_radius_bottom_left = 12
	status_style.corner_radius_bottom_right = 12
	status_panel.add_theme_stylebox_override("panel", status_style)
	layer.add_child(status_panel)

	status_label = RichTextLabel.new()
	status_label.position = Vector2(0.0, 8.0)
	status_label.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH, 34.0)
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

	status_bearing_badge_panel = Panel.new()
	status_bearing_badge_panel.position = Vector2(206.0, 7.0)
	status_bearing_badge_panel.custom_minimum_size = Vector2(88.0, 24.0)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.26, 0.38, 0.34, 0.82)
	badge_style.border_color = Color(0.72, 0.9, 0.84, 0.94)
	badge_style.border_width_left = 1
	badge_style.border_width_top = 1
	badge_style.border_width_right = 1
	badge_style.border_width_bottom = 1
	badge_style.corner_radius_top_left = 6
	badge_style.corner_radius_top_right = 6
	badge_style.corner_radius_bottom_left = 6
	badge_style.corner_radius_bottom_right = 6
	status_bearing_badge_panel.add_theme_stylebox_override("panel", badge_style)
	status_panel.add_child(status_bearing_badge_panel)

	status_bearing_badge_label = Label.new()
	status_bearing_badge_label.position = Vector2(1.0, 0.0)
	status_bearing_badge_label.custom_minimum_size = Vector2(72.0, 24.0)
	status_bearing_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_bearing_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_bearing_badge_label.add_theme_font_size_override("font_size", 13)
	status_bearing_badge_label.add_theme_color_override("font_color", Color(0.9, 0.98, 0.94, 0.98))
	status_bearing_badge_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	status_bearing_badge_label.add_theme_constant_override("shadow_offset_x", 0)
	status_bearing_badge_label.add_theme_constant_override("shadow_offset_y", 0)
	status_bearing_badge_panel.add_child(status_bearing_badge_label)

	status_mutator_icon = TextureRect.new()
	status_mutator_icon.position = Vector2(10.0, 41.0)
	status_mutator_icon.custom_minimum_size = Vector2(18.0, 18.0)
	status_mutator_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_mutator_icon.visible = false
	status_panel.add_child(status_mutator_icon)

	status_mutator_label = Label.new()
	status_mutator_label.position = Vector2(34.0, 39.0)
	status_mutator_label.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH - 46.0, 24.0)
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
	stats_panel.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH, 214.0)
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.03, 0.06, 0.1, 0.5)
	stats_style.border_color = Color(0.54, 0.7, 0.84, 0.26)
	stats_style.border_width_left = 1
	stats_style.border_width_top = 1
	stats_style.border_width_right = 1
	stats_style.border_width_bottom = 1
	stats_style.corner_radius_top_left = 12
	stats_style.corner_radius_top_right = 12
	stats_style.corner_radius_bottom_left = 12
	stats_style.corner_radius_bottom_right = 12
	stats_panel.add_theme_stylebox_override("panel", stats_style)
	layer.add_child(stats_panel)

	stats_label = RichTextLabel.new()
	stats_label.position = Vector2(10.0, 8.0)
	stats_label.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH - 20.0, 198.0)
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

	player_mutator_panel = Panel.new()
	player_mutator_panel.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH, 136.0)
	var mutator_panel_style := StyleBoxFlat.new()
	mutator_panel_style.bg_color = Color(0.03, 0.06, 0.1, 0.56)
	mutator_panel_style.border_color = Color(0.54, 0.7, 0.84, 0.26)
	mutator_panel_style.border_width_left = 1
	mutator_panel_style.border_width_top = 1
	mutator_panel_style.border_width_right = 1
	mutator_panel_style.border_width_bottom = 1
	mutator_panel_style.corner_radius_top_left = 12
	mutator_panel_style.corner_radius_top_right = 12
	mutator_panel_style.corner_radius_bottom_left = 12
	mutator_panel_style.corner_radius_bottom_right = 12
	player_mutator_panel.add_theme_stylebox_override("panel", mutator_panel_style)
	layer.add_child(player_mutator_panel)

	var mutator_title := Label.new()
	mutator_title.position = Vector2(10.0, 8.0)
	mutator_title.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH - 20.0, 24.0)
	mutator_title.text = "My Mutators"
	mutator_title.add_theme_font_size_override("font_size", 15)
	mutator_title.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 0.95))
	mutator_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.86))
	mutator_title.add_theme_constant_override("shadow_offset_x", 1)
	mutator_title.add_theme_constant_override("shadow_offset_y", 1)
	player_mutator_panel.add_child(mutator_title)

	player_mutator_rows.clear()
	player_mutator_icons.clear()
	player_mutator_labels.clear()
	for i in range(4):
		var row := HBoxContainer.new()
		row.position = Vector2(10.0, 32.0 + float(i) * 24.0)
		row.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH - 20.0, 22.0)
		row.visible = false
		row.add_theme_constant_override("separation", 8)
		player_mutator_panel.add_child(row)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.visible = false
		row.add_child(icon)

		var row_label := Label.new()
		row_label.custom_minimum_size = Vector2(HUD_INFO_PANEL_WIDTH - 44.0, 22.0)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_label.add_theme_font_size_override("font_size", 14)
		row_label.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0, 0.94))
		row_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.86))
		row_label.add_theme_constant_override("shadow_offset_x", 1)
		row_label.add_theme_constant_override("shadow_offset_y", 1)
		row.add_child(row_label)

		player_mutator_rows.append(row)
		player_mutator_icons.append(icon)
		player_mutator_labels.append(row_label)

	player_mutator_panel.visible = false

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


func _layout_hud_panels(viewport_size: Vector2, room_size: Vector2, canvas_xform: Transform2D) -> void:
	var edge_margin := 14.0
	var column_gap := 10.0
	var arena_top_screen := INF
	if room_size != Vector2.ZERO:
		arena_top_screen = (canvas_xform * Vector2(0.0, -room_size.y * 0.5)).y
	if status_panel != null:
		var panel_width := _panel_width(status_panel)
		var panel_height := _panel_height(status_panel)
		var status_y := edge_margin
		if arena_top_screen < INF:
			var candidate_y := arena_top_screen - panel_height - 8.0
			if candidate_y >= edge_margin:
				status_y = candidate_y
		if panel_width <= 0.0:
			panel_width = status_panel.custom_minimum_size.x
		status_panel.position = Vector2(edge_margin, status_y)
	if stats_panel != null:
		var stats_h := _panel_height(stats_panel)
		var status_bottom := edge_margin
		if status_panel != null:
			status_bottom = status_panel.position.y + _panel_height(status_panel)
		var preferred_stats_y := status_bottom + column_gap
		var max_stats_y := viewport_size.y - stats_h - edge_margin
		stats_panel.position = Vector2(edge_margin, clampf(preferred_stats_y, edge_margin, max_stats_y))
	if player_mutator_panel != null:
		var panel_width := _panel_width(player_mutator_panel)
		var panel_height := _panel_height(player_mutator_panel)
		if panel_width <= 0.0:
			panel_width = player_mutator_panel.custom_minimum_size.x
		var mutator_y := edge_margin
		if arena_top_screen < INF:
			var candidate_y := arena_top_screen - panel_height - 8.0
			if candidate_y >= edge_margin:
				mutator_y = candidate_y
		player_mutator_panel.position = Vector2(viewport_size.x - panel_width - edge_margin, mutator_y)

func _panel_width(panel: Control) -> float:
	if panel == null:
		return 0.0
	if panel.size.x > 0.0:
		return panel.size.x
	return panel.custom_minimum_size.x

func _panel_height(panel: Control) -> float:
	if panel == null:
		return 0.0
	if panel.size.y > 0.0:
		return panel.size.y
	return panel.custom_minimum_size.y

func _update_status_panel_text(state: Dictionary) -> void:
	if status_label == null:
		return
	var run_cleared := bool(state.get("run_cleared", false))
	var _rooms_cleared := int(state.get("rooms_cleared", 0))
	var room_depth := int(state.get("room_depth", 0))
	var current_room_enemy_mutator := state.get("current_room_enemy_mutator", {}) as Dictionary
	var objective_kind := String(state.get("active_objective_kind", ""))
	var objective_time_left := float(state.get("objective_time_left", 0.0))
	var objective_kills := int(state.get("objective_kills", 0))
	var objective_kill_target := int(state.get("objective_kill_target", 0))
	var objective_overtime := bool(state.get("objective_overtime", false))
	var objective_target_name := String(state.get("objective_target_name", "Target"))
	var objective_target_health := int(state.get("objective_target_health", 0))
	var objective_target_max_health := int(state.get("objective_target_max_health", 0))
	var objective_hunt_kill_progress := int(state.get("objective_hunt_kill_progress", 0))
	var objective_hunt_kill_goal := int(state.get("objective_hunt_kill_goal", 0))
	var objective_control_progress := float(state.get("objective_control_progress", 0.0))
	var objective_control_goal := float(state.get("objective_control_goal", 0.0))
	var objective_control_enemies_in_zone := int(state.get("objective_control_enemies_in_zone", 0))
	var objective_control_contested := bool(state.get("objective_control_contested", false))
	var objective_control_player_inside := bool(state.get("objective_control_player_inside", false))
	var objective_exposure_left := float(state.get("objective_exposure_left", 0.0))
	var objective_last_relocated_escort_count := int(state.get("objective_last_relocated_escort_count", 0))
	var objective_relocation_hint_left := float(state.get("objective_relocation_hint_left", 0.0))
	var _encounter_intro_grace_left := float(state.get("encounter_intro_grace_left", 0.0))
	var encounter_intro_grace_active := bool(state.get("encounter_intro_grace_active", false))
	var current_difficulty_tier := int(state.get("current_difficulty_tier", 0))
	_update_bearing_badge(current_difficulty_tier)

	var boss_unlocked := bool(state.get("boss_unlocked", false))
	var first_boss_defeated := bool(state.get("first_boss_defeated", false))
	if run_cleared:
		status_label.text = "[center][b]Depth %d[/b]\n[color=#A8FFB0]Run Clear[/color][/center]" % room_depth
		var run_clear_text_h := maxf(34.0, status_label.get_content_height())
		if status_panel != null:
			status_panel.custom_minimum_size.y = maxf(84.0, status_label.position.y + run_clear_text_h + 30.0)
		if status_mutator_icon != null:
			status_mutator_icon.visible = false
		if status_mutator_label != null:
			status_mutator_label.visible = false
		return

	var second_boss_unlocked := bool(state.get("second_boss_unlocked", false))
	if boss_unlocked and not first_boss_defeated:
		status_label.text = "[center][b]Act I[/b]\n[color=#A5B6C9]Depth %d[/color][/center]" % room_depth
	elif second_boss_unlocked:
		status_label.text = "[center][b]Act II[/b]\n[color=#A5B6C9]Depth %d[/color][/center]" % room_depth
	elif first_boss_defeated:
		status_label.text = "[center][b]Act II[/b]\n[color=#A5B6C9]Depth %d[/color][/center]" % room_depth
	else:
		status_label.text = "[center][b]Act I[/b]\n[color=#A5B6C9]Depth %d[/color][/center]" % room_depth

	if encounter_intro_grace_active:
		status_label.text += "\n[center][color=#C8F0FF]Move to engage[/color][/center]"

	if objective_kind == "survival":
		if objective_overtime:
			status_label.text += "\n[center][color=#FFB36D]Objective: Overtime  Kills %d/%d[/color][/center]" % [objective_kills, objective_kill_target]
		else:
			var objective_seconds := maxi(0, int(ceil(objective_time_left)))
			var quota_met := objective_kill_target > 0 and objective_kills >= objective_kill_target
			if quota_met:
				status_label.text += "\n[center][color=#A8FFB0]Objective: Cleanup %ds  Hold position[/color][/center]" % objective_seconds
				status_label.text += "\n[center][color=#C8F0FF]Quota met: timer is accelerating[/color][/center]"
			else:
				status_label.text += "\n[center][color=#FCD77A]Objective: Survive %ds  Kills %d/%d[/color][/center]" % [objective_seconds, objective_kills, objective_kill_target]
	elif objective_kind == "priority_target":
		var target_seconds := maxi(0, int(ceil(objective_time_left)))
		if objective_overtime:
			status_label.text += "\n[center][color=#FFB36D]Objective: Eliminate %s  HP %d/%d[/color][/center]" % [objective_target_name, objective_target_health, objective_target_max_health]
		else:
			status_label.text += "\n[center][color=#FCD77A]Objective: Kill %s %ds  HP %d/%d[/color][/center]" % [objective_target_name, target_seconds, objective_target_health, objective_target_max_health]
		var safe_goal := maxi(1, objective_hunt_kill_goal)
		var safe_progress := mini(maxi(0, objective_hunt_kill_progress), safe_goal)
		var remaining_kills := maxi(0, safe_goal - safe_progress)
		if objective_exposure_left > 0.0:
			status_label.text += "\n[center][color=#FFECA8]Signal Exposed: attack the mark[/color][/center]"
		else:
			status_label.text += "\n[center][color=#9FD6FF]Expose Signal: escort kills %d/%d  (%d left)[/color][/center]" % [safe_progress, safe_goal, remaining_kills]
		if objective_relocation_hint_left > 0.0 and objective_last_relocated_escort_count > 0:
			status_label.text += "\n[center][color=#A9E6FF]Breakaway carried %d nearby escorts[/color][/center]" % objective_last_relocated_escort_count
	elif objective_kind == "control":
		var control_seconds := maxi(0, int(ceil(objective_time_left)))
		var control_goal := maxf(0.01, objective_control_goal)
		var control_ratio := clampf(objective_control_progress / control_goal, 0.0, 1.0)
		if objective_overtime:
			status_label.text += "\n[center][color=#FFB36D]Objective: Hold the Line  %d%% secured[/color][/center]" % int(round(control_ratio * 100.0))
		else:
			status_label.text += "\n[center][color=#FCD77A]Objective: Hold %ds  Secure %d%%[/color][/center]" % [control_seconds, int(round(control_ratio * 100.0))]
		if objective_control_player_inside and not objective_control_contested:
			status_label.text += "\n[center][color=#A8FFB0]Zone stable: keep pressure inside the ring[/color][/center]"
		elif objective_control_contested:
			status_label.text += "\n[center][color=#FFCAA0]Zone contested: clear %d enemies from the point[/color][/center]" % objective_control_enemies_in_zone
		else:
			status_label.text += "\n[center][color=#9FD6FF]Re-enter the zone before progress decays[/color][/center]"


	var status_text_h := maxf(34.0, status_label.get_content_height())
	var row_top := status_label.position.y + status_text_h + 4.0
	if status_panel != null:
		status_panel.custom_minimum_size.y = maxf(84.0, row_top + 30.0)

	if current_room_enemy_mutator.is_empty():
		if status_mutator_icon != null:
			status_mutator_icon.visible = false
		if status_mutator_label != null:
			status_mutator_label.visible = false
		if status_panel != null:
			status_panel.custom_minimum_size.y = maxf(84.0, row_top + 8.0)
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
	var panel_w := HUD_INFO_PANEL_WIDTH
	var start_x := maxf(8.0, (panel_w - row_w) * 0.5)
	if status_mutator_icon != null:
		status_mutator_icon.position = Vector2(start_x, row_top + 1.0)
	if status_mutator_label != null:
		status_mutator_label.position = Vector2(start_x + icon_w + gap, row_top)
		status_mutator_label.custom_minimum_size = Vector2(maxf(text_w + 2.0, 60.0), 24.0)
	if status_panel != null:
		status_panel.custom_minimum_size.y = maxf(84.0, row_top + 32.0)

func _bearing_name_from_tier(tier: int) -> String:
	match tier:
		0:
			return "Pilgrim"
		1:
			return "Delver"
		2:
			return "Harbinger"
		3:
			return "Forsworn"
		_:
			return "Pilgrim"

func _bearing_color_from_tier(tier: int) -> Color:
	match tier:
		0:
			return Color("#9FE7C7")
		1:
			return Color("#F3CE78")
		2:
			return Color("#F5A462")
		3:
			return Color("#E56D6D")
		_:
			return Color("#9FE7C7")

func _update_bearing_badge(tier: int) -> void:
	if status_bearing_badge_panel == null or status_bearing_badge_label == null:
		return
	var bearing_name := _bearing_name_from_tier(tier)
	var tier_color := _bearing_color_from_tier(tier)
	var tier_border := Color(tier_color.r, tier_color.g, tier_color.b, 0.98)
	var tier_fill := Color(tier_color.r * 0.24, tier_color.g * 0.24, tier_color.b * 0.24, 0.86)
	var style := status_bearing_badge_panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var badge_style := style as StyleBoxFlat
		badge_style.bg_color = tier_fill
		badge_style.border_color = tier_border
		status_bearing_badge_panel.add_theme_stylebox_override("panel", badge_style)
	status_bearing_badge_label.text = bearing_name
	status_bearing_badge_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.98))
	var hud_font := ThemeDB.fallback_font
	var text_w := 50.0
	if hud_font != null:
		text_w = hud_font.get_string_size(bearing_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
	var badge_w := clampf(text_w + 20.0, 78.0, 122.0)
	status_bearing_badge_panel.custom_minimum_size = Vector2(badge_w, 24.0)
	status_bearing_badge_panel.size = Vector2(badge_w, 24.0)
	status_bearing_badge_panel.position = Vector2(HUD_INFO_PANEL_WIDTH - badge_w - 8.0, 7.0)
	status_bearing_badge_label.position = Vector2(1.0, 0.0)
	status_bearing_badge_label.custom_minimum_size = Vector2(badge_w - 1.0, 24.0)

func _update_player_mutator_panel(state: Dictionary) -> void:
	if player_mutator_panel == null:
		return
	var active_mutators := state.get("active_player_mutators", []) as Array[Dictionary]
	if active_mutators.is_empty():
		player_mutator_panel.visible = false
		for row in player_mutator_rows:
			row.visible = false
		return

	player_mutator_panel.visible = true
	for i in range(player_mutator_rows.size()):
		var row := player_mutator_rows[i]
		var icon := player_mutator_icons[i]
		var row_label := player_mutator_labels[i]
		if i >= active_mutators.size():
			row.visible = false
			continue
		row.visible = true
		var mutator := active_mutators[i]
		var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if mutator_name.is_empty():
			mutator_name = "Mutator"
		var color := ENCOUNTER_CONTRACTS.mutator_theme_color(mutator, Color(0.86, 0.94, 1.0, 0.94))
		var icon_texture := _get_mutator_icon_texture(ENCOUNTER_CONTRACTS.mutator_icon_shape_id(mutator))
		icon.texture = icon_texture
		icon.modulate = Color(color.r, color.g, color.b, 1.0)
		icon.visible = icon_texture != null
		var remaining := int(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_REMAINING_ENCOUNTERS, 0))
		var mutator_id := ENCOUNTER_CONTRACTS.mutator_id(mutator)
		var runtime_stacks := int(mutator.get("runtime_combo_relay_stacks", 0))
		var runtime_max_stacks := int(mutator.get("runtime_combo_relay_max_stacks", 0))
		var stat_parts: Array[String] = []
		var damage_resist := float(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_RESIST, 0.0))
		if damage_resist > 0.0:
			stat_parts.append("-%d%% dmg taken" % int(round(damage_resist * 100.0)))
		var damage_mult := float(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_MULT, 0.0))
		if damage_mult > 0.0:
			stat_parts.append("+%d%% dmg" % int(round(damage_mult * 100.0)))
		var stat_text := ""
		if not stat_parts.is_empty():
			stat_text = "  [" + ", ".join(stat_parts) + "]"
		if mutator_id == "combo_relay" and runtime_max_stacks > 0:
			row_label.text = "%s  (%d enc)  x%d/%d%s" % [mutator_name, remaining, runtime_stacks, runtime_max_stacks, stat_text]
		else:
			row_label.text = "%s  (%d enc)%s" % [mutator_name, remaining, stat_text]
		row_label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.98))
func _update_stats_panel_text(player: Node) -> void:
	if stats_label == null:
		return
	if not is_instance_valid(player):
		stats_label.text = "[b]Stats[/b]\nNo player"
		return

	var hp := int(player.get("max_health"))
	var hp_now := int(player._get_current_health())
	var dmg := int(player.get("attack_damage"))
	var atk_range := float(player.get("attack_range"))
	var atk_cd := float(player.get("attack_cooldown"))
	var move_spd := float(player.get("max_speed"))
	var dash_cd := float(player.get("dash_cooldown"))
	var armor := int(player.get("iron_skin_armor"))
	var trial_stacks := 0
	for trial_id in ["razor_wind", "execution_edge", "rupture_wave", "phantom_step", "reaper_step", "static_wake"]:
		trial_stacks += int(player.get_trial_power_stack_count(trial_id))

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
		"killbox":
			return _get_killbox_icon_texture()
		"fortified":
			return _get_fortified_icon_texture()
		"hunters_focus":
			return _get_hunters_focus_icon_texture()
		"combo_relay":
			return _get_combo_relay_icon_texture()
		"breach_momentum":
			return _get_combo_relay_icon_texture()
		_:
			return null

func _get_killbox_icon_texture() -> Texture2D:
	if _mutator_icon_killbox != null:
		return _mutator_icon_killbox
	var icon_resource := load(MUTATOR_ICON_KILLBOX_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_killbox = icon_resource as Texture2D
		return _mutator_icon_killbox
	# Keep UI stable if the asset import is temporarily unavailable.
	return MUTATOR_ICON_SIEGEBREAK

func _get_fortified_icon_texture() -> Texture2D:
	if _mutator_icon_fortified != null:
		return _mutator_icon_fortified
	var icon_resource := load(MUTATOR_ICON_FORTIFIED_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_fortified = icon_resource as Texture2D
		return _mutator_icon_fortified
	return MUTATOR_ICON_SIEGEBREAK

func _get_hunters_focus_icon_texture() -> Texture2D:
	if _mutator_icon_hunters_focus != null:
		return _mutator_icon_hunters_focus
	var icon_resource := load(MUTATOR_ICON_HUNTERS_FOCUS_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_hunters_focus = icon_resource as Texture2D
		return _mutator_icon_hunters_focus
	return MUTATOR_ICON_IRON_VOLLEY

func _get_combo_relay_icon_texture() -> Texture2D:
	if _mutator_icon_combo_relay != null:
		return _mutator_icon_combo_relay
	var icon_resource := load(MUTATOR_ICON_COMBO_RELAY_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_combo_relay = icon_resource as Texture2D
		return _mutator_icon_combo_relay
	return _get_hunters_focus_icon_texture()
