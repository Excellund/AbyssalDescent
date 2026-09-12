extends "res://scripts/tests/test_boss_atmosphere.gd"
## Native Main HUD placement plus expiry through the actual replica visual path.
const CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
const CALLOUT_TEST := preload("res://scripts/tests/test_boss_callouts.gd")
const CAPTURE_SIZES := [Vector2i(960, 720), Vector2i(1920, 1080)]
const OWNED_POWERS := ["heavy_blow", "static_wake", "stormbrand", "shatterwake"]

var frames: Array[Dictionary] = []
var output_directory := ""

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-boss-callout-hud")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	output_directory = ProjectSettings.globalize_path("res://boss_callout_hud_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	for family in range(3):
		for capture_size: Vector2i in CAPTURE_SIZES:
			root.size = capture_size
			root.content_scale_size = capture_size
			await _exercise_hud_and_expiry(family)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after callout HUD scenes")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "scope": "Native Main arena, biome/status/stats/build HUD; original three bosses at top-left and build-chip edge at 960/1920; actual replica snapshots followed by expiry with no new snapshot or explicit redraw."}, "\t"))
	print("[OK] Boss callout HUD GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _exercise_hud_and_expiry(family: int) -> void:
	var stage := family + 1
	var id: String = BOSSES.DEFAULT_IDS[family]
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world._clear_all_enemies()
	world.first_boss_defeated = stage >= 2
	world.second_boss_defeated = stage >= 3
	world.run_session.act_boss_ids = BOSSES.normalize_roster(BOSSES.DEFAULT_IDS)
	world._choose_door(CONTRACTS.boss_door_option(id))
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	for power_id: String in OWNED_POWERS:
		check(world.player.upgrade_system.apply_power(power_id), "Native ownership populates the real build HUD: " + power_id)
	var boss: Node2D
	for enemy: Node in get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and String(enemy.get_meta("boss_id", "")) == id:
			boss = enemy as Node2D
			enemy.set_physics_process(false)
	check(is_instance_valid(boss), "Native boss door creates " + id)
	if not is_instance_valid(boss):
		await _dispose_world()
		return
	world._signal_local_player_ready()
	boss._update_spawn_transport(float(boss.spawn_transport_time_left) + 0.01)
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world.player.global_position = Vector2(150.0, 50.0)
	world._sync_renderer()
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	check(world.hud.is_in_group("attack_callout_hud"), "Actual HUD registers its callout exclusions")
	check(world.hud.status_panel.is_visible_in_tree() and world.hud.stats_panel.is_visible_in_tree() and world.hud.build_strip_passive_chip.is_visible_in_tree(), "Native biome/status/stats/build surface remains visible")
	var prefix := "%s_%d" % [id, root.size.x]
	# Warning names are supplied by the existing native move fixture. Only the
	# actor's placement is controlled; actual Main camera and HUD layout remain.
	_set_boss_screen_position(boss, Vector2(60.0, 85.0))
	CALLOUT_TEST.prepare(boss, family, 0)
	boss.queue_redraw()
	await _capture_hud(prefix + "_top_left", boss, true)
	var chip: Rect2 = world.hud.build_strip_passive_chip.get_global_rect()
	var world_scale := boss.get_global_transform_with_canvas().get_scale().abs().y
	var screen_y := minf(float(root.size.y) - 65.0, chip.get_center().y + 100.0 * world_scale + 15.0)
	_set_boss_screen_position(boss, Vector2(chip.end.x + 12.0, screen_y))
	CALLOUT_TEST.prepare(boss, family, 0)
	boss.queue_redraw()
	await _capture_hud(prefix + "_build_edge", boss, true)
	# Create the same native node used by the replicated spawn path, then apply
	# the authoritative runtime and projectile payloads to that separate actor.
	_set_boss_screen_position(boss, Vector2(root.size) * Vector2(0.60, 0.53))
	CALLOUT_TEST.prepare(boss, family, 0)
	var runtime: Dictionary = boss.get_network_runtime_state().duplicate(true)
	var projectiles: Dictionary = boss.get_projectile_network_sync_state().duplicate(true)
	var remote := STAGES.create_boss_node(stage, boss.global_position, id)
	world.add_child(remote)
	remote.set_network_simulation_enabled(false)
	remote.set_physics_process(false)
	remote.apply_network_runtime_state(runtime)
	remote.apply_projectile_network_sync_state(projectiles)
	check(remote.get_attack_callout() == boss.get_attack_callout() and not remote.get_attack_callout().is_empty(), id + ": separate replica receives the native callout")
	CALLOUT_TEST.clear_move(boss, family)
	if family == 2:
		boss._sync_attack_overlay()
	boss.hide()
	await _capture_hud(prefix + "_replica_warning", remote, true)
	var expiry_delta := float(remote.state_time_left) + 0.1
	remote._process_network_visuals(expiry_delta)
	check(remote.get_attack_callout().is_empty(), id + ": local replica timer expiry clears its name without another snapshot")
	# Deliberately no queue_redraw() here or in _capture_hud: this capture also
	# exposes a stale CanvasItem draw command if the visual path forgot it.
	await _capture_hud(prefix + "_replica_expired", remote, false)
	await _dispose_world()

func _set_boss_screen_position(boss: Node2D, screen_position: Vector2) -> void:
	boss.global_position = boss.get_canvas_transform().affine_inverse() * screen_position

func _capture_hud(frame_name: String, boss: Node2D, expected_visible: bool) -> void:
	await process_frame
	await process_frame
	var name_text: String = boss.get_attack_callout()
	var exclusions: Array = world.hud.call("get_attack_callout_exclusion_rects")
	check(exclusions.size() >= 3, "Native HUD supplies visible exclusions: " + frame_name)
	check(not name_text.is_empty() if expected_visible else name_text.is_empty(), "Expected callout visibility: " + frame_name)
	var callout_rect := Rect2()
	if expected_visible:
		var info := CALLOUT.layout(boss, name_text, -100.0)
		callout_rect = info.rect
		check(root.get_visible_rect().encloses(callout_rect), "Callout stays inside the viewport: " + frame_name)
		check(float(info.font_size) * root.get_stretch_transform().get_scale().x >= 18.0 - 0.01, "Callout retains 18 physical pixels: " + frame_name)
		for exclusion: Rect2 in exclusions:
			check(not callout_rect.intersects(exclusion), "Callout clears an actual HUD rectangle: " + frame_name)
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured native HUD callout: " + frame_name)
	frames.append({"name": frame_name, "path": path, "size": root.size, "callout": name_text, "callout_rect": callout_rect, "hud_exclusions": exclusions, "boss_screen_position": boss.get_global_transform_with_canvas().origin})
	print("[FRAME] " + path)
