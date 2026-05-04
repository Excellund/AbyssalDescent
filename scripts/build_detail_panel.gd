extends Node

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")

signal build_detail_opened
signal build_detail_closed

var panel: Panel
var is_visible := false

var passive_section: VBoxContainer
var passive_name_label: Label
var passive_desc_label: RichTextLabel

var boons_section: VBoxContainer
var boons_list_container: VBoxContainer

var arcana_section: VBoxContainer
var arcana_list_container: VBoxContainer

var boss_section: VBoxContainer
var boss_list_container: VBoxContainer

func setup() -> void:
	_create_panel()

func _create_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)

	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860.0, 640.0)
	panel.position = Vector2(-430.0, -320.0)
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
	layer.add_child(panel)

	var container := VBoxContainer.new()
	container.position = Vector2(24.0, 24.0)
	container.custom_minimum_size = Vector2(812.0, 592.0)
	container.add_theme_constant_override("separation", 14)
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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(812.0, 530.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)

	var content_vbox := VBoxContainer.new()
	content_vbox.custom_minimum_size = Vector2(790.0, 0.0)
	content_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(content_vbox)

	# Passive section panel
	var passive_panel := PanelContainer.new()
	passive_panel.custom_minimum_size = Vector2(790.0, 0.0)
	var passive_panel_style := StyleBoxFlat.new()
	passive_panel_style.bg_color = Color(0.07, 0.04, 0.13, 0.78)
	passive_panel_style.border_color = Color(0.72, 0.52, 1.0, 0.90)
	passive_panel_style.bg_color = Color(0.03, 0.10, 0.12, 0.78)
	passive_panel_style.border_color = Color(0.44, 0.86, 0.92, 0.90)
	passive_panel_style.content_margin_left = 14.0
	passive_panel_style.content_margin_right = 14.0
	passive_panel_style.content_margin_top = 12.0
	passive_panel_style.content_margin_bottom = 12.0
	passive_panel.add_theme_stylebox_override("panel", passive_panel_style)
	content_vbox.add_child(passive_panel)

	passive_section = VBoxContainer.new()
	passive_section.custom_minimum_size = Vector2(760.0, 0.0)
	passive_section.add_theme_constant_override("separation", 6)
	passive_panel.add_child(passive_section)

	var passive_header := Label.new()
	passive_header.text = "Passive"
	passive_header.add_theme_font_size_override("font_size", 18)
	passive_header.add_theme_color_override("font_color", Color(0.78, 0.60, 1.0, 0.98))
	passive_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_header.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0, 0.98))
	passive_header.add_theme_constant_override("shadow_offset_y", 2)
	passive_section.add_child(passive_header)

	passive_name_label = Label.new()
	passive_name_label.text = "—"
	passive_name_label.add_theme_font_size_override("font_size", 16)
	passive_name_label.add_theme_color_override("font_color", Color(0.82, 0.68, 1.0, 0.98))
	passive_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_name_label.add_theme_constant_override("shadow_offset_x", 2)
	passive_name_label.add_theme_constant_override("shadow_offset_y", 2)
	passive_section.add_child(passive_name_label)

	passive_desc_label = RichTextLabel.new()
	passive_desc_label.custom_minimum_size = Vector2(640.0, 70.0)
	passive_desc_label.bbcode_enabled = true
	passive_desc_label.fit_content = true
	passive_desc_label.scroll_active = false
	passive_desc_label.selection_enabled = false
	passive_desc_label.add_theme_font_size_override("normal_font_size", 13)
	passive_desc_label.add_theme_color_override("default_color", Color(0.88, 0.96, 1.0, 0.92))
	passive_desc_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	passive_desc_label.add_theme_constant_override("shadow_offset_x", 1)
	passive_desc_label.add_theme_constant_override("shadow_offset_y", 1)
	passive_desc_label.text = "No passive selected"
	passive_section.add_child(passive_desc_label)

	# Boss rewards section panel
	var boss_panel := PanelContainer.new()
	boss_panel.custom_minimum_size = Vector2(790.0, 0.0)
	var boss_panel_style := StyleBoxFlat.new()
	boss_panel_style.bg_color = Color(0.10, 0.04, 0.12, 0.76)
	boss_panel_style.border_color = Color(0.92, 0.72, 1.0, 0.9)
	boss_panel_style.set_border_width_all(2)
	boss_panel_style.set_corner_radius_all(12)
	boss_panel_style.content_margin_left = 14.0
	boss_panel_style.content_margin_right = 14.0
	boss_panel_style.content_margin_top = 12.0
	boss_panel_style.content_margin_bottom = 12.0
	boss_panel.add_theme_stylebox_override("panel", boss_panel_style)
	content_vbox.add_child(boss_panel)

	boss_section = VBoxContainer.new()
	boss_section.custom_minimum_size = Vector2(760.0, 0.0)
	boss_section.add_theme_constant_override("separation", 6)
	boss_panel.add_child(boss_section)

	var boss_header := Label.new()
	boss_header.text = "Boss"
	boss_header.add_theme_font_size_override("font_size", 18)
	boss_header.add_theme_color_override("font_color", Color(0.92, 0.72, 1.0, 0.98))
	boss_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	boss_header.add_theme_constant_override("shadow_offset_x", 2)
	boss_header.add_theme_constant_override("shadow_offset_y", 2)
	boss_section.add_child(boss_header)

	boss_list_container = VBoxContainer.new()
	boss_list_container.add_theme_constant_override("separation", 3)
	boss_section.add_child(boss_list_container)

	# Arcana section panel
	var arcana_panel := PanelContainer.new()
	arcana_panel.custom_minimum_size = Vector2(790.0, 0.0)
	var arcana_panel_style := StyleBoxFlat.new()
	arcana_panel_style.bg_color = Color(0.11, 0.09, 0.03, 0.72)
	arcana_panel_style.border_color = Color(1.0, 0.84, 0.50, 0.86)
	arcana_panel_style.set_border_width_all(2)
	arcana_panel_style.set_corner_radius_all(12)
	arcana_panel_style.content_margin_left = 14.0
	arcana_panel_style.content_margin_right = 14.0
	arcana_panel_style.content_margin_top = 12.0
	arcana_panel_style.content_margin_bottom = 12.0
	arcana_panel.add_theme_stylebox_override("panel", arcana_panel_style)
	content_vbox.add_child(arcana_panel)

	arcana_section = VBoxContainer.new()
	arcana_section.custom_minimum_size = Vector2(760.0, 0.0)
	arcana_section.add_theme_constant_override("separation", 6)
	arcana_panel.add_child(arcana_section)

	var arcana_header := Label.new()
	arcana_header.text = "Arcana"
	arcana_header.add_theme_font_size_override("font_size", 18)
	arcana_header.add_theme_color_override("font_color", Color(1.0, 0.84, 0.50, 0.98))
	arcana_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	arcana_header.add_theme_constant_override("shadow_offset_x", 2)
	arcana_header.add_theme_constant_override("shadow_offset_y", 2)
	arcana_section.add_child(arcana_header)

	arcana_list_container = VBoxContainer.new()
	arcana_list_container.add_theme_constant_override("separation", 3)
	arcana_section.add_child(arcana_list_container)

	# Boons section panel
	var boons_panel := PanelContainer.new()
	boons_panel.custom_minimum_size = Vector2(790.0, 0.0)
	var boons_panel_style := StyleBoxFlat.new()
	boons_panel_style.bg_color = Color(0.04, 0.09, 0.12, 0.74)
	boons_panel_style.border_color = Color(0.66, 0.90, 1.0, 0.88)
	boons_panel_style.set_border_width_all(2)
	boons_panel_style.set_corner_radius_all(12)
	boons_panel_style.content_margin_left = 14.0
	boons_panel_style.content_margin_right = 14.0
	boons_panel_style.content_margin_top = 12.0
	boons_panel_style.content_margin_bottom = 12.0
	boons_panel.add_theme_stylebox_override("panel", boons_panel_style)
	content_vbox.add_child(boons_panel)

	boons_section = VBoxContainer.new()
	boons_section.custom_minimum_size = Vector2(760.0, 0.0)
	boons_section.add_theme_constant_override("separation", 6)
	boons_panel.add_child(boons_section)

	var boons_header := Label.new()
	boons_header.text = "Boons"
	boons_header.add_theme_font_size_override("font_size", 18)
	boons_header.add_theme_color_override("font_color", Color(0.66, 0.90, 1.0, 0.98))
	boons_header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	boons_header.add_theme_constant_override("shadow_offset_x", 2)
	boons_header.add_theme_constant_override("shadow_offset_y", 2)
	boons_section.add_child(boons_header)

	boons_list_container = VBoxContainer.new()
	boons_list_container.add_theme_constant_override("separation", 3)
	boons_section.add_child(boons_list_container)

