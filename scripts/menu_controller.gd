extends Control

const GAMEPLAY_SCENE_PATH := "res://scenes/Main.tscn"
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_MUSIC := preload("res://music/msx1.mp3")
const ENUMS := preload("res://scripts/shared/enums.gd")
const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")

var root_panel: Panel
var options_panel: Panel
var glossary_panel: Panel
var difficulty_selector_panel: Panel
var master_slider: HSlider
var music_slider: HSlider
var master_value_label: Label
var music_value_label: Label
var menu_music_player: AudioStreamPlayer
var primary_run_button: Button
var difficulty_tier_buttons: Array[Button] = []

func _ready() -> void:
	if _should_autostart_debug_encounter():
		call_deferred("_change_to_gameplay_scene")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()
	_sync_options_from_context()
	_start_menu_music()

func _change_to_gameplay_scene() -> void:
	if get_tree() != null:
		get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _should_autostart_debug_encounter() -> bool:
	var packed := load(GAMEPLAY_SCENE_PATH) as PackedScene
	if packed == null:
		return false
	var main_root := packed.instantiate()
	if main_root == null:
		return false
	var encounter_value: Variant = main_root.get("debug_start_encounter")
	main_root.queue_free()
	if encounter_value == null:
		return false
	return int(encounter_value) != 0

func _exit_tree() -> void:
	if menu_music_player != null and menu_music_player.playing:
		menu_music_player.stop()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and options_panel != null and options_panel.visible:
		options_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and glossary_panel != null and glossary_panel.visible:
		glossary_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and difficulty_selector_panel != null and difficulty_selector_panel.visible:
		difficulty_selector_panel.visible = false
		root_panel.visible = true
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.08, 1.0)
	add_child(backdrop)

	root_panel = Panel.new()
	root_panel.custom_minimum_size = Vector2(520.0, 520.0)
	root_panel.position = Vector2(700.0, 170.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.09, 0.13, 0.92)
	panel_style.border_color = Color(0.34, 0.56, 0.84, 0.76)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	root_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(root_panel)

	var title := Label.new()
	title.text = "Abyssal Descent"
	title.position = Vector2(0.0, 44.0)
	title.custom_minimum_size = Vector2(520.0, 46.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	root_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose your run"
	subtitle.position = Vector2(0.0, 98.0)
	subtitle.custom_minimum_size = Vector2(520.0, 24.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.84, 1.0, 0.9))
	root_panel.add_child(subtitle)

	primary_run_button = _make_menu_button("Standard Run", Vector2(120.0, 170.0))
	primary_run_button.pressed.connect(_on_primary_run_pressed)
	root_panel.add_child(primary_run_button)

	var endless_button := _make_menu_button("Endless Mode", Vector2(120.0, 242.0))
	endless_button.pressed.connect(_on_endless_pressed)
	root_panel.add_child(endless_button)

	var options_button := _make_menu_button("Options", Vector2(120.0, 314.0))
	options_button.pressed.connect(_on_options_pressed)
	root_panel.add_child(options_button)

	var glossary_button := _make_menu_button("Glossary", Vector2(120.0, 386.0))
	glossary_button.pressed.connect(_on_glossary_pressed)
	root_panel.add_child(glossary_button)

	var exit_button := _make_menu_button("Exit Game", Vector2(120.0, 458.0))
	exit_button.pressed.connect(_on_exit_pressed)
	root_panel.add_child(exit_button)
	_refresh_primary_run_button()

	options_panel = _build_options_panel()
	options_panel.visible = false
	add_child(options_panel)

	glossary_panel = _build_glossary_panel()
	glossary_panel.visible = false
	add_child(glossary_panel)
	
	difficulty_selector_panel = _build_difficulty_selector_panel()
	difficulty_selector_panel.visible = false
	add_child(difficulty_selector_panel)

