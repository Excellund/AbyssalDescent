extends SceneTree
## Actual Main entry, native movement and ordinary spawned enemies. The fixture
## opens the existing Escape/Tab handlers; it does not reposition combat actors.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
var world: WORLD
var retirement := AUDIO.new()
var checks := 0
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var folder := ""
var movement_frames := 0
var natural_enemy_overlap := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _settle(count: int = 3) -> void:
	for _frame in count:
		await process_frame

func _player_screen() -> Vector2:
	return root.get_canvas_transform() * world.player.global_position

func _record_enemy_overlap() -> void:
	var rect: Rect2 = world.hud.stats_panel.get_global_rect()
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			var point: Vector2 = root.get_canvas_transform() * enemy.global_position
			natural_enemy_overlap = natural_enemy_overlap or rect.has_point(point)

func _walk_until(action: String, axis: int, target: float, direction: float, maximum: int = 240) -> void:
	Input.action_press(action)
	var reached := false
	for _frame in maximum:
		await physics_frame
		await process_frame
		movement_frames += 1
		_record_enemy_overlap()
		var point := _player_screen()
		if direction * (point[axis] - target) >= 0.0:
			reached = true
			break
		if world.player.is_dead():
			break
	Input.action_release(action)
	await _settle(4)
	check(reached and not world.player.is_dead(), "Native " + action + " reaches screen target with living player")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event, true)

func _build_chip() -> Panel:
	for chip in world.hud.build_strip_arcana_chips:
		if chip.visible:
			return chip
	return world.hud.build_strip_passive_chip

func _capture(key: String, size: Vector2i, stats_alpha: float, build_alpha: float) -> void:
	await _settle()
	world._refresh_frame_ui()
	await RenderingServer.frame_post_draw
	var stats: Panel = world.hud.stats_panel
	var strip: Panel = world.hud.build_strip_panel
	var chip := _build_chip()
	var point := _player_screen()
	check(is_equal_approx(stats.modulate.a, stats_alpha), key + ": Stats opacity matches actual phase and overlap")
	check(is_equal_approx(strip.modulate.a, build_alpha), key + ": build parent opacity matches actual phase and overlap")
	check(is_equal_approx(world.hud.status_panel.modulate.a, 1.0), key + ": status/objective card stays fully readable")
	check(is_equal_approx(world.hud.stats_label.modulate.a, 1.0), key + ": text retains its authored opacity under the faded parent")
	check(is_equal_approx(chip.modulate.a, 1.0), key + ": populated chip retains its authored opacity under the faded parent")
	check(not world.player.is_dead() and not world.choosing_next_room, key + ": ordinary encounter remains live")
	if key in ["stats", "pause", "stats_resumed"]:
		check(stats.get_global_rect().has_point(point), key + ": local body is inside actual Stats bounds")
	if key in ["build", "details", "build_resumed"]:
		check(chip.get_global_rect().grow(2.0).has_point(point), key + ": local body is inside a visible populated build chip")
	if key == "pause":
		check(world.pause_menu_controller.is_open() and not world.player.is_physics_processing(), "Escape opens actual Pause and pauses movement")
	if key == "details":
		check(world.build_detail_panel.is_open() and not world.player.is_physics_processing(), "Held Tab opens actual Build Details and pauses movement")
	var filename := "%s_%d.png" % [key, size.x]
	var picture := root.get_texture().get_image()
	check(picture.get_size() == size and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
	var stats_rect := stats.get_global_rect()
	var build_rect := chip.get_global_rect()
	frames.append({"file": filename, "size": [size.x, size.y], "state": key,
		"player_screen": [point.x, point.y], "player_world": [world.player.global_position.x, world.player.global_position.y],
		"health": world.player.get_current_health(), "native_movement_frames": movement_frames,
		"natural_enemy_under_stats_seen": natural_enemy_overlap, "stats_alpha": stats.modulate.a, "build_alpha": strip.modulate.a,
		"stats_rect": [stats_rect.position.x, stats_rect.position.y, stats_rect.size.x, stats_rect.size.y],
		"visible_chip_rect": [build_rect.position.x, build_rect.position.y, build_rect.size.x, build_rect.size.y],
		"pause_open": world.pause_menu_controller.is_open(), "build_details_open": world.build_detail_panel.is_open()})
	print("[FRAME] " + filename)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	folder = project_path.path_join("hud_overlap_fade_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for size: Vector2i in [Vector2i(960, 720), Vector2i(1280, 720)]:
		root.size = size
		root.content_scale_size = size
		world = MAIN.instantiate() as WORLD
		world.get_node("DebugSettings").enabled = false
		root.add_child(world)
		current_scene = world
		var choice: Dictionary = world.reward_selection_ui.boon_choices.front().duplicate(true)
		var mode: int = world.reward_selection_ui.reward_selection_mode
		world.reward_selection_ui.close_selection()
		world.reward_selection_ui.reward_selected.emit(choice, mode, true)
		await _settle()
		movement_frames = 0
		natural_enemy_overlap = false
		Input.action_press("move_left")
		await _settle(3)
		Input.action_release("move_left")
		check(not world.encounter_intro_grace_active and not world.player.encounter_input_frozen, "Fresh native Move engages the normal first encounter")
		await _capture("unoccluded", size, 1.0, 1.0)
		# Skirmish may legitimately roll horizontal center columns. Walk around
		# them instead of selecting an easier layout or moving any actor directly.
		await _walk_until("move_down", 1, 440.0, 1.0)
		await _walk_until("move_left", 0, 220.0, -1.0)
		await _walk_until("move_up", 1, 350.0, -1.0)
		await _capture("stats", size, 0.2, 1.0)
		_key(KEY_ESCAPE, true)
		await _settle(18)
		await _capture("pause", size, 1.0, 1.0)
		_key(KEY_ESCAPE, true)
		await _capture("stats_resumed", size, 0.2, 1.0)
		check(world.player.is_physics_processing(), "Closing Pause restores native player movement")
		var target_y := _build_chip().get_global_rect().get_center().y
		await _walk_until("move_down", 1, target_y, 1.0)
		await _capture("build", size, 1.0, 0.2)
		_key(KEY_TAB, true)
		await _capture("details", size, 1.0, 1.0)
		_key(KEY_TAB, false)
		_key(KEY_TAB, true)
		_key(KEY_TAB, false)
		await _capture("build_resumed", size, 1.0, 0.2)
		check(world.player.is_physics_processing(), "Toggling Tab closed restores native player movement")
		await _walk_until("move_right", 0, 400.0, 1.0)
		await _capture("exit", size, 1.0, 1.0)
		check(natural_enemy_overlap, "Ordinary pursuing enemies enter the Stats area during native movement")
		current_scene = null
		world.queue_free()
		world = null
		await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await retirement.wait_until_retired(self), "Native fixture audio retires")
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("[OK] HUD overlap GPU: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
