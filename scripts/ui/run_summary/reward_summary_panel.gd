extends VBoxContainer
class_name RewardSummaryPanel

var _unlocks_label: Label
var _timeline_scroll: ScrollContainer
var _timeline_list: VBoxContainer
var _timeline_section: VBoxContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Progression"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.98))
	add_child(title)

	_unlocks_label = Label.new()
	_unlocks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlocks_label.add_theme_font_size_override("font_size", 15)
	_unlocks_label.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0, 0.9))
	add_child(_unlocks_label)

	_timeline_section = VBoxContainer.new()
	_timeline_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_section.add_theme_constant_override("separation", 4)
	add_child(_timeline_section)

	var timeline_title := Label.new()
	timeline_title.text = "Build Timeline"
	timeline_title.add_theme_font_size_override("font_size", 16)
	timeline_title.add_theme_color_override("font_color", Color(0.72, 0.84, 0.98, 0.94))
	_timeline_section.add_child(timeline_title)

	_timeline_scroll = ScrollContainer.new()
	_timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_scroll.custom_minimum_size = Vector2(0.0, 160.0)
	_timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_timeline_scroll.clip_contents = true
	_timeline_section.add_child(_timeline_scroll)

	_timeline_list = VBoxContainer.new()
	_timeline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_list.add_theme_constant_override("separation", 3)
	_timeline_scroll.add_child(_timeline_list)

func set_progression(unlocks: Array, timeline: Array) -> void:
	if unlocks.is_empty():
		_unlocks_label.text = "Unlocks: None"
	else:
		_unlocks_label.text = "Unlocks: %s" % ", ".join(unlocks)

	for child in _timeline_list.get_children():
		child.queue_free()
	if timeline.is_empty():
		var empty := Label.new()
		empty.text = "No timeline events recorded"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84, 0.8))
		_timeline_list.add_child(empty)
		return
	var shown := 0
	for i in range(timeline.size() - 1, -1, -1):
		var event := timeline[i] as Dictionary
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_theme_font_size_override("font_size", 13)
		entry.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 0.88))
		entry.text = "Depth %d · %s" % [int(event.get("depth", 0)), String(event.get("label", "Unknown"))]
		_timeline_list.add_child(entry)
		shown += 1
		if shown >= 8:
			break

func set_timeline_visible(timeline_visible: bool) -> void:
	_timeline_section.visible = timeline_visible
