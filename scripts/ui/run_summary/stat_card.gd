extends Panel
class_name StatCard

var _title_label: Label
var _value_label: Label

func _init() -> void:
	custom_minimum_size = Vector2(210.0, 92.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.92)
	style.border_color = Color(0.36, 0.52, 0.8, 0.54)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.92, 0.9))
	stack.add_child(_title_label)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 28)
	_value_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	stack.add_child(_value_label)

func set_stat(title: String, value_text: String, value_color: Color = Color(0.95, 0.98, 1.0, 0.98)) -> void:
	_title_label.text = title
	_value_label.text = value_text
	_value_label.add_theme_color_override("font_color", value_color)
