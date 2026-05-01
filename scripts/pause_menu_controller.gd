extends Node

const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const AUDIO_DB_MIN := AUDIO_LEVELS.DB_MIN
const AUDIO_DB_MAX := AUDIO_LEVELS.DB_MAX

signal pause_opened
signal pause_closed
signal back_to_main_menu_requested
signal abandon_run_requested
signal exit_game_requested

var run_context_path: String = "/root/RunContext"
var apply_music_volume_callback: Callable

var pause_menu_layer: CanvasLayer
var pause_menu_panel: Panel
var pause_options_panel: Panel
var pause_glossary_panel: Panel
var pause_master_slider: HSlider
var pause_music_slider: HSlider
var pause_display_mode_selector: OptionButton
var pause_resolution_selector: OptionButton
var pause_telemetry_upload_checkbox: CheckBox
var pause_master_value_label: Label
var pause_music_value_label: Label
var pause_resolution_hint_label: Label
var pause_menu_visible: bool = false

func initialize(context_path: String, apply_music_volume: Callable) -> void:
	run_context_path = context_path
	apply_music_volume_callback = apply_music_volume
	_create_pause_menu_ui()

func is_open() -> bool:
	return pause_menu_visible

func is_options_open() -> bool:
	return pause_options_panel != null and pause_options_panel.visible

func is_glossary_open() -> bool:
	return pause_glossary_panel != null and pause_glossary_panel.visible

func open() -> void:
	pause_menu_visible = true
	if pause_menu_layer != null:
		pause_menu_layer.visible = true
	if pause_options_panel != null:
		pause_options_panel.visible = false
	if pause_glossary_panel != null:
		pause_glossary_panel.visible = false
	_sync_pause_options_from_context()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_opened.emit()

func close() -> void:
	pause_menu_visible = false
	if pause_menu_layer != null:
		pause_menu_layer.visible = false
	pause_closed.emit()

func close_options() -> void:
	if pause_options_panel != null:
		pause_options_panel.visible = false
	if pause_glossary_panel != null:
		pause_glossary_panel.visible = false

func close_glossary() -> void:
	if pause_glossary_panel != null:
		pause_glossary_panel.visible = false

func _create_pause_menu_ui() -> void:
	pause_menu_layer = CanvasLayer.new()
	pause_menu_layer.layer = 200
	add_child(pause_menu_layer)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.58)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu_layer.add_child(backdrop)

	pause_menu_panel = Panel.new()
	pause_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu_panel.custom_minimum_size = Vector2(440.0, 480.0)
	pause_menu_panel.position = Vector2(-220.0, -240.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.09, 0.13, 0.94)
	panel_style.border_color = Color(0.34, 0.56, 0.84, 0.78)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	pause_menu_panel.add_theme_stylebox_override("panel", panel_style)
	pause_menu_layer.add_child(pause_menu_panel)

	var title := Label.new()
	title.text = "Paused"
	title.position = Vector2(0.0, 34.0)
	title.custom_minimum_size = Vector2(440.0, 40.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.98))
	pause_menu_panel.add_child(title)

	var resume_button := _make_pause_button("Resume", Vector2(80.0, 88.0))
	resume_button.pressed.connect(func() -> void:
		close()
	)
	pause_menu_panel.add_child(resume_button)

	var back_to_menu_button := _make_pause_button("Back to Main Menu", Vector2(80.0, 148.0))
	back_to_menu_button.pressed.connect(func() -> void:
		back_to_main_menu_requested.emit()
	)
	pause_menu_panel.add_child(back_to_menu_button)

	var options_button := _make_pause_button("Options", Vector2(80.0, 208.0))
	options_button.pressed.connect(func() -> void:
		if pause_options_panel != null:
			pause_options_panel.visible = true
		if pause_glossary_panel != null:
			pause_glossary_panel.visible = false
	)
	pause_menu_panel.add_child(options_button)

	var glossary_button := _make_pause_button("Glossary", Vector2(80.0, 268.0))
	glossary_button.pressed.connect(func() -> void:
		if pause_glossary_panel != null:
			pause_glossary_panel.visible = true
		if pause_options_panel != null:
			pause_options_panel.visible = false
	)
	pause_menu_panel.add_child(glossary_button)

	var abandon_run_button := _make_pause_button("Abandon Descent", Vector2(80.0, 328.0))
	_apply_destructive_button_style(abandon_run_button)
	abandon_run_button.pressed.connect(func() -> void:
		abandon_run_requested.emit()
	)
	pause_menu_panel.add_child(abandon_run_button)

	var exit_button := _make_pause_button("Exit Game", Vector2(80.0, 388.0))
	exit_button.pressed.connect(func() -> void:
		exit_game_requested.emit()
	)
	pause_menu_panel.add_child(exit_button)

	pause_options_panel = _build_pause_options_panel()
	pause_options_panel.visible = false
	pause_menu_layer.add_child(pause_options_panel)

	pause_glossary_panel = _build_pause_glossary_panel()
	pause_glossary_panel.visible = false
	pause_menu_layer.add_child(pause_glossary_panel)

	pause_menu_layer.visible = false

