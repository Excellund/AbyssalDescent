extends Panel
class_name RunHistoryPanel

const RUN_HISTORY_STORE_SCRIPT := preload("res://scripts/core/run_history_store.gd")
const RUN_SUMMARY_WITH_PROFILE_SCRIPT := preload("res://scripts/core/run_summary_with_profile.gd")
const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_RARE := Color(0.46, 0.78, 1.0, 0.94)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

signal back_pressed

var _list_container: VBoxContainer
var _detail_panel: Panel
var _detail_content: VBoxContainer
var _empty_label: Label
var _selected_index: int = -1
var _records: Array = []
var _row_buttons: Array[Button] = []

func _build_ui(style_ref: Object) -> void:
	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 44)
	layout.add_theme_constant_override("margin_right", 44)
	layout.add_theme_constant_override("margin_top", 36)
	layout.add_theme_constant_override("margin_bottom", 30)
	add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Run History"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(title)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(180.0, 2.0)
	accent.color = Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.65)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(accent)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	stack.add_child(columns)

	# — Left column: scrollable run list —
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(340.0, 0.0)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(list_scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_list_container.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_list_container)

	_empty_label = Label.new()
	_empty_label.text = "No runs recorded yet.\nComplete a run to see it here."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80, 0.70))
	_list_container.add_child(_empty_label)

	# — Right column: detail view —
	_detail_panel = Panel.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if style_ref != null and style_ref.has_method("_make_panel_style"):
		_detail_panel.add_theme_stylebox_override("panel", style_ref._make_panel_style(Color(0.03, 0.05, 0.08, 0.72), Color(0.26, 0.40, 0.58, 0.56), 12, 1))
	else:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.03, 0.05, 0.08, 0.72)
		s.border_color = Color(0.26, 0.40, 0.58, 0.56)
		s.set_border_width_all(1)
		s.set_corner_radius_all(12)
		_detail_panel.add_theme_stylebox_override("panel", s)
	columns.add_child(_detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_margin.add_theme_constant_override("margin_left", 18)
	detail_margin.add_theme_constant_override("margin_right", 18)
	detail_margin.add_theme_constant_override("margin_top", 16)
	detail_margin.add_theme_constant_override("margin_bottom", 16)
	_detail_panel.add_child(detail_margin)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_margin.add_child(detail_scroll)

	_detail_content = VBoxContainer.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail_content.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail_content)

	_show_detail_placeholder()

	var back_button := _make_back_button()
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	stack.add_child(back_button)

func populate() -> void:
	_records = RUN_HISTORY_STORE_SCRIPT.load_all()
	_selected_index = -1
	_row_buttons.clear()
	for child in _list_container.get_children():
		if child == _empty_label:
			continue
		_list_container.remove_child(child)
		child.queue_free()
	if _records.is_empty():
		_empty_label.visible = true
		_show_detail_placeholder()
		return
	_empty_label.visible = false
	for i in range(_records.size()):
		var rec: Dictionary = _records[i] as Dictionary
		var row := _make_row_button(rec, i)
		_list_container.add_child(row)
		_row_buttons.append(row)
	_select_row(0)

func _make_row_button(rec: Dictionary, index: int) -> Button:
	var outcome := String(rec.get("outcome", "unknown"))
	var is_clear := outcome == "clear"
	var char_name := String(rec.get("character_name", String(rec.get("character_id", "Unknown")).capitalize()))
	var difficulty := String(rec.get("difficulty_label", "Pilgrim"))
	var depth := int(rec.get("max_depth", 0))
	var duration := int(rec.get("duration_seconds", 0))
	var party_size := maxi(1, int(rec.get("player_count", 1)))
	var is_mp := bool(rec.get("is_multiplayer", false)) or party_size > 1

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0.0, 58.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.text = ""
	btn.pressed.connect(func() -> void: _select_row(index))

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.13, 0.20, 0.88)
	normal_style.border_color = Color(0.26, 0.42, 0.62, 0.60)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 12.0
	normal_style.content_margin_right = 12.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.12, 0.19, 0.30, 0.96)
	hover_style.border_color = Color(0.50, 0.72, 0.98, 0.80)
	btn.add_theme_stylebox_override("hover", hover_style)

	var selected_style := normal_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = Color(0.14, 0.24, 0.40, 0.96)
	selected_style.border_color = Color(0.76, 0.90, 1.0, 0.92)
	btn.add_theme_stylebox_override("pressed", selected_style)
	btn.add_theme_stylebox_override("focus", selected_style)

	var row_content := VBoxContainer.new()
	row_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	row_content.offset_left = 12
	row_content.offset_right = -12
	row_content.offset_top = 8
	row_content.offset_bottom = -8
	row_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_content.add_theme_constant_override("separation", 2)
	btn.add_child(row_content)

	var outcome_color := Color(0.52, 0.88, 0.62, 1.0) if is_clear else Color(0.90, 0.46, 0.46, 1.0)
	var outcome_text := ("\u2713 " if is_clear else "\u2717 ") + char_name
	if is_mp:
		outcome_text += "  \u2014  Co-op %dP" % party_size
	var top_label := Label.new()
	top_label.text = outcome_text
	top_label.add_theme_font_size_override("font_size", 15)
	top_label.add_theme_color_override("font_color", outcome_color)
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_content.add_child(top_label)

	var sub_label := Label.new()
	sub_label.text = "%s  \u00b7  Depth %d  \u00b7  %s" % [difficulty, depth, _format_duration(duration)]
	sub_label.add_theme_font_size_override("font_size", 13)
	sub_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.90, 0.80))
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_content.add_child(sub_label)

	return btn

