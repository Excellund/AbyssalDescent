extends Node

const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const GLOSSARY_FONT := preload("res://scripts/ui/scaled_ui_font.gd")
const RUN_OATH_PANEL := preload("res://scripts/ui/run_oath_panel.gd")
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const MENU_STYLE_FACTORY := preload("res://scripts/core/menu_style_factory.gd")
const AUDIO_DB_MIN := AUDIO_LEVELS.DB_MIN
const AUDIO_DB_MAX := AUDIO_LEVELS.DB_MAX

signal pause_opened
signal pause_closed
signal back_to_main_menu_requested
signal abandon_run_requested
signal exit_game_requested

var run_context_path: String = "/root/RunContext"
var apply_music_volume_callback: Callable
var apply_sfx_volume_callback: Callable

var pause_menu_layer: CanvasLayer
var pause_menu_panel: Panel
var pause_options_panel: Panel
var pause_glossary_panel: Panel
var pause_oaths_panel: Panel
var _pause_buttons: Array[Button] = []
var _pause_title: Label
var _oaths_button: Button
var _options_button: Button
var _glossary_button: Button
var _overlay_return_button: Button
var _overlay_tweens: Dictionary = {}
var _overlay_origins: Dictionary = {}
var pause_master_slider: HSlider
var pause_music_slider: HSlider
var pause_sfx_slider: HSlider
var pause_display_mode_selector: OptionButton
var pause_resolution_selector: OptionButton
var pause_telemetry_upload_checkbox: CheckBox
var pause_master_value_label: Label
var pause_music_value_label: Label
var pause_sfx_value_label: Label
var pause_resolution_hint_label: Label
var _pause_options_scroll: ScrollContainer
var _pause_options_body: Control
var _pause_options_title: Label
var _pause_options_back: Button
var pause_menu_visible: bool = false
var checkpoint_notice_label: Label
var _pause_panel_tween: Tween

func set_checkpoint_notice(message: String) -> void:
	if checkpoint_notice_label == null:
		return
	checkpoint_notice_label.text = message
	checkpoint_notice_label.visible = not message.is_empty()
	if _pause_panel_tween != null and _pause_panel_tween.is_valid():
		_pause_panel_tween.kill()
		pause_menu_panel.modulate.a = 1.0
	_layout_pause_menu()

func initialize(context_path: String, apply_music_volume: Callable, apply_sfx_volume: Callable) -> void:
	run_context_path = context_path
	apply_music_volume_callback = apply_music_volume
	apply_sfx_volume_callback = apply_sfx_volume
	_create_pause_menu_ui()

func is_open() -> bool:
	return pause_menu_visible

func is_options_open() -> bool:
	return pause_options_panel != null and pause_options_panel.visible

func is_glossary_open() -> bool:
	return pause_glossary_panel != null and pause_glossary_panel.visible

func is_oaths_open() -> bool:
	return pause_oaths_panel != null and pause_oaths_panel.visible

func set_oath_provider(callback: Callable) -> void:
	if pause_oaths_panel != null:
		pause_oaths_panel.provider = callback

func open() -> void:
	pause_menu_visible = true
	if pause_menu_layer != null:
		pause_menu_layer.visible = true
	for panel in [pause_options_panel, pause_glossary_panel, pause_oaths_panel]:
		_hide_pause_overlay(panel)
	if pause_menu_panel != null:
		pause_menu_panel.visible = true
	_set_main_buttons_enabled(true)
	_layout_pause_menu()
	_sync_pause_options_from_context()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_opened.emit()
	if pause_menu_panel != null:
		_animate_pause_panel_in(pause_menu_panel, Vector2(0.0, 16.0))
		_pause_buttons[0].grab_focus()

func close() -> void:
	pause_menu_visible = false
	if pause_menu_layer != null:
		pause_menu_layer.visible = false
	pause_closed.emit()

func close_options() -> void:
	_hide_pause_overlay(pause_options_panel)
	_hide_pause_overlay(pause_glossary_panel)
	_restore_pause_main()

func close_glossary() -> void:
	_hide_pause_overlay(pause_glossary_panel)
	_restore_pause_main()