func open() -> void:
	if panel == null:
		return
	panel.visible = true
	is_visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	build_detail_opened.emit()

func close() -> void:
	if panel == null:
		return
	panel.visible = false
	is_visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	build_detail_closed.emit()

func is_open() -> bool:
	return is_visible

func refresh(character_id: String, active_boons: Array, active_arcana: Array, active_boss_rewards: Array = [], player: Node = null) -> void:
	if panel == null:
		return
	
	# Update passive
	_update_passive_section(character_id)
	
	# Update boons list
	_update_power_section(boons_list_container, active_boons, "boon", player)
	
	# Update arcana list
	_update_power_section(arcana_list_container, active_arcana, "arcana", player)

	# Update boss rewards list
	_update_power_section(boss_list_container, active_boss_rewards, "boss", player)

func _update_passive_section(character_id: String) -> void:
	var char_data := CHARACTER_REGISTRY.get_character(character_id)
	if char_data == null:
		passive_name_label.text = "Unknown Character"
		passive_desc_label.text = "No passive available"
		return
	
	var passive_id := _resolve_passive_id(character_id, char_data)
	passive_name_label.text = _format_passive_name(passive_id)
	
	# Get passive description based on ID
	var desc := ""
	match passive_id:
		"iron_retort":
			desc = "When you take damage, a counter window opens for 0.6s. Your next attack within the window deals 70% extra damage."
		"sigil_burst":
			desc = "Dashing arms a burst. Your next attack unleashes a 70% damage sigil explosion at the target."
		"death_tempo":
			desc = "Killing an enemy instantly resets your dash cooldown, allowing immediate repositioning."
		"farline_focus":
			desc = "Hits inside your farline band and tight aim lane deal 65% bonus damage. Keep distance and commit to precision angles."
		_:
			desc = "Passive ability"
	
	passive_desc_label.text = desc

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
			return "death_tempo"
		"riftlancer":
			return "farline_focus"
		_:
			return passive_id

