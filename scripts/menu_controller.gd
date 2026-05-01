extends Control

const GAMEPLAY_SCENE_PATH := "res://scenes/Main.tscn"
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_MUSIC := preload("res://music/msx1.mp3")
const ENUMS := preload("res://scripts/shared/enums.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const UPDATE_SERVICE_SCRIPT := preload("res://scripts/update_service.gd")
const MENU_QUOTE_NEUTRAL := "\"Something unfamiliar begins.\""
const MENU_QUOTES_AFTER_DEATH := [
	"\"Back already?\"",
	"\"I expected more from that attempt.\"",
	"\"You fell faster than the others.\"",
	"\"You left the dark hungry. Try again.\"",
	"\"Was that your whole answer?\""
]
const MENU_QUOTES_AFTER_CLEAR := [
	"\"A small victory. Keep it.\"",
	"\"Take the climb if you need it.\"",
	"\"You delayed the end. Nothing more.\"",
	"\"Enjoy the air while it lasts.\"",
	"\"You won a breath. Not freedom.\""
]
const QUOTE_PULSE_SPEED := 2.1
const QUOTE_PULSE_AMPLITUDE := 0.018
const QUOTE_COLOR_COOL := Color(0.72, 0.86, 1.0, 0.9)
const QUOTE_COLOR_WARM := Color(1.0, 0.95, 0.84, 1.0)
const AUDIO_DB_MIN := AUDIO_LEVELS.DB_MIN
const AUDIO_DB_MAX := AUDIO_LEVELS.DB_MAX
const MENU_LAYOUT_BASE_SIZE := Vector2(1020.0, 720.0)

var root_panel: Panel
var options_panel: Panel
var glossary_panel: Panel
var difficulty_selector_panel: Panel
var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var display_mode_selector: OptionButton
var resolution_selector: OptionButton
var telemetry_upload_checkbox: CheckBox
var master_value_label: Label
var music_value_label: Label
var sfx_value_label: Label
var resolution_hint_label: Label
var telemetry_consent_layer: Control
var menu_music_player: AudioStreamPlayer
var primary_run_button: Button
var difficulty_tier_buttons: Array[Button] = []
var difficulty_tier_name_labels: Array[Label] = []
var difficulty_tier_desc_labels: Array[Label] = []
var atmosphere_band: Panel
var flavor_quote_label: RichTextLabel
var quote_wrapper: Control
var _quote_pulse_active: bool = false
var _quote_pulse_time: float = 0.0
var update_panel: Panel
var update_status_label: Label
var update_detail_label: Label
var update_action_button: Button
var update_check_button: Button
var update_prompt_layer: Control
var update_prompt_title_label: Label
var update_prompt_body_label: Label
var update_prompt_pending: bool = false
var update_check_was_manual: bool = false
var update_service

func _ready() -> void:
	if _should_autostart_debug_encounter():
		call_deferred("_change_to_gameplay_scene")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()
	_apply_menu_layout()
	_play_menu_intro()
	_sync_options_from_context()
	_maybe_show_telemetry_consent_prompt()
	_start_menu_music()
	_start_update_check()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_menu_layout()

func _change_to_gameplay_scene() -> void:
	if get_tree() != null:
		get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _should_autostart_debug_encounter() -> bool:
	var debug_values := _read_main_debug_settings_values()
	if debug_values.is_empty():
		return false
	if not bool(debug_values.get("enabled", false)):
		return false
	var encounter_value: Variant = debug_values.get("start_encounter", null)
	if encounter_value == null:
		return false
	return int(encounter_value) != 0

func _read_main_debug_settings_values() -> Dictionary:
	var packed := load(GAMEPLAY_SCENE_PATH) as PackedScene
	if packed == null:
		return {}
	var main_root := packed.instantiate()
	if main_root == null:
		return {}
	var values := {}
	var debug_settings := main_root.get_node_or_null("DebugSettings")
	if debug_settings != null:
		values = {
			"enabled": bool(debug_settings.get("enabled")),
			"start_encounter": debug_settings.get("start_encounter"),
			"force_update_prompt_on_menu": bool(debug_settings.get("force_update_prompt_on_menu"))
		}
	main_root.queue_free()
	return values

func _exit_tree() -> void:
	if menu_music_player != null and menu_music_player.playing:
		menu_music_player.stop()

func _unhandled_input(event: InputEvent) -> void:
	if update_prompt_layer != null and update_prompt_layer.visible:
		return
	if event.is_action_pressed("ui_cancel") and options_panel != null and options_panel.visible:
		if telemetry_consent_layer != null and telemetry_consent_layer.visible:
			return
		_show_root_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and glossary_panel != null and glossary_panel.visible:
		_show_root_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and difficulty_selector_panel != null and difficulty_selector_panel.visible:
		_show_root_panel()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.08, 1.0)
	add_child(backdrop)

	atmosphere_band = Panel.new()
	atmosphere_band.set_anchors_preset(Control.PRESET_CENTER)
	atmosphere_band.position = Vector2(-310.0, -330.0)
	atmosphere_band.custom_minimum_size = Vector2(620.0, 660.0)
	atmosphere_band.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.10, 0.16, 0.42), Color(0.12, 0.24, 0.38, 0.20), 26, 1))
	add_child(atmosphere_band)

	root_panel = Panel.new()
	root_panel.set_anchors_preset(Control.PRESET_CENTER)
	root_panel.position = Vector2(-490.0, -320.0)
	root_panel.custom_minimum_size = Vector2(980.0, 640.0)
	root_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.09, 0.13, 0.94), Color(0.34, 0.56, 0.84, 0.76), 22, 2))
	add_child(root_panel)

	var shell := HBoxContainer.new()
	shell.position = Vector2(30.0, 30.0)
	shell.custom_minimum_size = Vector2(920.0, 580.0)
	shell.add_theme_constant_override("separation", 24)
	root_panel.add_child(shell)

	var hero_panel := Panel.new()
	hero_panel.custom_minimum_size = Vector2(362.0, 580.0)
	hero_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.09, 0.15, 0.24, 0.82), Color(0.30, 0.48, 0.72, 0.46), 20, 2))
	shell.add_child(hero_panel)

	var hero_content := VBoxContainer.new()
	hero_content.position = Vector2(28.0, 26.0)
	hero_content.custom_minimum_size = Vector2(306.0, 528.0)
	hero_content.add_theme_constant_override("separation", 10)
	hero_panel.add_child(hero_content)

	var hero_spacer_top := Control.new()
	hero_spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_content.add_child(hero_spacer_top)

	var title := Label.new()
	title.text = "Abyssal Descent"
	title.custom_minimum_size = Vector2(306.0, 72.0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	hero_content.add_child(title)

	quote_wrapper = Control.new()
	quote_wrapper.custom_minimum_size = Vector2(306.0, 72.0)
	hero_content.add_child(quote_wrapper)

	flavor_quote_label = RichTextLabel.new()
	flavor_quote_label.bbcode_enabled = true
	flavor_quote_label.fit_content = true
	flavor_quote_label.scroll_active = false
	flavor_quote_label.custom_minimum_size = Vector2(306.0, 72.0)
	flavor_quote_label.add_theme_font_size_override("normal_font_size", 20)
	flavor_quote_label.add_theme_color_override("default_color", Color(0.72, 0.86, 1.0, 0.92))
	flavor_quote_label.text = "[center][wave amp=14.0 freq=3.0]" + _pick_menu_quote() + "[/wave][/center]"
	quote_wrapper.add_child(flavor_quote_label)

	var hero_spacer := Control.new()
	hero_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_content.add_child(hero_spacer)

	var action_panel := Panel.new()
	action_panel.custom_minimum_size = Vector2(534.0, 580.0)
	action_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.11, 0.16, 0.88), Color(0.22, 0.36, 0.52, 0.44), 20, 2))
	shell.add_child(action_panel)

	var action_content := VBoxContainer.new()
	action_content.position = Vector2(32.0, 30.0)
	action_content.custom_minimum_size = Vector2(470.0, 520.0)
	action_content.add_theme_constant_override("separation", 14)
	action_panel.add_child(action_content)

	var action_spacer_top := Control.new()
	action_spacer_top.custom_minimum_size = Vector2(470.0, 32.0)
	action_content.add_child(action_spacer_top)

	var actions := VBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 14)
	action_content.add_child(actions)

	primary_run_button = _make_menu_button("Begin Descent", true)
	primary_run_button.pressed.connect(_on_primary_run_pressed)
	actions.add_child(primary_run_button)

	var endless_button := _make_menu_button("Endless Mode")
	endless_button.pressed.connect(_on_endless_pressed)
	actions.add_child(endless_button)

	var options_button := _make_menu_button("Options")
	options_button.pressed.connect(_on_options_pressed)
	actions.add_child(options_button)

	var glossary_button := _make_menu_button("Glossary")
	glossary_button.pressed.connect(_on_glossary_pressed)
	actions.add_child(glossary_button)

	var exit_button := _make_menu_button("Exit Game")
	exit_button.pressed.connect(_on_exit_pressed)
	actions.add_child(exit_button)

	var action_spacer_bottom := Control.new()
	action_spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_content.add_child(action_spacer_bottom)

	update_panel = _build_update_panel()
	update_panel.visible = false
	add_child(update_panel)

	_refresh_primary_run_button()
	primary_run_button.grab_focus()

	options_panel = _build_options_panel()
	options_panel.visible = false
	add_child(options_panel)

	glossary_panel = _build_glossary_panel()
	glossary_panel.visible = false
	add_child(glossary_panel)
	
	difficulty_selector_panel = _build_difficulty_selector_panel()
	difficulty_selector_panel.visible = false
	add_child(difficulty_selector_panel)

	telemetry_consent_layer = _build_telemetry_consent_layer()
	telemetry_consent_layer.visible = false
	add_child(telemetry_consent_layer)

	update_prompt_layer = _build_update_prompt_layer()
	update_prompt_layer.visible = false
	add_child(update_prompt_layer)
	_show_root_panel(false)

