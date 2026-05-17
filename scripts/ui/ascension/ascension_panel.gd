## Ascension & Oaths panel: lets the player pick a per-character ascension
## modifier loadout, equip catalysts, and review oath progress.
##
## The host controller (menu_controller.gd) builds an instance with the same
## panel style as other menu panels, calls _build_ui(host), and connects
## back_pressed to its root-panel show flow.
extends Panel

signal back_pressed
signal begin_descent_pressed
signal ascension_loadout_changed(loadout: Array)
signal lobby_done_pressed

const ASCENSION_REGISTRY := preload("res://scripts/progression/ascension_modifier_registry.gd")
const OATHS_REGISTRY := preload("res://scripts/progression/oaths_registry.gd")
const CATALYST_REGISTRY := preload("res://scripts/progression/catalyst_registry.gd")
const META_PROGRESS_STORE := preload("res://scripts/meta_progress_store.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const MENU_STYLE_FACTORY := preload("res://scripts/core/menu_style_factory.gd")
const RUN_CONTEXT_SCRIPT := preload("res://scripts/run_context.gd")
const SCRIPT_BUILD_MARKER := "ascension_panel_2026_05_11_guarded_style"

const RUN_CONTEXT_PATH := "/root/RunContext"

var _host: Node = null
var _character_id: String = ""

var _title_label: Label
var _character_label: RichTextLabel
var _rank_label: Label
var _modifier_list: VBoxContainer
var _catalyst_list: VBoxContainer
var _oath_list: VBoxContainer
var _modifier_lock_banner: PanelContainer
var _catalyst_wip_banner: PanelContainer
var _collapsed_clear_groups: Dictionary = {}
var _run_setup_mode_enabled: bool = false
var _oaths_only_mode_enabled: bool = false
var _lobby_mode_enabled: bool = false
var _lobby_is_host: bool = false
var _host_modifier_display_loadout: Array[String] = []
var _prev_char_button: Button
var _next_char_button: Button
var _modifier_column_root: Node
var _catalyst_column_root: Node
var _oath_column_root: Node
var _back_button: Button
var _begin_descent_button: Button

func _enter_tree() -> void:
	print("[AscensionPanel] Loaded script build:", SCRIPT_BUILD_MARKER)

func _build_ui(host: Node) -> void:
	_host = host
	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 44)
	layout.add_theme_constant_override("margin_right", 44)
	layout.add_theme_constant_override("margin_top", 32)
	layout.add_theme_constant_override("margin_bottom", 28)
	add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 18)
	layout.add_child(stack)

	_title_label = Label.new()
	_title_label.text = "Ascension & Oaths"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 38)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	stack.add_child(_title_label)

	var character_row := HBoxContainer.new()
	character_row.alignment = BoxContainer.ALIGNMENT_CENTER
	character_row.add_theme_constant_override("separation", 14)
	stack.add_child(character_row)

	var prev_button := _make_character_arrow_button("<")
	prev_button.pressed.connect(func() -> void:
		_step_character(-1)
	)
	character_row.add_child(prev_button)
	_prev_char_button = prev_button

	_character_label = RichTextLabel.new()
	_character_label.bbcode_enabled = true
	_character_label.fit_content = true
	_character_label.scroll_active = false
	_character_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_character_label.custom_minimum_size = Vector2(360.0, 0.0)
	_character_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_character_label.add_theme_font_size_override("normal_font_size", 18)
	_character_label.add_theme_color_override("default_color", Color(0.78, 0.92, 1.0, 0.92))
	character_row.add_child(_character_label)

	var next_button := _make_character_arrow_button(">")
	next_button.pressed.connect(func() -> void:
		_step_character(1)
	)
	character_row.add_child(next_button)
	_next_char_button = next_button

	_rank_label = Label.new()
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.add_theme_font_size_override("font_size", 22)
	_rank_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62, 1.0))
	stack.add_child(_rank_label)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	stack.add_child(columns)

	_modifier_list = _build_section_column(columns, "Ascension Modifiers", 1.0)
	_modifier_list.add_theme_constant_override("separation", 8)
	_modifier_lock_banner = _build_modifier_lock_banner()
	var modifier_column: Node = _modifier_list.get_parent().get_parent().get_parent()
	modifier_column.add_child(_modifier_lock_banner)
	modifier_column.move_child(_modifier_lock_banner, 1)
	_modifier_column_root = modifier_column
	_catalyst_list = _build_section_column(columns, "Catalysts (max %d)" % CATALYST_REGISTRY.get_slot_limit(), 1.0)
	_catalyst_list.add_theme_constant_override("separation", 8)
	_catalyst_wip_banner = _build_catalyst_wip_banner()
	var catalyst_column: Node = _catalyst_list.get_parent().get_parent().get_parent()
	catalyst_column.add_child(_catalyst_wip_banner)
	catalyst_column.move_child(_catalyst_wip_banner, 1)
	_catalyst_column_root = catalyst_column
	_oath_list = _build_section_column(columns, "Oaths", 1.7)
	_oath_list.add_theme_constant_override("separation", 8)
	_oath_column_root = _oath_list.get_parent().get_parent().get_parent()

	var footer := HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	stack.add_child(footer)

	var back := _make_back_button()
	back.pressed.connect(_on_back_or_descent_pressed)
	footer.add_child(back)
	_back_button = back

	_begin_descent_button = _make_begin_descent_button()
	_begin_descent_button.pressed.connect(func() -> void:
		emit_signal("begin_descent_pressed")
	)
	_begin_descent_button.visible = false
	footer.add_child(_begin_descent_button)