func open_oaths() -> void:
	if pause_oaths_panel == null or not is_open():
		return
	_hide_pause_overlay(pause_options_panel)
	_hide_pause_overlay(pause_glossary_panel)
	_overlay_return_button = _oaths_button
	pause_oaths_panel.refresh()
	_layout_pause_oaths()
	pause_oaths_panel.visible = true
	pause_menu_panel.visible = false
	_set_main_buttons_enabled(false)
	pause_oaths_panel.back_button.grab_focus()

func close_oaths() -> void:
	_hide_pause_overlay(pause_oaths_panel)
	_restore_pause_main()

func _hide_pause_overlay(panel: Panel) -> void:
	if panel == null:
		return
	var tween: Tween = _overlay_tweens.get(panel)
	if tween != null and tween.is_valid():
		tween.kill()
	if _overlay_origins.has(panel):
		panel.position = _overlay_origins[panel]
	_overlay_tweens.erase(panel)
	_overlay_origins.erase(panel)
	panel.visible = false
	panel.modulate.a = 1.0

func _restore_pause_main() -> void:
	if is_oaths_open() or is_options_open() or is_glossary_open():
		return
	if pause_menu_panel != null:
		pause_menu_panel.visible = true
		_layout_pause_menu()
	_set_main_buttons_enabled(true)
	if is_instance_valid(_overlay_return_button):
		_overlay_return_button.grab_focus()

func _set_main_buttons_enabled(enabled: bool) -> void:
	for button in _pause_buttons:
		button.disabled = not enabled

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
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.09, 0.13, 0.94)
	panel_style.border_color = Color(0.34, 0.56, 0.84, 0.78)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	pause_menu_panel.add_theme_stylebox_override("panel", panel_style)
	pause_menu_layer.add_child(pause_menu_panel)
	GLOSSARY_FONT.apply_to(pause_menu_panel)

	var title := Label.new()
	_pause_title = title
	title.text = "Paused"
	title.position = Vector2(0.0, 34.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.98))
	pause_menu_panel.add_child(title)

	var resume_button := _make_pause_button("Resume", Vector2(80.0, 88.0), true)
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
	_options_button = options_button
	options_button.pressed.connect(func() -> void:
		_show_pause_overlay_panel(pause_options_panel, pause_glossary_panel)
	)
	pause_menu_panel.add_child(options_button)

	var glossary_button := _make_pause_button("Glossary", Vector2(80.0, 268.0))
	_glossary_button = glossary_button
	glossary_button.pressed.connect(func() -> void:
		_show_pause_overlay_panel(pause_glossary_panel, pause_options_panel)
	)
	pause_menu_panel.add_child(glossary_button)

	_oaths_button = _make_pause_button("Oaths This Run", Vector2.ZERO)
	_oaths_button.pressed.connect(open_oaths)
	pause_menu_panel.add_child(_oaths_button)

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

	checkpoint_notice_label = Label.new()
	checkpoint_notice_label.position = Vector2(24.0, 452.0)
	checkpoint_notice_label.size = Vector2(392.0, 64.0)
	checkpoint_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	checkpoint_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	checkpoint_notice_label.add_theme_font_size_override("font_size", 18)
	checkpoint_notice_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.58))
	checkpoint_notice_label.visible = false
	pause_menu_panel.add_child(checkpoint_notice_label)

	pause_options_panel = _build_pause_options_panel()
	pause_options_panel.visible = false
	pause_menu_layer.add_child(pause_options_panel)

	pause_glossary_panel = _build_pause_glossary_panel()
	pause_glossary_panel.visible = false
	pause_menu_layer.add_child(pause_glossary_panel)
	pause_oaths_panel = RUN_OATH_PANEL.new()
	pause_oaths_panel.visible = false
	pause_menu_layer.add_child(pause_oaths_panel)
	pause_oaths_panel.back_requested.connect(close_oaths)
	if not get_viewport().size_changed.is_connected(_layout_pause_glossary):
		get_viewport().size_changed.connect(_layout_pause_glossary)
	get_viewport().size_changed.connect(_layout_pause_menu)
	get_viewport().size_changed.connect(_layout_pause_oaths)
	get_viewport().size_changed.connect(_layout_pause_options)
	_layout_pause_glossary()
	_layout_pause_menu()
	_layout_pause_oaths()
	_layout_pause_options()

	pause_menu_layer.visible = false