func _select_row(index: int) -> void:
	_selected_index = index
	for i in range(_row_buttons.size()):
		var btn := _row_buttons[i]
		var is_sel := i == index
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(10)
		s.content_margin_left = 12.0
		s.content_margin_right = 12.0
		s.content_margin_top = 8.0
		s.content_margin_bottom = 8.0
		if is_sel:
			s.bg_color = Color(0.14, 0.24, 0.40, 0.96)
			s.border_color = Color(0.76, 0.90, 1.0, 0.92)
			s.set_border_width_all(2)
		else:
			s.bg_color = Color(0.08, 0.13, 0.20, 0.88)
			s.border_color = Color(0.26, 0.42, 0.62, 0.60)
			s.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", s)
	if index >= 0 and index < _records.size():
		_show_detail(_records[index] as Dictionary)

func _show_detail(rec: Dictionary) -> void:
	for child in _detail_content.get_children():
		child.queue_free()

	var wrapped: RunSummaryWithProfile = RUN_SUMMARY_WITH_PROFILE_SCRIPT.create(rec, null)

	var outcome := wrapped.get_outcome()
	var is_clear := outcome == "clear"
	var outcome_color := Color(0.52, 0.88, 0.62, 1.0) if is_clear else Color(0.90, 0.46, 0.46, 1.0)
	var outcome_text := ("Victory" if is_clear else "Defeat") + " — " + wrapped.get_character_name()

	_add_detail_label(outcome_text, 24, outcome_color, true)
	_add_detail_label(wrapped.get_difficulty_label(), 16, Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.9), false)

	_add_detail_separator()

	_add_detail_row("Max Depth", str(wrapped.get_max_depth()))
	_add_detail_row("Rooms Cleared", str(wrapped.get_rooms_cleared()))
	_add_detail_row("Duration", _format_duration(wrapped.get_duration_seconds()))
	var detail_party_size := maxi(1, int(rec.get("player_count", 1)))
	var detail_is_mp := bool(rec.get("is_multiplayer", false)) or detail_party_size > 1
	if detail_is_mp:
		_add_detail_row("Mode", "Co-op (%d players)" % detail_party_size)
	else:
		_add_detail_row("Mode", "Solo")
	_add_detail_row("Enemies Killed", str(wrapped.get_enemies_killed()))
	_add_detail_row("Bosses Defeated", str(wrapped.get_bosses_defeated()))
	_add_detail_row("Damage Dealt", str(wrapped.get_damage_dealt()))
	_add_detail_row("Damage Taken", str(wrapped.get_damage_taken()))

	var display_name := wrapped.get_display_name()
	if not display_name.is_empty() and display_name != "Player":
		_add_detail_separator()
		_add_detail_row("Profile", display_name)

	var boons := wrapped.get_boons_list()
	var arcana := wrapped.get_arcana_list()
	var boss_rewards := wrapped.get_boss_rewards_list()
	if not boons.is_empty() or not arcana.is_empty() or not boss_rewards.is_empty():
		_add_detail_separator()
		_add_detail_label("Build", 15, Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.78), false)
		for item in boss_rewards:
			var d := item as Dictionary
			_add_detail_label("◆ " + String(d.get("name", "")), 14, Color(RARITY_LEGENDARY.r, RARITY_LEGENDARY.g, RARITY_LEGENDARY.b, 0.94), false)
		for item in arcana:
			var d := item as Dictionary
			_add_detail_label("\u2605 " + String(d.get("name", "")), 14, Color(RARITY_EPIC.r, RARITY_EPIC.g, RARITY_EPIC.b, 0.92), false)
		for item in boons:
			var d := item as Dictionary
			_add_detail_label("\u00b7 " + String(d.get("name", "")), 14, Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.9), false)

func _show_detail_placeholder() -> void:
	for child in _detail_content.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Select a run to see details."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.52, 0.62, 0.74, 0.60))
	_detail_content.add_child(lbl)

func _add_detail_label(text: String, font_size: int, color: Color, bold: bool) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if bold:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
	_detail_content.add_child(lbl)

func _add_detail_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_child(row)

	var key := Label.new()
	key.text = label_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size", 15)
	key.add_theme_color_override("font_color", Color(0.68, 0.78, 0.90, 0.78))
	row.add_child(key)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.96))
	row.add_child(val)

func _add_detail_separator() -> void:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = Color(0.30, 0.42, 0.58, 0.30)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_child(sep)

func _format_duration(seconds: int) -> String:
	if seconds <= 0:
		return "--:--"
	var m := int(floor(float(seconds) / 60.0))
	var s := int(seconds) % 60
	return "%d:%02d" % [m, s]

func _make_back_button() -> Button:
	var button := Button.new()
	button.text = "Back"
	button.custom_minimum_size = Vector2(180.0, 46.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.15, 0.22, 0.95)
	s.border_color = Color(0.34, 0.56, 0.84, 0.72)
	s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 14.0
	s.content_margin_bottom = 14.0
	button.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.13, 0.19, 0.28, 0.98)
	sh.border_color = Color(0.62, 0.82, 0.98, 0.88)
	button.add_theme_stylebox_override("hover", sh)
	button.add_theme_stylebox_override("focus", sh)
	return button
