extends Node

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const CHARACTER_PASSIVES := preload("res://scripts/shared/character_passive_catalogue.gd")
const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const COMBAT_KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const BUILD_KEYWORDS := preload("res://scripts/shared/build_keyword_summary.gd")
const SCALED_UI_FONT := preload("res://scripts/ui/scaled_ui_font.gd")
const CATALYST_REGISTRY := preload("res://scripts/progression/catalyst_registry.gd")
const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)
const BODY_FONT_SIZE := 18
const BODY_COLOR := Color(0.90, 0.93, 0.98, 1.0)

signal build_detail_opened
signal build_detail_closed

var panel: Panel
var is_visible := false
var opened_from_reward := false
var _layer: CanvasLayer
var _modal_backdrop: ColorRect
var _layout_container: VBoxContainer
var _scroll: ScrollContainer
var _content_vbox: VBoxContainer
var _close_button: Button
var _active_passive_id := ""
var power_registry_instance = POWER_REGISTRY.new()
var keyword_overview_toggle: Button
var keyword_summary_label: RichTextLabel
var keyword_breakdown: VBoxContainer
var keyword_effect_flow: HFlowContainer
var keyword_action_flow: HFlowContainer
var keyword_source_details: RichTextLabel
var _selected_keyword := ""

var passive_section: VBoxContainer
var passive_name_label: Label
var passive_desc_label: RichTextLabel

var catalyst_panel: PanelContainer
var catalyst_details: RichTextLabel

var boons_section: VBoxContainer
var boons_list_container: VBoxContainer

var arcana_section: VBoxContainer
var arcana_list_container: VBoxContainer

var boss_section: VBoxContainer
var boss_list_container: VBoxContainer

func _init() -> void:
	add_child(power_registry_instance)

func setup() -> void:
	_create_panel()
	get_viewport().size_changed.connect(_apply_layout)