func _on_back_or_descent_pressed() -> void:
	if _lobby_mode_enabled:
		emit_signal("lobby_done_pressed")
		return
	emit_signal("back_pressed")

func populate() -> void:
	if _character_id.is_empty():
		_character_id = _resolve_active_character_id()
	_sync_active_loadout_with_selection()
	_refresh_all()

func set_character_id(char_id: String) -> void:
	var normalized: String = String(char_id).strip_edges().to_lower()
	if not normalized.is_empty():
		_character_id = normalized

func set_run_setup_mode(enabled: bool) -> void:
	_run_setup_mode_enabled = enabled
	_apply_mode_visibility()

func set_oaths_only_mode(enabled: bool) -> void:
	_oaths_only_mode_enabled = enabled
	_apply_mode_visibility()

func set_lobby_mode(is_host: bool) -> void:
	_lobby_mode_enabled = true
	_lobby_is_host = is_host
	_apply_mode_visibility()

func set_host_modifier_display_loadout(loadout: Array) -> void:
	_host_modifier_display_loadout.clear()
	for entry_variant in loadout:
		var entry := String(entry_variant).strip_edges()
		if not entry.is_empty():
			_host_modifier_display_loadout.append(entry)

func _apply_mode_visibility() -> void:
	var lock_character: bool = _run_setup_mode_enabled or _oaths_only_mode_enabled or _lobby_mode_enabled
	if _prev_char_button != null:
		_prev_char_button.visible = not lock_character
	if _next_char_button != null:
		_next_char_button.visible = not lock_character
	if _back_button != null:
		_back_button.text = "Done" if _lobby_mode_enabled else "Back"
	if _begin_descent_button != null:
		_begin_descent_button.visible = _run_setup_mode_enabled and not _lobby_mode_enabled
	if _oath_column_root != null:
		(_oath_column_root as Control).visible = not _lobby_mode_enabled
	if _oaths_only_mode_enabled:
		if _title_label != null:
			_title_label.text = "Oaths"
		if _rank_label != null:
			_rank_label.visible = false
		if _character_label != null:
			_character_label.visible = false
		if _modifier_column_root != null:
			(_modifier_column_root as Control).visible = false
		if _catalyst_column_root != null:
			(_catalyst_column_root as Control).visible = false
	else:
		if _title_label != null:
			_title_label.text = "Ascension & Catalysts" if _lobby_mode_enabled else "Ascension & Oaths"
		if _rank_label != null:
			_rank_label.visible = true
		if _character_label != null:
			_character_label.visible = true
		if _modifier_column_root != null:
			(_modifier_column_root as Control).visible = true
		if _catalyst_column_root != null:
			(_catalyst_column_root as Control).visible = true

