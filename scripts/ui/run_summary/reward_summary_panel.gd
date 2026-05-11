extends VBoxContainer
class_name RewardSummaryPanel

const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_RARE := Color(0.46, 0.78, 1.0, 0.94)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

var _unlock_cards: VBoxContainer
var _timeline_list: VBoxContainer
var _timeline_section: VBoxContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Progression"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", RARITY_COMMON)
	add_child(title)

	var unlocks_title := Label.new()
	unlocks_title.text = "Progress Updates"
	unlocks_title.add_theme_font_size_override("font_size", 16)
	unlocks_title.add_theme_color_override("font_color", Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.94))
	add_child(unlocks_title)

	_unlock_cards = VBoxContainer.new()
	_unlock_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unlock_cards.add_theme_constant_override("separation", 6)
	add_child(_unlock_cards)

	_timeline_section = VBoxContainer.new()
	_timeline_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_section.add_theme_constant_override("separation", 4)
	add_child(_timeline_section)

	var timeline_title := Label.new()
	timeline_title.text = "Build Timeline"
	timeline_title.add_theme_font_size_override("font_size", 16)
	timeline_title.add_theme_color_override("font_color", Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.94))
	_timeline_section.add_child(timeline_title)

	_timeline_list = VBoxContainer.new()
	_timeline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_list.add_theme_constant_override("separation", 3)
	_timeline_section.add_child(_timeline_list)

func set_progression(unlocks: Array, timeline: Array) -> void:
	for child in _unlock_cards.get_children():
		child.queue_free()
	if unlocks.is_empty():
		var empty := Label.new()
		empty.text = "No new progression unlocks this run"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.84))
		_unlock_cards.add_child(empty)
	else:
		for unlock_entry in unlocks:
			var unlock_text := String(unlock_entry).strip_edges()
			if unlock_text.is_empty():
				continue
			_unlock_cards.add_child(_build_unlock_card(unlock_text))

	for child in _timeline_list.get_children():
		child.queue_free()
	if timeline.is_empty():
		var empty := Label.new()
		empty.text = "No timeline events recorded"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.82))
		_timeline_list.add_child(empty)
		return
	for i in range(timeline.size() - 1, -1, -1):
		var event := timeline[i] as Dictionary
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_theme_font_size_override("font_size", 13)
		entry.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.9))
		entry.text = "Depth %d · %s" % [int(event.get("depth", 0)), String(event.get("label", "Unknown"))]
		_timeline_list.add_child(entry)

func _build_unlock_card(unlock_text: String) -> Panel:
	var payload := _classify_unlock(unlock_text)
	var border_color: Color = payload.get("color", RARITY_RARE)
	var title_text: String = String(payload.get("title", "Progress Update"))
	var detail_text: String = String(payload.get("detail", unlock_text))

	var card := Panel.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 64.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.92)
	style.border_color = Color(border_color.r, border_color.g, border_color.b, 0.82)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 2.0)
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var title := Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(border_color.r, border_color.g, border_color.b, 0.96))
	stack.add_child(title)

	var detail := Label.new()
	detail.text = detail_text
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.92))
	stack.add_child(detail)

	return card

func _classify_unlock(unlock_text: String) -> Dictionary:
	if unlock_text.begins_with("Unlocked Character: "):
		return {
			"title": "Character Unlocked",
			"detail": unlock_text.trim_prefix("Unlocked Character: "),
			"color": RARITY_LEGENDARY
		}
	if unlock_text.begins_with("Unlocked Bearing: "):
		return {
			"title": "Bearing Unlocked",
			"detail": unlock_text.trim_prefix("Unlocked Bearing: "),
			"color": RARITY_RARE
		}
	if unlock_text.begins_with("Ascension Rank "):
		return {
			"title": "Ascension Progress",
			"detail": unlock_text,
			"color": RARITY_EPIC
		}
	if unlock_text.begins_with("Oath Complete: "):
		return {
			"title": "Oath Completed",
			"detail": unlock_text.trim_prefix("Oath Complete: "),
			"color": RARITY_EPIC
		}
	if unlock_text.begins_with("Catalyst Unlocked: "):
		return {
			"title": "Catalyst Unlocked",
			"detail": unlock_text.trim_prefix("Catalyst Unlocked: "),
			"color": RARITY_LEGENDARY
		}
	return {
		"title": "Progress Update",
		"detail": unlock_text,
		"color": RARITY_COMMON
	}

func set_timeline_visible(timeline_visible: bool) -> void:
	_timeline_section.visible = timeline_visible