func _create_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 95
	add_child(_layer)
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.color = Color(0.0, 0.0, 0.0, 0.28)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_backdrop.visible = false
	_layer.add_child(_modal_backdrop)

	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(940.0, 700.0)
	panel.position = Vector2(-470.0, -350.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.01, 0.02, 0.06, 0.98)
	panel_style.border_color = Color(0.70, 0.85, 1.0, 0.92)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.64)
	panel_style.shadow_offset = Vector2(2.0, 4.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.visible = false
	_layer.add_child(panel)
	SCALED_UI_FONT.apply_to(panel)

	_layout_container = VBoxContainer.new()
	var container := _layout_container
	container.position = Vector2(24.0, 24.0)
	container.custom_minimum_size = Vector2(892.0, 652.0)
	container.add_theme_constant_override("separation", 16)
	panel.add_child(container)

	# Title
	var title := Label.new()
	title.text = "Build Details"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.83, 0.91, 1.0, 0.98))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	# Scroll container for content
	_scroll = ScrollContainer.new()
	var scroll := _scroll
	scroll.custom_minimum_size = Vector2(892.0, 590.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	var content_vbox := _content_vbox
	content_vbox.custom_minimum_size = Vector2(870.0, 0.0)
	content_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(content_vbox)

	_close_button = Button.new()
	_close_button.text = "Return to rewards  [Tab / Esc]"
	_close_button.custom_minimum_size.y = 42.0
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.pressed.connect(close)
	container.add_child(_close_button)
	_create_keyword_overview(content_vbox)

	# Passive section panel
	var passive_panel := PanelContainer.new()
	passive_panel.custom_minimum_size = Vector2(870.0, 0.0)
	var passive_panel_style := StyleBoxFlat.new()
	passive_panel_style.bg_color = Color(0.07, 0.04, 0.13, 0.78)
	passive_panel_style.border_color = Color(0.72, 0.52, 1.0, 0.90)
	passive_panel_style.bg_color = Color(0.03, 0.10, 0.12, 0.78)
	passive_panel_style.border_color = Color(0.44, 0.86, 0.92, 0.90)
	passive_panel_style.content_margin_left = 14.0
	passive_panel_style.content_margin_right = 14.0
	passive_panel_style.content_margin_top = 14.0
	passive_panel_style.content_margin_bottom = 14.0
	passive_panel.add_theme_stylebox_override("panel", passive_panel_style)
	content_vbox.add_child(passive_panel)

	passive_section = VBoxContainer.new()
	passive_section.custom_minimum_size = Vector2(840.0, 0.0)
	passive_section.add_theme_constant_override("separation", 8)
	passive_panel.add_child(passive_section)

	var passive_header := Label.new()
	passive_header.text = "Passive"
	passive_header.add_theme_font_size_override("font_size", 20)
	passive_header.add_theme_color_override("font_color", Color(0.78, 0.60, 1.0, 0.98))
	passive_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_header.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0, 0.98))
	passive_header.add_theme_constant_override("shadow_offset_y", 2)
	passive_section.add_child(passive_header)

	passive_name_label = Label.new()
	passive_name_label.text = "—"
	passive_name_label.add_theme_font_size_override("font_size", 18)
	passive_name_label.add_theme_color_override("font_color", Color(0.82, 0.68, 1.0, 0.98))
	passive_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_name_label.add_theme_constant_override("shadow_offset_x", 2)
	passive_name_label.add_theme_constant_override("shadow_offset_y", 2)
	passive_section.add_child(passive_name_label)

	passive_desc_label = RichTextLabel.new()
	passive_desc_label.custom_minimum_size = Vector2(720.0, 0.0)
	passive_desc_label.bbcode_enabled = true
	passive_desc_label.fit_content = true
	passive_desc_label.scroll_active = false
	passive_desc_label.selection_enabled = false
	passive_desc_label.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)
	passive_desc_label.add_theme_font_size_override("bold_font_size", BODY_FONT_SIZE)
	passive_desc_label.add_theme_constant_override("line_separation", 4)
	passive_desc_label.add_theme_color_override("default_color", BODY_COLOR)
	passive_desc_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_desc_label.add_theme_constant_override("shadow_offset_x", 1)
	passive_desc_label.add_theme_constant_override("shadow_offset_y", 1)
	passive_desc_label.text = "No passive selected"
	passive_section.add_child(passive_desc_label)

	_create_catalyst_section(content_vbox)

	# Boss rewards section panel
	var boss_panel := PanelContainer.new()
	boss_panel.custom_minimum_size = Vector2(870.0, 0.0)
	var boss_panel_style := StyleBoxFlat.new()
	boss_panel_style.bg_color = Color(0.10, 0.04, 0.12, 0.76)
	boss_panel_style.border_color = Color(RARITY_LEGENDARY.r, RARITY_LEGENDARY.g, RARITY_LEGENDARY.b, 0.9)
	boss_panel_style.set_border_width_all(2)
	boss_panel_style.set_corner_radius_all(12)
	boss_panel_style.content_margin_left = 14.0
	boss_panel_style.content_margin_right = 14.0
	boss_panel_style.content_margin_top = 14.0
	boss_panel_style.content_margin_bottom = 14.0
	boss_panel.add_theme_stylebox_override("panel", boss_panel_style)
	content_vbox.add_child(boss_panel)

	boss_section = VBoxContainer.new()
	boss_section.custom_minimum_size = Vector2(840.0, 0.0)
	boss_section.add_theme_constant_override("separation", 8)
	boss_panel.add_child(boss_section)

	var boss_header := Label.new()
	boss_header.text = "Boss"
	boss_header.add_theme_font_size_override("font_size", 20)
	boss_header.add_theme_color_override("font_color", Color(RARITY_LEGENDARY.r, RARITY_LEGENDARY.g, RARITY_LEGENDARY.b, 0.98))
	boss_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	boss_header.add_theme_constant_override("shadow_offset_x", 2)
	boss_header.add_theme_constant_override("shadow_offset_y", 2)
	boss_section.add_child(boss_header)

	boss_list_container = VBoxContainer.new()
	boss_list_container.add_theme_constant_override("separation", 6)
	boss_section.add_child(boss_list_container)

	# Arcana section panel
	var arcana_panel := PanelContainer.new()
	arcana_panel.custom_minimum_size = Vector2(870.0, 0.0)
	var arcana_panel_style := StyleBoxFlat.new()
	arcana_panel_style.bg_color = Color(0.11, 0.09, 0.03, 0.72)
	arcana_panel_style.border_color = Color(RARITY_EPIC.r, RARITY_EPIC.g, RARITY_EPIC.b, 0.9)
	arcana_panel_style.set_border_width_all(2)
	arcana_panel_style.set_corner_radius_all(12)
	arcana_panel_style.content_margin_left = 14.0
	arcana_panel_style.content_margin_right = 14.0
	arcana_panel_style.content_margin_top = 14.0
	arcana_panel_style.content_margin_bottom = 14.0
	arcana_panel.add_theme_stylebox_override("panel", arcana_panel_style)
	content_vbox.add_child(arcana_panel)

	arcana_section = VBoxContainer.new()
	arcana_section.custom_minimum_size = Vector2(840.0, 0.0)
	arcana_section.add_theme_constant_override("separation", 8)
	arcana_panel.add_child(arcana_section)

	var arcana_header := Label.new()
	arcana_header.text = "Arcana"
	arcana_header.add_theme_font_size_override("font_size", 20)
	arcana_header.add_theme_color_override("font_color", Color(RARITY_EPIC.r, RARITY_EPIC.g, RARITY_EPIC.b, 0.98))
	arcana_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	arcana_header.add_theme_constant_override("shadow_offset_x", 2)
	arcana_header.add_theme_constant_override("shadow_offset_y", 2)
	arcana_section.add_child(arcana_header)

	arcana_list_container = VBoxContainer.new()
	arcana_list_container.add_theme_constant_override("separation", 6)
	arcana_section.add_child(arcana_list_container)

	# Boons section panel
	var boons_panel := PanelContainer.new()
	boons_panel.custom_minimum_size = Vector2(870.0, 0.0)
	var boons_panel_style := StyleBoxFlat.new()
	boons_panel_style.bg_color = Color(0.04, 0.09, 0.12, 0.74)
	boons_panel_style.border_color = Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.9)
	boons_panel_style.set_border_width_all(2)
	boons_panel_style.set_corner_radius_all(12)
	boons_panel_style.content_margin_left = 14.0
	boons_panel_style.content_margin_right = 14.0
	boons_panel_style.content_margin_top = 14.0
	boons_panel_style.content_margin_bottom = 14.0
	boons_panel.add_theme_stylebox_override("panel", boons_panel_style)
	content_vbox.add_child(boons_panel)

	boons_section = VBoxContainer.new()
	boons_section.custom_minimum_size = Vector2(840.0, 0.0)
	boons_section.add_theme_constant_override("separation", 8)
	boons_panel.add_child(boons_section)

	var boons_header := Label.new()
	boons_header.text = "Boons"
	boons_header.add_theme_font_size_override("font_size", 20)
	boons_header.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.98))
	boons_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	boons_header.add_theme_constant_override("shadow_offset_x", 2)
	boons_header.add_theme_constant_override("shadow_offset_y", 2)
	boons_section.add_child(boons_header)

	boons_list_container = VBoxContainer.new()
	boons_list_container.add_theme_constant_override("separation", 6)
	boons_section.add_child(boons_list_container)

