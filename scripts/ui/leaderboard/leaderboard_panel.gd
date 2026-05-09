extends Panel
class_name LeaderboardPanel

const RUN_TELEMETRY_STORE := preload("res://scripts/run_telemetry_store.gd")
const BUILD_INFO := preload("res://scripts/build_info.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const LEADERBOARD_SERVICE_SCRIPT := preload("res://scripts/leaderboard_service.gd")
const TAB_STRIP_SCRIPT := preload("res://scripts/ui/leaderboard/leaderboard_tab_strip.gd")
const LIST_VIEW_SCRIPT := preload("res://scripts/ui/leaderboard/leaderboard_list_view.gd")
const LEADERBOARD_MODEL := preload("res://scripts/core/leaderboard_entry_model.gd")

const RUN_CONTEXT_PATH := "/root/RunContext"

signal back_pressed

var _service: Node
var _tab_strip: Control
var _list_view: Control
var _patch_selector: OptionButton
var _bearing_selector: OptionButton
var _character_selector: OptionButton
var _party_size_selector: OptionButton
var _status_label: Label
var _refresh_button: Button

var _selected_patch_key: String = ""
var _selected_bearing: int = 0
var _selected_character_id: String = ""
var _selected_party_size: int = 1
var _current_patch_key: String = "dev"
var _current_player_uuid: String = ""
var _request_token: int = 0
var _loading: bool = false

func _build_ui(style_ref: Object) -> void:
	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 36)
	layout.add_theme_constant_override("margin_right", 36)
	layout.add_theme_constant_override("margin_top", 28)
	layout.add_theme_constant_override("margin_bottom", 24)
	add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Leaderboards"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Current patch and archived rankings by Bearing & party size"
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 0.84))
	stack.add_child(subtitle)

	var filters := HBoxContainer.new()
	filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_theme_constant_override("separation", 10)
	stack.add_child(filters)

	_patch_selector = OptionButton.new()
	_patch_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_patch_selector.custom_minimum_size = Vector2(220.0, 42.0)
	_patch_selector.item_selected.connect(_on_patch_selected)
	filters.add_child(_patch_selector)

	_bearing_selector = OptionButton.new()
	_bearing_selector.custom_minimum_size = Vector2(150.0, 42.0)
	_bearing_selector.item_selected.connect(_on_bearing_selected)
	filters.add_child(_bearing_selector)
	for i in range(4):
		_bearing_selector.add_item(_bearing_label(i), i)
	_bearing_selector.select(_selected_bearing)

	_character_selector = OptionButton.new()
	_character_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_selector.custom_minimum_size = Vector2(200.0, 42.0)
	_character_selector.item_selected.connect(_on_character_selected)
	filters.add_child(_character_selector)
	_rebuild_character_selector()

	_party_size_selector = OptionButton.new()
	_party_size_selector.custom_minimum_size = Vector2(140.0, 42.0)
	_party_size_selector.item_selected.connect(_on_party_size_selected)
	filters.add_child(_party_size_selector)
	for size in range(LEADERBOARD_MODEL.PARTY_SIZE_MIN, LEADERBOARD_MODEL.PARTY_SIZE_MAX + 1):
		_party_size_selector.add_item(LEADERBOARD_MODEL.party_size_label(size), size)
	_select_party_size_in_selector(_selected_party_size)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.custom_minimum_size = Vector2(110.0, 42.0)
	_refresh_button.pressed.connect(func() -> void:
		_request_reload(false)
	)
	filters.add_child(_refresh_button)

	_tab_strip = TAB_STRIP_SCRIPT.new()
	_tab_strip.tab_changed.connect(_on_tab_changed)
	stack.add_child(_tab_strip)

	_status_label = Label.new()
	_status_label.text = "Loading leaderboards..."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.add_theme_color_override("font_color", Color(0.74, 0.84, 0.94, 0.9))
	stack.add_child(_status_label)

	_list_view = LIST_VIEW_SCRIPT.new()
	stack.add_child(_list_view)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(180.0, 46.0)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if style_ref != null and style_ref.has_method("_make_panel_back_button"):
		var themed_back: Variant = style_ref._make_panel_back_button()
		if themed_back is Button:
			back_button = themed_back
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	stack.add_child(back_button)

	_service = LEADERBOARD_SERVICE_SCRIPT.new()
	add_child(_service)
	_update_character_filter_visibility()