func _make_pause_button(text: String, pos: Vector2, emphasize: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.custom_minimum_size = Vector2(280.0, 42.0)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68, 0.90))
	if emphasize:
		button.add_theme_stylebox_override("normal", _make_pause_button_style(Color(0.16, 0.27, 0.42, 0.95), Color(0.76, 0.90, 1.0, 0.92), 16, 2))
		button.add_theme_stylebox_override("hover", _make_pause_button_style(Color(0.19, 0.32, 0.50, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_pause_button_style(Color(0.12, 0.22, 0.34, 0.98), Color(0.92, 0.98, 1.0, 1.0), 16, 2))
	else:
		button.add_theme_stylebox_override("normal", _make_pause_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 16, 2))
		button.add_theme_stylebox_override("hover", _make_pause_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_pause_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 16, 2))
	button.add_theme_stylebox_override("focus", _make_pause_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
	button.add_theme_stylebox_override("disabled", _make_pause_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 16, 2))
	_pause_buttons.append(button)
	return button

func _apply_destructive_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_pause_button_style(Color(0.3, 0.07, 0.09, 0.9), Color(0.86, 0.26, 0.3, 0.95), 16, 2))
	button.add_theme_stylebox_override("hover", _make_pause_button_style(Color(0.4, 0.1, 0.12, 0.94), Color(0.96, 0.34, 0.38, 1.0), 16, 2))
	button.add_theme_stylebox_override("pressed", _make_pause_button_style(Color(0.25, 0.06, 0.08, 0.96), Color(0.84, 0.24, 0.3, 1.0), 16, 2))
	button.add_theme_stylebox_override("focus", _make_pause_button_style(Color(0.42, 0.11, 0.13, 0.98), Color(1.0, 0.70, 0.72, 1.0), 16, 2))
	button.add_theme_stylebox_override("disabled", _make_pause_button_style(Color(0.14, 0.08, 0.09, 0.80), Color(0.34, 0.20, 0.22, 0.56), 16, 2))

	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.94, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.82, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.72, 0.58, 0.58, 0.86))

func _make_pause_panel_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	return MENU_STYLE_FACTORY.make_panel_style(bg_color, border_color, corner_radius, border_width)

func _make_pause_button_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	return MENU_STYLE_FACTORY.make_button_style(bg_color, border_color, corner_radius, border_width)

func _make_pause_glossary_nav_button(label_text: String, btn_group: ButtonGroup) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.button_group = btn_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0, 0.90))
	btn.add_theme_color_override("font_hover_color", Color(0.96, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.78, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(0.96, 1.0, 1.0, 1.0))
	btn.add_theme_stylebox_override("normal", _make_pause_button_style(Color(0.06, 0.09, 0.14, 0.0), Color(0.0, 0.0, 0.0, 0.0), 10, 0))
	btn.add_theme_stylebox_override("hover", _make_pause_button_style(Color(0.10, 0.16, 0.24, 0.80), Color(0.44, 0.66, 0.90, 0.55), 10, 1))
	btn.add_theme_stylebox_override("pressed", _make_pause_button_style(Color(0.12, 0.22, 0.36, 0.95), Color(0.58, 0.80, 0.98, 0.85), 10, 2))
	btn.add_theme_stylebox_override("focus", _make_pause_button_style(Color(0.10, 0.16, 0.24, 0.80), Color(0.72, 0.88, 1.0, 0.90), 10, 1))
	btn.add_theme_stylebox_override("disabled", _make_pause_button_style(Color(0.04, 0.06, 0.10, 0.60), Color(0.18, 0.24, 0.32, 0.40), 10, 0))
	return btn

func _make_pause_panel_back_button() -> Button:
	var button := Button.new()
	button.set_meta("pause_overlay_back", true)
	button.text = "Back"
	button.custom_minimum_size = Vector2(180.0, 46.0)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68, 0.90))
	button.add_theme_stylebox_override("normal", _make_pause_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 16, 2))
	button.add_theme_stylebox_override("hover", _make_pause_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 16, 2))
	button.add_theme_stylebox_override("pressed", _make_pause_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 16, 2))
	button.add_theme_stylebox_override("focus", _make_pause_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
	button.add_theme_stylebox_override("disabled", _make_pause_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 16, 2))
	return button