func _update_power_section(container: VBoxContainer, power_ids: Array, power_type: String, player: Node = null) -> void:
	# Clear existing entries
	for child in container.get_children():
		child.queue_free()
	
	if power_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "—  None acquired"
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.62, 0.77, 0.9, 0.56))
		container.add_child(empty_label)
		return
	
	for power_id in power_ids:
		var name_text := _power_display_name(power_id)
		var desc_text := _get_power_current_desc(power_id, power_type, player)
		var stack_count := 0
		if is_instance_valid(player):
			if power_type == "boon" and player.has_method("get_upgrade_stack_count"):
				stack_count = int(player.get_upgrade_stack_count(String(power_id)))
			elif power_type == "arcana" and player.has_method("get_trial_power_stack_count"):
				stack_count = int(player.get_trial_power_stack_count(String(power_id)))
		if stack_count <= 0:
			stack_count = 1
		var stack_suffix := ""
		if stack_count > 1:
			stack_suffix = "  x%d" % stack_count
		
		# Add power entry
		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 2)
		container.add_child(entry_vbox)
		
		var power_name := Label.new()
		power_name.text = "  • %s%s" % [name_text, stack_suffix]
		power_name.add_theme_font_size_override("font_size", 13)
		power_name.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.98))
		power_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
		power_name.add_theme_constant_override("shadow_offset_x", 1)
		power_name.add_theme_constant_override("shadow_offset_y", 1)
		entry_vbox.add_child(power_name)
		
		if not desc_text.is_empty():
			var power_desc := RichTextLabel.new()
			power_desc.custom_minimum_size = Vector2(640.0, 0.0)
			power_desc.bbcode_enabled = true
			power_desc.fit_content = true
			power_desc.scroll_active = false
			power_desc.selection_enabled = false
			power_desc.add_theme_font_size_override("normal_font_size", 12)
			power_desc.add_theme_color_override("default_color", Color(0.85, 0.90, 0.96, 0.88))
			power_desc.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
			power_desc.add_theme_constant_override("shadow_offset_x", 1)
			power_desc.add_theme_constant_override("shadow_offset_y", 1)
			power_desc.text = "    %s" % desc_text
			entry_vbox.add_child(power_desc)

