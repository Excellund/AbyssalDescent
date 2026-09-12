extends VBoxContainer
## A detached draft editor. Only Practice may validate and apply a build.

const STYLES := preload("res://scripts/core/menu_style_factory.gd")
const WORDING := preload("res://scripts/shared/combat_keyword_catalogue.gd")

signal config_changed(config: Dictionary)

var tabs: TabContainer
var encounter_page: ScrollContainer
var build_page: VBoxContainer
var options_page: ScrollContainer
var character_selector: OptionButton
var floor_input: SpinBox
var bearing_selector: OptionButton
var biome_selector: OptionButton
var encounter_selector: OptionButton
var encounter_description: Label
var build_rows: Dictionary = {}
var search_input: LineEdit
var category_selector: OptionButton
var clear_build_button: Button
var build_summary: Label
var floor_note: Label
var no_results: Label
var ai_toggle: CheckBox
var invulnerable_toggle: CheckBox
var _draft: Dictionary = {}
var _catalogue: Dictionary = {}
var _editable := true
var _syncing := false
var _encounter_stack: VBoxContainer
var _build_stack: VBoxContainer
var _option_stack: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	tabs.add_theme_color_override("font_selected_color", Color("eef5ff"))
	tabs.add_theme_color_override("font_unselected_color", Color("bacbdc"))
	add_child(tabs)
	encounter_page = _scroll("Encounter")
	_encounter_stack = _scroll_stack(encounter_page)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	_encounter_stack.add_child(grid)
	character_selector = _selector()
	_field(grid, "Vessel", character_selector)
	character_selector.item_selected.connect(func(index: int) -> void: _set_scalar("character_id", character_selector.get_item_metadata(index)))
	encounter_selector = _selector()
	_field(grid, "Encounter", encounter_selector)
	encounter_selector.item_selected.connect(func(index: int) -> void: _set_scalar("encounter_id", encounter_selector.get_item_metadata(index)))
	encounter_description = _copy("")
	encounter_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field(grid, "Goal", encounter_description)
	floor_input = _number(1, 100)
	_field(grid, "Floor", floor_input)
	floor_input.value_changed.connect(func(value: float) -> void: _set_scalar("floor", int(value)))
	bearing_selector = _selector()
	_field(grid, "Bearing", bearing_selector)
	bearing_selector.item_selected.connect(func(index: int) -> void: _set_scalar("bearing", bearing_selector.get_item_metadata(index)))
	biome_selector = _selector()
	_field(grid, "Biome", biome_selector)
	biome_selector.item_selected.connect(func(index: int) -> void: _set_scalar("biome_id", biome_selector.get_item_metadata(index)))
	floor_note = _copy("")
	_encounter_stack.add_child(floor_note)
	build_page = VBoxContainer.new()
	build_page.name = "Build"
	build_page.add_theme_constant_override("separation", 8)
	tabs.add_child(build_page)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	build_page.add_child(filters)
	search_input = LineEdit.new()
	search_input.placeholder_text = "Search powers and effects"
	search_input.clear_button_enabled = true
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size.y = 38
	search_input.add_theme_font_size_override("font_size", 18)
	filters.add_child(search_input)
	search_input.text_changed.connect(func(_value: String) -> void: _filter_build())
	category_selector = _selector()
	category_selector.size_flags_horizontal = Control.SIZE_SHRINK_END
	for category: Array in [["All powers", "all"], ["Boons", "boon"], ["Arcana", "arcana"], ["Boss powers", "boss_reward"], ["Catalysts", "catalysts"], ["Ascension", "ascension"]]:
		category_selector.add_item(category[0])
		category_selector.set_item_metadata(category_selector.item_count - 1, category[1])
	category_selector.select(1)
	filters.add_child(category_selector)
	category_selector.item_selected.connect(func(_index: int) -> void: _filter_build())
	var build_header := HBoxContainer.new()
	build_page.add_child(build_header)
	build_summary = _copy("")
	build_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_header.add_child(build_summary)
	clear_build_button = Button.new()
	clear_build_button.text = "Clear build"
	clear_build_button.custom_minimum_size.y = 36
	clear_build_button.add_theme_font_size_override("font_size", 18)
	clear_build_button.pressed.connect(_clear_build)
	build_header.add_child(clear_build_button)
	var build_scroll := ScrollContainer.new()
	build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_scroll.follow_focus = true
	build_page.add_child(build_scroll)
	_build_stack = _scroll_stack(build_scroll)
	no_results = _copy("No matching powers.")
	_build_stack.add_child(no_results)
	options_page = _scroll("Options")
	_option_stack = _scroll_stack(options_page)
	ai_toggle = _toggle("Enemy AI")
	_option_stack.add_child(ai_toggle)
	_option_stack.add_child(_copy("Enemies move and use their ordinary attacks. Turn this off to test your build against stationary targets."))
	ai_toggle.toggled.connect(func(value: bool) -> void: _set_scalar("enemy_ai", value))
	invulnerable_toggle = _toggle("Take no damage")
	_option_stack.add_child(invulnerable_toggle)
	_option_stack.add_child(_copy("Keep fighting without losing HP. Turn this off to practise avoiding damage."))
	invulnerable_toggle.toggled.connect(func(value: bool) -> void: _set_scalar("invulnerable", value))
	_option_stack.add_child(_copy("Changes take effect when you start or apply a new attempt. Resume keeps the current encounter and build."))
	get_viewport().size_changed.connect(_fit_popups)
	_fit_popups()
	_present_controls()