func open(from_reward: bool = false) -> void:
	if panel == null:
		return
	opened_from_reward = from_reward
	if _layer != null:
		_layer.layer = 140 if from_reward else 95
	if _modal_backdrop != null:
		_modal_backdrop.visible = true
	if _close_button != null:
		_close_button.visible = true
		_close_button.text = "Return to rewards  [Tab / Esc]" if from_reward else "Close  [Tab / Esc]"
	panel.visible = true
	is_visible = true
	_apply_layout()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _close_button != null:
		_close_button.grab_focus()
	build_detail_opened.emit()

func close() -> void:
	if panel == null or not is_visible:
		return
	panel.visible = false
	if _modal_backdrop != null:
		_modal_backdrop.visible = false
	is_visible = false
	opened_from_reward = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	build_detail_closed.emit()

func is_open() -> bool:
	return is_visible

func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	if not is_visible:
		return false
	if _scroll_expanded_details(event):
		return true
	if event.is_echo():
		return event.is_action("reward_inspect") or event.is_action("reward_back")
	if event.is_action_pressed("reward_inspect") or event.is_action_pressed("reward_back"):
		close()
		return true
	# Tab is a toggle. Consume both its release and keyboard repeats before
	# Godot can move GUI focus and scroll to a different keyword or power.
	return event.is_action("reward_inspect") or event.is_action("reward_back")