func _refresh_all() -> void:
	_refresh_header()
	_refresh_modifier_list()
	_refresh_catalyst_list()
	_refresh_oath_list()

func _step_character(direction: int) -> void:
	if _run_setup_mode_enabled:
		return
	var ids: Array[String] = CHARACTER_REGISTRY.get_launch_character_ids()
	if ids.is_empty():
		return
	var current_index: int = ids.find(_character_id)
	if current_index < 0:
		current_index = 0
	var next_index: int = (current_index + direction + ids.size()) % ids.size()
	_character_id = String(ids[next_index])
	_refresh_all()

# --- header / data ---

func _resolve_active_character_id() -> String:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH) as RUN_CONTEXT_SCRIPT
	if run_context != null:
		var id: String = String(run_context.get_selected_character_id()).strip_edges().to_lower()
		if not id.is_empty():
			return id
	return CHARACTER_REGISTRY.get_default_character_id()

func _is_ascension_unlocked() -> bool:
	var profile: Dictionary = _get_profile()
	if profile.is_empty() or _character_id.is_empty():
		return false
	return META_PROGRESS_STORE.has_cleared_forsworn(profile, _character_id)

func _get_profile() -> Dictionary:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		return run_context.meta_progress_profile
	return {}

func _save_profile() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH) as RUN_CONTEXT_SCRIPT
	if run_context != null:
		run_context.save_meta_progress()

func _refresh_header() -> void:
	var char_data: Dictionary = CHARACTER_REGISTRY.get_character(_character_id)
	var char_name: String = String(char_data.get("name", _character_id.capitalize()))
	var visual: Dictionary = char_data.get("visual", {}) as Dictionary
	var body_color: Color = visual.get("body_color", Color(0.78, 0.92, 1.0, 0.92)) as Color
	var tinted: Color = _readable_label_color(body_color)
	_character_label.text = "[center]Character: [color=#%s]%s[/color][/center]" % [tinted.to_html(false), char_name]
	var loadout: Array[String] = META_PROGRESS_STORE.get_ascension_loadout(_get_profile(), _character_id)
	var rank: int = ASCENSION_REGISTRY.compute_loadout_rank(loadout)
	var highest: int = META_PROGRESS_STORE.get_ascension_highest_rank(_get_profile(), _character_id)
	_rank_label.text = "Ascension Rank: %d  (highest cleared: %d)" % [rank, highest]

# --- modifier list ---

func _refresh_modifier_list() -> void:
	_clear_children(_modifier_list)
	var profile: Dictionary = _get_profile()
	var loadout: Array[String] = META_PROGRESS_STORE.get_ascension_loadout(profile, _character_id)
	if _lobby_mode_enabled and not _lobby_is_host:
		loadout = _host_modifier_display_loadout.duplicate()
	var completed_oaths: Array[String] = META_PROGRESS_STORE.get_completed_oath_ids(profile)
	var ascension_unlocked: bool = _is_ascension_unlocked() or _lobby_mode_enabled
	if _modifier_lock_banner != null:
		_modifier_lock_banner.visible = not ascension_unlocked and not _lobby_mode_enabled
	for id_variant in ASCENSION_REGISTRY.get_modifier_ids():
		var modifier_id: String = String(id_variant)
		var def: Dictionary = ASCENSION_REGISTRY.get_definition(modifier_id)
		if def.is_empty():
			continue
		var locked_by: String = String(def.get("locked_by_oath_id", ""))
		var oath_unlocked: bool = locked_by.is_empty() or completed_oaths.has(locked_by)
		var unlocked: bool = ascension_unlocked and oath_unlocked
		var equipped: bool = loadout.has(modifier_id)
		if _lobby_mode_enabled and not _lobby_is_host and equipped:
			unlocked = true
		_modifier_list.add_child(_make_modifier_card(modifier_id, def, unlocked, equipped))