func _make_menu_button(text: String, pos: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.custom_minimum_size = Vector2(280.0, 52.0)
	button.add_theme_font_size_override("font_size", 20)
	return button

func _build_options_panel() -> Panel:
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

	master_slider = HSlider.new()
	master_slider.position = Vector2(42.0, 112.0)
	master_slider.custom_minimum_size = Vector2(450.0, 24.0)
	master_slider.min_value = -40.0
	master_slider.max_value = 6.0
	master_slider.step = 1.0
	master_slider.value_changed.connect(_on_master_volume_changed)
	panel.add_child(master_slider)

	master_value_label = Label.new()
	master_value_label.position = Vector2(510.0, 108.0)
	master_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	master_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(master_value_label)

	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.position = Vector2(42.0, 164.0)
	music_label.custom_minimum_size = Vector2(260.0, 24.0)
	music_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(music_label)

	music_slider = HSlider.new()
	music_slider.position = Vector2(42.0, 192.0)
	music_slider.custom_minimum_size = Vector2(450.0, 24.0)
	music_slider.min_value = -60.0
	music_slider.max_value = -6.0
	music_slider.step = 1.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	panel.add_child(music_slider)

	music_value_label = Label.new()
	music_value_label.position = Vector2(510.0, 188.0)
	music_value_label.custom_minimum_size = Vector2(90.0, 24.0)
	music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(music_value_label)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.position = Vector2(230.0, 242.0)
	back_button.custom_minimum_size = Vector2(160.0, 42.0)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(func() -> void:
		options_panel.visible = false
	)
	panel.add_child(back_button)

	return panel

func _on_primary_run_pressed() -> void:
	if _has_saved_run():
		_on_continue_pressed()
		return
	_clear_saved_run()
	_set_run_mode(ENUMS.RunMode.STANDARD)
	## Show difficulty selector before starting
	if difficulty_selector_panel != null:
		_update_difficulty_selector()
		difficulty_selector_panel.visible = true
		if options_panel != null:
			options_panel.visible = false
		if glossary_panel != null:
			glossary_panel.visible = false

func _on_continue_pressed() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	if run_context.has_method("request_resume_saved_run"):
		run_context.call("request_resume_saved_run")
	get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_endless_pressed() -> void:
	_clear_saved_run()
	_set_run_mode(ENUMS.RunMode.ENDLESS)
	get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_options_pressed() -> void:
	if options_panel != null:
		options_panel.visible = true
	if glossary_panel != null:
		glossary_panel.visible = false

func _on_glossary_pressed() -> void:
	if glossary_panel != null:
		glossary_panel.visible = true
	if options_panel != null:
		options_panel.visible = false

func _on_exit_pressed() -> void:
	get_tree().quit()

func _build_glossary_panel() -> Panel:
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
		if glossary_panel != null:
			glossary_panel.visible = false
	)
	panel.add_child(back_button)

	return panel

func _build_difficulty_selector_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(820.0, 520.0)
	panel.position = Vector2(550.0, 160.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.96)
	style.border_color = Color(0.44, 0.7, 0.96, 0.74)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var title := Label.new()
	title.text = "Select Difficulty"
	title.position = Vector2(0.0, 16.0)
	title.custom_minimum_size = Vector2(820.0, 32.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	panel.add_child(title)

	var tier_buttons_container := VBoxContainer.new()
	tier_buttons_container.position = Vector2(40.0, 70.0)
	tier_buttons_container.custom_minimum_size = Vector2(740.0, 360.0)
	tier_buttons_container.add_theme_constant_override("separation", 14)
	panel.add_child(tier_buttons_container)

	difficulty_tier_buttons.clear()
	for tier in range(4):
		var tier_button_container := HBoxContainer.new()
		tier_button_container.custom_minimum_size = Vector2(740.0, 80.0)
		tier_buttons_container.add_child(tier_button_container)

		var button := Button.new()
		button.custom_minimum_size = Vector2(700.0, 80.0)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_difficulty_tier_selected.bindv([tier]))
		tier_button_container.add_child(button)
		difficulty_tier_buttons.append(button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.position = Vector2(330.0, 460.0)
	back_button.custom_minimum_size = Vector2(160.0, 42.0)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(func() -> void:
		difficulty_selector_panel.visible = false
		root_panel.visible = true
	)
	panel.add_child(back_button)

	return panel

func _update_difficulty_selector() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	
	var current_tier: int = META_PROGRESS.TIER_STANDARD
	var highest_unlocked_tier: int = META_PROGRESS.TIER_APPRENTICE
	
	if run_context.has_method("get_current_difficulty_tier"):
		current_tier = int(run_context.call("get_current_difficulty_tier"))
	if run_context.has_method("get_highest_unlocked_difficulty_tier"):
		highest_unlocked_tier = int(run_context.call("get_highest_unlocked_difficulty_tier"))
	
	for i in range(difficulty_tier_buttons.size()):
		var button := difficulty_tier_buttons[i]
		var config := DIFFICULTY_CONFIG.get_tier_config(i)
		var tier_name: String = config.get("name", "Unknown")
		var tier_desc: String = config.get("description", "")
		var is_unlocked := i <= highest_unlocked_tier
		var is_selected := i == current_tier
		
		var status := ""
		if not is_unlocked:
			status = " [LOCKED]"
		elif is_selected:
			status = " [CURRENT]"
		
		button.text = "%s%s\n%s" % [tier_name, status, tier_desc]
		button.disabled = not is_unlocked
		
		## Visual styling for selected/unlocked state
		if is_selected:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.22, 0.35, 0.55, 0.95)
			selected_style.border_color = Color(0.8, 0.95, 1.0, 1.0)
			selected_style.set_border_width_all(2)
			selected_style.set_corner_radius_all(8)
			button.add_theme_stylebox_override("normal", selected_style)
		elif is_unlocked:
			var unlocked_style := StyleBoxFlat.new()
			unlocked_style.bg_color = Color(0.10, 0.14, 0.20, 0.90)
			unlocked_style.border_color = Color(0.44, 0.66, 0.88, 0.85)
			unlocked_style.set_border_width_all(2)
			unlocked_style.set_corner_radius_all(8)
			button.add_theme_stylebox_override("normal", unlocked_style)
		else:
			var locked_style := StyleBoxFlat.new()
			locked_style.bg_color = Color(0.08, 0.08, 0.10, 0.70)
			locked_style.border_color = Color(0.30, 0.30, 0.35, 0.50)
			locked_style.set_border_width_all(2)
			locked_style.set_corner_radius_all(8)
			button.add_theme_stylebox_override("normal", locked_style)

