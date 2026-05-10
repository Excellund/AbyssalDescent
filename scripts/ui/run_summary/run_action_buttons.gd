extends HBoxContainer
class_name RunActionButtons

signal return_to_menu_pressed
signal retry_run_pressed
signal toggle_timeline_pressed

var _timeline_button: Button
var _retry_button: Button

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 10)

	var menu_button := _make_button("Return to Main Menu")
	menu_button.pressed.connect(func() -> void:
		return_to_menu_pressed.emit()
	)
	add_child(menu_button)

	_retry_button = _make_button("Retry Run")
	_retry_button.pressed.connect(func() -> void:
		retry_run_pressed.emit()
	)
	add_child(_retry_button)

	_timeline_button = _make_button("Build Timeline")
	_timeline_button.pressed.connect(func() -> void:
		toggle_timeline_pressed.emit()
	)
	add_child(_timeline_button)

func set_timeline_expanded(expanded: bool) -> void:
	_timeline_button.text = "Hide Timeline" if expanded else "Build Timeline"

func set_retry_visible(should_show: bool) -> void:
	if _retry_button == null:
		return
	_retry_button.visible = should_show

func set_retry_label(text: String) -> void:
	if _retry_button == null:
		return
	_retry_button.text = text

func set_retry_disabled(disabled: bool) -> void:
	if _retry_button == null:
		return
	_retry_button.disabled = disabled

func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(210.0, 52.0)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.18, 0.28, 0.96), Color(0.54, 0.72, 0.96, 0.88)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.24, 0.36, 0.98), Color(0.72, 0.86, 1.0, 0.98)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.1, 0.16, 0.24, 0.98), Color(0.84, 0.94, 1.0, 1.0)))
	return button

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style