func _apply_menu_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var fit_scale := minf(1.0, minf(viewport_size.x / MENU_LAYOUT_BASE_SIZE.x, viewport_size.y / MENU_LAYOUT_BASE_SIZE.y))
	if root_panel != null:
		_set_centered_panel_layout(root_panel, Vector2(980.0, 640.0), fit_scale, viewport_size)
	if options_panel != null:
		_set_centered_panel_layout(options_panel, Vector2(760.0, 700.0), fit_scale, viewport_size)
	if glossary_panel != null:
		_set_centered_panel_layout(glossary_panel, Vector2(980.0, 680.0), fit_scale, viewport_size)
	if difficulty_selector_panel != null:
		_set_centered_panel_layout(difficulty_selector_panel, Vector2(1020.0, 720.0), fit_scale, viewport_size)
	if update_panel != null and root_panel != null:
		var update_base_size := Vector2(470.0, 190.0)
		update_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		update_panel.size = update_base_size
		update_panel.scale = Vector2(fit_scale, fit_scale)
		var vertical_gap := 16.0 * fit_scale
		var root_scaled_size := root_panel.size * root_panel.scale
		update_panel.position = Vector2(root_panel.position.x, root_panel.position.y + root_scaled_size.y + vertical_gap)
	if atmosphere_band != null:
		_set_centered_panel_layout(atmosphere_band, Vector2(620.0, 660.0), fit_scale, viewport_size)

func _set_centered_panel_layout(panel: Panel, base_size: Vector2, panel_scale: float, viewport_size: Vector2) -> void:
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = base_size
	panel.scale = Vector2(panel_scale, panel_scale)
	var scaled_size := base_size * panel_scale
	panel.position = (viewport_size - scaled_size) * 0.5

func _make_menu_button(text: String, emphasize: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(470.0, 64.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68, 0.90))
	if emphasize:
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.16, 0.27, 0.42, 0.95), Color(0.76, 0.90, 1.0, 0.92), 16, 2))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.19, 0.32, 0.50, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.12, 0.22, 0.34, 0.98), Color(0.92, 0.98, 1.0, 1.0), 16, 2))
	else:
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 16, 2))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 16, 2))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 16, 2))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 16, 2))
	return button

