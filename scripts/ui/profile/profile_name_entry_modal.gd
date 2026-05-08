extends Control
class_name ProfileNameEntryModal

signal profile_submitted(profile_name: String)
signal profile_cancelled

const PROFILE_NAME_MAX_LEN := 16

var _panel_container: PanelContainer
var _title_label: Label
var _body_label: Label
var _error_label: Label
var _name_input: LineEdit
var _confirm_button: Button
var _cancel_button: Button
var _allow_cancel: bool = true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()

func show_prompt(title_text: String, body_text: String, initial_name: String, allow_cancel: bool) -> void:
	_allow_cancel = allow_cancel
	if _title_label != null:
		_title_label.text = title_text
	if _body_label != null:
		_body_label.text = body_text
	if _name_input != null:
		_name_input.text = initial_name.strip_edges()
		_name_input.caret_column = _name_input.text.length()
	if _cancel_button != null:
		_cancel_button.visible = _allow_cancel
	clear_error()
	visible = true
	call_deferred("_reposition")
	call_deferred("_focus_name_input")

func hide_prompt() -> void:
	visible = false
	clear_error()

func show_validation_error(message: String) -> void:
	if _error_label != null:
		_error_label.text = message.strip_edges()
	if _name_input != null:
		_name_input.grab_focus()

func clear_error() -> void:
	if _error_label != null:
		_error_label.text = ""

func is_prompt_visible() -> bool:
	return visible

func _reposition() -> void:
	if _panel_container == null:
		return
	var vp := get_viewport_rect().size
	var s := _panel_container.size
	_panel_container.position = ((vp - s) * 0.5).floor()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_reposition()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel_container = PanelContainer.new()
	_panel_container.custom_minimum_size = Vector2(680.0, 0.0)
	_panel_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.08, 0.12, 0.97)
	panel_style.border_color = Color(0.44, 0.70, 0.96, 0.74)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 32.0
	panel_style.content_margin_right = 32.0
	panel_style.content_margin_top = 22.0
	panel_style.content_margin_bottom = 24.0
	_panel_container.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel_container)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	_panel_container.add_child(stack)

	_title_label = Label.new()
	_title_label.text = "Profile Name"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 0.98))
	stack.add_child(_title_label)

	_body_label = Label.new()
	_body_label.text = "Choose a profile name."
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 18)
	_body_label.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98, 0.94))
	stack.add_child(_body_label)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Letters, numbers, underscore"
	_name_input.max_length = PROFILE_NAME_MAX_LEN
	_name_input.custom_minimum_size = Vector2(0.0, 54.0)
	_name_input.text_submitted.connect(_on_name_submitted)
	_apply_line_edit_theme(_name_input)
	stack.add_child(_name_input)

	_error_label = Label.new()
	_error_label.text = ""
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_font_size_override("font_size", 15)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.73, 0.73, 0.98))
	stack.add_child(_error_label)

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 14)
	stack.add_child(actions)

	_confirm_button = _make_button("Save", true)
	_confirm_button.custom_minimum_size = Vector2(0.0, 56.0)
	_confirm_button.pressed.connect(_emit_submit)
	actions.add_child(_confirm_button)

	_cancel_button = _make_button("Cancel", false)
	_cancel_button.custom_minimum_size = Vector2(0.0, 56.0)
	_cancel_button.pressed.connect(_emit_cancel)
	actions.add_child(_cancel_button)

func _on_name_submitted(_new_text: String) -> void:
	_emit_submit()

func _emit_submit() -> void:
	var submitted_name := ""
	if _name_input != null:
		submitted_name = _name_input.text.strip_edges()
	profile_submitted.emit(submitted_name)

func _emit_cancel() -> void:
	if not _allow_cancel:
		return
	profile_cancelled.emit()

func _focus_name_input() -> void:
	if _name_input != null:
		_name_input.grab_focus()

func _make_button(label_text: String, emphasize: bool) -> Button:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	if emphasize:
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.16, 0.27, 0.42, 0.95), Color(0.76, 0.90, 1.0, 0.92), 16, 2))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.19, 0.32, 0.50, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.12, 0.22, 0.34, 0.98), Color(0.92, 0.98, 1.0, 1.0), 16, 2))
	else:
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 16, 2))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 16, 2))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
	return button

func _apply_line_edit_theme(line_edit: LineEdit) -> void:
	line_edit.add_theme_font_size_override("font_size", 20)
	line_edit.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.66, 0.78, 0.90, 0.58))
	line_edit.add_theme_color_override("font_selected_color", Color(0.98, 1.0, 1.0, 1.0))
	line_edit.add_theme_color_override("selection_color", Color(0.24, 0.42, 0.64, 0.92))
	line_edit.add_theme_stylebox_override("normal", _make_button_style(Color(0.06, 0.10, 0.16, 0.96), Color(0.26, 0.44, 0.66, 0.74), 16, 2))
	line_edit.add_theme_stylebox_override("focus", _make_button_style(Color(0.10, 0.16, 0.24, 0.98), Color(0.82, 0.94, 1.0, 1.0), 16, 2))

func _make_button_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style