func _apply_pause_option_selector_theme(selector: OptionButton) -> void:
	if selector == null:
		return
	var normal_style := _make_pause_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 10, 2)
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
	GLOSSARY_FONT.apply_to(panel)
	var style := _make_pause_panel_style(Color(0.04, 0.06, 0.1, 0.95), Color(0.44, 0.7, 0.96, 0.74), 12, 2)
	panel.add_theme_stylebox_override("panel", style)

	var title := Label.new()
	_pause_options_title = title
	title.text = "Options"
	title.position = Vector2(0.0, 16.0)
	title.custom_minimum_size = Vector2(0.0, 32.0)
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

	var sfx_label := Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.position = Vector2(42.0, 244.0)
	sfx_label.custom_minimum_size = Vector2(260.0, 24.0)
	sfx_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(sfx_label)

	pause_sfx_slider = HSlider.new()
	pause_sfx_slider.position = Vector2(42.0, 272.0)
	pause_sfx_slider.custom_minimum_size = Vector2(486.0, 24.0)
	pause_sfx_slider.min_value = 0.0
	pause_sfx_slider.max_value = 100.0
	pause_sfx_slider.step = 1.0
	pause_sfx_slider.value_changed.connect(_on_pause_sfx_volume_changed)
	panel.add_child(pause_sfx_slider)

	pause_sfx_value_label = Label.new()
	pause_sfx_value_label.position = Vector2(548.0, 268.0)
	pause_sfx_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	pause_sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(pause_sfx_value_label)

	var display_mode_label := Label.new()
	display_mode_label.text = "Display Mode"
	display_mode_label.position = Vector2(42.0, 324.0)
	display_mode_label.custom_minimum_size = Vector2(260.0, 24.0)
	display_mode_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(display_mode_label)

	pause_display_mode_selector = OptionButton.new()
	pause_display_mode_selector.position = Vector2(42.0, 352.0)
	pause_display_mode_selector.custom_minimum_size = Vector2(576.0, 48.0)
	_apply_pause_option_selector_theme(pause_display_mode_selector)
	pause_display_mode_selector.item_selected.connect(_on_pause_display_mode_selected)
	panel.add_child(pause_display_mode_selector)

	var resolution_label := Label.new()
	resolution_label.text = "Resolution"
	resolution_label.position = Vector2(42.0, 412.0)
	resolution_label.custom_minimum_size = Vector2(260.0, 24.0)
	resolution_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(resolution_label)

	pause_resolution_selector = OptionButton.new()
	pause_resolution_selector.position = Vector2(42.0, 440.0)
	pause_resolution_selector.custom_minimum_size = Vector2(576.0, 48.0)
	_apply_pause_option_selector_theme(pause_resolution_selector)
	pause_resolution_selector.item_selected.connect(_on_pause_resolution_selected)
	panel.add_child(pause_resolution_selector)

	pause_resolution_hint_label = Label.new()
	pause_resolution_hint_label.text = "Applies immediately and recenters the game window."
	pause_resolution_hint_label.position = Vector2(42.0, 494.0)
	pause_resolution_hint_label.custom_minimum_size = Vector2(576.0, 52.0)
	pause_resolution_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_resolution_hint_label.add_theme_font_size_override("font_size", 18)
	pause_resolution_hint_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.90, 0.76))
	panel.add_child(pause_resolution_hint_label)

	pause_telemetry_upload_checkbox = CheckBox.new()
	pause_telemetry_upload_checkbox.text = "Send Anonymous Telemetry"
	pause_telemetry_upload_checkbox.position = Vector2(42.0, 556.0)
	pause_telemetry_upload_checkbox.custom_minimum_size = Vector2(576.0, 30.0)
	pause_telemetry_upload_checkbox.add_theme_font_size_override("font_size", 18)
	pause_telemetry_upload_checkbox.add_theme_icon_override("unchecked", RUN_OATH_PANEL._checkbox_icon(false))
	pause_telemetry_upload_checkbox.add_theme_icon_override("checked", RUN_OATH_PANEL._checkbox_icon(true))
	pause_telemetry_upload_checkbox.add_theme_stylebox_override("focus", _make_pause_panel_style(Color.TRANSPARENT, Color("badfff"), 4, 2))
	pause_telemetry_upload_checkbox.toggled.connect(_on_pause_telemetry_upload_toggled)
	panel.add_child(pause_telemetry_upload_checkbox)

	var back_button := _make_pause_panel_back_button()
	_pause_options_back = back_button
	back_button.position = Vector2(250.0, 602.0)
	back_button.pressed.connect(close_options)
	panel.add_child(back_button)
	# Preserve the existing controls and settings callbacks inside a scrolling
	# body. Title and Back remain available at every scroll position.
	var authored_controls := panel.get_children()
	_pause_options_scroll = ScrollContainer.new()
	_pause_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_options_scroll.follow_focus = true
	panel.add_child(_pause_options_scroll)
	_pause_options_body = Control.new()
	_pause_options_body.custom_minimum_size = Vector2(660.0, 534.0)
	_pause_options_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_options_scroll.add_child(_pause_options_body)
	for control: Control in authored_controls:
		if control == title or control == back_button:
			continue
		control.reparent(_pause_options_body, false)
		control.position.y -= 70.0
		if control is Label:
			control.add_theme_font_size_override("font_size", 18)
	# PopupMenu owns a Window theme, so assign the same crisp font explicitly.
	var popup_theme := panel.theme.duplicate() as Theme
	popup_theme.set_font("font", "PopupMenu", panel.theme.default_font)
	popup_theme.set_font_size("font_size", "PopupMenu", 18)
	popup_theme.set_color("font_color", "PopupMenu", Color("ecf3fa"))
	popup_theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var popup_style := _make_pause_panel_style(Color("111b29"), Color("557b9e"), 8, 2)
	for side in ["left", "right", "top", "bottom"]:
		popup_style.set("content_margin_" + side, 8.0)
	popup_theme.set_stylebox("panel", "PopupMenu", popup_style)
	popup_theme.set_stylebox("hover", "PopupMenu", _make_pause_panel_style(Color("284764"), Color("badfff"), 4, 1))
	for selector: OptionButton in [pause_display_mode_selector, pause_resolution_selector]:
		selector.get_popup().theme = popup_theme
	for slider: HSlider in [pause_master_slider, pause_music_slider, pause_sfx_slider]:
		for style_name in ["slider", "grabber_area", "grabber_area_highlight"]:
			var track := StyleBoxFlat.new()
			track.bg_color = Color("354e68") if style_name == "slider" else Color("86b9dc")
			track.set_corner_radius_all(3)
			track.content_margin_top = 3
			track.content_margin_bottom = 3
			slider.add_theme_stylebox_override(style_name, track)

	return panel