func _make_panel_back_button() -> Button:
	var button := Button.new()
	button.text = "Back"
	button.custom_minimum_size = Vector2(180.0, 46.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68, 0.90))
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 16, 2))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 16, 2))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 16, 2))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 16, 2))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 16, 2))
	return button

func _make_panel_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style

func _make_button_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := _make_panel_style(bg_color, border_color, corner_radius, border_width)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style

func _apply_option_selector_theme(selector: OptionButton) -> void:
	if selector == null:
		return
	selector.alignment = HORIZONTAL_ALIGNMENT_LEFT
	selector.add_theme_font_size_override("font_size", 18)
	selector.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	selector.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	selector.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	selector.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 14, 2))
	selector.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 14, 2))
	selector.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 14, 2))
	selector.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 14, 2))
	selector.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 14, 2))

func _apply_difficulty_button_theme(button: Button, state: String) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.56, 0.62, 0.68, 0.86))
	match state:
		"current":
			button.add_theme_stylebox_override("normal", _make_button_style(Color(0.18, 0.30, 0.47, 0.96), Color(0.88, 0.97, 1.0, 1.0), 18, 2))
			button.add_theme_stylebox_override("hover", _make_button_style(Color(0.20, 0.34, 0.53, 0.98), Color(0.94, 0.99, 1.0, 1.0), 18, 2))
			button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.14, 0.24, 0.38, 0.98), Color(0.95, 1.0, 1.0, 1.0), 18, 2))
		"revealed":
			button.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.96), Color(0.44, 0.66, 0.88, 0.86), 18, 2))
			button.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.68, 0.86, 1.0, 0.94), 18, 2))
			button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.78, 0.92, 1.0, 0.96), 18, 2))
		_:
			button.add_theme_stylebox_override("normal", _make_button_style(Color(0.08, 0.09, 0.12, 0.86), Color(0.24, 0.28, 0.34, 0.60), 18, 2))
			button.add_theme_stylebox_override("hover", _make_button_style(Color(0.08, 0.09, 0.12, 0.86), Color(0.24, 0.28, 0.34, 0.60), 18, 2))
			button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.09, 0.12, 0.86), Color(0.24, 0.28, 0.34, 0.60), 18, 2))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.14, 0.22, 0.32, 0.98), Color(0.92, 0.98, 1.0, 1.0), 18, 2))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.09, 0.12, 0.86), Color(0.24, 0.28, 0.34, 0.60), 18, 2))

func _pick_menu_quote() -> String:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	var outcome := "none"
	if run_context != null:
		outcome = String(run_context.get_last_run_outcome())
	match outcome:
		"death":
			return _pick_random_quote(MENU_QUOTES_AFTER_DEATH)
		"clear":
			return _pick_random_quote(MENU_QUOTES_AFTER_CLEAR)
		_:
			return MENU_QUOTE_NEUTRAL

func _pick_random_quote(quotes: Array) -> String:
	if quotes.is_empty():
		return MENU_QUOTE_NEUTRAL
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return String(quotes[rng.randi_range(0, quotes.size() - 1)])

func _show_root_panel(animate: bool = true) -> void:
	if root_panel != null:
		root_panel.visible = true
		if animate:
			_animate_panel_in(root_panel, Vector2(0.0, 14.0))
	if options_panel != null:
		options_panel.visible = false
	if glossary_panel != null:
		glossary_panel.visible = false
	if difficulty_selector_panel != null:
		difficulty_selector_panel.visible = false

func _show_options_panel() -> void:
	if root_panel != null:
		root_panel.visible = true
	if options_panel != null:
		options_panel.visible = true
	if glossary_panel != null:
		glossary_panel.visible = false
	if difficulty_selector_panel != null:
		difficulty_selector_panel.visible = false

func _show_glossary_panel() -> void:
	if root_panel != null:
		root_panel.visible = true
	if options_panel != null:
		options_panel.visible = false
	if glossary_panel != null:
		glossary_panel.visible = true
	if difficulty_selector_panel != null:
		difficulty_selector_panel.visible = false

func _show_difficulty_selector() -> void:
	if root_panel != null:
		root_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	if glossary_panel != null:
		glossary_panel.visible = false
	if difficulty_selector_panel != null:
		difficulty_selector_panel.visible = true
		_animate_panel_in(difficulty_selector_panel, Vector2(0.0, 28.0))

