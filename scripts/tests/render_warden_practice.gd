extends "res://scripts/tests/test_warden_practice.gd"
## Actual Menu / Practice / Menu with native keyboard events and production
## canvas stretch. Terminal health is deliberately staged and labelled.

const WARNING_ENUMS := preload("res://scripts/shared/enemy_state_enums.gd")

var frames: Array[Dictionary] = []
var frame_folder := ""

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	ProjectSettings.set_setting("application/config/update_feed_url", "")
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	check(not MultiplayerSessionManager.has_active_session_state(), "Actual idle SceneMultiplayer permits solo Practice")
	root.content_scale_size = Vector2i(2560, 1440)
	frame_folder = ProjectSettings.globalize_path("res://warden_practice_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	await _prepare_normal_checkpoint()
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.base_viewport_width = 2560
	RunContext.base_viewport_height = 1440
	for screen in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = screen
		await _settle_native()
		RunContext.clear_active_run()
		var menu: Control = (load("res://scenes/Menu.tscn") as PackedScene).instantiate() as Control
		root.add_child(menu)
		current_scene = menu
		await _settle_native(24)
		check(menu.primary_run_button.text == "Begin Descent", "Actual normal Menu offers Begin")
		_check_menu_layout(menu, screen)
		await _capture("menu_normal", "Actual Menu with checkpoint cleared only inside the isolated fixture")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == menu.practice_button, "Native Tab reaches Practice directly after Begin")
		if screen.x == 960:
			MultiplayerSessionManager.room_code = "fixture-pending-party"
			menu._refresh_practice_button()
			await _key(KEY_ENTER)
			check(current_scene == menu and menu.practice_button.disabled, "Native disabled Practice cannot enter a pending party")
			await _capture("menu_practice_blocked", "Actual entry disabled by deliberately staged pending-party metadata")
			MultiplayerSessionManager.room_code = ""
			menu._refresh_practice_button()
			menu.practice_button.grab_focus()
		var last_action := menu.root_actions.get_child(menu.root_actions.get_child_count() - 1) as Button
		for _step in 14:
			if root.gui_get_focus_owner() == last_action:
				break
			await _key(KEY_TAB)
		await _settle_native()
		check(root.gui_get_focus_owner() == last_action and _physical_rect(menu._root_action_scroll).grow(1).encloses(_physical_rect(last_action)), "Native keyboard scrolls through every main action to Exit")
		await _capture("menu_bottom", "Actual main action list scrolled to Exit through native Tab input")
		RunContext.save_active_run(saved_snapshot)
		menu._refresh_primary_run_button()
		menu.primary_run_button.grab_focus()
		await _settle_native()
		check(menu.primary_run_button.text == "Resume Descent", "Actual Menu reads the preserved Main checkpoint")
		await _capture("menu_continue", "Actual Menu reading a valid isolated Main checkpoint")
		# Exercise the actual Resume failure callback before entering Practice.
		var corrupt := FileAccess.open(RunContext._active_run_save_path(), FileAccess.WRITE)
		corrupt.store_string("deliberately invalid native-fixture checkpoint")
		corrupt.close()
		await _key(KEY_ENTER)
		await _settle_native()
		check(current_scene == menu and menu.primary_run_button.text == "Retry Resume" and menu.checkpoint_discard_button.visible, "Native Resume failure keeps the saved checkpoint and its recovery controls")
		var return_token: Dictionary = menu._practice_menu_return_state()
		await _capture("menu_checkpoint_error", "Actual Resume pressed against a deliberately corrupt isolated checkpoint")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == menu.checkpoint_discard_button, "Error keyboard order reaches Discard")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == menu.practice_button, "Error keyboard order reaches Practice")
		file_baseline = _file_hashes()
		context_baseline = _context_state()
		await _key(KEY_ENTER)
		await _settle_native()
		arena = current_scene as ARENA
		check(arena != null and arena.mode == "setup" and arena.player == null, "Native Practice entry opens editable setup before any combat")
		if arena == null:
			break
		_check_panel_layout(arena.ui, screen)
		await _capture("practice_setup", "Actual Menu enters editable sandbox setup with useful defaults and no actors")
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.mode == "active" and arena.player.active_character_id == "bastion", "Native Start applies the default build and roster atomically")
		_check_panel_layout(arena.ui, screen)
		_check_arena_frame(screen, "Entry")
		await _capture("practice_active", "Actual standalone Practice with base combat, no staged health or powers")
		if screen.x == 960:
			root.size = Vector2i(1280, 720)
			await _settle_native()
			_check_arena_frame(Vector2i(1280, 720), "Live resize")
			root.size = screen
			await _settle_native()
			_check_arena_frame(screen, "Live resize return")
		await _key(KEY_ESCAPE)
		await _settle_native()
		check(arena.mode == "paused" and root.gui_get_focus_owner() == arena.ui.resume_button, "Native Escape pauses and focuses Resume")
		_check_panel_layout(arena.ui, screen)
		await _capture("practice_paused", "Actual Practice paused through native Escape")
		await _key(KEY_ENTER)
		check(arena.mode == "active" and root.gui_get_focus_owner() == null, "Native Resume returns combat without a button consuming Dash")
		await _key(KEY_ESCAPE)
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == arena.ui.retry_button, "Native paused traversal reaches Retry")
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.attempt == 2 and arena.mode == "active" and arena.player._get_current_health() == 130, "Native Retry starts exactly one new full-health attempt")
		_check_arena_frame(screen, "Retry")
		await _capture("practice_retry", "Actual Retry from Pause; new base actors and retained score")
		if screen.x == 960:
			await _capture_warning_phases()
		arena.boss.health_state.set_health(1)
		var hit := INTERACTIONS.damage_context(arena.player.new_combat_action("melee"), "melee", {"raw_amount": 25.0, "damage_coefficient": 1.0})
		DAMAGE.apply_damage(arena.boss, 25, hit, 1)
		await _settle_native()
		check(arena.mode == "victory" and root.gui_get_focus_owner() == arena.ui.retry_button, "Accepted terminal damage displays victory and focuses Retry")
		_check_panel_layout(arena.ui, screen)
		await _capture("practice_victory", "Actual victory presentation; boss health staged to1 before final accepted Attack damage")
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.attempt == 3 and arena.mode == "active", "Native Retry leaves victory for a new attempt")
		DAMAGE.apply_damage(arena.player, 10000, {"source": "enemy_ability", "ability": "fixture_terminal"})
		await _settle_native()
		check(arena.mode == "defeat" and root.gui_get_focus_owner() == arena.ui.retry_button, "Accepted lethal damage displays defeat and focuses Retry")
		_check_panel_layout(arena.ui, screen)
		await _capture("practice_defeat", "Actual defeat presentation after deliberately staged accepted lethal damage")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == arena.ui.menu_button, "Native terminal traversal reaches Menu")
		await _key(KEY_ENTER)
		await _settle_native(24)
		menu = current_scene
		check(menu != null and menu.scene_file_path == "res://scenes/Menu.tscn", "Native Menu returns to the real normal Menu scene")
		check(menu._practice_menu_return_state() == return_token, "Return preserves the exact corrupt-checkpoint retry/error/discard presentation")
		check(root.gui_get_focus_owner() == menu.practice_button, "Returned normal Menu focuses Practice")
		_check_preserved("Native full roundtrip %s" % screen)
		check(EnemyReplicationService.world_generator == null and get_nodes_in_group("enemies").is_empty() and get_nodes_in_group("combat_players").is_empty(), "Returning retires all Practice actors and registry ownership")
		await _capture("menu_returned", "Actual Menu after native terminal return; checkpoint bytes and selected profile unchanged")
		current_scene = null
		menu.queue_free()
		arena = null
		await _settle_native()
	await _cleanup_recovery_world()
	FileAccess.open(frame_folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "checks": checks, "failures": failures, "frames": frames}, "\t"))
	print("[OK] Warden Practice native: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_menu_layout(menu: Control, screen: Vector2i) -> void:
	check(Rect2(Vector2.ZERO, Vector2(screen)).encloses(_physical_rect(menu.root_panel)), "Native physical main panel fits %s" % screen)
	for action in menu.root_actions.get_children():
		if action is Button:
			check(_physical_font_size(action) >= 17.99, "Native main action remains readable: " + action.text)
	check(menu.practice_button.text == "Practice" and menu.root_actions.get_child(menu.practice_button.get_index() + 1).get("text") == "Multiplayer", "Practice has no subtitle before the next menu action")

func _check_panel_layout(panel: CanvasLayer, screen: Vector2i) -> void:
	check(Rect2(Vector2.ZERO, Vector2(screen)).encloses(_physical_rect(panel.hud)), "Native Practice HUD fits %s" % screen)
	check(_physical_font_size(panel.context_label) >= 17.99, "Native Practice no-progression text is readable")
	if panel.modal.visible:
		check(Rect2(Vector2.ZERO, Vector2(screen)).encloses(_physical_rect(panel.modal)), "Native Practice dialog fits %s" % screen)
		check(_physical_rect(panel.modal).encloses(_physical_rect(panel.modal_notice)), "Native isolation notice fits fully in its dialog")
		for button in [panel.resume_button, panel.retry_button, panel.menu_button]:
			if button.visible:
				check(_physical_rect(panel.modal).encloses(_physical_rect(button)) and _physical_font_size(button) >= 17.99, "Native dialog action fits and stays readable: " + button.text)

func _physical_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var stretch := root.get_stretch_transform().get_scale()
	return Rect2(transform.origin * stretch, control.size * transform.get_scale() * stretch)

func _check_arena_frame(screen: Vector2i, source: String) -> void:
	var world_rect := Rect2(-arena.current_effective_room_size * 0.5, arena.current_effective_room_size)
	var drawn_rect: Rect2 = root.get_canvas_transform() * world_rect
	check(arena.ui.get_gameplay_rect().grow(2.0).encloses(drawn_rect), "Actual arena stays between the readable HUD and controls: %s %s" % [screen, source])

func _capture_warning_phases() -> void:
	# Stage only selection/timing for visual QA; use each actual boss setup and
	# windup renderer. The separate live smoke exercises unstaged attacks.
	arena.player.set_physics_process(false)
	arena.boss.set_physics_process(false)
	arena.player.position = Vector2(-150, 0)
	arena.boss.position = Vector2(100, 0)
	var kinds: Dictionary = {"charge": WARNING_ENUMS.BossAttack.CHARGE, "nova": WARNING_ENUMS.BossAttack.NOVA, "cleave": WARNING_ENUMS.BossAttack.CLEAVE}
	for label in kinds:
		var wanted: int = kinds[label]
		for _selection in 100:
			arena.boss._start_next_attack(200.0)
			if int(arena.boss.active_attack) == wanted:
				break
		check(int(arena.boss.active_attack) == wanted, "Staged warning uses the actual Warden attack setup: " + label)
		arena.boss._process_telegraph_state(arena.boss._get_windup_time(wanted) * 0.65)
		arena.boss.queue_redraw()
		await _settle_native()
		_check_arena_frame(Vector2i(960, 540), label)
		await _capture("practice_warning_" + label, "Actual Warden warning renderer; attack choice, actor positions and windup time deliberately staged for visual QA")

func _physical_font_size(control: Control) -> float:
	return control.get_theme_font_size("font_size") * control.get_global_transform_with_canvas().get_scale().y * root.get_stretch_transform().get_scale().y

func _capture(label: String, source: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var name_text := "%s_%d" % [label, picture.get_width()]
	var path := frame_folder.path_join(name_text + ".png")
	check(picture.save_png(path) == OK, "Native Practice frame saves: " + name_text)
	frames.append({"name": name_text, "path": path, "size": picture.get_size(), "canvas": root.content_scale_size, "source": source})

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release, true)
	await process_frame

func _open_practice_tab(index: int) -> void:
	var bar: TabBar = arena.ui.editor.tabs.get_tab_bar()
	var point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(index).get_center()
	await _click_point(point)
	check(arena.ui.editor.tabs.current_tab == index, "Native mouse opens the requested Practice tab")

func _click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await _settle_native(3)

func _settle_native(count: int = 6) -> void:
	for _step in count:
		await process_frame
	await RenderingServer.frame_post_draw