func _build_pause_glossary_panel() -> Panel:
	var panel := Panel.new()
	panel.name = "PauseGlossaryPanel"
	GLOSSARY_FONT.apply_to(panel)
	# Absolute position: (2560-1200)/2, (1440-820)/2 — centered in 2560x1440 viewport
	panel.position = Vector2(680.0, 310.0)
	panel.size = Vector2(1200.0, 820.0)
	var style := _make_pause_panel_style(Color(0.04, 0.06, 0.1, 0.96), Color(0.44, 0.7, 0.96, 0.74), 12, 2)
	panel.add_theme_stylebox_override("panel", style)

	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 30)
	layout.add_theme_constant_override("margin_right", 30)
	layout.add_theme_constant_override("margin_top", 24)
	layout.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Glossary"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	stack.add_child(title)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 12)
	stack.add_child(content_row)

	var nav_panel := Panel.new()
	nav_panel.custom_minimum_size = Vector2(200.0, 0.0)
	nav_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_panel.add_theme_stylebox_override("panel", _make_pause_panel_style(Color(0.03, 0.05, 0.08, 0.72), Color(0.26, 0.4, 0.58, 0.56), 10, 1))
	content_row.add_child(nav_panel)

	var nav_margin := MarginContainer.new()
	nav_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_margin.add_theme_constant_override("margin_left", 8)
	nav_margin.add_theme_constant_override("margin_right", 8)
	nav_margin.add_theme_constant_override("margin_top", 12)
	nav_margin.add_theme_constant_override("margin_bottom", 12)
	nav_panel.add_child(nav_margin)

	var nav_vbox := VBoxContainer.new()
	nav_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_vbox.add_theme_constant_override("separation", 6)
	var nav_scroll := ScrollContainer.new()
	nav_scroll.name = "GlossaryNavigationScroll"
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nav_scroll.follow_focus = true
	nav_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_margin.add_child(nav_scroll)
	nav_scroll.add_child(nav_vbox)

	var body_panel := Panel.new()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_panel.add_theme_stylebox_override("panel", _make_pause_panel_style(Color(0.03, 0.05, 0.08, 0.72), Color(0.26, 0.4, 0.58, 0.56), 10, 1))
	content_row.add_child(body_panel)

	var body := RichTextLabel.new()
	body.name = "GlossaryBody"
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 14.0
	body.offset_top = 10.0
	body.offset_right = -14.0
	body.offset_bottom = -10.0
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.selection_enabled = false
	body.add_theme_font_size_override("normal_font_size", 18)
	body.add_theme_font_size_override("bold_font_size", 18)
	body.add_theme_color_override("default_color", Color(0.86, 0.94, 1.0, 0.96))
	body_panel.add_child(body)

	var btn_group := ButtonGroup.new()
	var sections := GLOSSARY_DATA.glossary_sections()
	var first_btn: Button = null
	var first_bbcode: String = ""
	for section in sections:
		var btn := _make_pause_glossary_nav_button(section["label"], btn_group)
		var bbcode: String = section["bbcode"]
		if first_bbcode.is_empty():
			first_bbcode = bbcode
		btn.pressed.connect(func() -> void:
			body.text = bbcode
			body.scroll_to_line(0)
		)
		nav_vbox.add_child(btn)
		if first_btn == null:
			first_btn = btn

	var nav_spacer := Control.new()
	nav_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_vbox.add_child(nav_spacer)

	if first_btn != null:
		first_btn.button_pressed = true
		body.text = first_bbcode

	var back_button := _make_pause_panel_back_button()
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(close_glossary)
	stack.add_child(back_button)

	return panel