func _play_menu_intro() -> void:
	if atmosphere_band != null:
		atmosphere_band.modulate.a = 0.0
		atmosphere_band.position += Vector2(-10.0, 0.0)
	if root_panel != null:
		root_panel.modulate.a = 0.0
		root_panel.position += Vector2(0.0, 14.0)
	if flavor_quote_label != null:
		flavor_quote_label.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	if atmosphere_band != null:
		tween.tween_property(atmosphere_band, "modulate:a", 1.0, 0.18)
		tween.tween_property(atmosphere_band, "position", atmosphere_band.position + Vector2(10.0, 0.0), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if root_panel != null:
		tween.tween_property(root_panel, "modulate:a", 1.0, 0.16)
		tween.tween_property(root_panel, "position", root_panel.position - Vector2(0.0, 14.0), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if flavor_quote_label != null:
		tween.tween_property(flavor_quote_label, "modulate:a", 1.0, 0.28).set_delay(0.06)
		call_deferred("_start_quote_idle_animation")

func _start_quote_idle_animation() -> void:
	if flavor_quote_label == null or quote_wrapper == null:
		return
	flavor_quote_label.modulate = QUOTE_COLOR_COOL
	_quote_pulse_time = 0.0
	_quote_pulse_active = true
	set_process(true)

func _process(delta: float) -> void:
	if not _quote_pulse_active or flavor_quote_label == null:
		return
	_quote_pulse_time += delta
	var t := (sin(_quote_pulse_time * QUOTE_PULSE_SPEED) + 1.0) * 0.5
	flavor_quote_label.modulate = QUOTE_COLOR_COOL.lerp(QUOTE_COLOR_WARM, t)

func _animate_panel_in(panel: Control, offset: Vector2) -> void:
	if panel == null:
		return
	var target_position := panel.position
	panel.modulate.a = 0.0
	panel.position = target_position + offset
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.14)
	tween.tween_property(panel, "position", target_position, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _build_options_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-380.0, -350.0)
	panel.custom_minimum_size = Vector2(760.0, 700.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.06, 0.1, 0.97), Color(0.44, 0.7, 0.96, 0.74), 20, 2))

	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 52)
	layout.add_theme_constant_override("margin_right", 52)
	layout.add_theme_constant_override("margin_top", 40)
	layout.add_theme_constant_override("margin_bottom", 36)
	panel.add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 16)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Options"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(title)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(180.0, 2.0)
	accent.color = Color(0.62, 0.78, 0.96, 0.65)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(accent)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	var scroll_content := MarginContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll_content.add_theme_constant_override("margin_right", 18)
	scroll.add_child(scroll_content)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rows.add_theme_constant_override("separation", 18)
	scroll_content.add_child(rows)

	var master_row := VBoxContainer.new()
	master_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_row.add_theme_constant_override("separation", 6)
	rows.add_child(master_row)

	var master_label := Label.new()
	master_label.text = "Master Volume"
	master_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_label.add_theme_font_size_override("font_size", 18)
	master_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.96))
	master_row.add_child(master_label)

	var master_controls := HBoxContainer.new()
	master_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_controls.add_theme_constant_override("separation", 14)
	master_row.add_child(master_controls)

	master_slider = HSlider.new()
	master_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_slider.min_value = 0.0
	master_slider.max_value = 100.0
	master_slider.step = 1.0
	master_slider.value_changed.connect(_on_master_volume_changed)
	master_controls.add_child(master_slider)

	master_value_label = Label.new()
	master_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	master_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	master_controls.add_child(master_value_label)

	var music_row := VBoxContainer.new()
	music_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_theme_constant_override("separation", 6)
	rows.add_child(music_row)

	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_label.add_theme_font_size_override("font_size", 18)
	music_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.96))
	music_row.add_child(music_label)

	var music_controls := HBoxContainer.new()
	music_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_controls.add_theme_constant_override("separation", 14)
	music_row.add_child(music_controls)

	music_slider = HSlider.new()
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.min_value = 0.0
	music_slider.max_value = 100.0
	music_slider.step = 1.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	music_controls.add_child(music_slider)

	music_value_label = Label.new()
	music_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_controls.add_child(music_value_label)

	var sfx_row := VBoxContainer.new()
	sfx_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_theme_constant_override("separation", 6)
	rows.add_child(sfx_row)

	var sfx_label := Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_label.add_theme_font_size_override("font_size", 18)
	sfx_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.96))
	sfx_row.add_child(sfx_label)

	var sfx_controls := HBoxContainer.new()
	sfx_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_controls.add_theme_constant_override("separation", 14)
	sfx_row.add_child(sfx_controls)

	sfx_slider = HSlider.new()
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 100.0
	sfx_slider.step = 1.0
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_controls.add_child(sfx_slider)

	sfx_value_label = Label.new()
	sfx_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_controls.add_child(sfx_value_label)

	var display_mode_row := VBoxContainer.new()
	display_mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_mode_row.add_theme_constant_override("separation", 6)
	rows.add_child(display_mode_row)

	var display_mode_label := Label.new()
	display_mode_label.text = "Display Mode"
	display_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_mode_label.add_theme_font_size_override("font_size", 18)
	display_mode_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.96))
	display_mode_row.add_child(display_mode_label)

	display_mode_selector = OptionButton.new()
	display_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_mode_selector.custom_minimum_size = Vector2(0.0, 50.0)
	_apply_option_selector_theme(display_mode_selector)
	display_mode_selector.item_selected.connect(_on_display_mode_selected)
	display_mode_row.add_child(display_mode_selector)

	var resolution_row := VBoxContainer.new()
	resolution_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_row.add_theme_constant_override("separation", 6)
	rows.add_child(resolution_row)

	var resolution_label := Label.new()
	resolution_label.text = "Resolution"
	resolution_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_label.add_theme_font_size_override("font_size", 18)
	resolution_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.96))
	resolution_row.add_child(resolution_label)

	resolution_selector = OptionButton.new()
	resolution_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_selector.custom_minimum_size = Vector2(0.0, 50.0)
	_apply_option_selector_theme(resolution_selector)
	resolution_selector.item_selected.connect(_on_resolution_selected)
	resolution_row.add_child(resolution_selector)

	resolution_hint_label = Label.new()
	resolution_hint_label.text = "Applies immediately and keeps the window centered."
	resolution_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resolution_hint_label.add_theme_font_size_override("font_size", 14)
	resolution_hint_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.90, 0.76))
	resolution_row.add_child(resolution_hint_label)

	var telemetry_row := VBoxContainer.new()
	telemetry_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_row.add_theme_constant_override("separation", 6)
	rows.add_child(telemetry_row)

	telemetry_upload_checkbox = CheckBox.new()
	telemetry_upload_checkbox.text = "Send Anonymous Telemetry"
	telemetry_upload_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_upload_checkbox.add_theme_font_size_override("font_size", 18)
	telemetry_upload_checkbox.button_pressed = false
	telemetry_upload_checkbox.toggled.connect(_on_telemetry_upload_toggled)
	telemetry_row.add_child(telemetry_upload_checkbox)

	var telemetry_hint := Label.new()
	telemetry_hint.text = "Uploads run summaries in the background to help tune balance."
	telemetry_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	telemetry_hint.add_theme_font_size_override("font_size", 14)
	telemetry_hint.add_theme_color_override("font_color", Color(0.70, 0.80, 0.90, 0.76))
	telemetry_row.add_child(telemetry_hint)

	var back_button := _make_panel_back_button()
	back_button.pressed.connect(func() -> void:
		_show_root_panel()
	)
	stack.add_child(back_button)

	return panel