func _make_pause_button(text: String, pos: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.custom_minimum_size = Vector2(280.0, 52.0)
	button.add_theme_font_size_override("font_size", 20)
	return button

func _apply_destructive_button_style(button: Button) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.3, 0.07, 0.09, 0.9)
	normal_style.border_color = Color(0.86, 0.26, 0.3, 0.95)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.4, 0.1, 0.12, 0.94)
	hover_style.border_color = Color(0.96, 0.34, 0.38, 1.0)
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.25, 0.06, 0.08, 0.96)
	pressed_style.border_color = Color(0.84, 0.24, 0.3, 1.0)
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("pressed", pressed_style)

	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.94, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.82, 1.0))

func _apply_pause_option_selector_theme(selector: OptionButton) -> void:
	if selector == null:
		return
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.10, 0.15, 0.22, 0.95)
	normal_style.border_color = Color(0.34, 0.56, 0.84, 0.72)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 18.0
	normal_style.content_margin_right = 18.0
	normal_style.content_margin_top = 12.0
	normal_style.content_margin_bottom = 12.0
	selector.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.13, 0.19, 0.28, 0.98)
	hover_style.border_color = Color(0.62, 0.82, 0.98, 0.88)
	selector.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.08, 0.12, 0.18, 0.98)
	pressed_style.border_color = Color(0.74, 0.90, 1.0, 0.92)
	selector.add_theme_stylebox_override("pressed", pressed_style)

	var focus_style := normal_style.duplicate() as StyleBoxFlat
	focus_style.bg_color = Color(0.13, 0.20, 0.29, 0.98)
	focus_style.border_color = Color(0.86, 0.96, 1.0, 1.0)
	selector.add_theme_stylebox_override("focus", focus_style)
	selector.add_theme_font_size_override("font_size", 18)
	selector.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	selector.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	selector.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	selector.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _build_pause_options_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(660.0, 620.0)
	panel.position = Vector2(-330.0, -310.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.95)
	style.border_color = Color(0.44, 0.7, 0.96, 0.74)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var title := Label.new()
	title.text = "Options"
	title.position = Vector2(0.0, 16.0)
	title.custom_minimum_size = Vector2(660.0, 32.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	panel.add_child(title)

	var master_label := Label.new()
	master_label.text = "Master Volume"
	master_label.position = Vector2(42.0, 84.0)
	master_label.custom_minimum_size = Vector2(260.0, 24.0)
	master_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(master_label)

	pause_master_slider = HSlider.new()
	pause_master_slider.position = Vector2(42.0, 112.0)
	pause_master_slider.custom_minimum_size = Vector2(486.0, 24.0)
	pause_master_slider.min_value = 0.0
	pause_master_slider.max_value = 100.0
	pause_master_slider.step = 1.0
	pause_master_slider.value_changed.connect(_on_pause_master_volume_changed)
	panel.add_child(pause_master_slider)

	pause_master_value_label = Label.new()
	pause_master_value_label.position = Vector2(548.0, 108.0)
	pause_master_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	pause_master_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(pause_master_value_label)

	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.position = Vector2(42.0, 164.0)
	music_label.custom_minimum_size = Vector2(260.0, 24.0)
	music_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(music_label)

	pause_music_slider = HSlider.new()
	pause_music_slider.position = Vector2(42.0, 192.0)
	pause_music_slider.custom_minimum_size = Vector2(486.0, 24.0)
	pause_music_slider.min_value = 0.0
	pause_music_slider.max_value = 100.0
	pause_music_slider.step = 1.0
	pause_music_slider.value_changed.connect(_on_pause_music_volume_changed)
	panel.add_child(pause_music_slider)

	pause_music_value_label = Label.new()
	pause_music_value_label.position = Vector2(548.0, 188.0)
	pause_music_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	pause_music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(pause_music_value_label)

	var display_mode_label := Label.new()
	display_mode_label.text = "Display Mode"
	display_mode_label.position = Vector2(42.0, 244.0)
	display_mode_label.custom_minimum_size = Vector2(260.0, 24.0)
	display_mode_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(display_mode_label)

	pause_display_mode_selector = OptionButton.new()
	pause_display_mode_selector.position = Vector2(42.0, 272.0)
	pause_display_mode_selector.custom_minimum_size = Vector2(576.0, 48.0)
	_apply_pause_option_selector_theme(pause_display_mode_selector)
	pause_display_mode_selector.item_selected.connect(_on_pause_display_mode_selected)
	panel.add_child(pause_display_mode_selector)

	var resolution_label := Label.new()
	resolution_label.text = "Resolution"
	resolution_label.position = Vector2(42.0, 332.0)
	resolution_label.custom_minimum_size = Vector2(260.0, 24.0)
	resolution_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(resolution_label)

	pause_resolution_selector = OptionButton.new()
	pause_resolution_selector.position = Vector2(42.0, 360.0)
	pause_resolution_selector.custom_minimum_size = Vector2(576.0, 48.0)
	_apply_pause_option_selector_theme(pause_resolution_selector)
	pause_resolution_selector.item_selected.connect(_on_pause_resolution_selected)
	panel.add_child(pause_resolution_selector)

	pause_resolution_hint_label = Label.new()
	pause_resolution_hint_label.text = "Applies immediately and recenters the game window."
	pause_resolution_hint_label.position = Vector2(42.0, 414.0)
	pause_resolution_hint_label.custom_minimum_size = Vector2(576.0, 34.0)
	pause_resolution_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_resolution_hint_label.add_theme_font_size_override("font_size", 14)
	pause_resolution_hint_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.90, 0.76))
	panel.add_child(pause_resolution_hint_label)

	pause_telemetry_upload_checkbox = CheckBox.new()
	pause_telemetry_upload_checkbox.text = "Send Anonymous Telemetry"
	pause_telemetry_upload_checkbox.position = Vector2(42.0, 456.0)
	pause_telemetry_upload_checkbox.custom_minimum_size = Vector2(576.0, 30.0)
	pause_telemetry_upload_checkbox.add_theme_font_size_override("font_size", 18)
	pause_telemetry_upload_checkbox.toggled.connect(_on_pause_telemetry_upload_toggled)
	panel.add_child(pause_telemetry_upload_checkbox)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.position = Vector2(250.0, 522.0)
	back_button.custom_minimum_size = Vector2(160.0, 42.0)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(func() -> void:
		if pause_options_panel != null:
			pause_options_panel.visible = false
	)
	panel.add_child(back_button)

	return panel