func _layout_pause_glossary() -> void:
	if pause_glossary_panel == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	var canvas_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return
	# The game stretches a 2560 canvas. Counter only that transform here so
	# glossary text remains 18 screen pixels at smaller playtest resolutions.
	var screen_size := canvas_size * stretch
	var panel_size := Vector2(minf(1360.0, screen_size.x - 48.0), minf(900.0, screen_size.y - 48.0))
	panel_size = panel_size.max(Vector2(480.0, 360.0))
	pause_glossary_panel.scale = Vector2.ONE / stretch
	pause_glossary_panel.size = panel_size
	pause_glossary_panel.position = (canvas_size - panel_size / stretch) * 0.5

func _layout_pause_menu() -> void:
	if pause_menu_panel == null or _pause_title == null or not is_inside_tree():
		return
	if _pause_panel_tween != null and _pause_panel_tween.is_valid():
		_pause_panel_tween.kill()
		pause_menu_panel.modulate.a = 1.0
	var viewport := get_viewport()
	var canvas_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return
	var screen_size := canvas_size * stretch
	var has_notice := checkpoint_notice_label != null and checkpoint_notice_label.visible
	var panel_size := Vector2(minf(460.0, screen_size.x - 32.0), 498.0 if has_notice else 434.0)
	pause_menu_panel.scale = Vector2.ONE / stretch
	pause_menu_panel.size = panel_size
	pause_menu_panel.position = (canvas_size - panel_size / stretch) * 0.5
	_pause_title.position = Vector2(20, 18)
	_pause_title.size = Vector2(panel_size.x - 40, 40)
	for i in _pause_buttons.size():
		var button := _pause_buttons[i]
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			var button_style := button.get_theme_stylebox(style_name) as StyleBoxFlat
			if button_style != null:
				button_style.content_margin_top = 8
				button_style.content_margin_bottom = 8
		button.custom_minimum_size.x = 0
		button.position = Vector2(48, 70 + i * 49)
		button.size = Vector2(panel_size.x - 96, 42)
	if checkpoint_notice_label != null:
		checkpoint_notice_label.position = Vector2(24, 420)
		checkpoint_notice_label.size = Vector2(panel_size.x - 48, 62)