func _build_update_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(470.0, 170.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.08, 0.13, 0.90), Color(0.36, 0.64, 0.88, 0.74), 16, 2))

	var content := MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 14)
	content.add_theme_constant_override("margin_right", 14)
	content.add_theme_constant_override("margin_top", 14)
	content.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(content)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	content.add_child(stack)

	var title := Label.new()
	title.text = "Game Update"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 0.98))
	stack.add_child(title)

	update_status_label = Label.new()
	update_status_label.text = "Checking for updates..."
	update_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_status_label.add_theme_font_size_override("font_size", 17)
	update_status_label.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0, 0.96))
	stack.add_child(update_status_label)

	update_detail_label = Label.new()
	update_detail_label.text = "Current version: unknown"
	update_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_detail_label.add_theme_font_size_override("font_size", 14)
	update_detail_label.add_theme_color_override("font_color", Color(0.68, 0.80, 0.92, 0.84))
	stack.add_child(update_detail_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	stack.add_child(actions)

	update_action_button = _make_menu_button("Open Releases", true)
	update_action_button.custom_minimum_size = Vector2(0.0, 50.0)
	update_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_action_button.pressed.connect(_on_update_action_pressed)
	actions.add_child(update_action_button)

	update_check_button = _make_menu_button("Check Again")
	update_check_button.custom_minimum_size = Vector2(130.0, 50.0)
	update_check_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	update_check_button.pressed.connect(_on_update_check_pressed)
	actions.add_child(update_check_button)

	return panel

func _build_update_prompt_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.05, 0.76)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(700.0, 252.0)
	panel.position = Vector2(-350.0, -126.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.08, 0.12, 0.97), Color(0.44, 0.7, 0.96, 0.74), 18, 2))
	layer.add_child(panel)

	var content := MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 34)
	content.add_theme_constant_override("margin_right", 34)
	content.add_theme_constant_override("margin_top", 22)
	content.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(content)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_theme_constant_override("separation", 10)
	content.add_child(stack)

	update_prompt_title_label = Label.new()
	update_prompt_title_label.text = "Update Available"
	update_prompt_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_prompt_title_label.add_theme_font_size_override("font_size", 34)
	update_prompt_title_label.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 0.98))
	stack.add_child(update_prompt_title_label)

	update_prompt_body_label = Label.new()
	update_prompt_body_label.text = "A new version is ready to install."
	update_prompt_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_prompt_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_prompt_body_label.add_theme_font_size_override("font_size", 18)
	update_prompt_body_label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.98, 0.94))
	stack.add_child(update_prompt_body_label)

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 14)
	stack.add_child(actions)

	var update_now_button := _make_menu_button("Update Now", true)
	update_now_button.custom_minimum_size = Vector2(0.0, 58.0)
	update_now_button.pressed.connect(func() -> void:
		if update_prompt_layer != null:
			update_prompt_layer.visible = false
		_on_update_action_pressed()
	)
	actions.add_child(update_now_button)

	var not_now_button := _make_menu_button("Not Now")
	not_now_button.custom_minimum_size = Vector2(0.0, 58.0)
	not_now_button.pressed.connect(func() -> void:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null and update_service != null and not String(update_service.latest_version).is_empty():
			run_context.set_skipped_update_version(String(update_service.latest_version), true)
		if update_prompt_layer != null:
			update_prompt_layer.visible = false
	)
	actions.add_child(not_now_button)

	return layer

func _start_update_check() -> void:
	if update_service == null:
		update_service = UPDATE_SERVICE_SCRIPT.new()
		add_child(update_service)
		update_service.state_changed.connect(_on_update_service_state_changed)
		update_service.check_finished.connect(_on_update_service_check_finished)
		update_service.download_finished.connect(_on_update_service_download_finished)
	update_service.initialize(_current_game_version())
	update_service.configure_runtime_mode(_is_editor_run(), _is_debug_update_prompt_forced())
	_refresh_update_ui()
	update_check_was_manual = false
	update_service.request_check(false)

func _on_update_check_pressed() -> void:
	if update_service == null:
		return
	update_check_was_manual = true
	update_service.request_check(true)

func _on_update_service_state_changed() -> void:
	if update_service == null:
		return
	if update_status_label != null:
		update_status_label.text = String(update_service.status_text)
	if update_detail_label != null:
		update_detail_label.text = String(update_service.detail_text)
	_refresh_update_ui()

func _on_update_service_check_finished() -> void:
	if not update_check_was_manual:
		_maybe_show_update_prompt()
	update_check_was_manual = false
	_refresh_update_ui()

func _on_update_service_download_finished(success: bool, _message: String) -> void:
	if update_service == null:
		return
	if not bool(update_service.action_enabled):
		_refresh_update_ui()
		return
	if success and update_service.launch_downloaded_installer():
		if update_status_label != null:
			update_status_label.text = "Update ready. Closing game to apply..."
		if update_detail_label != null:
			update_detail_label.text = "The game will relaunch automatically once updated."
		_refresh_update_ui()
		get_tree().quit()
		return
	if update_status_label != null:
		update_status_label.text = "Could not install automatically. Opening release page."
	if update_detail_label != null:
		update_detail_label.text = "Download may have failed or installer launch was blocked."
	update_service.open_release_page()
	_refresh_update_ui()

func _maybe_show_update_prompt() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	if update_service == null:
		return
	if _is_editor_run() and not bool(update_service.force_prompt_mode):
		return
	if not update_service.should_prompt_for_update(String(run_context.get_skipped_update_version())):
		return
	if telemetry_consent_layer != null and telemetry_consent_layer.visible:
		update_prompt_pending = true
		return
	_show_update_prompt()

func _show_update_prompt() -> void:
	if update_prompt_layer == null:
		return
	if update_service == null:
		return
	var latest_version := String(update_service.latest_version)
	if update_prompt_title_label != null:
		update_prompt_title_label.text = "Update %s Available" % latest_version
	if update_prompt_body_label != null:
		update_prompt_body_label.text = "Install %s now? The game will close while the installer opens." % latest_version
	update_prompt_pending = false
	update_prompt_layer.visible = true