func _make_modifier_card(modifier_id: String, def: Dictionary, unlocked: bool, equipped: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_state: int = 2 if equipped else (1 if unlocked else 0)
	var panel_style: StyleBoxFlat = _make_catalyst_card_style(card_state)
	if panel_style == null:
		panel_style = StyleBoxFlat.new()
	card.add_theme_stylebox_override("panel", panel_style)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	inner.add_child(header)

	var title_color: Color = Color(0.6, 0.6, 0.7, 0.6) if not unlocked else (Color(1.0, 0.86, 0.52, 0.98) if equipped else Color(0.86, 0.96, 1.0, 0.94))
	var title_label := Label.new()
	title_label.text = String(def.get("label", modifier_id))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", title_color)
	header.add_child(title_label)

	var rank_tag := _make_rank_tag_pill(int(def.get("heat_cost", 1)), unlocked, equipped)
	header.add_child(rank_tag)

	var description: String = String(def.get("description", "")).strip_edges()
	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 13)
		var desc_color: Color = Color(0.62, 0.66, 0.74, 0.6) if not unlocked else Color(0.72, 0.84, 0.96, 0.82)
		desc_label.add_theme_color_override("font_color", desc_color)
		inner.add_child(desc_label)

	var footer := HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 0)
	inner.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var toggle := _make_toggle_button(equipped, unlocked)
	if not unlocked:
		toggle.text = "Locked"
		toggle.disabled = true
	elif _lobby_mode_enabled and not _lobby_is_host:
		toggle.text = "Host"
		toggle.disabled = true
	else:
		toggle.text = "Equipped" if equipped else "Equip"
		toggle.pressed.connect(func() -> void:
			_toggle_modifier(modifier_id)
		)
	footer.add_child(toggle)

	return card

func _toggle_modifier(modifier_id: String) -> void:
	if _lobby_mode_enabled and not _lobby_is_host:
		return
	if not _is_ascension_unlocked() and not _lobby_mode_enabled:
		return
	var profile: Dictionary = _get_profile()
	var loadout: Array[String] = META_PROGRESS_STORE.get_ascension_loadout(profile, _character_id)
	if loadout.has(modifier_id):
		loadout.erase(modifier_id)
	else:
		loadout.append(modifier_id)
	META_PROGRESS_STORE.set_ascension_loadout(profile, _character_id, loadout)
	_save_profile()
	_sync_active_loadout_with_selection()
	if _lobby_mode_enabled and _lobby_is_host:
		emit_signal("ascension_loadout_changed", loadout.duplicate())
	_refresh_header()
	_refresh_modifier_list()

func _sync_active_loadout_with_selection() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH) as RUN_CONTEXT_SCRIPT
	if run_context == null:
		return
	var saved: Array[String] = META_PROGRESS_STORE.get_ascension_loadout(_get_profile(), _character_id)
	run_context.set_active_ascension_loadout(saved)

# --- catalyst list ---

func _refresh_catalyst_list() -> void:
	_clear_children(_catalyst_list)
	var profile: Dictionary = _get_profile()
	var unlocked_ids: Array[String] = META_PROGRESS_STORE.get_unlocked_catalyst_ids(profile)
	var equipped_ids: Array[String] = META_PROGRESS_STORE.get_equipped_catalyst_ids(profile, _character_id)
	var slot_limit: int = CATALYST_REGISTRY.get_slot_limit()
	for id_variant in CATALYST_REGISTRY.get_catalyst_ids():
		var catalyst_id: String = String(id_variant)
		var def: Dictionary = CATALYST_REGISTRY.get_definition(catalyst_id)
		if def.is_empty():
			continue
		var unlocked: bool = unlocked_ids.has(catalyst_id)
		var equipped: bool = equipped_ids.has(catalyst_id)
		_catalyst_list.add_child(_make_catalyst_card(catalyst_id, def, unlocked, equipped, equipped_ids.size(), slot_limit))