func _layout_pause_oaths() -> void:
	if pause_oaths_panel == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	var canvas_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return
	var panel_size := (canvas_size * stretch - Vector2(40, 40)).min(Vector2(1080, 900))
	pause_oaths_panel.scale = Vector2.ONE / stretch
	pause_oaths_panel.size = panel_size
	pause_oaths_panel.position = (canvas_size - panel_size / stretch) * 0.5

func _layout_pause_options() -> void:
	if pause_options_panel == null or _pause_options_scroll == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	var canvas_size := viewport.get_visible_rect().size
	var stretch := viewport.get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return
	var tween: Tween = _overlay_tweens.get(pause_options_panel)
	if tween != null and tween.is_valid():
		tween.kill()
	_overlay_tweens.erase(pause_options_panel)
	_overlay_origins.erase(pause_options_panel)
	var panel_size := (canvas_size * stretch - Vector2(40, 40)).min(Vector2(740, 700))
	pause_options_panel.modulate.a = 1.0
	pause_options_panel.scale = Vector2.ONE / stretch
	pause_options_panel.size = panel_size
	pause_options_panel.position = (canvas_size - panel_size / stretch) * 0.5
	_pause_options_title.position = Vector2(20, 16)
	_pause_options_title.size = Vector2(panel_size.x - 40, 38)
	_pause_options_scroll.position = Vector2(24, 70)
	_pause_options_scroll.size = Vector2(panel_size.x - 48, panel_size.y - 152)
	_pause_options_back.position = Vector2((panel_size.x - 180) * 0.5, panel_size.y - 66)
	_pause_options_back.size = Vector2(180, 46)

func _get_run_context() -> Node:
	return get_node_or_null(run_context_path)