func _show_pending_update_prompt() -> void:
	if not update_prompt_pending:
		return
	if telemetry_consent_layer != null and telemetry_consent_layer.visible:
		return
	_show_update_prompt()

func _on_update_action_pressed() -> void:
	if update_service == null:
		return
	if not bool(update_service.action_enabled):
		if update_prompt_layer != null:
			update_prompt_layer.visible = false
		_refresh_update_ui()
		return
	if update_service.download_in_progress:
		return
	if update_service.update_available:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null:
			run_context.clear_skipped_update_version(true)
		if update_service.request_download():
			return
	update_service.open_release_page()

func _refresh_update_ui() -> void:
	if update_action_button == null or update_panel == null:
		return
	var show_update_panel := false
	if update_service != null:
		if _is_editor_run() and not bool(update_service.force_prompt_mode):
			show_update_panel = false
		else:
			show_update_panel = bool(update_service.update_available) or bool(update_service.force_prompt_mode)
	update_panel.visible = show_update_panel
	if not show_update_panel:
		return
	if update_service == null:
		update_action_button.text = "Open Releases"
		update_action_button.disabled = false
		if update_check_button != null:
			update_check_button.disabled = false
		return
	var controls_disabled := bool(update_service.check_in_progress) or bool(update_service.download_in_progress)
	if bool(update_service.download_in_progress):
		update_action_button.text = "Downloading..."
		update_action_button.disabled = true
	elif bool(update_service.update_available):
		update_action_button.text = "Update to %s" % String(update_service.latest_version)
		update_action_button.disabled = controls_disabled
	else:
		update_action_button.text = "Open Releases"
		update_action_button.disabled = controls_disabled
	if update_check_button != null:
		update_check_button.disabled = controls_disabled

func _current_game_version() -> String:
	var stamped_version := _read_build_version_stamp()
	if not stamped_version.is_empty() and stamped_version != "dev":
		print("[Version] Using stamped build version: %s" % stamped_version)
		return stamped_version
	var configured_version := String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if not configured_version.is_empty():
		print("[Version] Using project config version: %s" % configured_version)
		return configured_version
	var fallback_version := "dev"
	if not OS.has_feature("editor"):
		print("[Version] WARNING: Packaged build with no version stamp. Defaulting to dev.")
	else:
		print("[Version] Editor mode, using dev.")
	return fallback_version

func _read_build_version_stamp() -> String:
	if not ResourceLoader.exists("res://build_version.txt"):
		return ""
	var stamp_file := FileAccess.open("res://build_version.txt", FileAccess.READ)
	if stamp_file == null:
		return ""
	return stamp_file.get_as_text().strip_edges()

func _is_editor_run() -> bool:
	return OS.has_feature("editor")

func _is_debug_update_prompt_forced() -> bool:
	var debug_values := _read_main_debug_settings_values()
	if debug_values.is_empty():
		return false
	if not bool(debug_values.get("enabled", false)):
		return false
	return bool(debug_values.get("force_update_prompt_on_menu", false))

func _on_primary_run_pressed() -> void:
	if _has_saved_run():
		_on_continue_pressed()
		return
	_clear_saved_run()
	_set_run_mode(ENUMS.RunMode.STANDARD)
	if difficulty_selector_panel != null:
		_update_difficulty_selector()
		_show_difficulty_selector()

func _on_continue_pressed() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	run_context.request_resume_saved_run()
	get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_endless_pressed() -> void:
	_clear_saved_run()
	_set_run_mode(ENUMS.RunMode.ENDLESS)
	get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_options_pressed() -> void:
	_show_options_panel()

func _on_glossary_pressed() -> void:
	_show_glossary_panel()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _build_glossary_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-490.0, -340.0)
	panel.custom_minimum_size = Vector2(980.0, 680.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.06, 0.1, 0.97), Color(0.44, 0.7, 0.96, 0.74), 20, 2))

	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 44)
	layout.add_theme_constant_override("margin_right", 44)
	layout.add_theme_constant_override("margin_top", 36)
	layout.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Glossary"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(title)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(180.0, 2.0)
	accent.color = Color(0.62, 0.78, 0.96, 0.65)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(accent)

	var body_panel := Panel.new()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.03, 0.05, 0.08, 0.72), Color(0.26, 0.4, 0.58, 0.56), 12, 1))
	stack.add_child(body_panel)

	var body := RichTextLabel.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 16.0
	body.offset_top = 12.0
	body.offset_right = -16.0
	body.offset_bottom = -12.0
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.selection_enabled = false
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", Color(0.86, 0.94, 1.0, 0.96))
	body.text = GLOSSARY_DATA.glossary_bbcode()
	body_panel.add_child(body)

	var back_button := _make_panel_back_button()
	back_button.pressed.connect(func() -> void:
		_show_root_panel()
	)
	stack.add_child(back_button)

	return panel

func _build_difficulty_selector_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-510.0, -360.0)
	panel.custom_minimum_size = Vector2(1020.0, 720.0)
	panel.size = Vector2(1020.0, 720.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.06, 0.1, 0.97), Color(0.44, 0.7, 0.96, 0.74), 20, 2))

	var layout := MarginContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 60)
	layout.add_theme_constant_override("margin_right", 60)
	layout.add_theme_constant_override("margin_top", 44)
	layout.add_theme_constant_override("margin_bottom", 44)
	panel.add_child(layout)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 18)
	layout.add_child(stack)

	var title := Label.new()
	title.text = "Set Your Bearing"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(title)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(180.0, 2.0)
	accent.color = Color(0.62, 0.78, 0.96, 0.65)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(accent)

	var intro := Label.new()
	intro.text = "Choose the burden you will carry."
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 0.78))
	stack.add_child(intro)

	var tier_buttons_container := VBoxContainer.new()
	tier_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_buttons_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tier_buttons_container.add_theme_constant_override("separation", 14)
	stack.add_child(tier_buttons_container)

	difficulty_tier_buttons.clear()
	difficulty_tier_name_labels.clear()
	difficulty_tier_desc_labels.clear()
	for tier in range(4):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 84.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.text = ""
		button.pressed.connect(_on_difficulty_tier_selected.bindv([tier]))
		_apply_difficulty_button_theme(button, "revealed")
		tier_buttons_container.add_child(button)

		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 22
		content.offset_right = -22
		content.offset_top = 12
		content.offset_bottom = -12
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 4)
		button.add_child(content)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 26)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
		name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)

		var desc_label := Label.new()
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 15)
		desc_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96, 0.78))
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(desc_label)

		difficulty_tier_buttons.append(button)
		difficulty_tier_name_labels.append(name_label)
		difficulty_tier_desc_labels.append(desc_label)

	var back_button := _make_panel_back_button()
	back_button.pressed.connect(func() -> void:
		_show_root_panel()
	)
	stack.add_child(back_button)

	return panel