func _pi(node: Node, prop: String, fallback: int = 0) -> int:
	var v = node.get(prop)
	return v if v != null else fallback

func _pf(node: Node, prop: String, fallback: float = 0.0) -> float:
	var v = node.get(prop)
	return v if v != null else fallback

func _damage_kind_prefix(_power_id: String, _player: Node) -> String:
	return ""

func _get_power_current_desc(power_id: String, _power_type: String, player: Node) -> String:
	if not is_instance_valid(player) or not player.has_method("get_power_current_desc"):
		return ""
	return player.get_power_current_desc(power_id)

func _power_display_name(power_id: String) -> String:
	match power_id:
		# Map power IDs to display names
		"first_strike":
			return "First Strike"
		"heavy_blow":
			return "Heavy Blow"
		"wide_arc":
			return "Wide Arc"
		"long_reach":
			return "Long Reach"
		"fleet_foot":
			return "Fleet Foot"
		"blink_dash":
			return "Blink Dash"
		"iron_skin":
			return "Iron Skin"
		"battle_trance":
			return "Battle Trance"
		"surge_step":
			return "Surge Step"
		"heartstone":
			return "Heartstone"
		"crushed_vow":
			return "Crushed Vow"
		"severing_edge":
			return "Severing Edge"
		"razor_wind":
			return "Razor Wind"
		"execution_edge":
			return "Execution Edge"
		"rupture_wave":
			return "Rupture Wave"
		"aegis_field":
			return "Aegis Field"
		"hunters_snare":
			return "Hunter's Snare"
		"phantom_step":
			return "Phantom Step"
		"reaper_step":
			return "Reaper Step"
		"static_wake":
			return "Static Wake"
		"storm_crown":
			return "Storm Crown"
		"wraithstep":
			return "Wraithstep"
		"voidfire":
			return "Voidfire"
		"dread_resonance":
			return "Dread Resonance"
		"vow_shatter":
			return "Vow Shatter"
		"eclipse_mark":
			return "Eclipse Mark"
		"fracture_field":
			return "Fracture Field"
		"wardens_verdict":
			return "Warden's Verdict"
		"lacuna_echo":
			return "Lacuna Echo"
		"sovereign_tempo":
			return "Sovereign Tempo"
		"pillar_convergence":
			return "Pillar Convergence"
		"unbroken_oath":
			return "Unbroken Oath"
		_:
			return power_id.capitalize()

func _format_passive_name(passive_id: String) -> String:
	var normalized_id := passive_id.strip_edges().to_lower()
	match normalized_id:
		"iron_retort":
			return "Iron Retort"
		"sigil_burst":
			return "Sigil Burst"
		"death_tempo":
			return "Death's Tempo"
		"farline_focus":
			return "Farline Focus"
		_:
			var words := normalized_id.split("_", false)
			var formatted := ""
			for i in range(words.size()):
				if i > 0:
					formatted += " "
				formatted += String(words[i]).capitalize()
			return formatted.strip_edges()
