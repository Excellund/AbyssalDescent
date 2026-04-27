extends Node

const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const AUDIO_DB_MIN := -80.0
const AUDIO_DB_MAX := 6.0

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
var pause_master_value_label: Label
var pause_music_value_label: Label
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
	pause_menu_panel.custom_minimum_size = Vector2(440.0, 480.0)
	pause_menu_panel.position = Vector2(740.0, 260.0)
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

func _build_pause_options_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(620.0, 300.0)
	panel.position = Vector2(650.0, 380.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.95)
	style.border_color = Color(0.44, 0.7, 0.96, 0.74)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var title := Label.new()
	title.text = "Options"
	title.position = Vector2(0.0, 16.0)
	title.custom_minimum_size = Vector2(620.0, 32.0)
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
	pause_master_slider.custom_minimum_size = Vector2(450.0, 24.0)
	pause_master_slider.min_value = 0.0
	pause_master_slider.max_value = 100.0
	pause_master_slider.step = 1.0
	pause_master_slider.value_changed.connect(_on_pause_master_volume_changed)
	panel.add_child(pause_master_slider)

	pause_master_value_label = Label.new()
	pause_master_value_label.position = Vector2(510.0, 108.0)
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
	pause_music_slider.custom_minimum_size = Vector2(450.0, 24.0)
	pause_music_slider.min_value = 0.0
	pause_music_slider.max_value = 100.0
	pause_music_slider.step = 1.0
	pause_music_slider.value_changed.connect(_on_pause_music_volume_changed)
	panel.add_child(pause_music_slider)

	pause_music_value_label = Label.new()
	pause_music_value_label.position = Vector2(510.0, 188.0)
	pause_music_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	pause_music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(pause_music_value_label)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.position = Vector2(230.0, 242.0)
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
	panel.custom_minimum_size = Vector2(760.0, 520.0)
	panel.position = Vector2(580.0, 160.0)
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
	if pause_master_slider == null or pause_music_slider == null:
		return
	pause_master_slider.set_block_signals(true)
	pause_music_slider.set_block_signals(true)
	var run_context := _get_run_context()
	if run_context == null:
		pause_master_slider.value = _db_to_percent(0.0)
		pause_music_slider.value = _db_to_percent(-20.0)
		pause_master_slider.set_block_signals(false)
		pause_music_slider.set_block_signals(false)
		_update_pause_option_labels()
		return
	pause_master_slider.value = _db_to_percent(float(run_context.get("master_volume_db")))
	pause_music_slider.value = _db_to_percent(float(run_context.get("music_volume_db")))
	pause_master_slider.set_block_signals(false)
	pause_music_slider.set_block_signals(false)
	_update_pause_option_labels()

func _on_pause_master_volume_changed(value: float) -> void:
	_apply_pause_options(value, pause_music_slider.value)

func _on_pause_music_volume_changed(value: float) -> void:
	_apply_pause_options(pause_master_slider.value, value)

func _apply_pause_options(master_percent: float, music_percent: float) -> void:
	var master_db := _percent_to_db(master_percent)
	var music_db := _percent_to_db(music_percent)
	var run_context := _get_run_context()
	if run_context != null and run_context.has_method("set_audio_settings"):
		run_context.call("set_audio_settings", master_db, music_db, true)
	if apply_music_volume_callback.is_valid():
		apply_music_volume_callback.call(clampf(music_db, AUDIO_DB_MIN, AUDIO_DB_MAX))
	_update_pause_option_labels()

func _update_pause_option_labels() -> void:
	if pause_master_value_label != null and pause_master_slider != null:
		pause_master_value_label.text = "%d%%" % int(round(pause_master_slider.value))
	if pause_music_value_label != null and pause_music_slider != null:
		pause_music_value_label.text = "%d%%" % int(round(pause_music_slider.value))

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