func _scroll_expanded_details(event: InputEvent) -> bool:
	var direction := 1 if event.is_action_pressed("ui_down", true) else (-1 if event.is_action_pressed("ui_up", true) else 0)
	if direction == 0 or _scroll == null:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	if not (focused is Button) or not focused.has_meta("build_details"):
		return false
	var reference: WeakRef = focused.get_meta("build_details")
	var details := reference.get_ref() as RichTextLabel
	if not is_instance_valid(details) or not details.is_visible_in_tree():
		return false
	var visible_rect := _scroll.get_global_rect()
	var remaining := details.get_global_rect().end.y - visible_rect.end.y if direction > 0 else visible_rect.position.y - focused.get_global_rect().position.y
	if remaining <= 1.0:
		return false
	remaining /= maxf(0.01, _scroll.get_global_transform().get_scale().abs().y)
	var before := _scroll.scroll_vertical
	_scroll.scroll_vertical += direction * mini(96, int(ceil(remaining)))
	return _scroll.scroll_vertical != before

func refresh_from_player(player: PLAYER_SCRIPT, character_id: String, catalyst_ids: Array = [], _candidate: Dictionary = {}) -> void:
	var boons: Array[String] = []
	var arcana: Array[String] = []
	var bosses: Array[String] = []
	if is_instance_valid(player):
		for id: String in POWER_REGISTRY.UPGRADE_BALANCE:
			if player.get_upgrade_stack_count(id) > 0:
				boons.append(id)
		for id: String in POWER_REGISTRY.TRIAL_POWER_POOL_IDS:
			if player.get_trial_power_stack_count(id) > 0:
				arcana.append(id)
		for id: String in POWER_REGISTRY.BOSS_REWARD_BALANCE:
			if player.get_upgrade_stack_count(id) > 0:
				bosses.append(id)
	refresh(character_id, boons, arcana, bosses, player, catalyst_ids)

func refresh(character_id: String, active_boons: Array, active_arcana: Array, active_boss_rewards: Array = [], player: PLAYER_SCRIPT = null, catalyst_ids: Array = [], _candidate: Dictionary = {}) -> void:
	if panel == null:
		return
	_update_passive_section(character_id)
	_update_keyword_overview(player)
	_update_catalyst_section(catalyst_ids)
	_update_power_section(boons_list_container, active_boons, "boon", player)
	_update_power_section(arcana_list_container, active_arcana, "arcana", player)
	_update_power_section(boss_list_container, active_boss_rewards, "boss", player)
	_scroll.scroll_vertical = 0
	_apply_layout()

func _apply_layout() -> void:
	if panel == null or _layout_container == null or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	# The shipped canvas stays 2560x1440 when the physical window shrinks.
	# Keep inspection text readable in physical pixels on those smaller windows.
	var layout_scale := 1.0
	var window := get_viewport() as Window
	if window != null and window.size.y > 0:
		layout_scale = maxf(1.0, viewport_size.y / float(window.size.y))
	var available_size := viewport_size / layout_scale
	var panel_size := Vector2(minf(940.0, available_size.x - 48.0), minf(700.0, available_size.y - 48.0))
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	panel.scale = Vector2.ONE * layout_scale
	panel.position = (viewport_size - panel_size * layout_scale) * 0.5
	_layout_container.custom_minimum_size = Vector2.ZERO
	_layout_container.size = panel_size - Vector2(48.0, 48.0)
	_scroll.custom_minimum_size = Vector2(0.0, 0.0)
	_content_vbox.custom_minimum_size.x = panel_size.x - 70.0
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit_content_widths(_content_vbox)