func _scroll(title: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	return scroll

func _scroll_stack(scroll: ScrollContainer) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	scroll.add_child(stack)
	return stack

func _label(value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eef5ff"))
	return label

func _copy(value: String) -> Label:
	var label := _label(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("bacbdc"))
	return label

func _selector() -> OptionButton:
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(180, 38)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_theme_font_size_override("font_size", 18)
	selector.add_theme_color_override("font_color", Color("eef5ff"))
	for state in ["normal", "hover", "pressed", "focus"]:
		selector.add_theme_stylebox_override(state, STYLES.make_button_style(Color("192b3e"), Color("badfff") if state == "focus" else Color("557b9e"), 8, 2))
	var popup_theme := Theme.new()
	popup_theme.default_font = get_theme_font("font")
	popup_theme.default_font_size = 18
	popup_theme.set_font("font", "PopupMenu", get_theme_font("font"))
	popup_theme.set_font_size("font_size", "PopupMenu", 18)
	popup_theme.set_color("font_color", "PopupMenu", Color("eef5ff"))
	popup_theme.set_stylebox("panel", "PopupMenu", STYLES.make_panel_style(Color("111b29"), Color("557b9e"), 8, 2))
	popup_theme.set_stylebox("hover", "PopupMenu", STYLES.make_panel_style(Color("284764"), Color("badfff"), 4, 1))
	selector.get_popup().theme = popup_theme
	return selector

func _fit_popups() -> void:
	for selector: OptionButton in [character_selector, encounter_selector, bearing_selector, biome_selector, category_selector]:
		_fit_popup(selector.get_popup())

func _fit_popup(popup: PopupMenu) -> void:
	# Embedded popups use viewport coordinates. Both maximum dimensions must
	# cover their minimum; a zero width also disables Window's height clamp.
	var viewport := get_viewport()
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	var visible_size := viewport.get_visible_rect().size
	popup.max_size = Vector2i(maxi(1, floori(visible_size.x - 32.0 / maxf(stretch.x, 0.01))), maxi(1, floori(visible_size.y - 32.0 / maxf(stretch.y, 0.01))))

func _number(minimum: int, maximum: int) -> SpinBox:
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = 1
	number.custom_minimum_size = Vector2(100, 38)
	number.get_line_edit().add_theme_font_size_override("font_size", 18)
	return number

func _toggle(value: String) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = value
	toggle.add_theme_font_size_override("font_size", 18)
	toggle.custom_minimum_size.y = 38
	return toggle

func _field(grid: GridContainer, title: String, control: Control) -> void:
	var label := _label(title)
	label.custom_minimum_size.x = 130
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(label)
	grid.add_child(control)

func present(draft: Dictionary, catalogue: Dictionary, editable: bool = true) -> void:
	var catalogue_changed := catalogue != _catalogue
	var structure_changed := not _same_catalogue_structure(_catalogue, catalogue)
	if tabs != null and not catalogue_changed and draft == _draft and editable == _editable:
		return # Preserve partially typed numeric/search text and open popups.
	_draft = draft.duplicate(true)
	_editable = editable
	if catalogue_changed:
		_catalogue = catalogue.duplicate(true)
	if tabs == null:
		return
	if catalogue_changed:
		if structure_changed:
			_rebuild_catalogue()
		else:
			_refresh_catalogue_text()
	_present_controls()

func _same_catalogue_structure(previous: Dictionary, next: Dictionary) -> bool:
	for group in ["characters", "bearings", "biomes", "encounters", "powers", "catalysts", "ascension"]:
		var before: Array = previous.get(group, [])
		var after: Array = next.get(group, [])
		if before.size() != after.size():
			return false
		for index in before.size():
			for key in ["id", "max_level", "supports_prismatic"]:
				if before[index].get(key) != after[index].get(key):
					return false
	return not previous.is_empty()

func _refresh_catalogue_text() -> void:
	for group in ["powers", "catalysts", "ascension"]:
		for metadata: Dictionary in _catalogue.get(group, []):
			var key := String(metadata.get("id", ""))
			var row: Dictionary = build_rows.get(String(group) + ":" + key, {})
			if row.is_empty():
				continue
			row["metadata"] = metadata.duplicate(true)
			row["available"] = bool(metadata.get("available", true))
			row.title.text = String(metadata.get("name", ""))
			row.description.text = String(metadata.get("description", ""))
			row.description.visible = not row.description.text.is_empty()
			row.reason.text = String(metadata.get("unavailable_reason", metadata.get("arena_note", "")))
			row.reason.visible = not row.reason.text.is_empty()
	_filter_build()

func _fill_selector(selector: OptionButton, rows: Array) -> void:
	selector.clear()
	for row: Dictionary in rows:
		selector.add_item(String(row.get("name", "")))
		selector.set_item_metadata(selector.item_count - 1, row.get("id"))
		selector.set_item_disabled(selector.item_count - 1, not bool(row.get("available", true)))

func _rebuild_catalogue() -> void:
	floor_input.min_value = int(_catalogue.get("floor_min", 1))
	floor_input.max_value = int(_catalogue.get("floor_max", 25))
	floor_note.text = String(_catalogue.get("floor_note", ""))
	_fill_selector(character_selector, _catalogue.get("characters", []))
	_fill_selector(bearing_selector, _catalogue.get("bearings", []))
	_fill_selector(biome_selector, _catalogue.get("biomes", []))
	_fill_selector(encounter_selector, _catalogue.get("encounters", []))
	for child in _build_stack.get_children():
		if child == no_results:
			continue
		_build_stack.remove_child(child)
		child.queue_free()
	build_rows.clear()
	for category in ["powers", "catalysts", "ascension"]:
		for row: Dictionary in _catalogue.get(category, []):
			var id := String(row.get("id", ""))
			var key: String = String(category) + ":" + id
			var built := _entry_row(row)
			built["category"] = String(row.get("category", "boon")) if category == "powers" else category
			built["id"] = id
			built["group"] = category
			built["metadata"] = row.duplicate(true)
			_build_stack.add_child(built.root)
			if category == "powers":
				var input := _number(0, int(row.get("max_level", 1)))
				built.controls.add_child(input)
				input.value_changed.connect(func(value: float) -> void: _set_power(id, int(value)))
				built["input"] = input
				var remove := Button.new()
				remove.text = "Remove"
				remove.add_theme_font_size_override("font_size", 18)
				remove.custom_minimum_size.y = 36
				remove.pressed.connect(func() -> void: _set_power(id, 0))
				built.controls.add_child(remove)
				built["remove"] = remove
				if bool(row.get("supports_prismatic", false)):
					var prismatic := _toggle("Prismatic")
					built.controls.add_child(prismatic)
					prismatic.toggled.connect(func(value: bool) -> void: _set_membership("prismatic", id, value))
					prismatic.tooltip_text = "Available when this Arcana reaches its maximum level."
					built["prismatic"] = prismatic
			else:
				var input := _toggle("Include")
				built.controls.add_child(input)
				input.toggled.connect(func(value: bool) -> void: _set_membership(category, id, value))
				built["input"] = input
			build_rows[key] = built
	_filter_build()

func _entry_row(metadata: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var style := STYLES.make_panel_style(Color("172637"), Color("334d67"), 8, 1)
	for side in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + side, 10.0)
	panel.add_theme_stylebox_override("panel", style)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	content.add_child(text)
	var title := _label(String(metadata.get("name", "")), 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	var description: Control
	if metadata.has("max_level"):
		var rich := RichTextLabel.new()
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rich.add_theme_font_size_override("normal_font_size", 18)
		rich.add_theme_font_size_override("bold_font_size", 18)
		rich.add_theme_font_size_override("italics_font_size", 18)
		rich.add_theme_color_override("default_color", Color("bacbdc"))
		rich.text = String(metadata.get("description", ""))
		description = rich
	else:
		description = _copy(String(metadata.get("description", "")))
	description.visible = not String(metadata.get("description", "")).is_empty()
	text.add_child(description)
	var reason := String(metadata.get("unavailable_reason", metadata.get("arena_note", "")))
	var reason_label := _copy(reason)
	reason_label.visible = not reason.is_empty()
	text.add_child(reason_label)
	var controls := VBoxContainer.new()
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(controls)
	return {"root": panel, "title": title, "description": description, "reason": reason_label, "controls": controls, "available": bool(metadata.get("available", true))}

func _select_value(selector: OptionButton, value: Variant) -> void:
	for index in selector.item_count:
		if selector.get_item_metadata(index) == value:
			selector.select(index)
			break
	selector.disabled = not _editable

func _present_controls() -> void:
	if tabs == null:
		return
	_syncing = true
	_select_value(character_selector, _draft.get("character_id", "bastion"))
	_select_value(bearing_selector, _draft.get("bearing", 0))
	_select_value(biome_selector, _draft.get("biome_id", "shatterfield"))
	floor_input.set_value_no_signal(float(_draft.get("floor", 1)))
	floor_input.editable = _editable
	_select_value(encounter_selector, _draft.get("encounter_id", "warden"))
	encounter_description.text = ""
	for encounter: Dictionary in _catalogue.get("encounters", []):
		if String(encounter.get("id", "")) == String(_draft.get("encounter_id", "warden")):
			encounter_description.text = WORDING.to_plain(String(encounter.get("description", "")))
			break
	var powers: Dictionary = _draft.get("powers", {})
	var prism: Array = _draft.get("prismatic", [])
	for key: String in build_rows:
		var row: Dictionary = build_rows[key]
		if row.group == "powers":
			row.input.set_value_no_signal(float(powers.get(row.id, 0)))
			row.input.editable = _editable and row.available
			row.remove.visible = not row.available and int(powers.get(row.id, 0)) > 0
			row.remove.disabled = not _editable
			if row.has("prismatic"):
				row.prismatic.set_pressed_no_signal(prism.has(row.id))
				row.prismatic.disabled = not _editable or not row.available or int(powers.get(row.id, 0)) != int(row.metadata.get("max_level", 1))
		else:
			row.input.set_pressed_no_signal((_draft.get(row.group, []) as Array).has(row.id))
			row.input.disabled = not _editable or (not row.available and not (_draft.get(row.group, []) as Array).has(row.id))
	ai_toggle.set_pressed_no_signal(bool(_draft.get("enemy_ai", true)))
	ai_toggle.disabled = not _editable
	invulnerable_toggle.set_pressed_no_signal(bool(_draft.get("invulnerable", false)))
	invulnerable_toggle.disabled = not _editable
	clear_build_button.disabled = not _editable
	build_summary.text = "%d powers · %d Catalysts · %d Ascension modifiers" % [powers.size(), (_draft.get("catalysts", []) as Array).size(), (_draft.get("ascension", []) as Array).size()]
	_syncing = false

func _set_scalar(key: String, value: Variant) -> void:
	if _syncing or not _editable:
		return
	_draft[key] = value
	_emit_edit()

func _set_power(id: String, level: int) -> void:
	if _syncing or not _editable:
		return
	var powers: Dictionary = (_draft.get("powers", {}) as Dictionary).duplicate(true)
	if level > 0:
		powers[id] = level
	else:
		powers.erase(id)
	var row: Dictionary = build_rows.get("powers:" + id, {})
	if level == 0 or level < int((row.get("metadata", {}) as Dictionary).get("max_level", 1)):
		var prism: Array = (_draft.get("prismatic", []) as Array).duplicate()
		prism.erase(id)
		_draft["prismatic"] = prism
	_draft["powers"] = powers
	_emit_edit()

func _set_membership(key: String, id: String, included: bool) -> void:
	if _syncing or not _editable:
		return
	var entries: Array = (_draft.get(key, []) as Array).duplicate()
	entries.erase(id)
	if included:
		entries.append(id)
	_draft[key] = entries
	_emit_edit()

func _clear_build() -> void:
	if not _editable:
		return
	_draft["powers"] = {}
	_draft["prismatic"] = []
	_draft["catalysts"] = []
	_draft["ascension"] = []
	_emit_edit()

func _emit_edit() -> void:
	_present_controls()
	config_changed.emit(_draft.duplicate(true))

func _filter_build() -> void:
	if category_selector == null:
		return
	var category := String(category_selector.get_selected_metadata())
	var query := search_input.text.strip_edges().to_lower()
	var visible_count := 0
	for key: String in build_rows:
		var row: Dictionary = build_rows[key]
		var matches_category: bool = row.category == category or (category == "all" and row.group == "powers")
		var searchable := (String(row.metadata.get("name", "")) + " " + WORDING.to_plain(String(row.metadata.get("description", "")))).to_lower()
		row.root.visible = matches_category and (query.is_empty() or searchable.contains(query))
		if row.root.visible:
			visible_count += 1
	no_results.visible = visible_count == 0