func _on_difficulty_tier_selected(tier: int) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	
	if run_context.has_method("set_difficulty_tier"):
		if run_context.call("set_difficulty_tier", tier):
			difficulty_selector_panel.visible = false
			get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)

func _on_master_volume_changed(value: float) -> void:
	_apply_options(value, music_slider.value)

func _on_music_volume_changed(value: float) -> void:
	_apply_options(master_slider.value, value)

func _sync_options_from_context() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		master_slider.value = 0.0
		music_slider.value = -46.0
		_update_option_labels()
		return
	master_slider.value = float(run_context.get("master_volume_db"))
	music_slider.value = float(run_context.get("music_volume_db"))
	_update_option_labels()

func _apply_options(master_db: float, music_db: float) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("set_audio_settings"):
		run_context.call("set_audio_settings", master_db, music_db, true)
	_apply_menu_music_volume(music_db)
	_update_option_labels()

func _update_option_labels() -> void:
	if master_value_label != null:
		master_value_label.text = "%+d dB" % int(round(master_slider.value))
	if music_value_label != null:
		music_value_label.text = "%+d dB" % int(round(music_slider.value))

func _start_menu_music() -> void:
	if MENU_MUSIC == null:
		return
	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.stream = MENU_MUSIC
	menu_music_player.bus = "Master"
	menu_music_player.finished.connect(_on_menu_music_finished)
	add_child(menu_music_player)
	_apply_menu_music_volume(music_slider.value)
	menu_music_player.play()

func _on_menu_music_finished() -> void:
	if menu_music_player == null:
		return
	menu_music_player.play(0.0)

func _apply_menu_music_volume(music_db: float) -> void:
	if menu_music_player == null:
		return
	menu_music_player.volume_db = clampf(music_db, -60.0, -6.0)

func _set_run_mode(mode: int) -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("set_run_mode"):
		run_context.call("set_run_mode", mode)

func _refresh_primary_run_button() -> void:
	if primary_run_button == null:
		return
	primary_run_button.text = "Continue Run" if _has_saved_run() else "Standard Run"

func _has_saved_run() -> bool:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null or not run_context.has_method("has_saved_run"):
		return false
	return bool(run_context.call("has_saved_run"))

func _clear_saved_run() -> void:
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context == null:
		return
	if run_context.has_method("clear_active_run"):
		run_context.call("clear_active_run")
	if run_context.has_method("clear_resume_saved_run_request"):
		run_context.call("clear_resume_saved_run_request")