func _update_difficulty_selector() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	var current_tier: int = int(run_context.get_current_difficulty_tier())
	var highest_unlocked_tier: int = int(run_context.get_highest_unlocked_difficulty_tier())
	for i in range(difficulty_tier_buttons.size()):
		var button := difficulty_tier_buttons[i]
		var name_label := difficulty_tier_name_labels[i]
		var desc_label := difficulty_tier_desc_labels[i]
		var config := DIFFICULTY_CONFIG.get_tier_config(i)
		var tier_name: String = config.get("name", "Unknown")
		var tier_desc: String = config.get("description", "")
		var is_unlocked := i <= highest_unlocked_tier
		var is_selected := i == current_tier
		if is_unlocked:
			name_label.text = tier_name
			desc_label.text = tier_desc
			desc_label.visible = true
		else:
			name_label.text = "\u2014  Sealed  \u2014"
			desc_label.text = ""
			desc_label.visible = false
		button.disabled = not is_unlocked
		if is_selected:
			_apply_difficulty_button_theme(button, "current")
		elif is_unlocked:
			_apply_difficulty_button_theme(button, "revealed")
		else:
			_apply_difficulty_button_theme(button, "sealed")

func _on_difficulty_tier_selected(tier: int) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	
	if run_context.set_difficulty_tier(tier):
		difficulty_selector_panel.visible = false
		get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_master_volume_changed(value: float) -> void:
	_apply_options(value, music_slider.value, sfx_slider.value)

func _on_music_volume_changed(value: float) -> void:
	_apply_options(master_slider.value, value, sfx_slider.value)

func _on_sfx_volume_changed(value: float) -> void:
	_apply_options(master_slider.value, music_slider.value, value)

func _on_resolution_selected(index: int) -> void:
	if resolution_selector == null:
		return
	var metadata: Variant = resolution_selector.get_item_metadata(index)
	if not (metadata is Dictionary):
		return
	var resolution := metadata as Dictionary
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_resolution_settings(int(resolution.get("width", 0)), int(resolution.get("height", 0)), true)

func _on_display_mode_selected(index: int) -> void:
	if display_mode_selector == null:
		return
	var metadata: Variant = display_mode_selector.get_item_metadata(index)
	var selected_mode := String(metadata)
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_display_mode(selected_mode, true)
	_sync_options_from_context()

func _on_telemetry_upload_toggled(enabled: bool) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	run_context.set_telemetry_upload_enabled(enabled, true, true)

func _sync_options_from_context() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if master_slider != null:
		master_slider.set_block_signals(true)
	if music_slider != null:
		music_slider.set_block_signals(true)
	if sfx_slider != null:
		sfx_slider.set_block_signals(true)
	if display_mode_selector != null:
		display_mode_selector.set_block_signals(true)
	if resolution_selector != null:
		resolution_selector.set_block_signals(true)
	if telemetry_upload_checkbox != null:
		telemetry_upload_checkbox.set_block_signals(true)
	if run_context == null:
		master_slider.value = _db_to_percent(0.0)
		music_slider.value = _db_to_percent(-20.0)
		sfx_slider.value = _db_to_percent(0.0)
		_populate_display_mode_selector([], SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_populate_resolution_selector([], SETTINGS_STORE.DEFAULT_RESOLUTION_WIDTH, SETTINGS_STORE.DEFAULT_RESOLUTION_HEIGHT)
		if telemetry_upload_checkbox != null:
			telemetry_upload_checkbox.button_pressed = SETTINGS_STORE.DEFAULT_TELEMETRY_UPLOAD_ENABLED
		if master_slider != null:
			master_slider.set_block_signals(false)
		if music_slider != null:
			music_slider.set_block_signals(false)
		if sfx_slider != null:
			sfx_slider.set_block_signals(false)
		if display_mode_selector != null:
			display_mode_selector.set_block_signals(false)
		if resolution_selector != null:
			resolution_selector.set_block_signals(false)
		if telemetry_upload_checkbox != null:
			telemetry_upload_checkbox.set_block_signals(false)
		_update_resolution_control_state(SETTINGS_STORE.DEFAULT_DISPLAY_MODE)
		_update_option_labels()
		return
	master_slider.value = _db_to_percent(float(run_context.get("master_volume_db")))
	music_slider.value = _db_to_percent(float(run_context.get("music_volume_db")))
	sfx_slider.value = _db_to_percent(float(run_context.get("sfx_volume_db")))
	var mode_options: Array[Dictionary] = run_context.get_display_mode_options() as Array[Dictionary]
	_populate_display_mode_selector(mode_options, String(run_context.get("display_mode")))
	var resolution_options: Array[Dictionary] = run_context.get_supported_resolution_options() as Array[Dictionary]
	_populate_resolution_selector(
		resolution_options,
		int(run_context.get("resolution_width")),
		int(run_context.get("resolution_height"))
	)
	if telemetry_upload_checkbox != null:
		telemetry_upload_checkbox.button_pressed = bool(run_context.get("telemetry_upload_enabled"))
	if master_slider != null:
		master_slider.set_block_signals(false)
	if music_slider != null:
		music_slider.set_block_signals(false)
	if sfx_slider != null:
		sfx_slider.set_block_signals(false)
	if display_mode_selector != null:
		display_mode_selector.set_block_signals(false)
	if resolution_selector != null:
		resolution_selector.set_block_signals(false)
	if telemetry_upload_checkbox != null:
		telemetry_upload_checkbox.set_block_signals(false)
	_update_resolution_control_state(String(run_context.get("display_mode")))
	_update_option_labels()

func _build_telemetry_consent_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640.0, 300.0)
	panel.position = Vector2(-320.0, -150.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.08, 0.12, 0.97), Color(0.44, 0.7, 0.96, 0.74), 18, 2))
	layer.add_child(panel)

	var content := MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 30)
	content.add_theme_constant_override("margin_right", 30)
	content.add_theme_constant_override("margin_top", 26)
	content.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(content)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	content.add_child(stack)

	var title := Label.new()
	title.text = "Help Improve Balance"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	stack.add_child(title)

	var body := Label.new()
	body.text = "Allow anonymous run telemetry uploads? This sends run outcomes and combat summary data only."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color(0.82, 0.9, 0.98, 0.94))
	stack.add_child(body)

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 14)
	stack.add_child(actions)

	var allow_button := _make_menu_button("Allow", true)
	allow_button.custom_minimum_size = Vector2(0.0, 56.0)
	allow_button.pressed.connect(func() -> void:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null:
			run_context.set_telemetry_upload_enabled(true, true, true)
		_sync_options_from_context()
		if telemetry_consent_layer != null:
			telemetry_consent_layer.visible = false
		_show_pending_update_prompt()
	)
	actions.add_child(allow_button)

	var not_now_button := _make_menu_button("Not Now")
	not_now_button.custom_minimum_size = Vector2(0.0, 56.0)
	not_now_button.pressed.connect(func() -> void:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null:
			run_context.set_telemetry_upload_enabled(false, true, true)
		_sync_options_from_context()
		if telemetry_consent_layer != null:
			telemetry_consent_layer.visible = false
		_show_pending_update_prompt()
	)
	actions.add_child(not_now_button)

	return layer