func _make_catalyst_card(catalyst_id: String, def: Dictionary, unlocked: bool, equipped: bool, equipped_count: int, slot_limit: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_state: int = 2 if equipped else (1 if unlocked else 0)
	var panel_style: StyleBoxFlat = _make_catalyst_card_style(card_state)
	if panel_style == null:
		panel_style = StyleBoxFlat.new()
	card.add_theme_stylebox_override("panel", panel_style)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	inner.add_child(header)

	var title_color: Color = Color(0.6, 0.6, 0.7, 0.6) if not unlocked else (Color(1.0, 0.86, 0.52, 0.98) if equipped else Color(0.86, 0.96, 1.0, 0.94))
	var title_label := Label.new()
	title_label.text = String(def.get("label", catalyst_id))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", title_color)
	header.add_child(title_label)

	var description: String = String(def.get("description", "")).strip_edges()
	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 13)
		var desc_color: Color = Color(0.62, 0.66, 0.74, 0.6) if not unlocked else Color(0.72, 0.84, 0.96, 0.82)
		desc_label.add_theme_color_override("font_color", desc_color)
		inner.add_child(desc_label)

	var footer := HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 0)
	inner.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var toggle := _make_toggle_button(equipped, unlocked)
	if not unlocked:
		toggle.text = "Locked"
		toggle.disabled = true
	elif equipped:
		toggle.text = "Equipped"
	elif equipped_count >= slot_limit:
		toggle.text = "Full"
		toggle.disabled = true
	else:
		toggle.text = "Equip"
	if not toggle.disabled:
		toggle.pressed.connect(func() -> void:
			_toggle_catalyst(catalyst_id)
		)
	footer.add_child(toggle)

	return card

