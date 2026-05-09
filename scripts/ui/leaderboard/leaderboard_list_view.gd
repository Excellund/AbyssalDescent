extends VBoxContainer
class_name LeaderboardListView

const ENTRY_ROW_SCRIPT := preload("res://scripts/ui/leaderboard/leaderboard_entry_row.gd")

var _rows_container: VBoxContainer
var _empty_label: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	add_child(_build_header())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_container)
	_empty_label = Label.new()
	_empty_label.text = "No leaderboard entries yet for this board."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92, 0.70))
	_rows_container.add_child(_empty_label)

func set_entries(entries: Array, current_player_uuid: String) -> void:
	for child in _rows_container.get_children():
		if child == _empty_label:
			continue
		_rows_container.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false
	for entry_variant in entries:
		var row := ENTRY_ROW_SCRIPT.new()
		row.set_entry(entry_variant as Dictionary, current_player_uuid)
		_rows_container.add_child(row)

func _build_header() -> PanelContainer:
	var container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.bg_color = Color(0.08, 0.14, 0.22, 0.92)
	style.border_color = Color(0.36, 0.56, 0.78, 0.74)
	style.set_border_width_all(1)
	container.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	container.add_child(row)
	_add_header_column(row, "#", 56, HORIZONTAL_ALIGNMENT_CENTER)
	_add_header_column(row, "Bearing", 90, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_column(row, "Player", 160, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_column(row, "Character", 120, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_column(row, "Party", 64, HORIZONTAL_ALIGNMENT_CENTER)
	_add_header_column(row, "Patch", 90, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_column(row, "Time", 78, HORIZONTAL_ALIGNMENT_RIGHT)
	_add_header_column(row, "Run Ended", 150, HORIZONTAL_ALIGNMENT_RIGHT)
	return container

func _add_header_column(parent: HBoxContainer, text: String, min_width: float, text_alignment: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 30.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = text_alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 0.96))
	parent.add_child(label)
