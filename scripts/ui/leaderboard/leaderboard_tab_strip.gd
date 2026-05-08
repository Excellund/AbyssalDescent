extends HBoxContainer
class_name LeaderboardTabStrip

signal tab_changed(tab_key: String)

const TAB_GLOBAL := "global"
const TAB_PER_CHARACTER := "per_character"

var _global_button: Button
var _character_button: Button
var _active_tab: String = TAB_GLOBAL

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_global_button = _make_tab_button("Global Top 25", TAB_GLOBAL)
	add_child(_global_button)
	_character_button = _make_tab_button("Per-Character Top 25", TAB_PER_CHARACTER)
	add_child(_character_button)
	_apply_active_state()

func set_active(tab_key: String) -> void:
	var normalized := tab_key.strip_edges().to_lower()
	if normalized != TAB_PER_CHARACTER:
		normalized = TAB_GLOBAL
	_active_tab = normalized
	_apply_active_state()

func get_active() -> String:
	return _active_tab

func _make_tab_button(text: String, tab_key: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		set_active(tab_key)
		tab_changed.emit(_active_tab)
	)
	return button

func _apply_active_state() -> void:
	_apply_button_state(_global_button, _active_tab == TAB_GLOBAL)
	_apply_button_state(_character_button, _active_tab == TAB_PER_CHARACTER)

func _apply_button_state(button: Button, active: bool) -> void:
	if button == null:
		return
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.bg_color = Color(0.14, 0.22, 0.34, 0.95) if active else Color(0.08, 0.12, 0.18, 0.86)
	normal.border_color = Color(0.80, 0.92, 1.0, 0.95) if active else Color(0.34, 0.52, 0.74, 0.72)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.30, 0.46, 0.98) if active else Color(0.12, 0.18, 0.28, 0.94)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.98, 1.0, 1.0, 1.0) if active else Color(0.86, 0.94, 1.0, 0.94))
