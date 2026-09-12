extends "res://scripts/tests/test_warden_practice.gd"
## Real Menu, actual elapsed transitions and native action dispatch. No test
## calls layout after a Window resize: production owns that notification.

var menu: Control

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	await _prepare_normal_checkpoint()
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.base_viewport_width = 2560
	RunContext.base_viewport_height = 1440
	for screen in ["glossary", "history"]:
		await _new_menu()
		_open_panel(screen)
		await _settled()
		_check_panel(screen, "Ordinary open")
		await _escape()
		await _settled()
		check(menu.root_panel.visible and not _panel(screen).visible, screen + ": ordinary close restores Main")
		check(root.gui_get_focus_owner() == menu.primary_run_button, screen + ": close retains normal main focus")
		_open_panel(screen)
		await _settled()
		_check_panel(screen, "Ordinary reopen")
		await _free_menu()

		await _new_menu()
		_open_panel(screen)
		await create_timer(0.025).timeout
		await _escape()
		_open_panel(screen)
		await _settled()
		_check_panel(screen, "Reopen before old exit completes")
		check(menu._panel_transitions.is_empty(), screen + ": completed transitions release their references")
		await _free_menu()

		await _new_menu()
		_open_panel(screen)
		await create_timer(0.025).timeout
		root.size = Vector2i(1280, 720)
		await _settled()
		_check_panel(screen, "Resize during entry")
		root.size = Vector2i(1920, 1080)
		await _settled()
		_check_panel(screen, "Resize while settled")
		await _escape()
		root.size = Vector2i(960, 540)
		await _settled()
		check(menu.root_panel.visible and not _panel(screen).visible, screen + ": resize completes intended outgoing hide")
		check(is_equal_approx(_font_pixels(menu.practice_button), 18.0), "Window resize restores Main physical button font")
		_open_panel(screen)
		await _settled()
		_check_panel(screen, "Reopen after outgoing resize")
		await _free_menu()

	await _new_menu()
	menu._show_character_selector()
	root.size = Vector2i(1280, 720)
	await _settled()
	check(not menu.root_panel.visible and menu.character_selector_panel.visible, "Root outgoing resize preserves selector visibility")
	menu._show_root_panel()
	await _settled()
	check(menu.root_panel.visible and not menu.character_selector_panel.visible, "Root returns from selector after resize")
	menu.practice_button.pressed.emit()
	await _settled()
	var practice := current_scene as ARENA
	check(practice != null and practice.mode == "setup" and practice.player == null, "Normal Practice button enters detached setup before combat")
	menu = null
	if practice != null:
		practice.request_menu()
		await _settled()
		menu = current_scene as Control
		check(menu != null and menu.root_panel.visible, "Practice returns to visible real Menu")
		check(menu != null and root.gui_get_focus_owner() == menu.practice_button, "Practice return focus is preserved")
	await _free_menu()
	await _cleanup_recovery_world()
	print("[OK] Menu panel transitions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new_menu() -> void:
	root.size = Vector2i(960, 540)
	await process_frame
	menu = (load("res://scenes/Menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _settled()

func _free_menu() -> void:
	if is_instance_valid(menu):
		current_scene = null
		menu.queue_free()
		menu = null
	await process_frame
	await process_frame

func _settled() -> void:
	await create_timer(0.30).timeout
	await process_frame

func _open_panel(screen: String) -> void:
	if screen == "glossary":
		menu._on_glossary_pressed()
	else:
		menu._on_history_pressed()

func _panel(screen: String) -> Control:
	return menu.glossary_panel if screen == "glossary" else menu.history_panel

func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _font_pixels(control: Control) -> float:
	return control.get_theme_font_size("font_size") * control.get_global_transform_with_canvas().get_scale().y * root.get_stretch_transform().get_scale().y

func _check_panel(screen: String, label: String) -> void:
	var panel := _panel(screen)
	var stretch := root.get_stretch_transform().get_scale().abs()
	var actual_size := panel.size * panel.get_global_transform_with_canvas().get_scale().abs() * stretch
	var actual_position := panel.get_global_transform_with_canvas().origin * stretch
	var physical_window := Vector2(root.size)
	var expected_size := Vector2(minf(1360, physical_window.x - 48), minf(900, physical_window.y - 48)) if screen == "glossary" else Vector2(minf(980, physical_window.x - 32), minf(680, physical_window.y - 32))
	check(panel.visible and not menu.root_panel.visible, "%s %s: only requested panel remains visible" % [screen, label])
	check(actual_size.distance_to(expected_size) < 0.1, "%s %s: physical size matches current window" % [screen, label])
	check(actual_position.distance_to((physical_window - expected_size) * 0.5) < 0.1, "%s %s: current centered bounds survive old tween targets" % [screen, label])
	check(is_equal_approx(panel.modulate.a, 1.0), "%s %s: panel returns to full opacity" % [screen, label])