func _fit_content_widths(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.custom_minimum_size.x = 0.0
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if child is Label:
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fit_content_widths(child)

func _make_detail_label(font_size: int = BODY_FONT_SIZE) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_color_override("default_color", BODY_COLOR)
	label.add_theme_constant_override("line_separation", 3)
	return label

func _create_keyword_overview(content: VBoxContainer) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	content.add_child(stack)
	keyword_overview_toggle = Button.new()
	keyword_overview_toggle.custom_minimum_size.y = 42.0
	keyword_overview_toggle.toggle_mode = true
	keyword_overview_toggle.tooltip_text = "Inspect every keyword and its contributing powers. Counts include your passive; each owned power counts once, regardless of level. Temporary bonuses are excluded."
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.65)
	style.border_color = Color(0.44, 0.60, 0.70, 0.55)
	style.border_width_bottom = 1
	style.set_corner_radius_all(5)
	keyword_overview_toggle.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.14, 0.20, 0.90)
	keyword_overview_toggle.add_theme_stylebox_override("hover", hover)
	keyword_overview_toggle.add_theme_stylebox_override("pressed", hover)
	stack.add_child(keyword_overview_toggle)
	keyword_summary_label = _make_detail_label(17)
	keyword_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keyword_summary_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyword_summary_label.offset_left = 12.0
	keyword_summary_label.offset_right = -34.0
	keyword_summary_label.offset_top = 9.0
	keyword_summary_label.offset_bottom = -7.0
	keyword_overview_toggle.add_child(keyword_summary_label)
	var arrow := Label.new()
	arrow.text = "+"
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	arrow.position = Vector2(-24.0, -12.0)
	arrow.add_theme_font_size_override("font_size", 19)
	keyword_overview_toggle.add_child(arrow)
	keyword_breakdown = VBoxContainer.new()
	keyword_breakdown.add_theme_constant_override("separation", 8)
	keyword_breakdown.hide()
	stack.add_child(keyword_breakdown)
	keyword_overview_toggle.toggled.connect(func(expanded: bool):
		keyword_breakdown.visible = expanded
		arrow.text = "−" if expanded else "+")
	var explanation := _make_detail_label(15)
	explanation.text = "Owned powers + passive · Each source counts once. Select a keyword to inspect."
	keyword_breakdown.add_child(explanation)
	keyword_effect_flow = HFlowContainer.new()
	keyword_effect_flow.add_theme_constant_override("h_separation", 6)
	keyword_effect_flow.add_theme_constant_override("v_separation", 4)
	keyword_breakdown.add_child(keyword_effect_flow)
	var actions_heading := _make_detail_label(15)
	actions_heading.text = "Actions & triggers"
	keyword_breakdown.add_child(actions_heading)
	keyword_action_flow = HFlowContainer.new()
	keyword_action_flow.add_theme_constant_override("h_separation", 6)
	keyword_action_flow.add_theme_constant_override("v_separation", 4)
	keyword_breakdown.add_child(keyword_action_flow)
	keyword_source_details = _make_detail_label()
	keyword_source_details.hide()
	keyword_breakdown.add_child(keyword_source_details)

func _update_keyword_overview(player: PLAYER_SCRIPT) -> void:
	var summary := BUILD_KEYWORDS.from_levels(BUILD_KEYWORDS.owned_levels(player), _active_passive_id if is_instance_valid(player) else "")
	_selected_keyword = ""
	keyword_source_details.hide()
	keyword_overview_toggle.button_pressed = false
	keyword_breakdown.hide()
	keyword_summary_label.text = "[b]Keywords[/b]     " + BUILD_KEYWORDS.compact_bbcode(summary)
	_fill_keyword_flow(keyword_effect_flow, summary.effects)
	_fill_keyword_flow(keyword_action_flow, summary.actions)

func _fill_keyword_flow(flow: HFlowContainer, entries: Array) -> void:
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "None acquired"
		empty.add_theme_font_size_override("font_size", 17)
		flow.add_child(empty)
		return
	for entry: Dictionary in entries:
		var id := String(entry.id)
		var button := Button.new()
		button.text = "%s  %d" % [COMBAT_KEYWORDS.KEYWORDS[id].label, entry.count]
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", Color(COMBAT_KEYWORDS.keyword_color(id)))
		button.custom_minimum_size.y = 32.0
		button.toggle_mode = true
		button.tooltip_text = "%d owned sources; select to inspect." % entry.count
		button.set_meta("keyword_id", id)
		button.set_meta("build_details", weakref(keyword_source_details))
		button.pressed.connect(func():
			var show_details := _selected_keyword != id or not keyword_source_details.visible
			_selected_keyword = id
			keyword_source_details.text = _keyword_source_text(entry)
			keyword_source_details.visible = show_details
			for row: HFlowContainer in [keyword_effect_flow, keyword_action_flow]:
				for item in row.get_children():
					if item is Button:
						item.set_pressed_no_signal(show_details and item == button))
		flow.add_child(button)