func _build_pause_glossary_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760.0, 520.0)
	panel.position = Vector2(-380.0, -260.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.96)
	style.border_color = Color(0.44, 0.7, 0.96, 0.74)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var title := Label.new()
	title.text = "Glossary"
	title.position = Vector2(0.0, 16.0)
	title.custom_minimum_size = Vector2(760.0, 32.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	panel.add_child(title)

	var body := RichTextLabel.new()
	body.position = Vector2(28.0, 62.0)
	body.custom_minimum_size = Vector2(704.0, 396.0)
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.selection_enabled = false
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", Color(0.86, 0.94, 1.0, 0.96))
	body.text = GLOSSARY_DATA.glossary_bbcode()
	panel.add_child(body)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.position = Vector2(300.0, 468.0)
	back_button.custom_minimum_size = Vector2(160.0, 40.0)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(func() -> void:
		if pause_glossary_panel != null:
			pause_glossary_panel.visible = false
	)
	panel.add_child(back_button)

	return panel

func _get_run_context() -> Node:
	return get_node_or_null(run_context_path)

func _sync_pause_options_from_context() -> void:
	if pause_master_slider == null or pause_music_slider == null or pause_resolution_selector == null or pause_display_mode_selector == null or pause_telemetry_upload_checkbox == null:
		return
	pause_master_slider.set_block_signals(true)
	pause_music_slider.set_block_signals(true)
	pause_display_mode_selector.set_block_signals(true)
	pause_resolution_selector.set_block_signals(true)
	pause_telemetry_upload_checkbox.set_block_signals(true)
	var run_context := _get_run_context()
	if run_context == null:
		pause_master_slider.value = _db_to_percent(0.0)
		pause_music_slider.value = _db_to_percent(-20.0)
		_populate_pause_display_mode_selector([], SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_populate_pause_resolution_selector([], 1920, 1080)
		pause_telemetry_upload_checkbox.button_pressed = SETTINGS_STORE.DEFAULT_TELEMETRY_UPLOAD_ENABLED
		pause_master_slider.set_block_signals(false)
		pause_music_slider.set_block_signals(false)
		pause_display_mode_selector.set_block_signals(false)
		pause_resolution_selector.set_block_signals(false)
		pause_telemetry_upload_checkbox.set_block_signals(false)
		_update_pause_resolution_control_state(SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_update_pause_option_labels()
		return
	pause_master_slider.value = _db_to_percent(float(run_context.get("master_volume_db")))
	pause_music_slider.value = _db_to_percent(float(run_context.get("music_volume_db")))
	var mode_options: Array[Dictionary] = run_context.get_display_mode_options() as Array[Dictionary]
	_populate_pause_display_mode_selector(mode_options, String(run_context.get("display_mode")))
	var resolution_options: Array[Dictionary] = run_context.get_supported_resolution_options() as Array[Dictionary]
	_populate_pause_resolution_selector(
		resolution_options,
		int(run_context.get("resolution_width")),
		int(run_context.get("resolution_height"))
	)
	pause_telemetry_upload_checkbox.button_pressed = bool(run_context.get("telemetry_upload_enabled"))
	pause_master_slider.set_block_signals(false)
	pause_music_slider.set_block_signals(false)
	pause_display_mode_selector.set_block_signals(false)
	pause_resolution_selector.set_block_signals(false)
	pause_telemetry_upload_checkbox.set_block_signals(false)
	_update_pause_resolution_control_state(String(run_context.get("display_mode")))
	_update_pause_option_labels()

func _on_pause_master_volume_changed(value: float) -> void:
	_apply_pause_options(value, pause_music_slider.value)

func _on_pause_music_volume_changed(value: float) -> void:
	_apply_pause_options(pause_master_slider.value, value)

func _on_pause_resolution_selected(index: int) -> void:
	if pause_resolution_selector == null:
		return
	var metadata: Variant = pause_resolution_selector.get_item_metadata(index)
	if not (metadata is Dictionary):
		return
	var resolution := metadata as Dictionary
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_resolution_settings(int(resolution.get("width", 0)), int(resolution.get("height", 0)), true)

func _on_pause_display_mode_selected(index: int) -> void:
	if pause_display_mode_selector == null:
		return
	var metadata: Variant = pause_display_mode_selector.get_item_metadata(index)
	var selected_mode := String(metadata)
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_display_mode(selected_mode, true)
	_sync_pause_options_from_context()

func _on_pause_telemetry_upload_toggled(enabled: bool) -> void:
	var run_context := _get_run_context()
	if run_context != null and run_context.has_method("set_telemetry_upload_enabled"):
		run_context.call("set_telemetry_upload_enabled", enabled, true, true)

func _apply_pause_options(master_percent: float, music_percent: float) -> void:
	var master_db := _percent_to_db(master_percent)
	var music_db := _percent_to_db(music_percent)
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_audio_settings(master_db, music_db, true)
	if apply_music_volume_callback.is_valid():
		apply_music_volume_callback.callv([AUDIO_LEVELS.clamp_db(music_db)])
	_update_pause_option_labels()

func _update_pause_option_labels() -> void:
	if pause_master_value_label != null and pause_master_slider != null:
		pause_master_value_label.text = "%d%%" % int(round(pause_master_slider.value))
	if pause_music_value_label != null and pause_music_slider != null:
		pause_music_value_label.text = "%d%%" % int(round(pause_music_slider.value))

func _populate_pause_resolution_selector(options: Array[Dictionary], selected_width: int, selected_height: int) -> void:
	if pause_resolution_selector == null:
		return
	pause_resolution_selector.clear()
	if options.is_empty():
		options = [{
			"width": selected_width,
			"height": selected_height,
			"label": "%d x %d" % [selected_width, selected_height]
		}]
	var best_match := -1
	for index in range(options.size()):
		var option := options[index]
		var label := String(option.get("label", "%d x %d" % [int(option.get("width", 0)), int(option.get("height", 0))]))
		pause_resolution_selector.add_item(label)
		pause_resolution_selector.set_item_metadata(index, option)
		if int(option.get("width", 0)) == selected_width and int(option.get("height", 0)) == selected_height:
			best_match = index
	if best_match == -1 and pause_resolution_selector.item_count > 0:
		best_match = 0
	if best_match >= 0:
		pause_resolution_selector.select(best_match)

func _populate_pause_display_mode_selector(options: Array[Dictionary], selected_mode: String) -> void:
	if pause_display_mode_selector == null:
		return
	pause_display_mode_selector.clear()
	if options.is_empty():
		options = [
			{"id": SETTINGS_STORE.DISPLAY_MODE_FULLSCREEN, "label": "Borderless Fullscreen"},
			{"id": SETTINGS_STORE.DISPLAY_MODE_WINDOWED, "label": "Windowed"}
		]
	var best_match := -1
	for index in range(options.size()):
		var option := options[index]
		var mode_id := String(option.get("id", SETTINGS_STORE.DISPLAY_MODE_FULLSCREEN))
		var label := String(option.get("label", mode_id))
		pause_display_mode_selector.add_item(label)
		pause_display_mode_selector.set_item_metadata(index, mode_id)
		if mode_id == selected_mode:
			best_match = index
	if best_match == -1 and pause_display_mode_selector.item_count > 0:
		best_match = 0
	if best_match >= 0:
		pause_display_mode_selector.select(best_match)

func _update_pause_resolution_control_state(current_mode: String) -> void:
	var is_windowed := current_mode == SETTINGS_STORE.DISPLAY_MODE_WINDOWED
	if pause_resolution_selector != null:
		pause_resolution_selector.disabled = not is_windowed
	if pause_resolution_hint_label != null:
		if is_windowed:
			pause_resolution_hint_label.text = "Applies immediately and recenters the game window."
		else:
			pause_resolution_hint_label.text = "Disabled in fullscreen. Switch to Windowed to choose a resolution."

func _percent_to_db(percent: float) -> float:
	var clamped := clampf(percent, 0.0, 100.0)
	if clamped <= 0.0:
		return AUDIO_DB_MIN
	return lerpf(AUDIO_DB_MIN, AUDIO_DB_MAX, clamped / 100.0)

func _db_to_percent(db: float) -> float:
	var clamped := clampf(db, AUDIO_DB_MIN, AUDIO_DB_MAX)
	if clamped <= AUDIO_DB_MIN:
		return 0.0
	return inverse_lerp(AUDIO_DB_MIN, AUDIO_DB_MAX, clamped) * 100.0