func populate() -> void:
	_request_reload(true)

func _request_reload(sync_from_context: bool) -> void:
	if sync_from_context:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null and run_context.has_method("get_profile_uuid"):
			_current_player_uuid = String(run_context.get_profile_uuid()).strip_edges().to_lower()
		if run_context != null and run_context.has_method("get_current_difficulty_tier"):
			_selected_bearing = int(run_context.get_current_difficulty_tier())
			if _bearing_selector != null:
				_bearing_selector.select(_selected_bearing)
		if run_context != null and run_context.has_method("get_selected_character_id"):
			_selected_character_id = String(run_context.get_selected_character_id()).strip_edges().to_lower()
			_select_character_if_available(_selected_character_id)
	_current_patch_key = _resolve_current_patch_key()
	_request_token += 1
	var token := _request_token
	call_deferred("_load_all_async", token)

func _load_all_async(token: int) -> void:
	if token != _request_token:
		return
	if _loading:
		return
	_loading = true
	_set_status("Loading leaderboard data...")
	await _reload_patch_options(token)
	await _reload_entries(token)
	_loading = false
	if token != _request_token:
		call_deferred("_load_all_async", _request_token)

func _reload_patch_options(token: int) -> void:
	if _service == null:
		return
	var patch_result: Dictionary = await _service.fetch_patch_options(_current_patch_key, _selected_bearing, 24)
	if token != _request_token:
		return
	_patch_selector.clear()
	var patch_rows := patch_result.get("patches", []) as Array
	for patch_variant in patch_rows:
		var patch := patch_variant as Dictionary
		var patch_key := String(patch.get("patch_key", "")).strip_edges().to_lower()
		if patch_key.is_empty():
			continue
		var label_prefix := "Current" if bool(patch.get("is_current", false)) else "Archive"
		_patch_selector.add_item("%s: %s" % [label_prefix, patch_key])
		var index := _patch_selector.item_count - 1
		_patch_selector.set_item_metadata(index, patch_key)
	if _patch_selector.item_count == 0:
		_patch_selector.add_item("Current: %s" % _current_patch_key)
		_patch_selector.set_item_metadata(0, _current_patch_key)
	_select_patch_key_or_default(_selected_patch_key)

func _reload_entries(token: int) -> void:
	if _service == null:
		return
	var patch_key := _selected_patch_key
	if patch_key.is_empty() and _patch_selector.item_count > 0:
		patch_key = String(_patch_selector.get_item_metadata(_patch_selector.selected))
		_selected_patch_key = patch_key
	var board_mode: String = _tab_strip.get_active() if _tab_strip != null else "global"
	var character_id := _selected_character_id if board_mode == "per_character" else ""
	var result: Dictionary = await _service.fetch_top_entries(patch_key, _selected_bearing, board_mode, character_id, 25, _selected_party_size)
	if token != _request_token:
		return
	var entries := result.get("entries", []) as Array
	if _list_view != null:
		_list_view.set_entries(entries, _current_player_uuid)
	if bool(result.get("ok", false)):
		var mode_label := "Global" if board_mode == "global" else "Per-Character"
		_set_status("Showing %d entries for %s board (%s)." % [entries.size(), mode_label, LEADERBOARD_MODEL.party_size_label(_selected_party_size)])
	else:
		_set_status(String(result.get("error", "Unable to load leaderboard.")))

func _resolve_current_patch_key() -> String:
	var configured_version := String(BUILD_INFO.GAME_VERSION).strip_edges()
	if configured_version.is_empty() or configured_version == "dev":
		configured_version = String(ProjectSettings.get_setting("application/config/version", "dev")).strip_edges()
	return RUN_TELEMETRY_STORE.leaderboard_patch_key_from_version(configured_version)

