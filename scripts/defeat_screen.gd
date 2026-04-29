extends Node

signal back_to_main_menu_requested

var _layer: CanvasLayer
var _root: Control
var _tween: Tween
var _visible: bool = false

func show_defeat(room_label: String = "", depth: int = 0) -> void:
	if _layer == null:
		_build_ui()
	_visible = true
	_layer.visible = true
	_input_delay_left = 0.2
	_update_summary_text(room_label, depth)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _tween != null:
		_tween.kill()
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tween = create_tween()
	_tween.tween_property(_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.55).set_ease(Tween.EASE_OUT)

func is_open() -> bool:
	return _visible

var _summary_label: Label
var _input_delay_left: float = 0.0

func _process(delta: float) -> void:
	if _input_delay_left > 0.0:
		_input_delay_left = maxf(0.0, _input_delay_left - delta)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 211
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.01, 0.01, 0.9)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 250.0
	title.offset_bottom = 350.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = "Defeat"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.68, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	_root.add_child(title)

	var subtitle := Label.new()
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 352.0
	subtitle.offset_bottom = 398.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.text = "Your run has ended. Regroup and descend again."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(1.0, 0.84, 0.8, 0.78))
	subtitle.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	subtitle.add_theme_constant_override("shadow_offset_x", 2)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(subtitle)

	var sep := ColorRect.new()
	sep.set_anchor(SIDE_LEFT, 0.5)
	sep.set_anchor(SIDE_RIGHT, 0.5)
	sep.set_anchor(SIDE_TOP, 0.0)
	sep.set_anchor(SIDE_BOTTOM, 0.0)
	sep.offset_left = -180.0
	sep.offset_right = 180.0
	sep.offset_top = 420.0
	sep.offset_bottom = 422.0
	sep.color = Color(0.95, 0.42, 0.38, 0.36)
	_root.add_child(sep)

	_summary_label = Label.new()
	_summary_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_summary_label.offset_top = 444.0
	_summary_label.offset_bottom = 496.0
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.text = ""
	_summary_label.add_theme_font_size_override("font_size", 20)
	_summary_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.86, 0.9))
	_root.add_child(_summary_label)

	var btn := Button.new()
	btn.set_anchor(SIDE_LEFT, 0.5)
	btn.set_anchor(SIDE_RIGHT, 0.5)
	btn.set_anchor(SIDE_TOP, 0.0)
	btn.set_anchor(SIDE_BOTTOM, 0.0)
	btn.offset_left = -170.0
	btn.offset_right = 170.0
	btn.offset_top = 546.0
	btn.offset_bottom = 608.0
	btn.text = "Return to Main Menu"
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.98))
	btn.add_theme_stylebox_override("normal", _make_button_style(Color(0.24, 0.09, 0.11, 0.96), Color(0.93, 0.5, 0.52, 0.88)))
	btn.add_theme_stylebox_override("hover", _make_button_style(Color(0.34, 0.14, 0.16, 0.98), Color(1.0, 0.78, 0.74, 0.98)))
	btn.add_theme_stylebox_override("pressed", _make_button_style(Color(0.18, 0.07, 0.08, 0.98), Color(1.0, 0.88, 0.84, 1.0)))
	btn.pressed.connect(_on_menu_button_pressed)
	_root.add_child(btn)

	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_layer.visible = false
	set_process(true)

func _update_summary_text(room_label: String, depth: int) -> void:
	if _summary_label == null:
		return
	var shown_depth := maxi(0, depth)
	if room_label.strip_edges().is_empty():
		_summary_label.text = "Fell at depth %d." % shown_depth
		return
	_summary_label.text = "Fell in %s at depth %d." % [room_label, shown_depth]

func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.44)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 2.0)
	return style

func _on_menu_button_pressed() -> void:
	if _input_delay_left > 0.0:
		return
	back_to_main_menu_requested.emit()