func _sync_pause_options_from_context() -> void:
	if pause_master_slider == null or pause_music_slider == null or pause_sfx_slider == null or pause_resolution_selector == null or pause_display_mode_selector == null or pause_telemetry_upload_checkbox == null:
		return
	pause_master_slider.set_block_signals(true)
	pause_music_slider.set_block_signals(true)
	pause_sfx_slider.set_block_signals(true)
	pause_display_mode_selector.set_block_signals(true)
	pause_resolution_selector.set_block_signals(true)
	pause_telemetry_upload_checkbox.set_block_signals(true)
	var run_context := _get_run_context()
	if run_context == null:
		pause_master_slider.value = _db_to_percent(0.0)
		pause_music_slider.value = _db_to_percent(-20.0)
		pause_sfx_slider.value = _db_to_percent(0.0)
		_populate_pause_display_mode_selector([], SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_populate_pause_resolution_selector([], 1920, 1080)
		pause_telemetry_upload_checkbox.button_pressed = SETTINGS_STORE.DEFAULT_TELEMETRY_UPLOAD_ENABLED
		pause_master_slider.set_block_signals(false)
		pause_music_slider.set_block_signals(false)
		pause_sfx_slider.set_block_signals(false)
		pause_display_mode_selector.set_block_signals(false)
		pause_resolution_selector.set_block_signals(false)
		pause_telemetry_upload_checkbox.set_block_signals(false)
		_update_pause_resolution_control_state(SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_update_pause_option_labels()
		return
	pause_master_slider.value = _db_to_percent(float(run_context.get("master_volume_db")))
	pause_music_slider.value = _db_to_percent(float(run_context.get("music_volume_db")))
	pause_sfx_slider.value = _db_to_percent(float(run_context.get("sfx_volume_db")))
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
	pause_sfx_slider.set_block_signals(false)
	pause_display_mode_selector.set_block_signals(false)
	pause_resolution_selector.set_block_signals(false)
	pause_telemetry_upload_checkbox.set_block_signals(false)
	_update_pause_resolution_control_state(String(run_context.get("display_mode")))
	_update_pause_option_labels()

func _on_pause_master_volume_changed(value: float) -> void:
	_apply_pause_options(value, pause_music_slider.value, pause_sfx_slider.value)

func _on_pause_music_volume_changed(value: float) -> void:
	_apply_pause_options(pause_master_slider.value, value, pause_sfx_slider.value)

func _on_pause_sfx_volume_changed(value: float) -> void:
	_apply_pause_options(pause_master_slider.value, pause_music_slider.value, value)

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
	if run_context != null:
		run_context.set_telemetry_upload_enabled(enabled, true, true)

func _apply_pause_options(master_percent: float, music_percent: float, sfx_percent: float) -> void:
	var master_db := _percent_to_db(master_percent)
	var music_db := _percent_to_db(music_percent)
	var sfx_db := _percent_to_db(sfx_percent)
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_audio_settings(master_db, music_db, sfx_db, true)
	if apply_music_volume_callback.is_valid():
		apply_music_volume_callback.callv([AUDIO_LEVELS.clamp_db(music_db)])
	if apply_sfx_volume_callback.is_valid():
		apply_sfx_volume_callback.callv([AUDIO_LEVELS.clamp_db(sfx_db)])
	_update_pause_option_labels()

func _update_pause_option_labels() -> void:
	if pause_master_value_label != null and pause_master_slider != null:
		pause_master_value_label.text = "%d%%" % int(round(pause_master_slider.value))
	if pause_music_value_label != null and pause_music_slider != null:
		pause_music_value_label.text = "%d%%" % int(round(pause_music_slider.value))
	if pause_sfx_value_label != null and pause_sfx_slider != null:
		pause_sfx_value_label.text = "%d%%" % int(round(pause_sfx_slider.value))

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

func _show_pause_overlay_panel(panel_to_show: Panel, panel_to_hide: Panel) -> void:
	_hide_pause_overlay(pause_oaths_panel)
	_hide_pause_overlay(panel_to_hide)
	_hide_pause_overlay(panel_to_show)
	if panel_to_show != null:
		_overlay_return_button = _glossary_button if panel_to_show == pause_glossary_panel else _options_button
		if panel_to_show == pause_glossary_panel:
			_layout_pause_glossary()
		elif panel_to_show == pause_options_panel:
			_layout_pause_options()
		pause_menu_panel.visible = false
		_set_main_buttons_enabled(false)
		panel_to_show.visible = true
		_animate_pause_panel_in(panel_to_show, Vector2(0.0, 14.0))
		for button in panel_to_show.find_children("*", "Button", true, false):
			if button.has_meta("pause_overlay_back"):
				button.grab_focus()
				break

func _animate_pause_panel_in(panel: Control, offset: Vector2) -> void:
	if panel == null:
		return
	if panel == pause_menu_panel and _pause_panel_tween != null and _pause_panel_tween.is_valid():
		_pause_panel_tween.kill()
	var target_position := panel.position
	panel.modulate.a = 0.0
	panel.position = target_position + offset
	var tween := create_tween()
	if panel == pause_menu_panel:
		_pause_panel_tween = tween
	else:
		_overlay_tweens[panel] = tween
		_overlay_origins[panel] = target_position
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.14)
	tween.tween_property(panel, "position", target_position, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if panel == pause_glossary_panel:
		tween.finished.connect(_layout_pause_glossary)

func _percent_to_db(percent: float) -> float:
	return AUDIO_LEVELS.percent_to_db(percent)

func _db_to_percent(db: float) -> float:
	return AUDIO_LEVELS.db_to_percent(db)