func _make_catalyst_card_style(state: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if state == 2:
		style.bg_color = Color(0.20, 0.16, 0.08, 0.55)
		style.border_color = Color(1.0, 0.78, 0.40, 0.66)
	elif state == 1:
		style.bg_color = Color(0.08, 0.14, 0.22, 0.50)
		style.border_color = Color(0.40, 0.58, 0.82, 0.40)
	else:
		style.bg_color = Color(0.08, 0.10, 0.14, 0.40)
		style.border_color = Color(0.32, 0.36, 0.44, 0.32)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style

func _toggle_catalyst(catalyst_id: String) -> void:
	var profile: Dictionary = _get_profile()
	var equipped: Array[String] = META_PROGRESS_STORE.get_equipped_catalyst_ids(profile, _character_id)
	if equipped.has(catalyst_id):
		equipped.erase(catalyst_id)
	else:
		if equipped.size() >= CATALYST_REGISTRY.get_slot_limit():
			return
		equipped.append(catalyst_id)
	META_PROGRESS_STORE.set_equipped_catalyst_ids(profile, _character_id, equipped)
	_save_profile()
	_refresh_catalyst_list()

# --- oath list ---

func _refresh_oath_list() -> void:
	_clear_children(_oath_list)
	var profile: Dictionary = _get_profile()
	var defs: Dictionary = OATHS_REGISTRY.get_all_definitions()

	var boss_ids: Array[String] = []
	var build_ids: Array[String] = []
	var ascension_ids: Array[String] = []
	var clear_by_character: Dictionary = {}

	var keys: Array = defs.keys()
	keys.sort()
	for oath_id_variant in keys:
		var oath_id: String = String(oath_id_variant)
		if oath_id.ends_with("_no_hit"):
			boss_ids.append(oath_id)
		elif oath_id.begins_with("ascension_rank_"):
			ascension_ids.append(oath_id)
		elif oath_id.begins_with("clear_"):
			var trimmed: String = oath_id.substr("clear_".length())
			var underscore_index: int = trimmed.rfind("_")
			var character_id: String = trimmed.substr(0, underscore_index) if underscore_index > 0 else trimmed
			if not clear_by_character.has(character_id):
				clear_by_character[character_id] = []
			(clear_by_character[character_id] as Array).append(oath_id)
		else:
			build_ids.append(oath_id)

	_append_oath_group(profile, defs, "Boss Mastery", _sort_boss_oaths(boss_ids))
	_append_oath_group(profile, defs, "Build Discipline", build_ids)
	_append_oath_group(profile, defs, "Ascension Milestones", _sort_ascension_oaths(ascension_ids))
	_append_clear_groups(profile, defs, clear_by_character)

const _BOSS_ORDER: Array[String] = ["warden", "sovereign", "lacuna"]
const _BEARING_ORDER: Array[String] = ["pilgrim", "delver", "harbinger", "forsworn"]

func _sort_boss_oaths(oath_ids: Array[String]) -> Array[String]:
	var ordered: Array[String] = []
	for boss_id in _BOSS_ORDER:
		var candidate: String = "%s_no_hit" % boss_id
		if oath_ids.has(candidate):
			ordered.append(candidate)
	for oath_id in oath_ids:
		if not ordered.has(oath_id):
			ordered.append(oath_id)
	return ordered

func _sort_ascension_oaths(oath_ids: Array[String]) -> Array[String]:
	var with_rank: Array = []
	for oath_id in oath_ids:
		var suffix: String = oath_id.substr("ascension_rank_".length())
		var rank: int = suffix.to_int()
		with_rank.append({"id": oath_id, "rank": rank})
	with_rank.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	var ordered: Array[String] = []
	for entry in with_rank:
		ordered.append(String((entry as Dictionary)["id"]))
	return ordered

func _sort_clear_oaths(oath_ids: Array) -> Array[String]:
	var ordered: Array[String] = []
	for bearing in _BEARING_ORDER:
		var suffix: String = "_%s" % bearing
		for oath_id_variant in oath_ids:
			var oath_id: String = String(oath_id_variant)
			if oath_id.ends_with(suffix) and not ordered.has(oath_id):
				ordered.append(oath_id)
	for oath_id_variant in oath_ids:
		var oath_id_str: String = String(oath_id_variant)
		if not ordered.has(oath_id_str):
			ordered.append(oath_id_str)
	return ordered

func _append_oath_group(profile: Dictionary, defs: Dictionary, title: String, oath_ids: Array) -> void:
	if oath_ids.is_empty():
		return
	_oath_list.add_child(_make_oath_group_header(title))
	for oath_id_variant in oath_ids:
		var oath_id: String = String(oath_id_variant)
		var def: Dictionary = defs[oath_id] as Dictionary
		var completed: bool = META_PROGRESS_STORE.is_oath_completed(profile, oath_id)
		_oath_list.add_child(_make_oath_card(def, completed))

func _append_clear_groups(profile: Dictionary, defs: Dictionary, clear_by_character: Dictionary) -> void:
	if clear_by_character.is_empty():
		return
	_oath_list.add_child(_make_oath_group_header("Bearing Clears"))
	var character_keys: Array = clear_by_character.keys()
	character_keys.sort()
	for character_id_variant in character_keys:
		var character_id: String = String(character_id_variant)
		var oath_ids: Array[String] = _sort_clear_oaths(clear_by_character[character_id] as Array)
		var completed_count: int = 0
		for oath_id_variant in oath_ids:
			if META_PROGRESS_STORE.is_oath_completed(profile, String(oath_id_variant)):
				completed_count += 1
		var character_def: Dictionary = CHARACTER_REGISTRY.get_character(character_id)
		var character_name: String = String(character_def.get("name", character_id.capitalize()))
		var collapsed: bool = bool(_collapsed_clear_groups.get(character_id, true))
		var header_text: String = "%s  (%d / %d)" % [character_name, completed_count, oath_ids.size()]
		var header_button := _make_collapse_header_button(header_text, collapsed)
		header_button.pressed.connect(func() -> void:
			_collapsed_clear_groups[character_id] = not collapsed
			_refresh_oath_list()
		)
		_oath_list.add_child(header_button)
		if collapsed:
			continue
		for oath_id_variant in oath_ids:
			var oath_id: String = String(oath_id_variant)
			var def: Dictionary = defs[oath_id] as Dictionary
			var completed: bool = META_PROGRESS_STORE.is_oath_completed(profile, oath_id)
			_oath_list.add_child(_make_oath_card(def, completed))

func _make_oath_group_header(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52, 0.96))
	if _oath_list.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 14.0)
		_oath_list.add_child(spacer)
	return label

func _make_collapse_header_button(text: String, collapsed: bool) -> Button:
	var button := Button.new()
	var arrow: String = "▶" if collapsed else "▼"
	button.text = "%s  %s" % [arrow, text]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0, 0.92))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	return button