func _keyword_source_text(entry: Dictionary) -> String:
	var lines: Array[String] = [COMBAT_KEYWORDS.definitions_bbcode([String(entry.id)])]
	var produces: Array[String] = []
	var uses: Array[String] = []
	for source: Dictionary in entry.sources:
		var label := CHARACTER_PASSIVES.get_display_name(source.id) + " (passive)" if source.passive else _power_display_name(source.id) + " (Lv %d)" % source.level
		if source.produces:
			produces.append(label)
		if source.uses:
			uses.append(label)
	if not produces.is_empty():
		lines.append("[b]Produces:[/b] " + ", ".join(produces))
	if not uses.is_empty():
		lines.append("[b]Uses:[/b] " + ", ".join(uses))
	lines.append("Select a power below for its activation rules.")
	return "\n".join(lines)

func _power_level(id: String, arcana: bool, player: PLAYER_SCRIPT) -> int:
	if not is_instance_valid(player):
		return 1
	return player.get_trial_power_stack_count(id) if arcana else player.get_upgrade_stack_count(id)

func _level_text(id: String, level: int, arcana: bool, player: PLAYER_SCRIPT) -> String:
	var result := "Level %d" % level
	if arcana and is_instance_valid(player) and player.has_trial_power_prismatic(id):
		result += " · Prismatic"
	return result

func _keyword_details(id: String, level: int, prismatic: bool = false) -> String:
	var metadata := POWER_REGISTRY.get_power_keyword_metadata(id, level, prismatic)
	var ids: Array[String] = []
	ids.assign(metadata.get("description_keywords", []))
	ids.erase("damage")
	ids.erase("damage_stat")
	var rules := _rule_lines(String(metadata.get("condition_text", "")))
	var result := "[b]Rules[/b]\n" + "\n".join(rules) if not rules.is_empty() else ""
	var definitions := COMBAT_KEYWORDS.definitions_bbcode(ids)
	if not definitions.is_empty():
		result += ("\n\n" if not result.is_empty() else "") + "[b]Keywords[/b]\n" + definitions
	return result.strip_edges()

func _rule_lines(condition: String) -> Array[String]:
	var lines: Array[String] = []
	for sentence in condition.replace("; ", ". ").split(". ", false):
		var rule := String(sentence).strip_edges().trim_suffix(".")
		if not rule.is_empty():
			lines.append("• " + rule.left(1).to_upper() + rule.substr(1) + ".")
	return lines

func _create_catalyst_section(content: VBoxContainer) -> void:
	catalyst_panel = PanelContainer.new()
	catalyst_panel.custom_minimum_size = Vector2(870.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.12, 0.74)
	style.border_color = Color(0.44, 0.72, 0.86, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	catalyst_panel.add_theme_stylebox_override("panel", style)
	content.add_child(catalyst_panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	catalyst_panel.add_child(stack)
	var heading := Label.new()
	heading.text = "Catalysts"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0, 0.98))
	stack.add_child(heading)
	catalyst_details = RichTextLabel.new()
	catalyst_details.bbcode_enabled = true
	catalyst_details.fit_content = true
	catalyst_details.scroll_active = false
	catalyst_details.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)
	catalyst_details.add_theme_font_size_override("bold_font_size", BODY_FONT_SIZE)
	catalyst_details.add_theme_color_override("default_color", BODY_COLOR)
	stack.add_child(catalyst_details)
	catalyst_panel.hide()

func _update_catalyst_section(catalyst_ids: Array) -> void:
	var entries: Array[String] = []
	for id_variant in catalyst_ids:
		var definition := CATALYST_REGISTRY.get_definition(String(id_variant))
		if definition.is_empty():
			continue
		entries.append("[b]%s[/b]\n%s" % [String(definition["label"]), String(definition["description"])])
	catalyst_details.text = "\n\n".join(entries)
	catalyst_panel.visible = not entries.is_empty()

