## Ascension & Oaths panel: lets the player pick a per-character ascension
## modifier loadout, equip catalysts, and review oath progress.
##
## The host controller (menu_controller.gd) builds an instance with the same
## panel style as other menu panels, calls _build_ui(host), and connects
## back_pressed to its root-panel show flow.
extends Panel

signal back_pressed

const ASCENSION_REGISTRY := preload("res://scripts/progression/ascension_modifier_registry.gd")
const OATHS_REGISTRY := preload("res://scripts/progression/oaths_registry.gd")
const CATALYST_REGISTRY := preload("res://scripts/progression/catalyst_registry.gd")
const META_PROGRESS_STORE := preload("res://scripts/meta_progress_store.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const MENU_STYLE_FACTORY := preload("res://scripts/core/menu_style_factory.gd")

const RUN_CONTEXT_PATH := "/root/RunContext"

var _host: Node = null
var _character_id: String = ""

var _title_label: Label
var _character_label: RichTextLabel
var _rank_label: Label
var _modifier_list: VBoxContainer
var _catalyst_list: VBoxContainer
var _oath_list: VBoxContainer

func _build_ui(host: Node) -> void:
	_host = host
	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 36)
	layout.add_theme_constant_override("margin_right", 36)
	layout.add_theme_constant_override("margin_top", 28)
	layout.add_theme_constant_override("margin_bottom", 22)
	add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
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

	_character_label = RichTextLabel.new()
	_character_label.bbcode_enabled = true
	_character_label.fit_content = true
	_character_label.scroll_active = false
	_character_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_character_label.custom_minimum_size = Vector2(360.0, 0.0)
	_character_label.add_theme_font_size_override("normal_font_size", 18)
	_character_label.add_theme_color_override("default_color", Color(0.78, 0.92, 1.0, 0.92))
	character_row.add_child(_character_label)

	var next_button := _make_character_arrow_button(">")
	next_button.pressed.connect(func() -> void:
		_step_character(1)
	)
	character_row.add_child(next_button)

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

	_modifier_list = _build_section_column(columns, "Ascension Modifiers")
	_catalyst_list = _build_section_column(columns, "Catalysts (max %d)" % CATALYST_REGISTRY.get_slot_limit())
	_oath_list = _build_section_column(columns, "Oaths")

	var back := _make_back_button()
	back.pressed.connect(func() -> void:
		emit_signal("back_pressed")
	)
	stack.add_child(back)

func populate() -> void:
	if _character_id.is_empty():
		_character_id = _resolve_active_character_id()
	_refresh_all()

func _refresh_all() -> void:
	_refresh_header()
	_refresh_modifier_list()
	_refresh_catalyst_list()
	_refresh_oath_list()

func _step_character(direction: int) -> void:
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
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("get_selected_character_id"):
		var id: String = String(run_context.get_selected_character_id()).strip_edges().to_lower()
		if not id.is_empty():
			return id
	return CHARACTER_REGISTRY.get_default_character_id()

func _get_profile() -> Dictionary:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		return run_context.meta_progress_profile
	return {}

func _save_profile() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("save_meta_progress"):
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
	var completed_oaths: Array[String] = META_PROGRESS_STORE.get_completed_oath_ids(profile)
	for id_variant in ASCENSION_REGISTRY.get_modifier_ids():
		var modifier_id: String = String(id_variant)
		var def: Dictionary = ASCENSION_REGISTRY.get_definition(modifier_id)
		if def.is_empty():
			continue
		var locked_by: String = String(def.get("locked_by_oath_id", ""))
		var unlocked: bool = locked_by.is_empty() or completed_oaths.has(locked_by)
		var equipped: bool = loadout.has(modifier_id)
		var row := _make_row()
		var label := _make_row_label("%s  (rank +%d)" % [String(def.get("label", modifier_id)), int(def.get("heat_cost", 1))])
		label.tooltip_text = String(def.get("description", ""))
		if not unlocked:
			label.modulate = Color(0.6, 0.6, 0.7, 0.6)
		row.add_child(label)
		var toggle := _make_toggle_button(equipped, unlocked)
		if not unlocked:
			toggle.text = "Locked"
			toggle.disabled = true
		else:
			toggle.text = "Equipped" if equipped else "Equip"
			toggle.pressed.connect(func() -> void:
				_toggle_modifier(modifier_id)
			)
		row.add_child(toggle)
		_modifier_list.add_child(row)

func _toggle_modifier(modifier_id: String) -> void:
	var profile: Dictionary = _get_profile()
	var loadout: Array[String] = META_PROGRESS_STORE.get_ascension_loadout(profile, _character_id)
	if loadout.has(modifier_id):
		loadout.erase(modifier_id)
	else:
		loadout.append(modifier_id)
	META_PROGRESS_STORE.set_ascension_loadout(profile, _character_id, loadout)
	_save_profile()
	_sync_active_loadout_with_selection()
	_refresh_header()
	_refresh_modifier_list()

func _sync_active_loadout_with_selection() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null or not run_context.has_method("set_active_ascension_loadout"):
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
		var row := _make_row()
		var label := _make_row_label(String(def.get("label", catalyst_id)))
		label.tooltip_text = String(def.get("description", ""))
		if not unlocked:
			label.modulate = Color(0.6, 0.6, 0.7, 0.6)
		row.add_child(label)
		var toggle := _make_toggle_button(equipped, unlocked)
		if not unlocked:
			toggle.text = "Locked"
			toggle.disabled = true
		elif equipped:
			toggle.text = "Equipped"
		elif equipped_ids.size() >= slot_limit:
			toggle.text = "Full"
			toggle.disabled = true
		else:
			toggle.text = "Equip"
		if not toggle.disabled:
			toggle.pressed.connect(func() -> void:
				_toggle_catalyst(catalyst_id)
			)
		row.add_child(toggle)
		_catalyst_list.add_child(row)

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
	var keys: Array = defs.keys()
	keys.sort()
	for oath_id_variant in keys:
		var oath_id: String = String(oath_id_variant)
		var def: Dictionary = defs[oath_id] as Dictionary
		var completed: bool = META_PROGRESS_STORE.is_oath_completed(profile, oath_id)
		var row := _make_row()
		var status_glyph: String = "[X]" if completed else "[ ]"
		var label := _make_row_label("%s  %s" % [status_glyph, String(def.get("label", oath_id))])
		label.tooltip_text = String(def.get("description", ""))
		if completed:
			label.add_theme_color_override("font_color", Color(0.74, 1.0, 0.78, 0.96))
		else:
			label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0, 0.84))
		row.add_child(label)
		_oath_list.add_child(row)

# --- builders ---

func _build_section_column(parent: HBoxContainer, header_text: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
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

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	scroll.add_child(inner)
	return inner

func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	return row

func _make_row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.96))
	return label

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
