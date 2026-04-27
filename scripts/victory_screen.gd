extends Node

signal back_to_main_menu_requested

const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")

var _layer: CanvasLayer
var _root: Control
var _tween: Tween
var _visible: bool = false
var _unlocked_tier: int = -1

func show_victory(_rooms_cleared: int, unlocked_tier: int = -1) -> void:
	_unlocked_tier = unlocked_tier
	if _layer == null:
		_build_ui()
	_visible = true
	_layer.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _tween != null:
		_tween.kill()
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tween = create_tween()
	_tween.tween_property(_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.2).set_ease(Tween.EASE_OUT)

func is_open() -> bool:
	return _visible

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 210
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.06, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	# Title
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 280.0
	title.offset_bottom = 380.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = "Victory"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.0, 0.98))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	_root.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 375.0
	subtitle.offset_bottom = 425.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.text = "The Sovereign has fallen. The run is over."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0, 0.75))
	subtitle.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	subtitle.add_theme_constant_override("shadow_offset_x", 2)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(subtitle)

	# Divider
	var sep := ColorRect.new()
	sep.set_anchor(SIDE_LEFT, 0.5)
	sep.set_anchor(SIDE_RIGHT, 0.5)
	sep.set_anchor(SIDE_TOP, 0.0)
	sep.set_anchor(SIDE_BOTTOM, 0.0)
	sep.offset_left = -160.0
	sep.offset_right = 160.0
	sep.offset_top = 446.0
	sep.offset_bottom = 448.0
	sep.color = Color(0.9, 0.76, 0.42, 0.35)
	_root.add_child(sep)

	## Unlock notification (conditionally shown)
	if _unlocked_tier >= 0:
		var unlock_panel := Panel.new()
		unlock_panel.set_anchor(SIDE_LEFT, 0.5)
		unlock_panel.set_anchor(SIDE_RIGHT, 0.5)
		unlock_panel.set_anchor(SIDE_TOP, 0.0)
		unlock_panel.set_anchor(SIDE_BOTTOM, 0.0)
		unlock_panel.offset_left = -280.0
		unlock_panel.offset_right = 280.0
		unlock_panel.offset_top = 330.0
		unlock_panel.offset_bottom = 420.0
		var unlock_style := StyleBoxFlat.new()
		unlock_style.bg_color = Color(0.2, 0.25, 0.15, 0.92)
		unlock_style.border_color = Color(0.8, 0.95, 0.5, 0.95)
		unlock_style.set_border_width_all(2)
		unlock_style.set_corner_radius_all(10)
		unlock_panel.add_theme_stylebox_override("panel", unlock_style)
		_root.add_child(unlock_panel)

		var unlock_config := DIFFICULTY_CONFIG.get_tier_config(_unlocked_tier)
		var unlock_tier_name: String = unlock_config.get("name", "Unknown")

		var unlock_title := Label.new()
		unlock_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
		unlock_title.offset_left = 20.0
		unlock_title.offset_right = -20.0
		unlock_title.offset_top = 10.0
		unlock_title.offset_bottom = 40.0
		unlock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock_title.text = "New Difficulty Unlocked!"
		unlock_title.add_theme_font_size_override("font_size", 20)
		unlock_title.add_theme_color_override("font_color", Color(0.8, 0.95, 0.5, 1.0))
		unlock_panel.add_child(unlock_title)

		var unlock_desc := Label.new()
		unlock_desc.set_anchors_preset(Control.PRESET_CENTER)
		unlock_desc.offset_top = 25.0
		unlock_desc.offset_bottom = 70.0
		unlock_desc.offset_left = 20.0
		unlock_desc.offset_right = -20.0
		unlock_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock_desc.text = "%s is now available!\nYou can still choose easier difficulties whenever you prefer." % unlock_tier_name
		unlock_desc.add_theme_font_size_override("font_size", 14)
		unlock_desc.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.9))
		unlock_panel.add_child(unlock_desc)

	# Main menu button
	var btn_panel := Panel.new()
	btn_panel.set_anchor(SIDE_LEFT, 0.5)
	btn_panel.set_anchor(SIDE_RIGHT, 0.5)
	btn_panel.set_anchor(SIDE_TOP, 0.0)
	btn_panel.set_anchor(SIDE_BOTTOM, 0.0)
	btn_panel.offset_left = -150.0
	btn_panel.offset_right = 150.0
	btn_panel.offset_top = 500.0
	btn_panel.offset_bottom = 556.0
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.10, 0.14, 0.20, 0.96)
	btn_style.border_color = Color(0.62, 0.74, 0.96, 0.82)
	btn_style.border_width_left = 2
	btn_style.border_width_top = 2
	btn_style.border_width_right = 2
	btn_style.border_width_bottom = 2
	btn_style.corner_radius_top_left = 10
	btn_style.corner_radius_top_right = 10
	btn_style.corner_radius_bottom_left = 10
	btn_style.corner_radius_bottom_right = 10
	btn_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	btn_style.shadow_size = 6
	btn_style.shadow_offset = Vector2(0.0, 3.0)
	btn_panel.add_theme_stylebox_override("panel", btn_style)
	btn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(btn_panel)

	var btn_label := Label.new()
	btn_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn_label.text = "Return to Main Menu"
	btn_label.add_theme_font_size_override("font_size", 22)
	btn_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 0.95))
	btn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_panel.add_child(btn_label)

	btn_panel.gui_input.connect(_on_menu_button_input.bind(btn_panel, btn_style, btn_label))

	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_layer.visible = false

func _on_menu_button_input(event: InputEvent, btn_panel: Panel, btn_style: StyleBoxFlat, btn_label: Label) -> void:
	if event is InputEventMouseMotion:
		var rect := Rect2(btn_panel.global_position, btn_panel.custom_minimum_size)
		var hovered := rect.has_point(btn_panel.get_global_mouse_position())
		if hovered:
			btn_style.bg_color = Color(0.22, 0.30, 0.44, 0.97)
			btn_style.border_color = Color(0.96, 0.99, 1.0, 1.0)
			btn_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		else:
			btn_style.bg_color = Color(0.10, 0.14, 0.20, 0.96)
			btn_style.border_color = Color(0.62, 0.74, 0.96, 0.82)
			btn_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 0.95))
		btn_panel.add_theme_stylebox_override("panel", btn_style)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			back_to_main_menu_requested.emit()