func _rebuild_character_selector() -> void:
	if _character_selector == null:
		return
	_character_selector.clear()
	for character_variant in CHARACTER_REGISTRY.get_launch_characters():
		var character := character_variant as Dictionary
		var character_id := String(character.get("id", "")).strip_edges().to_lower()
		if character_id.is_empty():
			continue
		var character_name := String(character.get("name", character_id.capitalize()))
		_character_selector.add_item(character_name)
		var index := _character_selector.item_count - 1
		_character_selector.set_item_metadata(index, character_id)
	if _character_selector.item_count > 0 and _selected_character_id.is_empty():
		_selected_character_id = String(_character_selector.get_item_metadata(0))
		_character_selector.select(0)

func _select_patch_key_or_default(target_patch_key: String) -> void:
	var normalized_target := target_patch_key.strip_edges().to_lower()
	for i in range(_patch_selector.item_count):
		var key := String(_patch_selector.get_item_metadata(i)).strip_edges().to_lower()
		if key == normalized_target and not key.is_empty():
			_patch_selector.select(i)
			_selected_patch_key = key
			return
	for i in range(_patch_selector.item_count):
		var key := String(_patch_selector.get_item_metadata(i)).strip_edges().to_lower()
		if key == _current_patch_key:
			_patch_selector.select(i)
			_selected_patch_key = key
			return
	if _patch_selector.item_count > 0:
		_patch_selector.select(0)
		_selected_patch_key = String(_patch_selector.get_item_metadata(0)).strip_edges().to_lower()

func _select_character_if_available(character_id: String) -> void:
	var target := character_id.strip_edges().to_lower()
	if _character_selector == null:
		return
	for i in range(_character_selector.item_count):
		if String(_character_selector.get_item_metadata(i)).strip_edges().to_lower() == target:
			_character_selector.select(i)
			_selected_character_id = target
			return
	if _character_selector.item_count > 0:
		_selected_character_id = String(_character_selector.get_item_metadata(_character_selector.selected)).strip_edges().to_lower()

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

func _on_patch_selected(index: int) -> void:
	if _patch_selector == null or index < 0 or index >= _patch_selector.item_count:
		return
	_selected_patch_key = String(_patch_selector.get_item_metadata(index)).strip_edges().to_lower()
	_request_reload(false)

func _on_bearing_selected(index: int) -> void:
	_selected_bearing = clampi(index, 0, 3)
	_request_reload(false)

func _on_character_selected(index: int) -> void:
	if _character_selector == null or index < 0 or index >= _character_selector.item_count:
		return
	_selected_character_id = String(_character_selector.get_item_metadata(index)).strip_edges().to_lower()
	if _tab_strip != null and _tab_strip.get_active() == "per_character":
		_request_reload(false)

func _on_party_size_selected(index: int) -> void:
	if _party_size_selector == null or index < 0 or index >= _party_size_selector.item_count:
		return
	_selected_party_size = LEADERBOARD_MODEL.clamp_party_size(int(_party_size_selector.get_item_id(index)))
	_request_reload(false)

func _select_party_size_in_selector(target_size: int) -> void:
	if _party_size_selector == null:
		return
	var normalized := LEADERBOARD_MODEL.clamp_party_size(target_size)
	for i in range(_party_size_selector.item_count):
		if _party_size_selector.get_item_id(i) == normalized:
			_party_size_selector.select(i)
			_selected_party_size = normalized
			return

func _on_tab_changed(_tab_key: String) -> void:
	_update_character_filter_visibility()
	_request_reload(false)

func _update_character_filter_visibility() -> void:
	if _character_selector == null or _tab_strip == null:
		return
	_character_selector.visible = _tab_strip.get_active() == "per_character"

func _bearing_label(tier: int) -> String:
	match tier:
		0:
			return "Pilgrim"
		1:
			return "Delver"
		2:
			return "Harbinger"
		3:
			return "Forsworn"
		_:
			return "Pilgrim"
