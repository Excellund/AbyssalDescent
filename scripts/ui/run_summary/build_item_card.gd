extends Panel
class_name BuildItemCard

const RARITY_COLORS := {
	"common": Color(0.62, 0.7, 0.8, 0.9),
	"rare": Color(0.46, 0.78, 1.0, 0.94),
	"epic": Color(0.82, 0.58, 1.0, 0.96),
	"legendary": Color(1.0, 0.74, 0.42, 1.0),
}

var _name_label: Label
var _stack_label: Label

func _init() -> void:
	custom_minimum_size = Vector2(230.0, 64.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.16, 0.92)
	style.border_color = Color(0.34, 0.5, 0.78, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 2)
	row.add_child(text_stack)

	_name_label = Label.new()
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	text_stack.add_child(_name_label)

	_stack_label = Label.new()
	_stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stack_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stack_label.custom_minimum_size = Vector2(42.0, 42.0)
	_stack_label.add_theme_font_size_override("font_size", 15)
	_stack_label.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 1.0))
	row.add_child(_stack_label)

func set_item(item: Dictionary) -> void:
	var item_name := String(item.get("name", "Unknown"))
	var stacks := maxi(1, int(item.get("stacks", 1)))
	var rarity := String(item.get("rarity", "common")).to_lower()
	var rarity_color := RARITY_COLORS.get(rarity, Color(0.62, 0.7, 0.8, 0.9)) as Color

	_name_label.text = item_name
	_stack_label.text = "x%d" % stacks
	tooltip_text = "%s\nStacks: %d" % [item_name, stacks]

	var style := get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		flat.border_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.78)
		flat.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.24)
		flat.shadow_size = 5
		add_theme_stylebox_override("panel", flat)
	_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.98))
	_stack_label.add_theme_color_override("font_color", rarity_color)