func _make_oath_card(def: Dictionary, completed: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_oath_card_style(completed))

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)

	var glyph: String = "◆" if completed else "◇"
	var title_color: Color = Color(0.74, 1.0, 0.78, 0.98) if completed else Color(0.86, 0.96, 1.0, 0.94)
	var title_label := Label.new()
	title_label.text = "%s  %s" % [glyph, String(def.get("label", ""))]
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", title_color)
	inner.add_child(title_label)

	var description: String = String(def.get("description", "")).strip_edges()
	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 13)
		desc_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96, 0.82))
		inner.add_child(desc_label)

	var reward_text: String = _format_oath_reward(def)
	if not reward_text.is_empty():
		var reward_label := Label.new()
		reward_label.text = reward_text
		reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_label.add_theme_font_size_override("font_size", 13)
		reward_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.46, 0.94))
		inner.add_child(reward_label)

	return card

func _make_oath_card_style(completed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if completed:
		style.bg_color = Color(0.10, 0.22, 0.14, 0.55)
		style.border_color = Color(0.46, 0.84, 0.54, 0.62)
	else:
		style.bg_color = Color(0.08, 0.14, 0.22, 0.50)
		style.border_color = Color(0.40, 0.58, 0.82, 0.40)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style

func _format_oath_reward(def: Dictionary) -> String:
	var parts: Array[String] = []
	var catalyst_id: String = String(def.get("reward_catalyst_id", "")).strip_edges()
	if not catalyst_id.is_empty():
		var catalyst_def: Dictionary = CATALYST_REGISTRY.get_definition(catalyst_id)
		var catalyst_label: String = String(catalyst_def.get("label", catalyst_id))
		parts.append("Catalyst: %s" % catalyst_label)
	var modifier_id: String = String(def.get("reward_modifier_id", "")).strip_edges()
	if not modifier_id.is_empty():
		var modifier_def: Dictionary = ASCENSION_REGISTRY.get_definition(modifier_id)
		var modifier_label: String = String(modifier_def.get("label", modifier_id))
		parts.append("Unlocks: %s" % modifier_label)
	if parts.is_empty():
		return ""
	return "★ " + " · ".join(parts)

# --- builders ---

func _build_modifier_lock_banner() -> PanelContainer:
	return _build_notice_banner(
		"🔒",
		"Locked. Clear a Forsworn run with this character to unlock Ascension modifiers.",
		Color(0.28, 0.12, 0.06, 0.78),
		Color(1.0, 0.62, 0.32, 0.86),
		Color(1.0, 0.78, 0.50, 1.0),
		Color(1.0, 0.86, 0.70, 0.96)
	)

func _build_catalyst_wip_banner() -> PanelContainer:
	return _build_notice_banner(
		"⚙",
		"Work in progress. Only Iron Vigil applies in-run today; other catalysts are placeholders.",
		Color(0.10, 0.14, 0.22, 0.78),
		Color(0.52, 0.74, 1.0, 0.78),
		Color(0.74, 0.92, 1.0, 1.0),
		Color(0.84, 0.92, 1.0, 0.94)
	)

func _build_notice_banner(icon_text: String, message_text: String, bg: Color, border: Color, icon_color: Color, text_color: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	banner.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	banner.add_child(row)

	var icon := Label.new()
	icon.text = icon_text
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", icon_color)
	row.add_child(icon)

	var message := Label.new()
	message.text = message_text
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", text_color)
	row.add_child(message)
	return banner

func _build_section_column(parent: HBoxContainer, header_text: String, stretch_ratio: float = 1.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = stretch_ratio
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0, 1.0))
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var inner_margin := MarginContainer.new()
	inner_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_margin.add_theme_constant_override("margin_right", 14)
	inner_margin.add_theme_constant_override("margin_left", 2)
	inner_margin.add_theme_constant_override("margin_top", 2)
	inner_margin.add_theme_constant_override("margin_bottom", 2)
	scroll.add_child(inner_margin)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	inner_margin.add_child(inner)
	return inner

func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	return row

func _make_row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.96))
	return label

func _make_rank_tag_label(rank: int) -> Label:
	var label := Label.new()
	label.text = "+%d" % rank
	label.custom_minimum_size = Vector2(44.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62, 0.96))
	return label