func _update_passive_section(character_id: String) -> void:
	_active_passive_id = ""
	var char_data := CHARACTER_REGISTRY.get_character(character_id)
	if char_data == null:
		passive_name_label.text = "Unknown Character"
		passive_desc_label.text = "No passive available"
		return
	
	_active_passive_id = _resolve_passive_id(character_id, char_data)
	passive_name_label.text = _format_passive_name(_active_passive_id)
	passive_desc_label.text = CHARACTER_PASSIVES.get_build_description(_active_passive_id)

func _resolve_passive_id(character_id: String, char_data: Dictionary) -> String:
	var passive_id := String(char_data.get("passive_id", "")).strip_edges().to_lower()
	if not passive_id.is_empty() and passive_id != "passive":
		return passive_id
	var normalized_character_id := character_id.strip_edges().to_lower()
	match normalized_character_id:
		"bastion":
			return "iron_retort"
		"hexweaver":
			return "sigil_burst"
		"veilstrider":
			return "veilstep_rhythm"
		"riftlancer":
			return "farline_focus"
		_:
			return passive_id

func _update_power_section(container: VBoxContainer, power_ids: Array, power_type: String, player: PLAYER_SCRIPT = null) -> void:
	# Clear existing entries
	for child in container.get_children():
		child.queue_free()
	
	if power_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "—  None acquired"
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", Color(0.62, 0.77, 0.9, 0.56))
		container.add_child(empty_label)
		return
	
	for power_id in power_ids:
		var name_text := _power_display_name(power_id)
		var desc_text := _get_power_current_desc(power_id, power_type, player)
		var id := String(power_id)
		var stack_count := maxi(1, _power_level(id, power_type == "arcana", player))
		var stack_suffix := "  · " + _level_text(id, stack_count, power_type == "arcana", player)

		# Add power entry
		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 4)
		container.add_child(entry_vbox)
		
		var power_name := Button.new()
		power_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		power_name.flat = true
		power_name.tooltip_text = "Show keyword meanings and exact conditions."
		power_name.text = "  • %s%s  ›" % [name_text, stack_suffix]
		power_name.add_theme_font_size_override("font_size", 18)
		power_name.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.98))
		power_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
		power_name.add_theme_constant_override("shadow_offset_x", 1)
		power_name.add_theme_constant_override("shadow_offset_y", 1)
		entry_vbox.add_child(power_name)
		
		if not desc_text.is_empty():
			var power_desc := RichTextLabel.new()
			power_desc.custom_minimum_size = Vector2.ZERO
			power_desc.bbcode_enabled = true
			power_desc.fit_content = true
			power_desc.scroll_active = false
			power_desc.selection_enabled = false
			power_desc.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)
			power_desc.add_theme_font_size_override("bold_font_size", BODY_FONT_SIZE)
			power_desc.add_theme_constant_override("line_separation", 3)
			power_desc.add_theme_color_override("default_color", BODY_COLOR)
			power_desc.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
			power_desc.add_theme_constant_override("shadow_offset_x", 1)
			power_desc.add_theme_constant_override("shadow_offset_y", 1)
			power_desc.text = "    %s" % desc_text
			entry_vbox.add_child(power_desc)
		var keyword_details := _make_detail_label()
		keyword_details.text = _keyword_details(id, stack_count, power_type == "arcana" and is_instance_valid(player) and player.has_trial_power_prismatic(id))
		keyword_details.visible = false
		entry_vbox.add_child(keyword_details)
		power_name.set_meta("build_details", weakref(keyword_details))
		power_name.pressed.connect(func(): keyword_details.visible = not keyword_details.visible)

func _pi(node: Node, prop: String, fallback: int = 0) -> int:
	var v = node.get(prop)
	return v if v != null else fallback

func _pf(node: Node, prop: String, fallback: float = 0.0) -> float:
	var v = node.get(prop)
	return v if v != null else fallback

func _damage_kind_prefix(_power_id: String, _player: PLAYER_SCRIPT) -> String:
	return ""

func _get_power_current_desc(power_id: String, _power_type: String, player: PLAYER_SCRIPT) -> String:
	if player == null:
		return ""
	return player.get_power_current_desc(power_id)

func _power_display_name(power_id: String) -> String:
	return power_registry_instance.get_power_display_name(power_id)

func _format_passive_name(passive_id: String) -> String:
	return CHARACTER_PASSIVES.get_display_name(passive_id)