func _maybe_show_telemetry_consent_prompt() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	if not run_context.should_prompt_telemetry_consent():
		return
	if telemetry_consent_layer != null:
		telemetry_consent_layer.visible = true

func _apply_options(master_percent: float, music_percent: float, sfx_percent: float) -> void:
	var master_db := _percent_to_db(master_percent)
	var music_db := _percent_to_db(music_percent)
	var sfx_db := _percent_to_db(sfx_percent)
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_audio_settings(master_db, music_db, sfx_db, true)
	_apply_menu_music_volume(music_db)
	_update_option_labels()

func _update_option_labels() -> void:
	if master_value_label != null:
		master_value_label.text = "%d%%" % int(round(master_slider.value))
	if music_value_label != null:
		music_value_label.text = "%d%%" % int(round(music_slider.value))
	if sfx_value_label != null:
		sfx_value_label.text = "%d%%" % int(round(sfx_slider.value))

func _populate_resolution_selector(options: Array[Dictionary], selected_width: int, selected_height: int) -> void:
	if resolution_selector == null:
		return
	resolution_selector.clear()
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
		resolution_selector.add_item(label)
		resolution_selector.set_item_metadata(index, option)
		if int(option.get("width", 0)) == selected_width and int(option.get("height", 0)) == selected_height:
			best_match = index
	if best_match == -1 and resolution_selector.item_count > 0:
		best_match = 0
	if best_match >= 0:
		resolution_selector.select(best_match)

func _populate_display_mode_selector(options: Array[Dictionary], selected_mode: String) -> void:
	if display_mode_selector == null:
		return
	display_mode_selector.clear()
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
		display_mode_selector.add_item(label)
		display_mode_selector.set_item_metadata(index, mode_id)
		if mode_id == selected_mode:
			best_match = index
	if best_match == -1 and display_mode_selector.item_count > 0:
		best_match = 0
	if best_match >= 0:
		display_mode_selector.select(best_match)

func _update_resolution_control_state(current_mode: String) -> void:
	var is_windowed := current_mode == SETTINGS_STORE.DISPLAY_MODE_WINDOWED
	if resolution_selector != null:
		resolution_selector.disabled = not is_windowed
	if resolution_hint_label != null:
		if is_windowed:
			resolution_hint_label.text = "Applies immediately and keeps the window centered."
		else:
			resolution_hint_label.text = "Disabled in fullscreen. Switch to Windowed to choose a resolution."

func _start_menu_music() -> void:
	if MENU_MUSIC == null:
		return
	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.stream = MENU_MUSIC
	menu_music_player.bus = "Master"
	menu_music_player.finished.connect(_on_menu_music_finished)
	add_child(menu_music_player)
	menu_music_player.play()
	_apply_menu_music_volume(_percent_to_db(music_slider.value))

func _on_menu_music_finished() -> void:
	if menu_music_player == null:
		return
	if AUDIO_LEVELS.is_muted_db(menu_music_player.volume_db):
		return
	menu_music_player.play(0.0)

func _apply_menu_music_volume(music_db: float) -> void:
	if menu_music_player == null:
		return
	var clamped_db := AUDIO_LEVELS.menu_music_db(music_db)
	menu_music_player.volume_db = clamped_db
	if AUDIO_LEVELS.is_muted_db(clamped_db):
		if menu_music_player.playing:
			menu_music_player.stop()
		return
	if not menu_music_player.playing and menu_music_player.stream != null:
		menu_music_player.play()

func _percent_to_db(percent: float) -> float:
	return AUDIO_LEVELS.percent_to_db(percent)

func _db_to_percent(db: float) -> float:
	return AUDIO_LEVELS.db_to_percent(db)

func _set_run_mode(mode: int) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_run_mode(mode)

func _refresh_primary_run_button() -> void:
	if primary_run_button == null:
		return
	primary_run_button.text = "Resume Descent" if _has_saved_run() else "Begin Descent"

func _has_saved_run() -> bool:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return false
	return bool(run_context.has_saved_run())

func _clear_saved_run() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	run_context.clear_active_run()
	run_context.clear_resume_saved_run_request()