func _make_rank_tag_pill(rank: int, unlocked: bool, equipped: bool) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	if not unlocked:
		style.bg_color = Color(0.10, 0.10, 0.14, 0.70)
		style.border_color = Color(0.32, 0.32, 0.40, 0.60)
	elif equipped:
		style.bg_color = Color(0.32, 0.22, 0.08, 0.80)
		style.border_color = Color(1.0, 0.78, 0.40, 0.85)
	else:
		style.bg_color = Color(0.10, 0.16, 0.24, 0.80)
		style.border_color = Color(0.52, 0.74, 0.96, 0.70)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	pill.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = "+%d Heat" % rank
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	var text_color: Color = Color(0.96, 0.86, 0.62, 0.98)
	if not unlocked:
		text_color = Color(0.6, 0.6, 0.7, 0.7)
	pill.add_child(label)
	label.add_theme_color_override("font_color", text_color)
	return pill

func _make_toggle_button(equipped: bool, unlocked: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(96.0, 30.0)
	button.add_theme_font_size_override("font_size", 13)
	var bg: Color = Color(0.18, 0.32, 0.52, 0.95) if equipped else Color(0.10, 0.15, 0.22, 0.95)
	var border: Color = Color(0.86, 0.96, 1.0, 0.92) if equipped else Color(0.34, 0.56, 0.84, 0.72)
	if not unlocked:
		bg = Color(0.06, 0.08, 0.12, 0.85)
		border = Color(0.22, 0.26, 0.32, 0.54)
	button.add_theme_stylebox_override("normal", MENU_STYLE_FACTORY.make_button_style(bg, border, 10, 1))
	button.add_theme_stylebox_override("hover", MENU_STYLE_FACTORY.make_button_style(bg.lightened(0.10), border, 10, 1))
	button.add_theme_stylebox_override("pressed", MENU_STYLE_FACTORY.make_button_style(bg.darkened(0.10), border, 10, 1))
	button.add_theme_stylebox_override("disabled", MENU_STYLE_FACTORY.make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 10, 1))
	return button

func _make_character_arrow_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(48.0, 36.0)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	var bg := Color(0.10, 0.15, 0.22, 0.95)
	var border := Color(0.34, 0.56, 0.84, 0.72)
	button.add_theme_stylebox_override("normal", MENU_STYLE_FACTORY.make_button_style(bg, border, 10, 1))
	button.add_theme_stylebox_override("hover", MENU_STYLE_FACTORY.make_button_style(bg.lightened(0.10), border, 10, 1))
	button.add_theme_stylebox_override("pressed", MENU_STYLE_FACTORY.make_button_style(bg.darkened(0.10), border, 10, 1))
	return button

func _make_back_button() -> Button:
	var button := Button.new()
	button.text = "Back"
	button.custom_minimum_size = Vector2(180.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_stylebox_override("normal", MENU_STYLE_FACTORY.make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 14, 2))
	button.add_theme_stylebox_override("hover", MENU_STYLE_FACTORY.make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 14, 2))
	button.add_theme_stylebox_override("pressed", MENU_STYLE_FACTORY.make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 14, 2))
	return button

func _make_begin_descent_button() -> Button:
	var button := Button.new()
	button.text = "Begin Descent"
	button.custom_minimum_size = Vector2(240.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78, 1.0))
	button.add_theme_stylebox_override("normal", MENU_STYLE_FACTORY.make_button_style(Color(0.28, 0.18, 0.08, 0.95), Color(1.0, 0.78, 0.42, 0.85), 14, 2))
	button.add_theme_stylebox_override("hover", MENU_STYLE_FACTORY.make_button_style(Color(0.36, 0.22, 0.10, 0.98), Color(1.0, 0.90, 0.58, 0.95), 14, 2))
	button.add_theme_stylebox_override("pressed", MENU_STYLE_FACTORY.make_button_style(Color(0.22, 0.14, 0.06, 0.98), Color(1.0, 0.84, 0.50, 1.0), 14, 2))
	return button

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _readable_label_color(source: Color) -> Color:
	# Lift dim character body colors so they remain legible on the dark panel background
	# without losing the character's identity hue.
	var brightness: float = maxf(maxf(source.r, source.g), source.b)
	var lift: float = 0.0
	if brightness < 0.7:
		lift = clampf(0.7 - brightness, 0.0, 0.5)
	var result: Color = source.lightened(lift)
	result.a = 1.0
	return result
