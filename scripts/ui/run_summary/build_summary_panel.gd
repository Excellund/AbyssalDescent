extends VBoxContainer
class_name BuildSummaryPanel

const BUILD_ITEM_CARD_SCRIPT := preload("res://scripts/ui/run_summary/build_item_card.gd")
const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

var _boon_flow: FlowContainer
var _arcana_flow: FlowContainer
var _boss_flow: FlowContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Build Summary"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.98))
	add_child(title)

	_boon_flow = _add_group("Boons")
	_arcana_flow = _add_group("Arcana")
	_boss_flow = _add_group("Boss Rewards")

func set_build_summary(build_summary: Dictionary) -> void:
	_fill_flow(_boon_flow, build_summary.get("boons", []) as Array)
	_fill_flow(_arcana_flow, build_summary.get("arcana", []) as Array)
	_fill_flow(_boss_flow, build_summary.get("boss_rewards", []) as Array)

func _add_group(group_title: String) -> FlowContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	add_child(section)

	var label := Label.new()
	label.text = group_title
	label.add_theme_font_size_override("font_size", 16)
	var group_color := RARITY_COMMON
	if group_title == "Arcana":
		group_color = RARITY_EPIC
	elif group_title == "Boss Rewards":
		group_color = RARITY_LEGENDARY
	label.add_theme_color_override("font_color", Color(group_color.r, group_color.g, group_color.b, 0.96))
	section.add_child(label)

	var flow := FlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	section.add_child(flow)
	return flow

func _fill_flow(flow: FlowContainer, items: Array) -> void:
	for child in flow.get_children():
		child.queue_free()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "None"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84, 0.8))
		flow.add_child(empty)
		return
	for item_variant in items:
		var item := item_variant as Dictionary
		var card = BUILD_ITEM_CARD_SCRIPT.new()
		card.set_item(item)
		flow.add_child(card)
